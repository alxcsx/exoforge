defmodule Exoforge.WasmPluginRunnerTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.EventDispatcher
  alias Exoforge.ActionDispatcher
  alias Exoforge.Drivers.Runtime.WasmPluginRunner

  @fixture_path Path.expand("test/fixtures/combat.wasm")

  setup do
    start_supervised!({PluginRegistry, []})
    start_supervised!(Exoforge.WorkerRegistry)
    start_supervised!(Exoforge.EventDispatcher)
    start_supervised!({DynamicSupervisor, name: Exoforge.PluginSupervisor, strategy: :one_for_one})

    manifest = %Manifest{
      id: :combat_wasm,
      name: "Combat WASM Plugin",
      version: Version.parse!("1.0.0"),
      entry_point: "combat.wasm",
      type: :wasm,
      provides: [:combat],
      dependencies: [:database],
      physical_path: Path.dirname(@fixture_path),
      services: [
        %{
          name: :combat,
          actions: [
            %{name: :ping, mode: :sync, scope: :global, arity: 0, params: [], returns: :integer},
            %{name: :attack, mode: :sync, scope: :global, arity: 3, params: [attacker_id: :integer, target_id: :integer, damage: :integer], returns: :integer}
          ],
          events: [
            %{name: :player_damaged, topic: "combat:events", scope: :global}
          ],
          resources: [
            %{
              name: :combatants,
              primary_key: :entity_id,
              drawer: [:overview, :attributes, :events],
              actions: [:ping, :attack],
              columns: [
                %{name: :entity_id, type: :integer, label: "Entity ID", sortable: true, filterable: true, badge: false},
                %{name: :health, type: :integer, label: "Health Points", sortable: true, filterable: false, badge: false}
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
    assert {:ok, 42} = ActionDispatcher.dispatch(:combat, :ping, [])
    assert {:ok, 42} = ActionDispatcher.dispatch(:combat_wasm, :ping, [])
  end

  test "executes attack action and verifies event broadcast" do
    EventDispatcher.subscribe(:player_damaged, topic: "combat:events")

    assert {:ok, 35} = ActionDispatcher.dispatch(:combat, :attack, [1, 2, 35])

    assert_receive {:exo_event, :player_damaged, payload, context}, 1000
    assert context.topic == "combat:events"
    assert is_map(payload)
    assert payload["damage"] == 25
    assert payload["target_id"] == 2
  end

  test "executes attack action with map payload mapped to parameters", %{manifest: _manifest} do
    EventDispatcher.subscribe(:player_damaged, topic: "combat:events")

    assert {:ok, 35} =
             ActionDispatcher.dispatch(:combat, :attack, %{
               "attacker_id" => 1,
               "target_id" => 2,
               "damage" => 35
             })

    assert_receive {:exo_event, :player_damaged, _payload, _context}, 1000
  end

  test "proxy module acts as a first-class plugin façade", %{manifest: manifest} do
    mod = WasmPluginRunner.proxy_module(manifest)

    assert mod.__exoforge_plugin__?() == true
    assert function_exported?(mod, :manifest, 0)
    assert mod.manifest().id == :combat_wasm
    assert mod.provides_contracts() == [:combat]
    assert mod.handled_events() == []
    assert mod.children() == []
    assert mod.init(manifest) == :ok

    metadata = mod.__service_metadata__()
    assert metadata.name == :combat
    assert length(metadata.actions) == 2
    assert length(metadata.resources) == 1
    assert hd(metadata.resources).name == :combatants
  end

  test "returns error when action is not exported" do
    assert {:error, {:action_not_exported, "unknown_action"}} =
             ActionDispatcher.dispatch(:combat, :unknown_action, [])
  end

  test "records traps for observability when errors occur" do
    initial_stats = WasmPluginRunner.get_stats(:combat_wasm)
    assert is_map(initial_stats)

    # Calling an unknown action or a faulting action records stats
    WasmPluginRunner.record_trap(:combat_wasm, "test_trap_fault")
    updated_stats = WasmPluginRunner.get_stats(:combat_wasm)

    assert updated_stats.traps_count >= 1
    assert updated_stats.last_trap == "test_trap_fault"
    assert updated_stats.last_trap_at != nil
  end

  test "handles inbound events gracefully without crashing" do
    assert :ok = WasmPluginRunner.dispatch_event(:combat_wasm, :player_spawned, %{id: 123})
  end

  test "plugin registry discovers resources from WASM service metadata directly" do
    resources = PluginRegistry.all_resources()
    assert Enum.any?(resources, fn r -> r.resource.name == :combatants end)

    assert {:ok, found} = PluginRegistry.fetch_resource(:combatants)
    assert found.plugin_id == :combat_wasm
    assert found.resource.primary_key == :entity_id
  end
end
