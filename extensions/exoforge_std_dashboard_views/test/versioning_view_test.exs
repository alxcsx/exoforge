defmodule Exoforge.Std.VersioningViewTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  alias Exoforge.Std.DashboardViews
  alias Exoforge.Std.DashboardViews.VersioningView

  # A stand-in for the `versioning` service: the view only talks to its actions, so a small agent-backed
  # service is enough to see what it renders and which actions a click calls.
  defmodule Stub do
    use Exoforge.Extension

    def start, do: Agent.start_link(fn -> %{rows: [], calls: []} end, name: __MODULE__)
    def put(rows), do: Agent.update(__MODULE__, &%{&1 | rows: rows})
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))
    defp record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})

    defaction(list(), scope: :server) do
      {:ok, %{versions: Agent.get(__MODULE__, & &1.rows)}}
    end

    defaction(promote(payload), scope: :server) do
      record({:promote, payload.version})
      {:ok, %{version: payload.version, status: "live", blocked: []}}
    end

    defaction(block(payload), scope: :server) do
      record({:block, payload.version})
      {:ok, %{version: payload.version, status: "blocked"}}
    end

    defaction(set_locks(payload), scope: :server) do
      record({:set_locks, payload.version, payload.locks})
      {:ok, %{version: payload.version, status: "dev"}}
    end

    defaction(register(payload), scope: :server) do
      record({:register, payload.version, payload.locks})
      {:error, :already_exists}
    end
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    {:ok, _} = Stub.start()
    Exoforge.ExtensionCase.register_extension(Stub, id: :versioning, provides: [:versioning])
    :ok
  end

  defp rows do
    [
      %{version: "1.4.0", status: "dev", locks: %{"achievements" => "1.2.0"}, created_at: 3},
      %{version: "1.3.0", status: "live", locks: %{"achievements" => "1.1.0", "wallet" => "1.0.0"}, created_at: 2},
      %{version: "1.2.0", status: "blocked", locks: %{}, created_at: 1}
    ]
  end

  # A LiveComponent cannot be mounted alone in a test, so its callbacks are driven directly: the socket is
  # what the Studio would hold, and `html/1` is what the component renders from it.
  defp start do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, id: "versions", myself: %Phoenix.LiveComponent.CID{cid: 1}, flash: %{}}}
    {:ok, socket} = VersioningView.mount(socket)
    {:ok, socket} = VersioningView.update(%{id: "versions"}, socket)
    socket
  end

  defp event(socket, name, params) do
    {:noreply, socket} = VersioningView.handle_event(name, params, socket)
    socket
  end

  defp html(socket), do: rendered_to_string(VersioningView.render(socket.assigns))
  defp render_view, do: html(start())

  test "the studio resolves the view by convention" do
    assert DashboardViews.view_for(:versioning) == VersioningView
    assert DashboardViews.view_for(:exoforge_std_versioning) == VersioningView
  end

  test "with no game version it says versioning is off instead of showing an empty table" do
    html = render_view()

    assert html =~ "Versioning is off"
    assert html =~ "every client is served"
    refute html =~ "<table"
    assert html =~ "Register a game version"
  end

  test "versions show their status, locks and only the actions that make sense for the status" do
    Stub.put(rows())
    html = render_view()

    assert html =~ "achievements@1.2.0"
    assert html =~ "wallet@1.0.0"
    assert html =~ "no locks"

    dev = row(html, "1.4.0")
    assert dev =~ "Make live" and dev =~ "Edit locks" and dev =~ "Block"

    live = row(html, "1.3.0")
    assert live =~ "Block"
    refute live =~ "Make live"
    refute live =~ "Edit locks"

    blocked = row(html, "1.2.0")
    refute blocked =~ "Block"
    refute blocked =~ "Make live"

    # one served-of-max tile and the live version
    assert html =~ "2 of 3"
  end

  defp row(html, version) do
    [_, rest] = String.split(html, ~s(id="version-#{version}"), parts: 2)
    rest |> String.split("</tr>", parts: 2) |> hd()
  end

  test "promote and block ask first and call the action only after the confirmation" do
    Stub.put(rows())
    socket = start() |> event("ask", %{"op" => "promote", "version" => "1.4.0"})

    assert html(socket) =~ "Make 1.4.0 the live version?"
    assert Stub.calls() == []

    socket = event(socket, "confirm", %{})
    assert Stub.calls() == [{:promote, "1.4.0"}]
    assert html(socket) =~ "1.4.0 is live."
    refute html(socket) =~ "Make 1.4.0 the live version?"

    # cancelling does nothing
    socket = socket |> event("ask", %{"op" => "block", "version" => "1.3.0"})
    assert html(socket) =~ "Block 1.3.0?"
    socket = event(socket, "cancel", %{})
    refute html(socket) =~ "Block 1.3.0?"
    assert Stub.calls() == [{:promote, "1.4.0"}]

    socket = socket |> event("ask", %{"op" => "block", "version" => "1.3.0"}) |> event("confirm", %{})
    assert {:block, "1.3.0"} in Stub.calls()
    assert html(socket) =~ "1.3.0 is blocked"
  end

  test "edit locks opens the lines of that version and saving sends the parsed map" do
    Stub.put(rows())
    socket = start() |> event("edit_locks", %{"version" => "1.4.0"})
    assert html(socket) =~ "achievements@1.2.0"
    assert html(socket) =~ "Save locks"

    socket = event(socket, "save_locks", %{"version" => "1.4.0", "locks" => "achievements@1.3.0\nwallet@1.0.0"})
    assert {:set_locks, "1.4.0", %{"achievements" => "1.3.0", "wallet" => "1.0.0"}} in Stub.calls()
    assert html(socket) =~ "Locks of 1.4.0 saved."

    bad = start() |> event("save_locks", %{"version" => "1.4.0", "locks" => "what is this"})
    assert html(bad) =~ "is not a lock"
  end

  test "locks are written one per line and parsed back" do
    assert {:ok, %{"achievements" => "1.2.0", "wallet" => "1.0.0"}} =
             VersioningView.parse_locks("achievements@1.2.0\nwallet=1.0.0\n")

    assert {:ok, %{"a" => "1.0.0", "b" => "2.0.0"}} = VersioningView.parse_locks("a@1.0.0, b 2.0.0")
    assert {:ok, %{}} = VersioningView.parse_locks("  \n")
    assert {:error, {:bad_lock, "nonsense here now"}} = VersioningView.parse_locks("nonsense here now")

    locks = %{"wallet" => "1.0.0", "achievements" => "1.2.0"}
    assert {:ok, ^locks} = locks |> VersioningView.locks_to_text() |> VersioningView.parse_locks()
  end

  test "errors from the actions are said in the producer's words" do
    assert VersioningView.error_text(:locks_immutable) =~ "Only a dev version"
    assert VersioningView.error_text({:bad_lock, "x"}) =~ "achievements@1.2.0"
    assert VersioningView.error_text(:weird) =~ ":weird"
  end

  test "registering shows the action's refusal and keeps what was typed" do
    Stub.put(rows())
    socket = start() |> event("register", %{"version" => "1.3.0", "locks" => "wallet@1.0.0"})

    assert {:register, "1.3.0", %{"wallet" => "1.0.0"}} in Stub.calls()
    html = html(socket)
    assert html =~ "already registered"
    assert html =~ "wallet@1.0.0"
  end
end
