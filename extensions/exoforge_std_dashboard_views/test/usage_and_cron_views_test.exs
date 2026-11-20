defmodule Exoforge.Std.UsageAndCronViewsTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  alias Exoforge.Std.DashboardViews
  alias Exoforge.Std.DashboardViews.{CronView, MeteringView}

  defmodule StubMetering do
    use Exoforge.Extension

    def start, do: Agent.start_link(fn -> %{usage: nil, since: :never} end, name: __MODULE__)
    def put(usage), do: Agent.update(__MODULE__, &%{&1 | usage: usage})
    def since, do: Agent.get(__MODULE__, & &1.since)

    defaction(usage(payload), scope: :server) do
      Agent.update(__MODULE__, &%{&1 | since: Map.get(payload, :since)})
      {:ok, Agent.get(__MODULE__, & &1.usage)}
    end
  end

  defmodule StubCron do
    use Exoforge.Extension

    def start, do: Agent.start_link(fn -> %{jobs: [], ran: []} end, name: __MODULE__)
    def put(jobs), do: Agent.update(__MODULE__, &%{&1 | jobs: jobs})
    def ran, do: Agent.get(__MODULE__, &Enum.reverse(&1.ran))

    defaction(list_jobs(), scope: :server) do
      {:ok, %{jobs: Agent.get(__MODULE__, & &1.jobs)}}
    end

    defaction(trigger_job(payload), scope: :server) do
      Agent.update(__MODULE__, &%{&1 | ran: [payload.job_id | &1.ran]})
      {:ok, %{status: "triggered", result: %{}}}
    end
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    {:ok, _} = StubMetering.start()
    {:ok, _} = StubCron.start()
    Exoforge.ExtensionCase.register_extension(StubMetering, id: :metering, provides: [:metering])
    Exoforge.ExtensionCase.register_extension(StubCron, id: :cron, provides: [:cron])
    :ok
  end

  # A LiveComponent cannot be mounted alone in a test, so its callbacks are driven directly.
  defp start(view) do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, id: "v", myself: %Phoenix.LiveComponent.CID{cid: 1}, flash: %{}}}
    {:ok, socket} = view.mount(socket)
    {:ok, socket} = view.update(%{id: "v"}, socket)
    socket
  end

  defp event(view, socket, name, params) do
    {:noreply, socket} = view.handle_event(name, params, socket)
    socket
  end

  defp html(view, socket), do: rendered_to_string(view.render(socket.assigns))

  test "both screens are resolved by convention" do
    assert DashboardViews.view_for(:metering) == MeteringView
    assert DashboardViews.view_for(:exoforge_std_cron) == CronView
  end

  describe "usage" do
    defp usage do
      %{
        title_id: "t",
        studio_id: "s",
        totals: %{invocations: 150, errors: 3, wall_us: 300_000, bytes_in: 2048, bytes_out: 5_242_880, events: 12},
        plugins: [
          %{
            plugin_id: "wallet",
            plugin: %{starts: 2, restarts: 1, events: 4, host_calls: 9, cpu_ms: 0, peak_rss_kb: 0, uptime_ms: 0},
            actions: [%{action: "credit", invocations: 100, errors: 3, wall_us: 200_000, avg_wall_us: 2000, bytes_in: 1024, bytes_out: 2048}]
          },
          %{
            plugin_id: "achievements",
            plugin: %{starts: 1, restarts: 0, events: 8, host_calls: 1, cpu_ms: 0, peak_rss_kb: 0, uptime_ms: 0},
            actions: [%{action: "list", invocations: 50, errors: 0, wall_us: 100_000, avg_wall_us: 2000, bytes_in: 1024, bytes_out: 3_000_000}]
          }
        ]
      }
    end

    test "totals, extensions and error rate are shown, and a row opens into its actions" do
      StubMetering.put(usage())
      socket = start(MeteringView)
      html = html(MeteringView, socket)

      assert html =~ "150"
      assert html =~ "2.0%"
      assert html =~ "2.0 ms"
      assert html =~ "2.0 KB / 5.0 MB"
      assert html =~ ~s(id="usage-wallet")
      refute html =~ "credit"

      html = MeteringView |> event(socket, "toggle", %{"id" => "wallet"}) |> then(&html(MeteringView, &1))
      assert html =~ "credit"
      refute html =~ ~s(>list<)
    end

    test "choosing a range asks for usage since that moment, and all time asks for no limit" do
      StubMetering.put(usage())
      socket = start(MeteringView)
      assert StubMetering.since() |> is_integer()

      before = System.os_time(:second)
      event(MeteringView, socket, "range", %{"range" => "1h"})
      assert_in_delta StubMetering.since(), before - 3_600, 5

      event(MeteringView, socket, "range", %{"range" => "all"})
      assert StubMetering.since() == nil

      # an unknown range is ignored
      assert event(MeteringView, socket, "range", %{"range" => "forever"}).assigns.range == "24h"
    end

    test "with nothing recorded it says so instead of drawing empty tiles" do
      StubMetering.put(%{totals: %{}, plugins: []})
      html = html(MeteringView, start(MeteringView))

      assert html =~ "No usage in this range yet"
      refute html =~ "Share of calls"
    end

    test "the helpers read like a person would" do
      assert MeteringView.since("24h", 100_000) == 100_000 - 86_400
      assert MeteringView.since("all", 1) == nil
      assert MeteringView.bytes(0) == "0 B"
      assert MeteringView.bytes(1536) == "1.5 KB"
      assert MeteringView.avg_ms(0, 0) == "-"
      assert MeteringView.avg_ms(3_000, 3) == "1.0 ms"
      assert MeteringView.error_rate(1, 4) == "25.0%"
      assert MeteringView.error_rate(0, 0) == "0%"
    end
  end

  describe "scheduled tasks" do
    defp jobs do
      now = DateTime.utc_now() |> DateTime.add(-300) |> DateTime.to_iso8601()

      [
        %{id: "brainrot_market:tick_prices", name: "tick_prices", service: "brainrot_market", action: "tick_prices", schedule: "* * * * *", description: "Random-walks prices", last_run: now, last_latency_ms: 12, last_status: "ok", run_count: 41},
        %{id: "wallet:nightly", name: "nightly", service: "wallet", action: "reconcile", schedule: "30 3 * * *", description: "", last_run: nil, last_latency_ms: nil, last_status: nil, run_count: 0}
      ]
    end

    test "jobs show their schedule in words, the last result and how long ago it ran" do
      StubCron.put(jobs())
      html = html(CronView, start(CronView))

      assert html =~ "every minute"
      assert html =~ "every day at 03:30"
      assert html =~ "5 min ago"
      assert html =~ "Not yet"
      assert html =~ "12 ms"
      assert html =~ "Random-walks prices"
    end

    test "running a job asks first, names the action, and calls it only after the confirmation" do
      StubCron.put(jobs())
      socket = start(CronView) |> then(&event(CronView, &1, "ask", %{"id" => "wallet:nightly"}))

      assert html(CronView, socket) =~ "wallet.reconcile"
      assert StubCron.ran() == []

      socket = event(CronView, socket, "run", %{})
      assert StubCron.ran() == ["wallet:nightly"]
      assert html(CronView, socket) =~ "wallet:nightly ran."

      cancelled = start(CronView) |> then(&event(CronView, &1, "ask", %{"id" => "wallet:nightly"})) |> then(&event(CronView, &1, "cancel", %{}))
      refute html(CronView, cancelled) =~ "Yes, run it"
      assert StubCron.ran() == ["wallet:nightly"]
    end

    test "with no jobs it explains how one is declared" do
      html = html(CronView, start(CronView))
      assert html =~ "No scheduled tasks"
      assert html =~ "[ExoCron"
    end

    test "schedules and times are described, anything unusual is left as written" do
      assert CronView.describe("*/5 * * * *") == "every 5 minutes"
      assert CronView.describe("0 * * * *") == "every hour"
      assert CronView.describe("0 0 * * *") == "every day at 00:00"
      assert CronView.describe("15 4 * * *") == "every day at 04:15"
      assert CronView.describe("@daily") == "@daily"
      assert CronView.describe("0 9 * * 1") == "0 9 * * 1"

      now = ~U[2026-01-01 12:00:00Z]
      assert CronView.ago(nil, now) == "Not yet"
      assert CronView.ago("2026-01-01T11:59:30Z", now) == "30s ago"
      assert CronView.ago("2026-01-01T09:00:00Z", now) == "3 h ago"
      assert CronView.ago("2025-12-30T12:00:00Z", now) == "2 d ago"
    end
  end
end
