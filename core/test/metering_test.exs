defmodule Exoforge.MeteringTest do
  use ExUnit.Case, async: false

  alias Exoforge.Metering

  # Every test uses its own plugin id: the counters are a shared ETS table, and the runner tests
  # write to it too.
  defp plugin_id, do: "meter_test_#{System.unique_integer([:positive])}"

  test "aggregates calls per plugin and action" do
    id = plugin_id()

    Metering.record_invocation(id, :ping, 100, :ok, 10, 20)
    Metering.record_invocation(id, "ping", 300, :ok, 10, 40)
    Metering.record_invocation(id, :ping, 50, :error, 5, 0)

    assert %{plugins: [usage]} = Metering.snapshot(id)

    assert usage.plugin_id == id

    assert [%{action: "ping", invocations: 3, errors: 1, wall_us: 450, avg_wall_us: 150, bytes_in: 25, bytes_out: 60}] =
             usage.actions
  end

  test "counts events, host calls, starts and restarts" do
    id = plugin_id()

    Metering.record_start(id)
    Metering.record_start(id)
    Metering.record_event(id, :value_changed)
    Metering.record_event(id, "value_changed")
    Metering.record_host_call(id, "db_get")
    Metering.record_host_call(id, "db_get")
    Metering.record_host_call(id, :emit_event)

    assert %{plugins: [usage]} = Metering.snapshot(id)

    assert usage.plugin.starts == 2
    assert usage.plugin.restarts == 1
    assert is_integer(usage.plugin.started_at)
    assert usage.plugin.uptime_ms >= 0
    assert usage.plugin.events == 2
    assert usage.plugin.host_calls == 3
    assert usage.events == [%{event: "value_changed", count: 2}]

    assert usage.host_calls == [
             %{op: "db_get", count: 2},
             %{op: "emit_event", count: 1}
           ]
  end

  test "stamps the instance's title and studio on the snapshot" do
    id = plugin_id()
    Metering.record_invocation(id, :ping, 1, :ok, 0, 0)

    assert %{title_id: "local", studio_id: "local"} = Metering.snapshot(id)
  end

  test "an unknown plugin has no usage" do
    assert Metering.snapshot("never_seen_#{System.unique_integer([:positive])}").plugins == []
  end

  if File.exists?("/proc/self/stat") do
    test "samples CPU and peak RSS from the OS process" do
      id = plugin_id()
      os_pid = String.to_integer(System.pid())

      assert :ok = Metering.sample_os(id, os_pid)
      assert :ok = Metering.sample_os(id, os_pid)

      assert %{plugins: [usage]} = Metering.snapshot(id)
      assert usage.plugin.peak_rss_kb > 0
      assert usage.plugin.cpu_ms > 0
    end
  end

  test "sampling a process that does not exist is a no-op" do
    id = plugin_id()

    assert :ok = Metering.sample_os(id, 999_999_999)
    assert Metering.snapshot(id).plugins == []
  end

  test "a snapshot with no argument includes every plugin" do
    id = plugin_id()
    Metering.record_invocation(id, :ping, 1, :ok, 0, 0)

    assert Enum.any?(Metering.snapshot().plugins, &(&1.plugin_id == id))
  end
end
