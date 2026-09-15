defmodule Exoforge.PluginPipelineTest do
  @moduledoc """
  End-to-end kernel test: a plugin is registered, loaded through the runner,
  and receives a contract event it handles — emit -> subscribe -> deliver -> handle.
  """
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.ElixirPluginRunner
  alias Exoforge.PluginRegistry

  setup do
    start_supervised!(Exoforge.EventDispatcher)
    start_supervised!(PluginRegistry)
    start_supervised!(Exoforge.PluginSupervisor)
    :ok
  end

  test "plugin handles contract events through the runner" do
    Process.register(self(), :pipeline_spy)

    [{plugin, _}] =
      Code.eval_string("""
      defmodule Exoforge.Fixture.PipelinePlugin do
        use Exoforge.Plugin, provides: [:lldb]

        handle_event connection_lost(payload) do
          send(:pipeline_spy, {:handled, payload})
          :ok
        end
      end
      """)

    manifest = %Manifest{
      id: :pipeline_plugin,
      name: "pipeline_plugin",
      version: "0.1.0",
      entry_point: plugin
    }

    # the canonical event id: contract module + camelized event name
    assert plugin.handled_events() == [Exoforge.Std.Services.Lldb.ConnectionLost]

    assert :ok = PluginRegistry.register(manifest)
    assert {:ok, _sup} = ElixirPluginRunner.load(manifest)

    assert {:ok, Exoforge.Std.Services.Lldb.ConnectionLost} = plugin.connection_lost("timeout", 123)
    assert_receive {:handled, %{reason: "timeout", timestamp: 123}}, 1000
  end
end
