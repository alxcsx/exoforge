defmodule Exoforge.Std.ObservabilityViewTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  alias Exoforge.Std.DashboardViews
  alias Exoforge.Std.DashboardViews.ObservabilityView

  # A stand-in for the `observability` service. The view only reads and starts/stops captures, so a small
  # agent-backed service shows what it asks for and what it renders.
  defmodule Stub do
    use Exoforge.Extension

    def start, do: Agent.start_link(fn -> %{data: %{}, calls: []} end, name: __MODULE__)
    def put(key, value), do: Agent.update(__MODULE__, &%{&1 | data: Map.put(&1.data, key, value)})
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))
    defp get(key, default), do: Agent.get(__MODULE__, &Map.get(&1.data, key, default))
    defp record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})

    defaction(health(payload), scope: :server) do
      record({:health, payload})
      {:ok, get(:health, %{rows: [], attention: []})}
    end

    defaction(error_groups(payload), scope: :server) do
      record({:error_groups, payload})
      {:ok, %{groups: get(:groups, []), count: 0}}
    end

    defaction(events(payload), scope: :server) do
      record({:events, payload})
      {:ok, get(:events, %{events: [], total: 0, capped: false})}
    end

    defaction(timeline(payload), scope: :server) do
      record({:timeline, payload})
      {:ok, %{nodes: get(:nodes, []), count: 0}}
    end

    defaction(captures(), scope: :server) do
      {:ok, %{captures: get(:captures, [])}}
    end

    defaction(capture(payload), scope: :server) do
      record({:capture, payload})
      {:ok, %{capture: payload}}
    end

    defaction(stop_capture(payload), scope: :server) do
      record({:stop_capture, payload})
      {:ok, %{status: "stopped"}}
    end
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    {:ok, _} = Stub.start()
    Exoforge.ExtensionCase.register_extension(Stub, id: :observability, provides: [:observability])
    :ok
  end

  # A LiveComponent cannot be mounted alone in a test, so its callbacks are driven directly.
  defp start do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, id: "obs", myself: %Phoenix.LiveComponent.CID{cid: 1}, flash: %{}}}
    {:ok, socket} = ObservabilityView.mount(socket)
    {:ok, socket} = ObservabilityView.update(%{id: "obs"}, socket)
    socket
  end

  defp event(socket, name, params) do
    {:noreply, socket} = ObservabilityView.handle_event(name, params, socket)
    socket
  end

  defp html(socket), do: rendered_to_string(ObservabilityView.render(socket.assigns))

  test "the studio resolves the view by convention" do
    assert DashboardViews.view_for(:observability) == ObservabilityView
    assert DashboardViews.view_for(:exoforge_std_observability) == ObservabilityView
  end

  test "health opens first and says plainly when nothing needs attention" do
    html = html(start())

    assert html =~ "Nothing needs attention"
    assert html =~ "No calls recorded yet"
    assert {:health, %{limit: 50}} in Stub.calls()
  end

  test "an action that needs attention opens its request, and the table shows the numbers" do
    Stub.put(:health, %{
      rows: [%{service: "auth", action: "login", invocations: 40, calls_30m: 12, error_rate: 0.25, p50_ms: 1.2, p95_ms: 30.0}],
      attention: [%{label: "auth.login", kind: "error", rid: "r_abc", detail: "3× :invalid_credentials"}]
    })

    socket = start()
    html = html(socket)

    assert html =~ "auth.login"
    assert html =~ "3× :invalid_credentials"
    assert html =~ "25.0%"
    assert html =~ "30.0 ms"

    socket = event(socket, "open_rid", %{"rid" => "r_abc"})
    assert socket.assigns.tab == "request"
    assert {:timeline, %{rid: "r_abc"}} in Stub.calls()
  end

  test "a focus link (?focus=request:<rid>) lands on that request, once" do
    socket = start()
    {:ok, socket} = ObservabilityView.update(%{focus: %{kind: "request", id: "r_pasted123"}}, socket)

    assert socket.assigns.tab == "request"
    assert socket.assigns.lookup["rid"] == "r_pasted123"
    assert {:timeline, %{rid: "r_pasted123"}} in Stub.calls()

    # a re-render with the same focus does not ask again, and the person can leave the tab
    before = length(Stub.calls())
    {:ok, socket} = ObservabilityView.update(%{focus: %{kind: "request", id: "r_pasted123"}}, socket)
    assert length(Stub.calls()) == before
    socket = event(socket, "tab", %{"tab" => "failures"})
    assert socket.assigns.tab == "failures"
  end

  test "failures are grouped with a way to open a sample request" do
    Stub.put(:groups, [%{service: "auth", action: "login", reason: ":invalid_credentials", count: 3, callers: ["http"], rid: "r_1", last_seen: System.system_time(:millisecond) - 120_000}])

    html = start() |> event("tab", %{"tab" => "failures"}) |> html()

    assert html =~ "auth.login"
    assert html =~ ":invalid_credentials"
    assert html =~ "2 min ago"
    assert html =~ "Open a sample"
  end

  test "events are filtered, empty filters are not sent, and paging moves the offset" do
    Stub.put(:events, %{events: for(i <- 1..25, do: %{id: "e#{i}", status: "ok", day: "2026-11-20", time: "10:00:00", event: "action:x.y", origin: "internal", rid: "r_#{i}"}), total: 60, capped: false})

    socket = start() |> event("tab", %{"tab" => "events"})
    assert html(socket) =~ "60 events"
    assert html(socket) =~ "showing 1 to 25"

    socket = event(socket, "filter", %{"status" => "error", "event" => "", "rid" => "", "player" => ""})
    assert {:events, %{status: "error", limit: 25, offset: 0}} in Stub.calls()
    refute Enum.any?(Stub.calls(), &match?({:events, %{event: _}}, &1))

    socket = event(socket, "page", %{"dir" => "next"})
    assert socket.assigns.offset == 25
    assert {:events, %{status: "error", limit: 25, offset: 25}} in Stub.calls()
    assert html(socket) =~ "showing 26 to 50"

    assert event(socket, "page", %{"dir" => "prev"}).assigns.offset == 0
  end

  test "a request's timeline is shown in time order with its logs, calls and failures" do
    Stub.put(:nodes, [
      %{kind: "log", label: "error", message: "boom at Stub.cs", at: 1_700_000_000_500},
      %{kind: "event", label: "action:wallet.credit", at: 1_700_000_000_100, payload: %{status: "error", duration_ms: 4}}
    ])

    socket = start() |> event("tab", %{"tab" => "request"}) |> event("lookup", %{"rid" => " r_9 ", "player" => ""})
    html = html(socket)

    assert {:timeline, %{rid: "r_9"}} in Stub.calls()
    assert html =~ "Timeline of"
    assert html =~ "boom at Stub.cs"
    assert html =~ "status error · 4 ms"
    # the earlier node comes first
    assert :binary.match(html, "action:wallet.credit") < :binary.match(html, "boom at Stub.cs")

    assert start() |> event("tab", %{"tab" => "request"}) |> html() =~ "Paste the request id"
  end

  test "a player lookup asks for that player's recent activity" do
    start() |> event("tab", %{"tab" => "request"}) |> event("lookup", %{"rid" => "", "player" => "p_7"})
    assert {:timeline, %{player: "p_7", limit: 200}} in Stub.calls()
  end

  test "captures start with a bounded time, list their remaining seconds and stop" do
    Stub.put(:captures, [%{kind: "player", value: "p_7", remaining_s: 42, seconds: 60}])

    socket = start() |> event("tab", %{"tab" => "captures"})
    assert html(socket) =~ "42 s left"

    socket = event(socket, "start_capture", %{"kind" => "action", "value" => "wallet.credit", "seconds" => "99999"})
    assert {:capture, %{kind: "action", value: "wallet.credit", seconds: 3_600}} in Stub.calls()
    assert html(socket) =~ "Capturing action wallet.credit for 3600 s."

    event(socket, "stop_capture", %{"kind" => "player", "value" => "p_7"})
    assert {:stop_capture, %{kind: "player", value: "p_7"}} in Stub.calls()
  end

  test "an unknown tab is ignored" do
    assert event(start(), "tab", %{"tab" => "nonsense"}).assigns.tab == "health"
  end

  test "the helpers read like a person would" do
    now = 1_700_000_100_000
    assert ObservabilityView.ago_ms(nil, now) == "-"
    assert ObservabilityView.ago_ms(now - 5_000, now) == "5s ago"
    assert ObservabilityView.ago_ms(now - 7_200_000, now) == "2 h ago"
    assert ObservabilityView.rate(0.0123) == "1.2%"
    assert ObservabilityView.rate(nil) == "0%"
    assert ObservabilityView.ms(2) == "2.0 ms"
    assert ObservabilityView.ms(nil) == "-"
    assert ObservabilityView.clock(1_700_000_000_042) =~ ~r/^\d\d:\d\d:\d\d\.042$/
    assert ObservabilityView.parse_seconds("0") == 1
    assert ObservabilityView.parse_seconds("abc") == 300
    assert ObservabilityView.parse_seconds("120") == 120
  end
end
