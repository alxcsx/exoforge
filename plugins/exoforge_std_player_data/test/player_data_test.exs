defmodule Exoforge.PlayerDataTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.PlayerData
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher

  setup do
    Exoforge.PluginCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    Exoforge.PluginCase.register_database(Exoforge.Std.Database)
    Exoforge.PluginCase.register_auth(Exoforge.Std.Auth)

    Exoforge.PluginCase.register_plugin(Exoforge.Std.PlayerData,
      id: :exoforge_std_player_data,
      provides: [Exoforge.Std.Services.PlayerData],
      dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth]
    )

    PlayerData.init_schema()
    :ok
  end

  describe "Player Lifecycle and Persistence" do
    test "creates player and emits player_created event" do
      # Subscribe to player_created event
      EventDispatcher.subscribe(Exoforge.Std.Services.PlayerData.PlayerCreated)

      assert {:ok, result} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: "hero_1",
                 user_id: "u_arthur",
                 profile: %{"name" => "Arthur", "level" => 1, "class" => "paladin"}
               })

      assert result.player["name"] == "Arthur"
      assert result.player["level"] == 1
      assert result.player["user_id"] == "u_arthur"

      # Verify event was broadcast
      assert_receive {:exo_event, Exoforge.Std.Services.PlayerData.PlayerCreated, payload, _opts}
      assert payload.player_id == "hero_1"

      # Verify get_player returns the created player
      assert {:ok, %{player: player}} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{player_id: "hero_1"})

      assert player["name"] == "Arthur"
      assert player["class"] == "paladin"
    end

    test "display names are unique across players" do
      assert {:ok, _} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: "p_a",
                 profile: %{"name" => "Viper"}
               })

      # A second player cannot take the same name, even with different casing.
      assert {:error, :name_taken} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: "p_b",
                 profile: %{"name" => "viper"}
               })

      assert {:ok, _} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: "p_c",
                 profile: %{"name" => "Cobra"}
               })

      # Renaming onto a taken name is refused; keeping your own name is fine.
      assert {:error, :name_taken} =
               ActionDispatcher.dispatch(:player_data, :update_player, %{
                 player_id: "p_c",
                 data: %{"name" => "Viper"}
               })

      assert {:ok, _} =
               ActionDispatcher.dispatch(:player_data, :update_player, %{
                 player_id: "p_c",
                 data: %{"name" => "Cobra"}
               })
    end

    test "updates player record" do
      _ =
        ActionDispatcher.dispatch(:player_data, :create_player, %{
          player_id: "hero_2",
          profile: %{"name" => "Merlin", "level" => 10}
        })

      assert {:ok, %{player: updated}} =
               ActionDispatcher.dispatch(:player_data, :update_player, %{
                 player_id: "hero_2",
                 data: %{"level" => 11, "title" => "Archmage"}
               })

      assert updated["level"] == 11
      assert updated["title"] == "Archmage"
      assert updated["name"] == "Merlin"
    end

    test "deletes player and emits player_deleted event" do
      _ =
        ActionDispatcher.dispatch(:player_data, :create_player, %{
          player_id: "hero_3",
          profile: %{"name" => "Galahad"}
        })

      # Subscribe to player_deleted
      EventDispatcher.subscribe(Exoforge.Std.Services.PlayerData.PlayerDeleted)

      assert {:ok, %{status: "deleted"}} =
               ActionDispatcher.dispatch(:player_data, :delete_player, %{player_id: "hero_3"})

      assert_receive {:exo_event, Exoforge.Std.Services.PlayerData.PlayerDeleted, payload, _opts}
      assert payload.player_id == "hero_3"

      # Subsequent get_player returns error
      assert {:error, :player_not_found} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{player_id: "hero_3"})
    end
  end

  describe "User Linking, Retention, and Filtering" do
    test "retained player without user is inaccessible by default" do
      # Create player explicitly unlinked / retained
      assert {:ok, _} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: "retained_p1",
                 user_id: nil,
                 profile: %{"name" => "Old Telemetry", "coins" => 500}
               })

      # Direct get_player should be blocked
      assert {:error, :player_not_accessible} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{player_id: "retained_p1"})

      # With allow_retained flag (for studio / admin audit), it succeeds
      assert {:ok, %{player: p}} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{
                 player_id: "retained_p1",
                 allow_retained: true
               })

      assert p["coins"] == 500
    end

    test "retain_player unlinks user and scrubs PII" do
      assert {:ok, _} =
               ActionDispatcher.dispatch(:player_data, :create_player, %{
                 player_id: "player_to_retain",
                 user_id: "u_ret_user",
                 profile: %{"name" => "John Doe", "email" => "john@example.com", "score" => 999}
               })

      assert {:ok, %{status: "retained"}} =
               ActionDispatcher.dispatch(:player_data, :retain_player, %{
                 player_id: "player_to_retain"
               })

      # Now it is inaccessible via normal ingress
      assert {:error, :player_not_accessible} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{
                 player_id: "player_to_retain"
               })

      # Accessible when allow_retained is true; PII scrubbed
      assert {:ok, %{player: p}} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{
                 player_id: "player_to_retain",
                 allow_retained: true
               })

      assert p["name"] == "Retained Player"
      assert is_nil(p["email"])
      assert p["score"] == 999
    end

    test "list_players filters active vs retained players" do
      _ =
        ActionDispatcher.dispatch(:player_data, :create_player, %{
          player_id: "active_hero",
          user_id: "u_active",
          profile: %{"name" => "Active Hero"}
        })

      _ =
        ActionDispatcher.dispatch(:player_data, :create_player, %{
          player_id: "ghost_hero",
          user_id: nil,
          profile: %{"name" => "Ghost"}
        })

      assert {:ok, %{players: valid_players}} =
               ActionDispatcher.dispatch(:player_data, :list_players, %{filter: "valid"})

      assert Enum.any?(valid_players, &(&1.player_id == "active_hero"))
      refute Enum.any?(valid_players, &(&1.player_id == "ghost_hero"))

      assert {:ok, %{players: retained_players}} =
               ActionDispatcher.dispatch(:player_data, :list_players, %{filter: "retained"})

      assert Enum.any?(retained_players, &(&1.player_id == "ghost_hero"))
      refute Enum.any?(retained_players, &(&1.player_id == "active_hero"))
    end
  end

  describe "Fine-Grained Key-Value JSON Storage" do
    test "sets, gets, deletes, and lists key-value JSON entries for player" do
      _ =
        ActionDispatcher.dispatch(:player_data, :create_player, %{
          player_id: "kv_player",
          user_id: "u_kv",
          profile: %{"name" => "KV Tester"}
        })

      # Set structured JSON state under key "inventory"
      inv_data = %{"weapons" => ["excalibur", "dagger"], "gold" => 1500}

      assert {:ok, %{key: "inventory", value: ^inv_data}} =
               ActionDispatcher.dispatch(:player_data, :set_data, %{
                 player_id: "kv_player",
                 key: "inventory",
                 value: inv_data
               })

      # Set another key "settings"
      settings_data = %{"sound" => 0.8, "graphics" => "ultra"}

      assert {:ok, %{key: "settings", value: ^settings_data}} =
               ActionDispatcher.dispatch(:player_data, :set_data, %{
                 player_id: "kv_player",
                 key: "settings",
                 value: settings_data
               })

      # Get single key
      assert {:ok, %{key: "inventory", value: retrieved_inv}} =
               ActionDispatcher.dispatch(:player_data, :get_data, %{
                 player_id: "kv_player",
                 key: "inventory"
               })

      assert retrieved_inv["gold"] == 1500
      assert "excalibur" in retrieved_inv["weapons"]

      # Get all keys as map
      assert {:ok, %{data: all_data}} =
               ActionDispatcher.dispatch(:player_data, :get_all_data, %{
                 player_id: "kv_player"
               })

      assert Map.has_key?(all_data, "inventory")
      assert Map.has_key?(all_data, "settings")
      assert all_data["settings"]["graphics"] == "ultra"

      # Delete a key
      assert {:ok, %{status: "deleted"}} =
               ActionDispatcher.dispatch(:player_data, :delete_data, %{
                 player_id: "kv_player",
                 key: "settings"
               })

      assert {:error, :key_not_found} =
               ActionDispatcher.dispatch(:player_data, :get_data, %{
                 player_id: "kv_player",
                 key: "settings"
               })
    end

    test "scans keys by prefix in get_all_data and get_data" do
      _ =
        ActionDispatcher.dispatch(:player_data, :create_player, %{
          player_id: "prefix_player",
          user_id: "u_prefix",
          profile: %{"name" => "Prefix Hero"}
        })

      # Set items under 'inv:' prefix
      _ =
        ActionDispatcher.dispatch(:player_data, :set_data, %{
          player_id: "prefix_player",
          key: "inv:weapon:sword",
          value: %{"atk" => 50, "rarity" => "rare"}
        })

      _ =
        ActionDispatcher.dispatch(:player_data, :set_data, %{
          player_id: "prefix_player",
          key: "inv:armor:shield",
          value: %{"def" => 30, "rarity" => "common"}
        })

      # Set stats under 'stats:' prefix
      _ =
        ActionDispatcher.dispatch(:player_data, :set_data, %{
          player_id: "prefix_player",
          key: "stats:hp",
          value: 100
        })

      # Prefix scan via get_all_data with prefix: "inv:"
      assert {:ok, %{data: inv_items}} =
               ActionDispatcher.dispatch(:player_data, :get_all_data, %{
                 player_id: "prefix_player",
                 prefix: "inv:"
               })

      assert Map.has_key?(inv_items, "inv:weapon:sword")
      assert Map.has_key?(inv_items, "inv:armor:shield")
      refute Map.has_key?(inv_items, "stats:hp")

      # Subtree prefix scan with prefix: "inv:weapon"
      assert {:ok, %{data: weapons}} =
               ActionDispatcher.dispatch(:player_data, :get_all_data, %{
                 player_id: "prefix_player",
                 prefix: "inv:weapon"
               })

      assert map_size(weapons) == 1
      assert Map.has_key?(weapons, "inv:weapon:sword")

      # Prefix scan via get_data with prefix: "inv:"
      assert {:ok, %{data: via_get_data}} =
               ActionDispatcher.dispatch(:player_data, :get_data, %{
                 player_id: "prefix_player",
                 prefix: "inv:"
               })

      assert Map.has_key?(via_get_data, "inv:weapon:sword")
      refute Map.has_key?(via_get_data, "stats:hp")
    end
  end

  describe "M33 hardening" do
    test "user-facing listing and deletion is staff-gated over transports (M33 Fix 3)" do
      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(:player_data, :list_players, %{}, caller_scopes: ["player"])

      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(:player_data, :delete_player, %{player_id: "someone"}, caller_scopes: ["player"])

      # The Studio is staff; its calls are unaffected.
      assert {:ok, _} = ActionDispatcher.dispatch(:player_data, :list_players, %{user_id: "someone"})
    end

    test "list_players filters by user_id in the query (M33 Fix 33)" do
      {:ok, _} = ActionDispatcher.dispatch(:player_data, :create_player, %{player_id: "p_link", user_id: "u_link"})
      {:ok, _} = ActionDispatcher.dispatch(:player_data, :create_player, %{player_id: "p_other", user_id: "u_other"})

      assert {:ok, %{players: players}} =
               ActionDispatcher.dispatch(:player_data, :list_players, %{user_id: "u_link"})

      assert [%{id: "p_link"}] = players
    end
  end
end
