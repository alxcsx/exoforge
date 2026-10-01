defmodule Exoforge.PlayerDataTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.PlayerData
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.PluginRegistry
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher

  setup do
    PluginRegistry.initialize_ets()
    start_supervised!({DbManager, [driver: :sandbox]})

    unless Process.whereis(Exoforge.EventDispatcher.registry_name()) do
      start_supervised!(Exoforge.EventDispatcher)
    end

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_auth,
      name: "exoforge_std_auth",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [Exoforge.Std.Services.Auth],
      dependencies: [Exoforge.Std.Services.Database]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_player_data,
      name: "exoforge_std_player_data",
      version: "0.1.0",
      entry_point: Exoforge.Std.PlayerData,
      provides: [Exoforge.Std.Services.PlayerData],
      dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth]
    })

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
                 profile: %{"name" => "Arthur", "level" => 1, "class" => "paladin"}
               })

      assert result.player["name"] == "Arthur"
      assert result.player["level"] == 1

      # Verify event was broadcast
      assert_receive {:exo_event, Exoforge.Std.Services.PlayerData.PlayerCreated, payload, _opts}
      assert payload.player_id == "hero_1"

      # Verify get_player returns the created player
      assert {:ok, %{player: player}} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{player_id: "hero_1"})

      assert player["name"] == "Arthur"
      assert player["class"] == "paladin"
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
end
