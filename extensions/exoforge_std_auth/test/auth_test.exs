defmodule Exoforge.AuthTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Auth
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.ActionDispatcher

  # Minimal in-memory player store, so auth's create / look-up / rename paths behave like the
  # real plugin_data (a fixed stub cannot tell a new player from an existing one).
  defmodule StubPlayerData do
    use Exoforge.Extension, provides: [Exoforge.Std.Services.PlayerData]

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
    Exoforge.ExtensionCase.allow_dev_tokens()

    if :ets.info(:stub_player_data) != :undefined do
      :ets.delete_all_objects(:stub_player_data)
    end

    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!(DbManager)
    end

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)
    Exoforge.ExtensionCase.register_auth(Exoforge.Std.Auth)

    Exoforge.ExtensionCase.register_extension(StubPlayerData,
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
      assert {:ok, result} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: "dev:hero_99"})

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

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: ""})
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

    test "the administrator's scopes come from its stored row, like anyone else's" do
      assert {:ok, %{authorized: false}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "admin",
                 required_scope: "anything"
               })

      with_admin_env("root@exoforge.test", "s3cret")
      assert :ok = Auth.ensure_admin_account()

      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "admin",
                 required_scope: "admin"
               })
    end

    test "the dev_admin prefix is not a scope override in production (M33 Fix 4)" do
      Application.put_env(:exoforge, :allow_dev_tokens, false)

      assert {:ok, %{authorized: false}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "dev_admin_anyone",
                 required_scope: "admin"
               })
    after
      Application.delete_env(:exoforge, :allow_dev_tokens)
    end
  end

  describe "Sensitive actions are staff-gated over transports (M33 Fix 3)" do
    test "a player-scoped caller cannot reach them" do
      assert {:error, {:forbidden_scope, _}} =
               ActionDispatcher.dispatch(:auth, :list_users, %{}, caller_scopes: ["player"])

      assert {:error, {:forbidden_scope, _}} =
               ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: "someone"},
                 caller_scopes: ["player"]
               )
    end

    test "an unauthenticated caller without scopes is denied by default" do
      assert {:error, :unauthorized} = ActionDispatcher.dispatch(:auth, :list_users, %{})

      assert {:error, :unauthorized} =
               ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: "someone"})
    end

    test "an explicit in-process / internal caller keeps working" do
      assert {:ok, _} = ActionDispatcher.dispatch_internal(:auth, :list_users, %{})
    end
  end

  describe "Public registration scope clamp (M33 Fix 1)" do
    test "a public register cannot mint elevated scopes" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:auth, :register, %{
                 player_id: "self_escalator",
                 scopes: ["admin"],
                 # The shape a transport hands the action: an external caller's identity.
                 _auth: %{player_id: "self_escalator", scopes: ["player"]}
               })

      assert result.scopes == ["player"]

      assert {:ok, authed} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: result.token})

      refute "admin" in authed.scopes
    end

    test "an in-process caller keeps caller-chosen scopes" do
      assert {:ok, result} =
               ActionDispatcher.dispatch(:auth, :register, %{
                 player_id: "staff_maker",
                 scopes: ["player", "knight"]
               })

      assert "knight" in result.scopes
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
      assert {:ok, auth_res} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: result.token})

      assert auth_res.player_id == "p_lancelot"
      assert "knight" in auth_res.scopes

      # Verify player profile was hooked and stored in player_data
      assert {:ok, %{player: profile}} =
               ActionDispatcher.dispatch_internal(:player_data, :get_player, %{
                 player_id: "p_lancelot"
               })

      assert profile["name"] == "Sir Lancelot"
      assert profile["email"] == "lance@camelot.io"
    end

    test "list_users action returns registered users and active token counts" do
      # Register two users
      {:ok, _u1} =
        ActionDispatcher.dispatch(:auth, :register, %{
          player_id: "user_alpha",
          scopes: ["player", "admin"]
        })

      {:ok, _u2} =
        ActionDispatcher.dispatch(:auth, :register, %{player_id: "user_beta", scopes: ["player"]})

      # Issue additional token for user_alpha
      {:ok, _t2} =
        ActionDispatcher.dispatch_internal(:auth, :issue_token, %{player_id: "user_alpha"})

      assert {:ok, %{users: users, count: count}} =
               ActionDispatcher.dispatch_internal(:auth, :list_users, %{})

      assert count >= 2

      alpha = Enum.find(users, &(&1["player_id"] == "user_alpha"))
      assert alpha != nil
      assert "admin" in alpha["scopes"]
      assert alpha["tokens_count"] >= 2
      assert length(alpha["active_tokens"]) >= 2

      # A listing names the credentials by id, never by secret.
      for token <- alpha["active_tokens"] do
        assert is_binary(token["token_id"])
        assert token["kind"] in ["ses", "ref", "svc", "legacy"]
        refute Map.has_key?(token, "token")
      end

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
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "stu_scope",
                 required_scope: "player"
               })

      assert {:ok, %{authorized: true}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "stu_scope",
                 required_scope: "studio"
               })

      assert {:ok, %{authorized: false}} =
               ActionDispatcher.dispatch(:auth, :verify_scope, %{
                 player_id: "stu_scope",
                 required_scope: "admin"
               })
    end

    test "login returns a studio role for studio accounts" do
      {:ok, _} = Auth.upsert_account("studio", "studio@exoforge.test", "pw", ["studio"])

      assert {:ok, %{role: :studio, scopes: scopes}} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "studio@exoforge.test",
                 password: "pw"
               })

      assert "studio" in scopes
    end
  end

  describe "Admin account bootstrap & login" do
    test "ensure_admin_account creates the configured admin and login issues a token" do
      with_admin_env("root@exoforge.test", "s3cret")

      assert :ok = Auth.ensure_admin_account()

      assert {:ok, %{player_id: "admin", token: token, scopes: scopes}} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "root@exoforge.test",
                 password: "s3cret"
               })

      assert is_binary(token)
      assert "admin" in scopes

      assert {:ok, %{player_id: "admin", scopes: authed_scopes}} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})

      assert "admin" in authed_scopes

      # Also succeeds when passing player_id as the identifier
      assert {:ok, %{player_id: "admin"}} =
               ActionDispatcher.dispatch(:auth, :login, %{player_id: "admin", password: "s3cret"})
    end

    test "admin account can login with email 'admin' and password 'admin' in default dev setup" do
      with_admin_env("admin", "admin")

      assert :ok = Auth.ensure_admin_account()

      assert {:ok, %{player_id: "admin"}} =
               ActionDispatcher.dispatch(:auth, :login, %{email: "admin", password: "admin"})

      assert {:ok, %{player_id: "admin"}} =
               ActionDispatcher.dispatch(:auth, :login, %{player_id: "admin", password: "admin"})
    end

    test "ensure_admin_account never logs the configured password" do
      with_admin_env("env_admin@test.local", "supersecret")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :ok = Auth.ensure_admin_account()
        end)

      assert log =~ "env_admin@test.local"
      refute log =~ "supersecret"
    end

    test "login rejects a wrong password or unknown account" do
      with_admin_env("root2@exoforge.test", "right")

      assert :ok = Auth.ensure_admin_account()

      assert {:error, :invalid_credentials} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "root2@exoforge.test",
                 password: "wrong"
               })

      assert {:error, :invalid_credentials} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "nobody@exoforge.test",
                 password: "right"
               })
    end

    test "boot reconciles the admin with the environment and removes it when unconfigured" do
      with_admin_env("root@exoforge.test", "first_pass")
      assert :ok = Auth.ensure_admin_account()
      assert {:ok, %{player_id: "admin"}} = login("root@exoforge.test", "first_pass")

      # A changed environment takes effect at the next boot, not mid-session.
      System.put_env("EXOFORGE_ADMIN_PASSWORD", "second_pass")
      assert {:error, :invalid_credentials} = login("root@exoforge.test", "second_pass")
      assert :ok = Auth.ensure_admin_account()
      assert {:ok, %{player_id: "admin"}} = login("root@exoforge.test", "second_pass")
      assert {:error, :invalid_credentials} = login("root@exoforge.test", "first_pass")

      # Unconfigured means removed, including the sessions cached for it.
      {:ok, %{token: token}} = login("root@exoforge.test", "second_pass")
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})

      System.put_env("EXOFORGE_ADMIN_EMAIL", "")
      System.put_env("EXOFORGE_ADMIN_PASSWORD", "")
      assert :ok = Auth.ensure_admin_account()
      assert {:error, :invalid_credentials} = login("root@exoforge.test", "second_pass")

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})

      refute Enum.any?(users(), &(&1["player_id"] == "admin"))

      # Restored under the same constant id, so the player is the same player.
      System.put_env("EXOFORGE_ADMIN_EMAIL", "root@exoforge.test")
      System.put_env("EXOFORGE_ADMIN_PASSWORD", "third_pass")
      assert :ok = Auth.ensure_admin_account()

      assert {:ok, %{player_id: "admin", scopes: scopes}} =
               login("root@exoforge.test", "third_pass")

      assert "admin" in scopes
    end
  end

  describe "User directory paging" do
    test "list_users pages in the query and filters by search and scope" do
      # Unique prefix: the database is shared by this file's tests, so nothing may assume it is empty.
      prefix = "page#{System.unique_integer([:positive])}"

      for i <- 1..30 do
        Auth.upsert_account("#{prefix}_#{i}", "#{prefix}_#{i}@exoforge.test", "pw", ["player"])
      end

      {:ok, %{users: first, count: 30}} =
        ActionDispatcher.dispatch_internal(:auth, :list_users, %{
          search: prefix,
          scope: "player",
          limit: 10,
          offset: 0
        })

      assert length(first) == 10

      {:ok, %{users: second}} =
        ActionDispatcher.dispatch_internal(:auth, :list_users, %{
          search: prefix,
          scope: "player",
          limit: 10,
          offset: 10
        })

      assert length(second) == 10

      assert MapSet.disjoint?(
               MapSet.new(Enum.map(first, & &1["player_id"])),
               MapSet.new(Enum.map(second, & &1["player_id"]))
             )

      # Search matches the email too, and composes with the scope filter.
      {:ok, %{users: searched, count: 1}} =
        ActionDispatcher.dispatch_internal(:auth, :list_users, %{
          search: "#{prefix}_7@",
          scope: "player"
        })

      assert Enum.map(searched, & &1["player_id"]) == ["#{prefix}_7"]

      {:ok, %{users: admins, count: 0}} =
        ActionDispatcher.dispatch_internal(:auth, :list_users, %{search: prefix, scope: "admin"})

      assert admins == []
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

      assert {:ok, %{player_id: "user_pw_test"}} =
               ActionDispatcher.dispatch(:auth, :register, payload)

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
               ActionDispatcher.dispatch_internal(:auth, :reset_password, %{
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
               ActionDispatcher.dispatch_internal(:auth, :update_user_roles, %{
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

      # Authenticate once first, so the answer is cached: deletion has to revoke it anyway.
      unless Process.whereis(Exoforge.Std.Auth.Cache), do: start_supervised!(Exoforge.Std.Auth.Cache)
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})

      assert {:ok, %{status: "deleted"}} =
               ActionDispatcher.dispatch_internal(:auth, :delete_user, %{player_id: "to_delete"})

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})
    end

    test "a role change reaches tokens that were already authenticated" do
      unless Process.whereis(Exoforge.Std.Auth.Cache), do: start_supervised!(Exoforge.Std.Auth.Cache)
      {:ok, %{token: token}} =
        ActionDispatcher.dispatch_internal(:auth, :register, %{
          player_id: "to_demote",
          email: "demote@exoforge.test",
          scopes: ["studio"]
        })

      assert {:ok, %{scopes: before}} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})
      assert "studio" in before

      assert {:ok, _} =
               ActionDispatcher.dispatch_internal(:auth, :update_user_roles, %{player_id: "to_demote", role: "player"})

      assert {:ok, %{scopes: now}} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: token})
      refute "studio" in now
    end

    test "the administrator is an ordinary account except that user actions cannot remove it" do
      with_admin_env("envadmin@exoforge.test", "adm_pass")
      assert :ok = Auth.ensure_admin_account()

      admin = Enum.find(users(), &(&1["player_id"] == "admin"))
      assert admin, "the boot-configured administrator is a listed account, not a synthesized row"
      assert admin["is_protected"] == true
      assert "admin" in admin["scopes"]

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch_internal(:auth, :delete_user, %{player_id: "admin"})

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch_internal(:auth, :update_user_roles, %{
                 player_id: "admin",
                 scopes: ["player"]
               })

      assert {:error, :protected_admin_account} =
               ActionDispatcher.dispatch_internal(:auth, :reset_password, %{
                 player_id: "admin",
                 password: "hacked"
               })

      # Register upserts the account it names, so it must not be a way around the rules above.
      for action <- [:register, :create_player] do
        assert {:error, :protected_admin_account} =
                 ActionDispatcher.dispatch(:auth, action, %{
                   "player_id" => "admin",
                   "email" => "taken@exoforge.test",
                   "password" => "hacked",
                   "scopes" => ["player"],
                   "_auth" => %{"player_id" => "admin", "scopes" => ["admin"]}
                 })
      end

      admin = Enum.find(users(), &(&1["player_id"] == "admin"))
      assert "admin" in admin["scopes"]
      refute admin["email"] == "taken@exoforge.test"

      # Every other account is removable.
      assert {:ok, _} =
               ActionDispatcher.dispatch(:auth, :register, %{
                 player_id: "not_admin",
                 email: "not-admin@exoforge.test"
               })

      assert Enum.find(users(), &(&1["player_id"] == "not_admin"))["is_protected"] == false

      assert {:ok, %{status: "deleted"}} =
               ActionDispatcher.dispatch_internal(:auth, :delete_user, %{player_id: "not_admin"})
    end
  end

  describe "Anonymous sessions (two stage)" do
    test "anonymous refuses a password-protected account (M33 Fix 2)" do
      assert {:ok, %{player_id: "protected_user"}} =
               ActionDispatcher.dispatch(:auth, :register, %{
                 player_id: "protected_user",
                 email: "protected@exoforge.test",
                 password: "secret123"
               })

      # Knowing the player_id must not be enough to hold its token.
      assert {:error, :unauthorized} =
               ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: "protected_user"})

      # The passwordless path still reissues.
      assert {:ok, %{player_id: "protected_user"}} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "protected@exoforge.test",
                 password: "secret123"
               })
    end

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
               ActionDispatcher.dispatch_internal(:auth, :set_display_name, %{
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
               ActionDispatcher.dispatch_internal(:auth, :set_display_name, %{
                 player_id: device,
                 name: "   "
               })
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
    disp = "dev_disp_#{System.unique_integer([:positive])}"
    kept = "dev_kept_#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             ActionDispatcher.dispatch(:auth, :anonymous, %{
               player_id: disp,
               disposable: true
             })

    # Registered beside it and not disposable: a purge has to leave it alone.
    assert {:ok, _} = ActionDispatcher.dispatch(:auth, :anonymous, %{player_id: kept})

    # Changing roles must not quietly make a disposable account permanent.
    assert {:ok, _} =
             ActionDispatcher.dispatch_internal(:auth, :update_user_roles, %{
               player_id: disp,
               scopes: ["player"]
             })

    assert {:ok, %{purged: 1, dry_run: true}} =
             ActionDispatcher.dispatch(:auth, :purge_disposable, %{dry_run: true},
               caller_scopes: ["studio"]
             )

    # A dry run reports without removing.
    assert player_row(disp)

    assert {:ok, %{purged: 1}} =
             ActionDispatcher.dispatch(:auth, :purge_disposable, %{}, caller_scopes: ["studio"])

    refute player_row(disp)
    assert player_row(kept)

    # The tokens went with it, and the other account kept its own (an access/refresh pair).
    assert token_count(disp) == 0
    assert token_count(kept) == 2
  end

  # A token is a credential with a lifetime, not a row that never dies: `exo_<kind>_<id>.<secret>`,
  # hashed at rest, short-lived for a session and rotatable through a refresh token.
  describe "Expiring, revocable tokens" do
    test "the format names the kind and only the hash is stored" do
      {:ok, access, refresh} = session_for("token_fmt")

      assert access =~ ~r/^exo_ses_[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{43}$/
      assert refresh =~ ~r/^exo_ref_[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{43}$/

      token_id = token_id_of(access)
      secret = secret_of(access)

      [row] = rows("SELECT * FROM tokens WHERE token_id = $1", [token_id])
      assert row["kind"] == "ses"
      assert row["secret_hash"] == Base.encode64(:crypto.hash(:sha256, secret))
      assert row["expires_at"] && row["created_at"]
      assert row["family_id"]

      # Nothing at rest holds the credential itself.
      refute Enum.any?(rows("SELECT * FROM tokens", []), fn row -> secret in Map.values(row) end)
    end

    test "an expired access token is refused as token_expired" do
      with_token_config(:access_token_ttl, -1)
      {:ok, access, _refresh} = session_for("token_expiry")

      assert {:error, :token_expired} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})
    end

    test "an expired token stops working even after it authenticated once" do
      unless Process.whereis(Exoforge.Std.Auth.Cache), do: start_supervised!(Exoforge.Std.Auth.Cache)
      {:ok, access, _refresh} = session_for("token_expiry_cached")
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})

      # The cached answer carries the row's expiry; age it the way an hour would.
      [{^access, result, used_at}] = :ets.lookup(:exoforge_auth_tokens, access)

      :ets.insert(
        :exoforge_auth_tokens,
        {access, Map.put(result, :expires_at, "2000-01-01T00:00:00Z"), used_at}
      )

      assert {:error, :token_expired} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})
    end

    test "a refresh token is not a bearer token" do
      {:ok, _access, refresh} = session_for("token_kind")

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: refresh})
    end

    test "refreshing rotates the pair and replaying a rotated token kills the family" do
      {:ok, access, refresh} = session_for("token_rotate")

      assert {:ok, %{token: rotated_access, refresh_token: rotated_refresh}} =
               ActionDispatcher.dispatch(:auth, :refresh, %{token: refresh})

      assert rotated_access != access
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: rotated_access})

      # A rotated refresh token is single use. Presenting it again means it leaked, so the family
      # it belongs to - including the access token issued a moment ago - is revoked.
      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :refresh, %{token: refresh})

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: rotated_access})

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :refresh, %{token: rotated_refresh})
    end

    test "an expired refresh token is refused but the access token it replaced still works until it expires" do
      with_token_config(:refresh_token_ttl, -1)
      {:ok, access, refresh} = session_for("token_refresh_expiry")

      assert {:error, :token_expired} =
               ActionDispatcher.dispatch(:auth, :refresh, %{token: refresh})

      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})
    end

    test "a new login for the same device replaces that device's session" do
      unless Process.whereis(Exoforge.Std.Auth.Cache), do: start_supervised!(Exoforge.Std.Auth.Cache)

      {:ok, first_access, first_refresh} = session_for("token_device", "device_one")

      # Authenticated before the replacement, so the answer is cached: revoking the row has to
      # reach the cache as well, or the old token keeps working until the next flush.
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: first_access})

      {:ok, second_access, _} = session_for("token_device", "device_one")

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: first_access})

      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: second_access})

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :refresh, %{token: first_refresh})
    end

    test "sessions per account are capped and the oldest is evicted" do
      with_token_config(:max_sessions, 2)
      _ = Auth.upsert_account("token_cap", "token_cap@exoforge.test", "pw", ["player"])

      sessions =
        for i <- 1..3 do
          assert {:ok, session} =
                   ActionDispatcher.dispatch(:auth, :login, %{
                     email: "token_cap@exoforge.test",
                     password: "pw",
                     device_id: "cap_device_#{i}"
                   })

          session
        end

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{
                 token: Enum.at(sessions, 0).token
               })

      for session <- Enum.drop(sessions, 1) do
        assert {:ok, _} =
                 ActionDispatcher.dispatch(:auth, :authenticate, %{token: session.token})
      end

      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      [%{"n" => live}] =
        rows(
          "SELECT COUNT(DISTINCT family_id) AS n FROM tokens WHERE user_id = $1 AND kind = 'ref' AND revoked_at IS NULL AND expires_at > $2",
          ["token_cap", now]
        )

      assert live == 2
    end

    test "a service token is listed by id, carries the account's scopes, and can be revoked" do
      _ = Auth.upsert_account("token_revoke", "token_revoke@exoforge.test", "pw", ["player"])

      assert {:ok, %{token: access, token_id: token_id, expires_in: expires_in}} =
               ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: "token_revoke"},
                 caller_scopes: ["admin"]
               )

      assert expires_in == 7_776_000
      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})

      assert {:ok, %{tokens: tokens}} =
               ActionDispatcher.dispatch(:auth, :list_tokens, %{user_id: "token_revoke"},
                 caller_scopes: ["admin"]
               )

      listed = Enum.find(tokens, &(&1["token_id"] == token_id))
      assert listed["kind"] == "svc"
      assert listed["created_at"] && listed["expires_at"]
      refute Map.has_key?(listed, "token")

      assert {:ok, %{status: "revoked"}} =
               ActionDispatcher.dispatch(:auth, :revoke_token, %{token_id: token_id},
                 caller_scopes: ["admin"]
               )

      assert {:error, :invalid_token} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})

      assert {:error, :token_not_found} =
               ActionDispatcher.dispatch(:auth, :revoke_token, %{token_id: token_id},
                 caller_scopes: ["admin"]
               )
    end

    test "a shorter term can be asked for when a token is issued" do
      _ = Auth.upsert_account("token_term", "token_term@exoforge.test", "pw", ["service"])

      assert {:ok, %{expires_in: 2_592_000}} =
               ActionDispatcher.dispatch(
                 :auth,
                 :issue_token,
                 %{user_id: "token_term", expires_in: 2_592_000},
                 caller_scopes: ["admin"]
               )
    end

    test "issuing a token for an id nobody holds is refused" do
      assert {:error, :unknown_user} =
               ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: "nobody_here"},
                 caller_scopes: ["admin"]
               )
    end

    test "a role change applies to existing tokens without rewriting their rows" do
      _ = Auth.upsert_account("token_roles", "token_roles@exoforge.test", "pw", ["studio"])

      assert {:ok, %{token: access}} =
               ActionDispatcher.dispatch(:auth, :login, %{
                 email: "token_roles@exoforge.test",
                 password: "pw"
               })

      assert {:ok, %{scopes: before}} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})

      assert "studio" in before

      token_id = token_id_of(access)
      [row_before] = rows("SELECT * FROM tokens WHERE token_id = $1", [token_id])

      assert {:ok, _} =
               ActionDispatcher.dispatch(:auth, :update_user_roles, %{player_id: "token_roles", role: "player"},
                 caller_scopes: ["admin"]
               )

      assert {:ok, %{scopes: now}} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: access})

      refute "studio" in now

      [row_after] = rows("SELECT * FROM tokens WHERE token_id = $1", [token_id])
      assert Map.take(row_after, ["kind", "secret_hash", "expires_at", "created_at"]) ==
               Map.take(row_before, ["kind", "secret_hash", "expires_at", "created_at"])
    end

    test "the contract hands the token purge to the cron extension" do
      metadata = Exoforge.Std.Services.Auth.__service_metadata__()

      assert [%{name: :purge_tokens, action: :purge_tokens, schedule: schedule}] = metadata.crons
      assert schedule =~ ~r/^\S+ \S+ \S+ \S+ \S+$/
    end

    test "the cron purge deletes expired and revoked rows and keeps live ones" do
      {:ok, live_access, _} = session_for("token_purge_live")
      {:ok, dead_access, _} = session_for("token_purge_dead")

      assert {:ok, %{token_id: dead_id}} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: dead_access})

      assert {:ok, _} =
               ActionDispatcher.dispatch(:auth, :revoke_token, %{token_id: dead_id},
                 caller_scopes: ["admin"]
               )

      assert {:ok, %{purged: purged}} =
               ActionDispatcher.dispatch(:auth, :purge_tokens, %{}, caller_scopes: :internal)

      assert purged >= 2
      refute Enum.any?(rows("SELECT * FROM tokens", []), &(&1["token_id"] == dead_id))

      assert {:ok, _} = ActionDispatcher.dispatch(:auth, :authenticate, %{token: live_access})
    end

    test "rows written before hashing are hashed in place, cleared, and keep working" do
      legacy_token = "legacy_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

      # The shape of the table this change upgrades from.
      _ = execute_sql("DROP TABLE tokens")

      _ =
        execute_sql(
          "CREATE TABLE tokens (id text, token text, player_id text, scopes text)"
        )

      # `init_schema` adds the new columns to a table that already exists; do that before writing
      # the legacy row, the way an upgrade of a populated deployment happens.
      _ = Auth.init_schema()
      {:ok, _} = Auth.set_player_scopes("legacy_player", ["player"])

      _ =
        execute_sql(
          "INSERT INTO tokens (id, token, player_id, scopes) VALUES ($1, $2, $3, $4)",
          ["legacy_id", legacy_token, "legacy_player", "player"]
        )

      assert :ok = Auth.init_schema()

      assert {:ok, %{player_id: "legacy_player"}} =
               ActionDispatcher.dispatch(:auth, :authenticate, %{token: legacy_token})

      [row] = rows("SELECT * FROM tokens WHERE user_id = $1", ["legacy_player"])
      assert row["kind"] == "legacy"
      assert row["token"] == ""
      assert row["expires_at"]
      assert row["secret_hash"] == Base.encode64(:crypto.hash(:sha256, legacy_token))
      refute Enum.any?(rows("SELECT * FROM tokens", []), fn row -> legacy_token in Map.values(row) end)
    end
  end

  defp session_for(player_id, device_id \\ nil) do
    email = "#{player_id}@exoforge.test"

    assert {:ok, _} =
             ActionDispatcher.dispatch(:auth, :register, %{
               player_id: player_id,
               email: email,
               password: "pw"
             })

    payload =
      %{email: email, password: "pw"}
      |> then(fn p -> if device_id, do: Map.put(p, :device_id, device_id), else: p end)

    assert {:ok, %{token: access, refresh_token: refresh}} =
             ActionDispatcher.dispatch(:auth, :login, payload)

    {:ok, access, refresh}
  end

  defp token_id_of(token) do
    token |> String.replace_prefix("exo_ses_", "") |> String.split(".") |> hd()
  end

  defp secret_of(token), do: token |> String.split(".") |> List.last()

  defp execute_sql(sql, args \\ []) do
    ActionDispatcher.dispatch_internal(:database, :execute, %{
      plugin: :auth,
      operation: sql,
      arguments: args
    })
  end

  defp rows(sql, args \\ []) do
    case execute_sql(sql, args) do
      {:ok, %{rows: rows}} -> rows
      _ -> []
    end
  end

  defp with_token_config(key, value) do
    previous = Application.get_env(:exoforge, :auth, [])
    Application.put_env(:exoforge, :auth, Keyword.put(List.wrap(previous), key, value))

    on_exit(fn ->
      if previous in [nil, []],
        do: Application.delete_env(:exoforge, :auth),
        else: Application.put_env(:exoforge, :auth, previous)
    end)
  end

  defp player_row(player_id) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT player_id FROM players WHERE player_id = $1",
           arguments: [player_id]
         }) do
      {:ok, %{rows: [row | _]}} -> row["player_id"] || row[:player_id]
      _ -> nil
    end
  end

  defp token_count(player_id) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT count(*) as n FROM tokens WHERE user_id = $1",
           arguments: [player_id]
         }) do
      {:ok, %{rows: [row | _]}} -> row["n"] || row[:n]
      _ -> 0
    end
  end

  defp login(email, password) do
    ActionDispatcher.dispatch(:auth, :login, %{email: email, password: password})
  end

  defp users do
    {:ok, %{users: users}} =
      ActionDispatcher.dispatch(:auth, :list_users, %{}, caller_scopes: ["studio"])

    users
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
