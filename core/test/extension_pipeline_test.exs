defmodule Exoforge.ExtensionPipelineTest do
  @moduledoc """
  End-to-end kernel test: an extension is registered, loaded through the runner,
  and receives a contract event it handles — emit -> subscribe -> deliver -> handle.
  """
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.ElixirExtensionRunner
  alias Exoforge.ExtensionRegistry

  setup do
    start_supervised!(Exoforge.EventDispatcher)
    start_supervised!(ExtensionRegistry)
    start_supervised!(Exoforge.ExtensionSupervisor)
    :ok
  end

  test "extension handles contract events through the runner" do
    Process.register(self(), :pipeline_spy)

    [{extension, _}] =
      Code.compile_string("""
      defmodule Exoforge.Fixture.PipelineExtension do
        use Exoforge.Extension, provides: [:lldb]

        @impl true
        defaction connection_config(_payload), do: {:ok, %{url: "", pool_size: 1, driver: :test}}

        @impl true
        defaction health_check(), do: {:ok, %{status: "ok"}}

        handle_event connection_lost(payload) do
          send(:pipeline_spy, {:handled, payload})
          :ok
        end
      end
      """)

    manifest = %Manifest{
      id: :pipeline_extension,
      name: "pipeline_extension",
      version: "0.1.0",
      entry_point: extension
    }

    # the canonical event id: contract module + camelized event name
    assert extension.handled_events() == [Exoforge.Std.Services.Lldb.ConnectionLost]

    assert :ok = ExtensionRegistry.register(manifest)
    assert {:ok, _sup} = ElixirExtensionRunner.load(manifest)

    assert {:ok, Exoforge.Std.Services.Lldb.ConnectionLost} = extension.connection_lost("timeout", 123)
    assert_receive {:handled, %{reason: "timeout", timestamp: 123}}, 1000
  end
end
