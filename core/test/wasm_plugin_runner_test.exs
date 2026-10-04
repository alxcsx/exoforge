defmodule Exoforge.WasmPluginRunnerTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.EventDispatcher
  alias Exoforge.ActionDispatcher
  alias Exoforge.Drivers.Runtime.WasmPluginRunner

  @fixture_path Path.expand("test/fixtures/sample_wasm.wasm")

  setup do
    start_supervised!({PluginRegistry, []})
    start_supervised!(Exoforge.WorkerRegistry)
    start_supervised!(Exoforge.EventDispatcher)
    start_supervised!({DynamicSupervisor, name: Exoforge.PluginSupervisor, strategy: :one_for_one})

    manifest = %Manifest{
      id: :sample_wasm,
      name: "Sample WASM Plugin",
      version: Version.parse!("1.0.0"),
      entry_point: "sample_wasm.wasm",
      type: :wasm,
      provides: [:sample_wasm],
      dependencies: [:database],
      physical_path: Path.dirname(@fixture_path),
      services: [
        %{
          name: :sample_wasm,
          actions: [
            %{name: :ping, mode: :sync, scope: :global, arity: 0, params: [], returns: :integer},
            %{
              name: :increment,
              mode: :sync,
              scope: :global,
              arity: 2,
              params: [counter_id: :integer, amount: :integer],
              returns: :integer
            },
            %{name: :echo, mode: :sync, scope: :global, arity: 1, params: [value: :integer], returns: :integer}
          ],
          events: [
            %{name: :value_changed, topic: "sample:events", scope: :global}
          ],
          resources: [
            %{
              name: :counters,
              primary_key: :counter_id,
              drawer: [:overview, :attributes],
              actions: [:ping, :increment, :echo],
              columns: [
                %{name: :counter_id, type: :integer, label: "Counter ID", sortable: true, filterable: true, badge: false},
                %{
                  name: :value,
                  type: :integer,
                  label: "Value",
                  sortable: true,
                  filterable: false,
                  badge: false
                },
                %{
                  name: :status,
                  type: :string,
                  label: "Status",
                  sortable: false,
                  filterable: false,
                  badge: true
                }
              ]
            }
          ]
        }
      ]
    }

    PluginRegistry.register(manifest)
    {:ok, _sup_pid} = WasmPluginRunner.load(manifest)

    %{manifest: manifest}
  end

  test "executes direct ping action returning integer value" do
    assert {:ok, 42} = ActionDispatcher.dispatch(:sample_wasm, :ping, [])
  end

  test "executes increment action and verifies event broadcast" do
    EventDispatcher.subscribe(:value_changed, topic: "sample:events")

    assert {:ok, 35} = ActionDispatcher.dispatch(:sample_wasm, :increment, [1, 35])

    assert_receive {:exo_event, :value_changed, payload, context}, 1000
    assert context.topic == "sample:events"
    assert is_map(payload)
    assert payload["new_value"] == 35
    assert payload["counter_id"] == 1
  end

  test "executes increment action with map payload mapped to parameters", %{manifest: _manifest} do
    EventDispatcher.subscribe(:value_changed, topic: "sample:events")

    assert {:ok, 35} =
             ActionDispatcher.dispatch(:sample_wasm, :increment, %{
               "counter_id" => 1,
               "amount" => 35
             })

    assert_receive {:exo_event, :value_changed, _payload, _context}, 1000
  end

  test "executes echo action returning input value" do
    assert {:ok, 99} = ActionDispatcher.dispatch(:sample_wasm, :echo, [99])
  end

  test "proxy module acts as a first-class plugin façade", %{manifest: manifest} do
    mod = WasmPluginRunner.proxy_module(manifest)

    assert mod.__exoforge_plugin__?() == true
    assert function_exported?(mod, :manifest, 0)
    assert mod.manifest().id == :sample_wasm
    assert mod.provides_contracts() == [:sample_wasm]
    assert mod.handled_events() == []
    assert mod.children() == []
    assert mod.init(manifest) == :ok

    metadata = mod.__service_metadata__()
    assert metadata.name == :sample_wasm
    assert length(metadata.actions) == 3
    assert length(metadata.resources) == 1
    assert hd(metadata.resources).name == :counters
  end

  test "returns error when action is not exported" do
    assert {:error, {:action_not_exported, "unknown_action"}} =
             ActionDispatcher.dispatch(:sample_wasm, :unknown_action, [])
  end

  test "records traps for observability when errors occur" do
    initial_stats = WasmPluginRunner.get_stats(:sample_wasm)
    assert is_map(initial_stats)

    # Calling an unknown action or a faulting action records stats
    WasmPluginRunner.record_trap(:sample_wasm, "test_trap_fault")
    updated_stats = WasmPluginRunner.get_stats(:sample_wasm)

    assert updated_stats.traps_count >= 1
    assert updated_stats.last_trap == "test_trap_fault"
    assert updated_stats.last_trap_at != nil
  end

  test "handles inbound events gracefully without crashing" do
    assert :ok = WasmPluginRunner.dispatch_event(:sample_wasm, :some_event, %{id: 123})
  end

  test "plugin registry discovers resources from WASM service metadata directly" do
    resources = PluginRegistry.all_resources()
    assert Enum.any?(resources, fn r -> r.resource.name == :counters end)

    assert {:ok, found} = PluginRegistry.fetch_resource(:counters)
    assert found.plugin_id == :sample_wasm
    assert found.resource.primary_key == :counter_id
  end
end
