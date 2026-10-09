defmodule Exoforge.AuthTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Auth
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.ActionDispatcher

  # Minimal in-memory player store, so auth's create / look-up / rename paths behave like the
  # real plugin_data (a fixed stub cannot tell a new player from an existing one).
  defmodule StubPlayerData do
    use Exoforge.Plugin, provides: [Exoforge.Std.Services.PlayerData]

    @table :stub_player_data

    defp table do
      case :ets.info(@table) do
        :undefined -> :ets.new(@table, [:set, :public, :named_table])
        _ -> @table
      end
    end

    defp id(payload), do: payload[:player_id] || payload["player_id"]

    defaction create_player(payload) do
      profile = payload[:profile] || payload["profile"] || %{}
      pid = to_string(profile["player_id"] || id(payload))
      profile = Map.put(profile, "player_id", pid)
      :ets.insert(table(), {pid, profile})
      {:ok, %{player: profile}}
    end

    defaction get_player(payload) do
      pid = id(payload)

      case :ets.lookup(table(), pid) do
        [{^pid, profile}] -> {:ok, %{player: profile}}
        _ -> {:error, :player_not_found}
      end
    end

    defaction update_player(payload) do
      pid = id(payload)
      data = payload[:data] || payload["data"] || %{}

      case :ets.lookup(table(), pid) do
        [{^pid, profile}] ->
          updated = Map.merge(profile, data)
          :ets.insert(table(), {pid, updated})
          {:ok, %{player: updated}}

        _ ->
          {:error, :player_not_found}
      end
    end

    defaction(delete_player(_payload), do: {:ok, %{status: "deleted"}})
    defaction(retain_player(_payload), do: {:ok, %{status: "retained"}})
    defaction(list_players(_payload), do: {:ok, %{players: []}})
    defaction(get_data(_payload), do: {:ok, %{key: "", value: nil}})
    defaction(set_data(_payload), do: {:ok, %{key: "", value: nil}})
    defaction(delete_data(_payload), do: {:ok, %{status: "deleted"}})
    defaction(get_all_data(_payload), do: {:ok, %{data: %{}}})
  end

  setup do
    Exoforge.PluginCase.allow_dev_tokens()

    if :ets.info(:stub_player_data) != :undefined do
      :ets.delete_all_objects(:stub_player_data)
    end

    Exoforge.PluginCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    Exoforge.PluginCase.register_database(Exoforge.Std.Database)
    Exoforge.PluginCase.register_auth(Exoforge.Std.Auth)

    Exoforge.PluginCase.register_plugin(StubPlayerData,
      id: :exoforge_std_player_data,
      provides: [Exoforge.Std.Services.PlayerData],
      dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth]
    )

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

    test "rejects dev tokens when disabled" do
      Application.put_env(:exoforge, :allow_dev_tokens, false)

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: "dev:hero_99"})
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

  describe "Player Registration & Auth Hook" do
    test "register action creates credentials, token, and player_data profile" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:auth, :register, %{
                 player_id: "p_lancelot",
                 name: "Sir Lancelot",
                 email: "lance@camelot.io",
                 scopes: ["player", "knight"]
               })

      assert result.player_id == "p_lancelot"
      assert is_binary(result.token)
      assert "knight" in result.scopes
      assert result.player["name"] == "Sir Lancelot"

      # Verify token authenticates successfully
      assert {:ok, auth_res} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: result.token})
      assert auth_res.player_id == "p_lancelot"
      assert "knight" in auth_res.scopes

      # Verify player profile was hooked and stored in player_data
      assert {:ok, %{player: profile}} =
               ActionDispatcher.dispatch(:player_data, :get_player, %{player_id: "p_lancelot"})

      assert profile["name"] == "Sir Lancelot"
      assert profile["email"] == "lance@camelot.io"
    end

    test "list_users action returns registered users and active token counts" do
      # Register two users
      {:ok, _u1} = ActionDispatcher.dispatch(:auth, :register, %{player_id: "user_alpha", scopes: ["player", "admin"]})
      {:ok, _u2} = ActionDispatcher.dispatch(:auth, :register, %{player_id: "user_beta", scopes: ["player"]})

      # Issue additional token for user_alpha
      {:ok, _t2} = ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: "user_alpha"})

      assert {:ok, %{users: users, count: count}} = ActionDispatcher.dispatch(:auth, :list_users, %{})
      assert count >= 2

      alpha = Enum.find(users, &(&1["player_id"] == "user_alpha"))
      assert alpha != nil
      assert "admin" in alpha["scopes"]
      assert alpha["tokens_count"] >= 2
      assert length(alpha["active_tokens"]) >= 2

      beta = Enum.find(users, &(&1["player_id"] == "user_beta"))
      assert beta != nil
      assert beta["tokens_count"] >= 1
    end

    test "dashboard_view returns extension visualization metadata" do
      view_meta = Auth.dashboard_view()
      assert view_meta.id == :auth
      assert view_meta.title == "Users & Auth"
      assert view_meta.icon == "🛡️"
    end
  end

  describe "Role hierarchy" do
    test "derives role and rank from scopes" do
      assert Auth.role(["admin"]) == :admin
      assert Auth.role(["studio"]) == :studio
      assert Auth.role(["player"]) == :player
      assert Auth.role(["guest"]) == :guest
      assert Auth.role(["player", "studio"]) == :studio

      assert Auth.role_rank(["player"]) == 1
      assert Auth.role_rank(["studio"]) == 2
      assert Auth.role_rank(["admin"]) == 3
      assert Auth.role_rank([]) == 0
    end

    test "verify_scope honors the hierarchy" do
      {:ok, _} = Auth.set_player_scopes("stu_scope", ["studio"])

      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{player_id: "stu_scope", required_scope: "player"})

      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{player_id: "stu_scope", required_scope: "studio"})

      assert {:ok, %{authorized: false}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{player_id: "stu_scope", required_scope: "admin"})
    end

    test "login returns a studio role for studio accounts" do
      {:ok, _} = Auth.upsert_account("studio", "studio@exoforge.test", "pw", ["studio"])

      assert {:ok, %{role: :studio, scopes: scopes}} =
               ActionDispatcher.dispatch(:auth, :login, %{email: "studio@exoforge.test", password: "pw"})

      assert "studio" in scopes
    end
  end

  describe "Admin account bootstrap & login" do
    test "ensure_admin_account creates the configured admin and login issues a token" do
      with_admin_env("root@exoforge.test", "s3cret")

      assert :ok = Auth.ensure_admin_account()

      assert {:ok, %{player_id: "admin", token: token, scopes: scopes}} =
               ActionDispatcher.dispatch(:auth, :login, %{email: "root@exoforge.test", password: "s3cret"})

      assert is_binary(token)
      assert "admin" in scopes

      assert {:ok, %{player_id: "admin", scopes: authed_scopes}} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})

      assert "admin" in authed_scopes
    end

    test "login rejects a wrong password or unknown account" do
      with_admin_env("root2@exoforge.test", "right")

      assert :ok = Auth.ensure_admin_account()

      assert {:error, :invalid_credentials} =
               ActionDispatcher.dispatch(:auth, :login, %{email: "root2@exoforge.test", password: "wrong"})

      assert {:error, :invalid_credentials} =
               ActionDispatcher.dispatch(:auth, :login, %{email: "nobody@exoforge.test", password: "right"})
    end
  end

  describe "User account management actions" do
    test "register with password allows immediate login" do
      payload = %{
        player_id: "user_pw_test",
        email: "pwuser@exoforge.test",
        password: "secret_password_123",
        scopes: ["player"]
      }

      assert {:ok, %{player_id: "user_pw_test"}} = ActionDispatcher.dispatch(:auth, :register, payload)

      assert {:ok, %{player_id: "user_pw_test", token: token}} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "pwuser@exoforge.test",
                 password: "secret_password_123"
               })

      assert is_binary(token)
    end

    test "reset_password updates user credentials" do
      {:ok, _} =
        ActionDispatcher.dispatch(:auth, :register, %{
          player_id: "reset_me",
          email: "resetme@exoforge.test",
          password: "initial_pass"
        })

      assert {:ok, %{status: "password_reset"}} =
               ActionDispatcher.dispatch(:auth, :reset_password, %{
                 player_id: "reset_me",
                 password: "new_secret_pass"
               })

      assert {:error, :invalid_credentials} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "resetme@exoforge.test",
                 password: "initial_pass"
               })

      assert {:ok, %{player_id: "reset_me"}} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "resetme@exoforge.test",
                 password: "new_secret_pass"
               })
    end

    test "update_user_roles updates scopes for user" do
      {:ok, _} =
        ActionDispatcher.dispatch(:auth, :register, %{
          player_id: "role_changer",
          email: "roles@exoforge.test"
        })

      assert {:ok, %{scopes: ["player", "studio"]}} =
               ActionDispatcher.dispatch(:auth, :update_user_roles, %{
                 player_id: "role_changer",
                 scopes: ["player", "studio"]
               })

      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "role_changer",
                 required_scope: "studio"
               })
    end

    test "delete_user removes account and tokens" do
      {:ok, %{token: token}} =
        ActionDispatcher.dispatch(:auth, :register, %{
          player_id: "to_delete",
          email: "del@exoforge.test"
        })

      assert {:ok, %{status: "deleted"}} =
               ActionDispatcher.dispatch(:auth, :delete_user, %{player_id: "to_delete"})

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})
    end

    test "protected env admin cannot be deleted, roles modified, or password reset via user actions" do
      with_admin_env("envadmin@exoforge.test", "adm_pass")
      assert :ok = Auth.ensure_admin_account()

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch(:auth, :delete_user, %{player_id: "admin"})

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch(:auth, :delete_user, %{player_id: "envadmin@exoforge.test"})

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch(:auth, :update_user_roles, %{
                 player_id: "admin",
                 scopes: ["player"]
               })

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch(:auth, :reset_password, %{
                 player_id: "admin",
                 password: "hacked"
               })
    end
  end

  describe "Anonymous sessions (two stage)" do
    test "enters an unnamed account for a device, then names it" do
      device = "dev_test_#{System.unique_integer([:positive])}"

      # Stage 1: first sight of the device registers the account, with no display name.
      assert {:ok, first} = ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: device})
      assert first.player_id == device
      assert first.name == ""
      assert is_binary(first.token)

      # Re-entering the same device resolves to the same player, still unnamed.
      assert {:ok, second} = ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: device})
      assert second.player_id == device
      assert second.name == ""

      # Stage 2: the signed-in player names themselves.
      assert {:ok, %{name: "Viper"}} =
               ActionDispatcher.dispatch(:auth, :set_display_name, %{
                 player_id: device,
                 name: "  Viper  "
               })

      # The name now comes back with the session.
      assert {:ok, third} = ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: device})
      assert third.name == "Viper"
    end

    test "rejects an empty display name" do
      device = "dev_test_#{System.unique_integer([:positive])}"
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: device})

      assert {:error, :invalid_attributes} =
               ActionDispatcher.dispatch(:auth, :set_display_name, %{player_id: device, name: "   "})
    end

    test "set_display_name requires an identity" do
      assert {:error, :unauthorized} =
               ActionDispatcher.dispatch(:auth, :set_display_name, %{name: "Viper"})
    end
  end

  # An integration run creates accounts by the dozen and they were indistinguishable from a player who
  # signed up, so cleaning up after one meant wiping the database. A disposable account says so at
  # registration, and a purge removes only those.
  test "a disposable account is marked, survives a role change, and is purged" do
    assert {:ok, _} =
             ActionDispatcher.dispatch(:auth, :anonymous, %{
               player_id: "dev_disposable",
               disposable: true
             })

    # Registered beside it and not disposable: a purge has to leave it alone.
    assert {:ok, _} = ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: "dev_kept"})

    # Changing roles must not quietly make a disposable account permanent.
    assert {:ok, _} =
             ActionDispatcher.dispatch(:auth, :update_user_roles, %{
               player_id: "dev_disposable",
               scopes: ["player"]
             })

    assert {:ok, %{purged: 1, dry_run: true}} =
             ActionDispatcher.dispatch(:auth, :purge_disposable, %{dry_run: true},
               caller_scopes: ["studio"]
             )

    # A dry run reports without removing.
    assert player_row("dev_disposable")

    assert {:ok, %{purged: 1}} =
             ActionDispatcher.dispatch(:auth, :purge_disposable, %{}, caller_scopes: ["studio"])

    refute player_row("dev_disposable")
    assert player_row("dev_kept")

    # The tokens went with it, and the other account kept its own.
    assert token_count("dev_disposable") == 0
    assert token_count("dev_kept") == 1
  end

  defp player_row(player_id) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT player_id FROM players WHERE player_id = $1",
           arguments: [player_id]
         }) do
      {:ok, %{rows: [row | _]}} -> row["player_id"] || row[:player_id]
      _ -> nil
    end
  end

  defp token_count(player_id) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT count(*) as n FROM tokens WHERE player_id = $1",
           arguments: [player_id]
         }) do
      {:ok, %{rows: [row | _]}} -> row["n"] || row[:n]
      _ -> 0
    end
  end

  defp with_admin_env(email, password) do
    previous = {System.get_env("EXOFORGE_ADMIN_EMAIL"), System.get_env("EXOFORGE_ADMIN_PASSWORD")}
    System.put_env("EXOFORGE_ADMIN_EMAIL", email)
    System.put_env("EXOFORGE_ADMIN_PASSWORD", password)

    on_exit(fn ->
      restore_env("EXOFORGE_ADMIN_EMAIL", elem(previous, 0))
      restore_env("EXOFORGE_ADMIN_PASSWORD", elem(previous, 1))
    end)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
