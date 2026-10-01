defmodule Exoforge.AuthTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Auth
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.PluginRegistry
  alias Exoforge.ActionDispatcher

  setup do
    PluginRegistry.initialize_ets()
    start_supervised!({DbManager, [driver: :sandbox]})

    # Register database plugin in registry
    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    # Register auth plugin in registry
    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_auth,
      name: "exoforge_std_auth",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [Exoforge.Std.Services.Auth],
      dependencies: [Exoforge.Std.Services.Database]
    })

    Auth.init_schema()
    :ok
  end

  describe "Authentication" do
    test "authenticates issued tokens" do
      {:ok, token} = Auth.issue_token("player_42", ["player", "vip"])

      # Test via ActionDispatcher
      assert {:ok, result} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})
      assert result.player_id == "player_42"
      assert "vip" in result.scopes
      assert "player" in result.scopes
    end

    test "handles dev tokens" do
      assert {:ok, result} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: "dev:hero_99"})
      assert result.player_id == "hero_99"
      assert "admin" in result.scopes
    end

    test "handles guest token" do
      assert {:ok, result} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: "guest"})
      assert result.player_id == "guest_anon"
      assert "guest" in result.scopes
    end

    test "rejects invalid or unknown token" do
      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: "non_existent_token"})

      assert {:error, :invalid_token} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: ""})
    end
  end

  describe "Scope Verification" do
    test "verifies required scopes" do
      _ = Auth.set_player_scopes("alice", ["player", "moderator"])

      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "alice",
                 required_scope: "moderator"
               })

      assert {:ok, %{authorized: false}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "alice",
                 required_scope: "superadmin"
               })
    end

    test "admin override allows any scope" do
      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "admin",
                 required_scope: "anything"
               })
    end
  end
end
