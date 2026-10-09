defmodule Exoforge.Std.MeteringTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.Std.Metering.Flusher

  setup do
    PluginRegistry.initialize_ets()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    unless Process.whereis(Flusher) do
      start_supervised!(Flusher)
    end

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_metering,
      name: "exoforge_std_metering",
      version: "0.1.0",
      entry_point: Exoforge.Std.Metering,
      provides: [Exoforge.Std.Services.Metering],
      dependencies: [Exoforge.Std.Services.Database]
    })

    Exoforge.Std.Metering.init_schema()

    # Unique per test: the counters are a shared table, and so is the Flusher's delta memory.
    %{plugin: "metered_#{System.unique_integer([:positive])}"}
  end

  defp usage(plugin_id), do: ActionDispatcher.dispatch(:metering, :usage, %{plugin_id: plugin_id})

  test "persists the counters and serves the rollup", %{plugin: id} do
    Exoforge.Metering.record_start(id)
    Exoforge.Metering.record_invocation(id, :ping, 100, :ok, 10, 20)
    Exoforge.Metering.record_event(id, :value_changed)
    Exoforge.Metering.record_host_call(id, :db_get)

    assert {:ok, result} = usage(id)

    assert result.title_id == "local"
    assert result.studio_id == "local"

    assert result.totals == %{
             invocations: 1,
             errors: 0,
             wall_us: 100,
             bytes_in: 10,
             bytes_out: 20,
             events: 1,
             host_calls: 1,
             starts: 1,
             cpu_ms: 0,
             peak_rss_kb: 0
           }

    assert [%{plugin_id: ^id, plugin: plugin, actions: [action]}] = result.plugins

    assert plugin.starts == 1
    assert plugin.restarts == 0
    assert plugin.events == 1
    assert plugin.host_calls == 1

    assert action.action == "ping"
    assert action.invocations == 1
    assert action.errors == 0
    assert action.wall_us == 100
    assert action.avg_wall_us == 100
    assert action.bytes_in == 10
    assert action.bytes_out == 20
  end

  test "a flush writes deltas, not running totals", %{plugin: id} do
    Exoforge.Metering.record_invocation(id, :ping, 100, :ok, 0, 0)

    assert {:ok, first} = usage(id)
    assert first.totals.invocations == 1

    # Nothing new: the second flush has nothing to write and the total does not move.
    assert {:ok, second} = usage(id)
    assert second.totals.invocations == 1

    Exoforge.Metering.record_invocation(id, :ping, 50, :error, 1, 2)

    assert {:ok, third} = usage(id)
    assert third.totals.invocations == 2
    assert third.totals.errors == 1
    assert third.totals.wall_us == 150
    assert third.totals.bytes_in == 1
  end

  if File.exists?("/proc/self/stat") do
    test "persists sampled CPU and peak RSS", %{plugin: id} do
      Exoforge.Metering.sample_os(id, String.to_integer(System.pid()))

      assert {:ok, result} = usage(id)
      assert result.totals.cpu_ms > 0
      assert result.totals.peak_rss_kb > 0
    end
  end

  test "filters by plugin and by time", %{plugin: id} do
    Exoforge.Metering.record_invocation(id, :ping, 1, :ok, 0, 0)

    assert {:ok, all} = usage(id)
    assert all.totals.invocations == 1

    # A `since` in the future excludes what is already stored.
    assert {:ok, future} =
             ActionDispatcher.dispatch(:metering, :usage, %{
               plugin_id: id,
               since: System.system_time(:second) + 3600
             })

    assert future.totals.invocations == 0
    assert future.plugins == []
  end
end
