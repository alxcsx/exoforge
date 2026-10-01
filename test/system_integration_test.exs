defmodule Exoforge.SystemIntegrationTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.PluginBootstrapper

  setup_all do
    # Boot the full kernel with all plugins in topological dependency order
    PluginBootstrapper.boot()
    :ok
  end

  describe "Kernel Boot and Plugin Discovery" do
    test "loads all standard plugins and WASM plugins" do
      database = PluginRegistry.fetch_service(:database)
      assert database != nil
      assert database.id == :exoforge_std_database

      auth = PluginRegistry.fetch_service(:auth)
      assert auth != nil
      assert auth.id == :exoforge_std_auth

      player_data = PluginRegistry.fetch_service(:player_data)
      assert player_data != nil
      assert player_data.id == :exoforge_std_player_data

      http = PluginRegistry.fetch_service(:http)
      assert http != nil
      assert http.id == :exoforge_std_http

      ws = PluginRegistry.fetch_service(:ws)
      assert ws != nil
      assert ws.id == :exoforge_std_ws

      dashboard = PluginRegistry.fetch_service(:dashboard_view)
      assert dashboard != nil
      assert dashboard.id == :exoforge_std_dashboard

      combat = PluginRegistry.fetch_service(:combat)
      assert combat != nil
      assert combat.type == :wasm
      assert combat.entry_point == Exoforge.Plugins.CombatWasm
      assert function_exported?(combat.entry_point, :__exoforge_plugin__?, 0)
      assert combat.entry_point.provides_contracts() == [:combat]

      # Verify combatants resource is discovered with columns derived from C# attributes
      combatants = Enum.find(PluginRegistry.all_resources(), fn r -> r.resource.name == :combatants end)
      assert combatants != nil
      assert combatants.plugin_id == :combat_wasm
      assert Enum.any?(combatants.resource.columns, fn c -> c.name == :entity_id end)
    end
  end

  describe "End-to-End Multi-Plugin Workflow with Database Isolation" do
    test "verifies database isolation between auth and player_data" do
      # Auth creates a record in its isolated database
      {:ok, _} =
        ActionDispatcher.dispatch(:database, :execute, %{
          plugin: :auth,
          operation: "INSERT INTO system_info (id, key, val) VALUES ($1, $2, $3)",
          arguments: ["1", "auth_secret", "super_secret_auth_token"]
        })

      # PlayerData queries system_info in its isolated database -> does not see Auth's record!
      {:ok, %{rows: player_system_rows}} =
        ActionDispatcher.dispatch(:database, :execute, %{
          plugin: :player_data,
          operation: "SELECT * FROM system_info"
        })

      assert player_system_rows == []

      # Auth queries its own system_info -> sees the record
      {:ok, %{rows: auth_system_rows}} =
        ActionDispatcher.dispatch(:database, :execute, %{
          plugin: :auth,
          operation: "SELECT * FROM system_info"
        })

      assert length(auth_system_rows) == 1
      assert hd(auth_system_rows)["val"] == "super_secret_auth_token"
    end

    test "complete gameplay loop: Auth -> PlayerData -> WASM Combat -> Event" do
      # 1. Subscribe to combat event
      EventDispatcher.subscribe(:player_damaged, topic: "combat:events")

      # 2. Authenticate
      assert {:ok, auth_result} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: "dev:hero_arthur"})

      assert auth_result.player_id == "hero_arthur"

      # 3. Create Player Profile
      assert {:ok, player_res} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: auth_result.player_id,
                 profile: %{"name" => "King Arthur", "hp" => 100, "attack" => 25}
               })

      assert player_res.player["name"] == "King Arthur"

      # 4. Invoke C# WASM Plugin action
      assert {:ok, _damage} =
               ActionDispatcher.dispatch(:combat, :attack, [1, 101, 25])

      # 5. Verify C# WASM host_emit_event reached EventDispatcher
      assert_receive {:exo_event, :player_damaged, event_payload, _ctx}, 1000
      assert event_payload["target_id"] == 2 or event_payload["target_id"] == 101

      # 6. Verify Dashboard overview can see everything
      assert {:ok, %{data: overview}} =
               ActionDispatcher.dispatch(:dashboard_view, :get_dashboard_data, %{view_id: :main})

      assert overview.plugins_count >= 6
      assert overview.status == "running"
    end
  end
end
