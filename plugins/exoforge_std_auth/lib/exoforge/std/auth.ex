defmodule Exoforge.Std.Auth do
  @moduledoc """
  Standard authentication and authorization plugin for Exoforge.
  Provides the :auth service contract.
  Relies on the :database service for isolated persistence of tokens and scopes.
  """
  use Exoforge.Plugin, provides: [:auth]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.PlayerData],
    category: "Identity",
    dashboard_view: %{
      id: :auth,
      title: "Users & Auth",
      icon: "🛡️"
    },
    ui_hooks: %{
      settings: [
        %{
          id: :auth,
          title: "Auth & Security",
          icon: "🔐",
          order: 25
        }
      ],
      resource_column: [
        %{
          id: :user_id,
          role: "user_id",
          target: "exoforge_std_auth",
          focus: "user",
          icon: "↗",
          order: 10
        }
      ]
    }
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Auth.Roles
  require Logger

  @admin_id "admin"
  @studio_id "studio"
  @dev_admin_prefix "dev_admin"

  @tokens_table "tokens"
  @players_table "players"
  @accounts_table "accounts"

  def on_init(_manifest) do
    init_schema()
    ensure_admin_account()
    ensure_studio_account()
    :ok
  end

  @doc "Dashboard visualization specification for Exoforge Game Producer & Designer Studio."
  def dashboard_view, do: @manifest.dashboard_view

  @doc "Initializes the required tables in the isolated auth database."
  def init_schema do
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "CREATE TABLE IF NOT EXISTS #{@tokens_table} (id text, token text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "CREATE TABLE IF NOT EXISTS #{@players_table} (id text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "CREATE TABLE IF NOT EXISTS #{@accounts_table} (id text, player_id text, email text, password_hash text, scopes text)"
      })

    # `CREATE TABLE IF NOT EXISTS` does not add a column to a table that already exists, so databases
    # that predate this one are brought forward here rather than by a schema reset.
    unless column_exists?(@players_table, "disposable") do
      _ =
        ActionDispatcher.dispatch(:database, :execute, %{
          plugin: :auth,
          operation: "ALTER TABLE #{@players_table} ADD COLUMN disposable integer DEFAULT 0"
        })
    end

    :ok
  end

  defp column_exists?(table, column) do
    # Column inspection is the adapter's dialect, not a PRAGMA here (M33 Fix 9): PostgreSQL does
    # not answer `PRAGMA table_info`, so the check read "no such column" there forever.
    case ActionDispatcher.dispatch(:database, :table_columns, %{plugin: :auth, table: table}) do
      {:ok, %{columns: columns}} -> to_string(column) in columns
      _ -> false
    end
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction authenticate(payload) do
    token = extract_token(payload)

    cond do
      is_nil(token) or token == "" ->
        {:error, :invalid_token}

      # Development tokens are opt-in and never valid in production.
      String.starts_with?(token, "dev:") and Exoforge.Config.allow_dev_tokens?() ->
        uid = String.replace_prefix(token, "dev:", "")
        scopes = [Roles.player(), Roles.admin()]
        {:ok, %{user_id: uid, player_id: uid, scopes: scopes, role: role(scopes)}}

      token == Roles.guest() ->
        scopes = [Roles.guest()]

        {:ok, %{user_id: "guest_anon", player_id: "guest_anon", scopes: scopes, role: role(scopes)}}

      true ->
        query = "SELECT * FROM #{@tokens_table} WHERE token = $1"

        case ActionDispatcher.dispatch(:database, :execute, %{
               plugin: :auth,
               operation: query,
               arguments: [token]
             }) do
          {:ok, %{rows: [row | _]}} ->
            uid =
              Map.get(row, "user_id") || Map.get(row, :user_id) || Map.get(row, "player_id") ||
                Map.get(row, :player_id)

            raw_scopes = Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player()
            scopes = parse_scopes(raw_scopes)
            {:ok, %{user_id: uid, player_id: uid, scopes: scopes, role: role(scopes)}}

          {:ok, %{rows: []}} ->
            {:error, :invalid_token}

          {:error, _reason} ->
            {:error, :invalid_token}
        end
    end
  end

  @impl true
  defaction login(payload) do
    identifier =
      Map.get(payload, :email) || Map.get(payload, "email") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    password = Map.get(payload, :password) || Map.get(payload, "password")

    if is_nil(identifier) or identifier == "" or is_nil(password) or password == "" do
      {:error, :invalid_credentials}
    else
      clean_id = String.downcase(to_string(identifier))
      {admin_email, env_password} = credentials(:admin, "EXOFORGE_ADMIN_EMAIL", "EXOFORGE_ADMIN_PASSWORD")
      admin_match? = clean_id == @admin_id or (is_binary(admin_email) and clean_id == String.downcase(to_string(admin_email)))

      # If the admin password is actively configured in the env, it immediately overrides and replaces any stored password
      if admin_match? and is_binary(env_password) and env_password != "" do
        if password == env_password do
          effective_email = if is_binary(admin_email) and admin_email != "", do: admin_email, else: @admin_id
          _ = upsert_account(@admin_id, effective_email, env_password, [Roles.admin()])

          case generate_and_store_token(@admin_id, [Roles.admin()]) do
            {:ok, token} ->
              {:ok, %{player_id: @admin_id, token: token, scopes: [Roles.admin()], role: role([Roles.admin()])}}

            error ->
              error
          end
        else
          {:error, :invalid_credentials}
        end
      else
        query = "SELECT * FROM #{@accounts_table} WHERE email = $1 OR player_id = $2"

        case ActionDispatcher.dispatch(:database, :execute, %{
               plugin: :auth,
               operation: query,
               arguments: [clean_id, to_string(identifier)]
             }) do
          {:ok, %{rows: rows}} when is_list(rows) and rows != [] ->
            matching_row =
              Enum.find(rows, fn row ->
                hash = Map.get(row, "password_hash") || Map.get(row, :password_hash)
                verify_password(password, hash)
              end)

            if matching_row do
              player_id = Map.get(matching_row, "player_id") || Map.get(matching_row, :player_id)
              scopes = parse_scopes(Map.get(matching_row, "scopes") || Map.get(matching_row, :scopes) || Roles.player())

              case generate_and_store_token(player_id, scopes) do
                {:ok, token} ->
                  {:ok, %{player_id: player_id, token: token, scopes: scopes, role: role(scopes)}}

                error ->
                  error
              end
            else
              {:error, :invalid_credentials}
            end

          _ ->
            {:error, :invalid_credentials}
        end
      end
    end
  end

  @impl true
  defaction verify_scope(payload) do
    user_id =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    required = Map.get(payload, :required_scope) || Map.get(payload, "required_scope")

    cond do
      is_nil(user_id) or is_nil(required) ->
        {:error, :unauthorized}

      user_id == @admin_id ->
        {:ok, %{authorized: true}}

      # dev_admin_* ids only exist while dev tokens do (M33 Fix 4): in production, where
      # `allow_dev_tokens?` is false, the prefix must not answer yes to anything.
      String.starts_with?(user_id, @dev_admin_prefix) and Exoforge.Config.allow_dev_tokens?() ->
        {:ok, %{authorized: true}}

      true ->
        scopes =
          case ActionDispatcher.dispatch(:database, :execute, %{
                 plugin: :auth,
                 operation: "SELECT * FROM #{@players_table} WHERE player_id = $1",
                 arguments: [user_id]
               }) do
            {:ok, %{rows: [row | _]}} ->
              parse_scopes(Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player())

            _ ->
              [Roles.player()]
          end

        authorized =
          if Exoforge.Auth.Roles.rank(required) == 0 do
            to_string(required) in scopes
          else
            Exoforge.Auth.Roles.rank_of(scopes) >= Exoforge.Auth.Roles.rank(required)
          end

        {:ok, %{authorized: authorized}}
    end
  end

  @impl true
  defaction register(payload) do
    do_register_player(payload)
  end

  @impl true
  defaction create_player(payload) do
    do_register_player(payload)
  end

  @doc """
  Creates or resumes an anonymous player session.

  Supply `player_id` to reissue a token for an existing player (a returning device);
  otherwise a new player is registered using the optional display `name`.
  """
  @impl true
  defaction anonymous(payload) do
    player_id = Map.get(payload, :player_id) || Map.get(payload, "player_id")

    cond do
      # Entering (or claiming) an account for a known device identity.
      is_binary(player_id) and player_id != "" ->
        cond do
          # A password-protected account cannot be entered by naming its player_id (M33 Fix 2):
          # anonymous mints a token for the id it is given, so for someone who learned another
          # player's id that is account takeover. Such an account is entered by password (`login`),
          # not by id.
          password_protected?(player_id) ->
            {:error, :unauthorized}

          # First sight of this device: register the account, unnamed. The whole payload goes
          # through: rebuilding it here silently dropped every other field a caller sent, scopes
          # and the disposable marker among them.
          player_name(player_id) == nil ->
            register_unnamed(Map.put(payload, :player_id, player_id))

          # A returning device, still passwordless: reissue its token.
          true ->
            case anonymous_token(player_id) do
              {:ok, result} -> {:ok, Map.put(result, :name, player_name(player_id))}
              error -> error
            end
        end

      # No device identity supplied: register a fresh unnamed account.
      true ->
        register_unnamed(payload)
    end
  end

  @doc """
  Sets the signed-in player's display name. The player is taken from the caller's identity,
  so a player can only name themselves.
  """
  @impl true
  defaction set_display_name(payload) do
    player_id = Map.get(payload, :player_id) || Map.get(payload, "player_id")
    name = Map.get(payload, :name) || Map.get(payload, "name")

    trimmed = if is_binary(name), do: String.trim(name), else: ""

    cond do
      is_nil(player_id) or player_id == "" ->
        {:error, :unauthorized}

      trimmed == "" ->
        {:error, :invalid_attributes}

      true ->
        case rename_player(player_id, trimmed) do
          :ok -> {:ok, %{player_id: player_id, name: trimmed}}
          {:error, reason} -> {:error, reason}
          :error -> {:error, :player_not_found}
        end
    end
  end

  @impl true
  defaction issue_token(payload), scope: Exoforge.Auth.Roles.admin() do
    user_id =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    raw_scopes = Map.get(payload, :scopes) || Map.get(payload, "scopes")

    if is_nil(user_id) or user_id == "" do
      {:error, :invalid_player}
    else
      scopes =
        if is_nil(raw_scopes) do
          query = "SELECT * FROM #{@players_table} WHERE player_id = $1"

          case ActionDispatcher.dispatch(:database, :execute, %{
                 plugin: :auth,
                 operation: query,
                 arguments: [user_id]
               }) do
            {:ok, %{rows: [row | _]}} ->
              parse_scopes(Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player())

            _ ->
              [Roles.player()]
          end
        else
          parse_scopes(raw_scopes)
        end

      case generate_and_store_token(user_id, scopes) do
        {:ok, token} -> {:ok, %{token: token, user_id: user_id, player_id: user_id}}
        error -> error
      end
    end
  end

  @impl true
  defaction list_users(payload), scope: Exoforge.Auth.Roles.studio() do
    init_schema()

    players_query = "SELECT * FROM #{@players_table}"
    tokens_query = "SELECT * FROM #{@tokens_table}"
    accounts_query = "SELECT * FROM #{@accounts_table}"

    players_rows =
      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :auth,
             operation: players_query
           }) do
        {:ok, %{rows: rows}} when is_list(rows) -> rows
        _ -> []
      end

    tokens_rows =
      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :auth,
             operation: tokens_query
           }) do
        {:ok, %{rows: rows}} when is_list(rows) -> rows
        _ -> []
      end

    accounts_rows =
      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :auth,
             operation: accounts_query
           }) do
        {:ok, %{rows: rows}} when is_list(rows) -> rows
        _ -> []
      end

    tokens_by_player =
      Enum.group_by(tokens_rows, fn row ->
        to_string(Map.get(row, "player_id") || Map.get(row, :player_id))
      end)

    players_by_id =
      Enum.reduce(players_rows, %{}, fn row, acc ->
        pid = to_string(Map.get(row, "player_id") || Map.get(row, :player_id))
        Map.put(acc, pid, row)
      end)

    accounts_by_id =
      Enum.reduce(accounts_rows, %{}, fn row, acc ->
        pid = to_string(Map.get(row, "player_id") || Map.get(row, :player_id))
        Map.put(acc, pid, row)
      end)

    all_player_ids =
      (Map.keys(players_by_id) ++ Map.keys(tokens_by_player) ++ Map.keys(accounts_by_id))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    users =
      Enum.map(all_player_ids, fn pid ->
        p_row = Map.get(players_by_id, pid, %{})
        acc_row = Map.get(accounts_by_id, pid, %{})

        raw_scopes =
          Map.get(p_row, "scopes") || Map.get(p_row, :scopes) ||
            Map.get(acc_row, "scopes") || Map.get(acc_row, :scopes) ||
            Roles.player()

        scopes = parse_scopes(raw_scopes)
        tokens = Map.get(tokens_by_player, pid, [])
        email = Map.get(acc_row, "email") || Map.get(acc_row, :email)

        token_strings =
          Enum.map(tokens, fn t ->
            to_string(Map.get(t, "token") || Map.get(t, :token))
          end)

        %{
          "user_id" => pid,
          "player_id" => pid,
          "name" => Map.get(acc_row, "name") || Map.get(acc_row, :name) || pid,
          "email" => email,
          "scopes" => scopes,
          "tokens_count" => length(tokens),
          "active_tokens" => token_strings,
          "status" => "Active",
          "is_protected" => is_env_admin?(pid)
        }
      end)

    # A page, not the whole directory (M33 Fix 33): the Studio asks for a bounded list; count says
    # how many exist in total. Unlimited remains possible by passing a big limit.
    limit = Map.get(payload, :limit) || Map.get(payload, "limit")
    total = length(users)

    users =
      if is_integer(limit) and limit > 0, do: Enum.take(users, limit), else: users

    {:ok, %{users: users, count: total}}
  end

  @impl true
  defaction reset_password(payload), scope: Exoforge.Auth.Roles.admin() do
    user_id =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    password = Map.get(payload, :password) || Map.get(payload, "password")

    cond do
      is_nil(user_id) or user_id == "" ->
        {:error, :user_not_found}

      is_env_admin?(user_id) ->
        {:error, :protected_admin_account}

      is_nil(password) or password == "" ->
        {:error, :invalid_password}

      true ->
        init_schema()
        pid = to_string(user_id)

        acc_by_pid =
          case ActionDispatcher.dispatch(:database, :execute, %{
                 plugin: :auth,
                 operation: "SELECT * FROM #{@accounts_table} WHERE player_id = $1",
                 arguments: [pid]
               }) do
            {:ok, %{rows: [r | _]}} -> r
            _ -> nil
          end

        acc_row =
          acc_by_pid ||
            case ActionDispatcher.dispatch(:database, :execute, %{
                   plugin: :auth,
                   operation: "SELECT * FROM #{@accounts_table} WHERE email = $1",
                   arguments: [String.downcase(pid)]
                 }) do
              {:ok, %{rows: [r | _]}} -> r
              _ -> nil
            end

        case acc_row do
          %{} ->
            email = Map.get(acc_row, "email") || Map.get(acc_row, :email)
            actual_pid = Map.get(acc_row, "player_id") || Map.get(acc_row, :player_id) || pid

            scopes =
              parse_scopes(Map.get(acc_row, "scopes") || Map.get(acc_row, :scopes) || Roles.player())

            _ = upsert_account(actual_pid, email, password, scopes)
            {:ok, %{user_id: actual_pid, player_id: actual_pid, status: "password_reset"}}

          nil ->
            pquery = "SELECT * FROM #{@players_table} WHERE player_id = $1"

            case ActionDispatcher.dispatch(:database, :execute, %{
                   plugin: :auth,
                   operation: pquery,
                   arguments: [pid]
                 }) do
              {:ok, %{rows: [prow | _]}} ->
                scopes =
                  parse_scopes(Map.get(prow, "scopes") || Map.get(prow, :scopes) || Roles.player())

                _ = upsert_account(pid, "#{pid}@player.exoforge.io", password, scopes)
                {:ok, %{user_id: pid, player_id: pid, status: "password_reset"}}

              _ ->
                {:error, :user_not_found}
            end
        end
    end
  end

  @impl true
  defaction update_user_roles(payload), scope: Exoforge.Auth.Roles.admin() do
    user_id =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    explicit_role = Map.get(payload, :role) || Map.get(payload, "role")
    raw_scopes = Map.get(payload, :scopes) || Map.get(payload, "scopes") || explicit_role

    cond do
      is_nil(user_id) or user_id == "" ->
        {:error, :user_not_found}

      is_env_admin?(user_id) ->
        {:error, :protected_admin_account}

      is_nil(raw_scopes) ->
        {:error, :invalid_scopes}

      true ->
        init_schema()
        pid = to_string(user_id)

        scopes =
          if explicit_role && (is_binary(explicit_role) or is_atom(explicit_role)) do
            Roles.scopes_for_role(explicit_role)
          else
            parse_scopes(raw_scopes)
          end

        scopes_str = Enum.join(scopes, ",")

        _ = set_player_scopes(pid, scopes)

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "UPDATE #{@accounts_table} SET scopes = $1 WHERE player_id = $2",
            arguments: [scopes_str, pid]
          })

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "UPDATE #{@accounts_table} SET scopes = $1 WHERE email = $2",
            arguments: [scopes_str, pid]
          })

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "UPDATE #{@tokens_table} SET scopes = $1 WHERE player_id = $2",
            arguments: [scopes_str, pid]
          })

        {:ok, %{user_id: pid, player_id: pid, scopes: scopes}}
    end
  end

  @doc """
  Removes every account a test or a demo created.

  A player is disposable because it said so: `auth.anonymous` or `auth.register` with
  `disposable: true`. Nothing is inferred from a name or a scope, so a purge on a live cluster
  removes the guests a test made and leaves the players who signed up.
  """
  @impl true
  defaction purge_disposable(payload), scope: Exoforge.Auth.Roles.studio() do
    init_schema()

    dry_run = Map.get(payload, :dry_run) || Map.get(payload, "dry_run") || false

    ids =
      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :auth,
             operation: "SELECT player_id FROM #{@players_table} WHERE disposable = 1"
           }) do
        {:ok, %{rows: rows}} -> Enum.map(rows, &(&1["player_id"] || &1[:player_id]))
        _ -> []
      end

    if as_flag(dry_run) == 1 do
      {:ok, %{purged: length(ids), dry_run: true}}
    else
      remove_disposable(ids)
      {:ok, %{purged: length(ids), dry_run: false}}
    end
  end

  @impl true
  defaction delete_user(payload), scope: Exoforge.Auth.Roles.admin() do
    user_id =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    cond do
      is_nil(user_id) or user_id == "" ->
        {:error, :user_not_found}

      is_env_admin?(user_id) ->
        {:error, :protected_admin_account}

      true ->
        init_schema()
        pid = to_string(user_id)

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@players_table} WHERE player_id = $1",
            arguments: [pid]
          })

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@tokens_table} WHERE player_id = $1",
            arguments: [pid]
          })

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@accounts_table} WHERE player_id = $1",
            arguments: [pid]
          })

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@accounts_table} WHERE email = $1",
            arguments: [pid]
          })

        # Retain player record without user linkage for data retention and telemetry compliance
        _ = ActionDispatcher.dispatch(:player_data, :retain_player, %{player_id: pid})

        {:ok, %{user_id: pid, player_id: pid, status: "deleted"}}
    end
  end

  # Anonymous accounts start unnamed; the client prompts for a display name afterwards.
  defp rename_player(player_id, name) do
    case ActionDispatcher.dispatch(:player_data, :update_player, %{
           player_id: player_id,
           data: %{"name" => name}
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> :error
    end
  end

  defp anonymous_token(player_id) do
    scopes = [Roles.player()]

    case generate_and_store_token(player_id, scopes) do
      {:ok, token} ->
        {:ok, %{player_id: player_id, token: token, scopes: scopes, role: role(scopes)}}

      error ->
        error
    end
  end

  defp remove_disposable(ids) do
    Enum.each(ids, fn player_id ->
      Enum.each([@tokens_table, @accounts_table, @players_table], fn table ->
        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{table} WHERE player_id = $1",
            arguments: [player_id]
          })
      end)

      # The rest of a player's data belongs to other plugins; asked to clean up after itself, a
      # disposable player should not leave a profile and a leaderboard row behind.
      _ = ActionDispatcher.dispatch(:player_data, :delete_player, %{player_id: player_id})
    end)
  end

  defp register_unnamed(payload) do
    case do_register_player(payload, allow_empty_name: true) do
      {:ok, %{player: profile} = result} ->
        {:ok, Map.put(result, :name, Map.get(profile, "name") || "")}

      error ->
        error
    end
  end

  defp player_name(player_id) do
    case ActionDispatcher.dispatch(:player_data, :get_player, %{player_id: player_id}) do
      {:ok, %{player: profile}} -> Map.get(profile, "name") || Map.get(profile, :name)
      _ -> nil
    end
  end

  defp do_register_player(payload, opts \\ []) do
    init_schema()

    raw_uid =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    user_id =
      if raw_uid && raw_uid != "",
        do: to_string(raw_uid),
        else: "u_#{System.unique_integer([:positive])}"

    raw_name =
      Map.get(payload, :name) || Map.get(payload, "name") ||
        Map.get(payload, :username) || Map.get(payload, "username")

    name =
      cond do
        is_binary(raw_name) and raw_name != "" -> raw_name
        Keyword.get(opts, :allow_empty_name, false) -> ""
        true -> "User_#{user_id}"
      end

    raw_email = Map.get(payload, :email) || Map.get(payload, "email")

    email =
      if raw_email && raw_email != "",
        do: to_string(raw_email),
        else: "#{user_id}@player.exoforge.io"

    raw_scopes = Map.get(payload, :scopes) || Map.get(payload, "scopes") || [Roles.player()]

    # Register is a public action, so a payload naming `scopes: ["admin"]` would mint an admin
    # token to whoever sent it (M33 Fix 1). Only a trusted caller may choose scopes; everyone
    # else gets a player.
    scopes =
      if trusted_caller?(payload), do: parse_scopes(raw_scopes), else: [Roles.player()]

    raw_password = Map.get(payload, :password) || Map.get(payload, "password")

    # A caller that says the account is disposable gets one that a purge may remove. Nothing is
    # inferred from the name or the scopes: a guess about which accounts are junk is a guess that
    # eventually deletes someone's.
    disposable = Map.get(payload, :disposable) || Map.get(payload, "disposable")

    if raw_password && raw_password != "" do
      _ = upsert_account(user_id, email, raw_password, scopes)
    end

    case generate_and_store_token(user_id, scopes, disposable) do
      {:ok, token} ->
        profile = %{
          "user_id" => user_id,
          "player_id" => user_id,
          "name" => name,
          "email" => email,
          "total_spent" => "$0.00",
          "time_in_game" => "0m",
          "status" => "Active",
          "attributes" => [
            %{"key" => "locale", "value" => "en_US"},
            %{
              "key" => "registered_at",
              "value" => Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")
            }
          ]
        }

        # Hook into player_data canonical profile store, linking player to user
        case ActionDispatcher.dispatch(:player_data, :create_player, %{
               player_id: user_id,
               user_id: user_id,
               profile: profile
             }) do
          {:error, reason} ->
            {:error, reason}

          _ ->
            {:ok, %{user_id: user_id, player_id: user_id, token: token, scopes: scopes, player: profile}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Checks if a player ID belongs to the protected env-configured admin."
  def is_env_admin?(player_id) do
    pid = to_string(player_id)
    {env_email, env_password} = credentials(:admin, "EXOFORGE_ADMIN_EMAIL", "EXOFORGE_ADMIN_PASSWORD")
    is_admin = pid == @admin_id or (is_binary(env_email) and env_email != "" and pid == env_email)
    is_admin and is_binary(env_password) and env_password != ""
  end

  @doc "True when the account has a password, so `anonymous` may not reissue its token."
  def password_protected?(player_id) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT password_hash FROM #{@accounts_table} WHERE player_id = $1",
           arguments: [to_string(player_id)]
         }) do
      {:ok, %{rows: rows}} ->
        Enum.any?(rows, fn row ->
          hash = Map.get(row, "password_hash") || Map.get(row, :password_hash)
          is_binary(hash) and hash != ""
        end)

      _ ->
        false
    end
  end

  ## ---- ROLES (context differentiation) ----

  # Role hierarchy: admin > studio > player > guest.

  @doc "Derives the caller role from scopes: :admin | :studio | :player | :guest."
  def role(scopes), do: Exoforge.Auth.Roles.role(scopes)

  @doc "Highest rank held by a scope list."
  def role_rank(scopes), do: Exoforge.Auth.Roles.rank_of(scopes)

  @doc "Numeric rank required by a declared scope."
  def scope_rank(scope), do: Exoforge.Auth.Roles.rank(scope)

  ## ---- ADMIN BOOTSTRAP (first access) ----

  @doc """
  Ensures the admin account configured via `config :exoforge, :admin`
  (or EXOFORGE_ADMIN_EMAIL / EXOFORGE_ADMIN_PASSWORD) exists.
  Called at plugin boot so the dashboard is reachable on first access.
  """
  def ensure_admin_account do
    case credentials(:admin, "EXOFORGE_ADMIN_EMAIL", "EXOFORGE_ADMIN_PASSWORD") do
      {email, password} when is_binary(email) and email != "" and is_binary(password) and password != "" ->
        _ = upsert_account(@admin_id, email, password, [Roles.admin()])
        Logger.info("[Auth] Admin credentials defined on environment: email=#{email}, password=#{password}")
        Logger.warning("[Auth] Admin credentials should not be defined in environment variables in production after the initial setup.")
        :ok

      {email, _} when is_binary(email) and email != "" ->
        sync_admin_email_if_needed(email)
        :ok

      _ ->
        :ok
    end
  end

  defp sync_admin_email_if_needed(email) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT * FROM #{@accounts_table} WHERE player_id = $1",
           arguments: [@admin_id]
         }) do
      {:ok, %{rows: [row | _]}} ->
        current_email = Map.get(row, "email") || Map.get(row, :email)

        if String.downcase(to_string(current_email)) != String.downcase(to_string(email)) do
          hash = Map.get(row, "password_hash") || Map.get(row, :password_hash)
          scopes = parse_scopes(Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.admin())
          _ = upsert_account_with_hash(@admin_id, email, hash, scopes)
        end

      _ ->
        :ok
    end
  end

  @doc """
  Ensures the optional studio account configured via `config :exoforge, :studio`
  (or EXOFORGE_STUDIO_EMAIL / EXOFORGE_STUDIO_PASSWORD) exists.
  Studio users can read the Studio but cannot run admin-only actions.
  """
  def ensure_studio_account do
    case credentials(:studio, "EXOFORGE_STUDIO_EMAIL", "EXOFORGE_STUDIO_PASSWORD") do
      {email, password} when is_binary(email) and is_binary(password) ->
        _ = upsert_account(@studio_id, email, password, [Roles.studio()])
        :ok

      _ ->
        :ok
    end
  end

  @doc "Creates or updates an email/password account and its scopes."
  def upsert_account(player_id, email, password, scopes) do
    upsert_account_with_hash(player_id, email, hash_password(password), scopes)
  end

  @doc "Creates or updates an account preserving an existing password hash."
  def upsert_account_with_hash(player_id, email, hash, scopes) do
    init_schema()
    email = String.downcase(to_string(email))
    player_id = to_string(player_id)

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM #{@accounts_table} WHERE email = $1 OR player_id = $2",
        arguments: [email, player_id]
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "INSERT INTO #{@accounts_table} (id, player_id, email, password_hash, scopes) VALUES ($1, $2, $3, $4, $5)",
        arguments: [email, player_id, email, hash, Enum.join(scopes, ",")]
      })

    _ = set_player_scopes(player_id, scopes)
    {:ok, %{player_id: player_id, email: email, scopes: scopes}}
  end

  @doc "True when the caller may choose an account's scopes, not just receive `player`."
  def trusted_caller?(payload) do
    auth = Map.get(payload, :_auth) || Map.get(payload, "_auth")

    # Mirrors the dispatcher's trust rule (`extract_caller_scopes`): a payload without `_auth` is an
    # in-process caller - kernel or plugin code, the server itself. Anything presenting `_auth` is
    # an external caller and must hold admin scopes (M33 Fix 1).
    if auth == nil do
      true
    else
      caller = Map.get(auth, "scopes") || Map.get(auth, :scopes) || []
      Roles.satisfies?(List.wrap(caller), Roles.admin())
    end
  end

  defp credentials(config_key, env_email, env_password) do
    config = Application.get_env(:exoforge, config_key, [])

    email =
      case System.get_env(env_email) do
        nil -> config[:email]
        "" -> nil
        val -> val
      end

    password =
      case System.get_env(env_password) do
        nil -> config[:password]
        "" -> nil
        val -> val
      end

    {email, password}
  end

  ## ---- PASSWORD HASHING (PBKDF2, stdlib only) ----

  @pbkdf2_iterations 100_000

  defp hash_password(password) do
    salt = :crypto.strong_rand_bytes(16)
    hash = :crypto.pbkdf2_hmac(:sha256, to_string(password), salt, @pbkdf2_iterations, 32)
    "pbkdf2$" <> Base.encode64(salt) <> "$" <> Base.encode64(hash)
  end

  defp verify_password(password, "pbkdf2$" <> _ = stored) do
    case String.split(stored, "$") do
      ["pbkdf2", salt_b64, hash_b64] ->
        salt = Base.decode64!(salt_b64)
        expected = Base.decode64!(hash_b64)
        actual = :crypto.pbkdf2_hmac(:sha256, to_string(password), salt, @pbkdf2_iterations, 32)
        :crypto.hash_equals(actual, expected)

      _ ->
        false
    end
  end

  defp verify_password(_password, _stored), do: false

  ## ---- DIRECT ELIXIR FACADE ----

  @doc "Issues and stores a new authentication token for a player."
  def issue_token(player_id, scopes) when is_list(scopes) do
    generate_and_store_token(player_id, scopes)
  end

  defp generate_and_store_token(player_id, scopes, disposable \\ nil) do
    init_schema()
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    scopes_str = Enum.join(scopes, ",")

    insert_query =
      "INSERT INTO #{@tokens_table} (id, token, player_id, scopes) VALUES ($1, $2, $3, $4)"

    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: insert_query,
           arguments: [token, token, player_id, scopes_str]
         }) do
      {:ok, _} ->
        # Also record/update the player's primary scopes, and whether it is disposable.
        _ = set_player_scopes(player_id, scopes, disposable)
        {:ok, token}

      error ->
        error
    end
  end

  @doc """
  Registers or updates scopes for a player.

  `disposable` marks the account as one a test or a demo made. `nil` keeps whatever the row already
  had, so changing a player's roles does not quietly make a disposable account permanent — or the
  other way round.
  """
  def set_player_scopes(player_id, scopes, disposable \\ nil) do
    init_schema()
    scopes_str = Enum.join(scopes, ",")
    marked = if is_nil(disposable), do: stored_disposable(player_id), else: as_flag(disposable)

    # Delete previous entry if exists
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM #{@players_table} WHERE player_id = $1",
        arguments: [player_id]
      })

    insert_query =
      "INSERT INTO #{@players_table} (id, player_id, scopes, disposable) VALUES ($1, $2, $3, $4)"

    ActionDispatcher.dispatch(:database, :execute, %{
      plugin: :auth,
      operation: insert_query,
      arguments: [player_id, player_id, scopes_str, marked]
    })
  end

  defp stored_disposable(player_id) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT disposable FROM #{@players_table} WHERE player_id = $1",
           arguments: [player_id]
         }) do
      {:ok, %{rows: [row | _]}} -> row["disposable"] || row[:disposable] || 0
      _ -> 0
    end
  end

  defp as_flag(value), do: if(value in [true, "true", "1", 1], do: 1, else: 0)

  ## ---- PRIVATE HELPERS ----

  defp extract_token(payload) when is_binary(payload), do: payload

  defp extract_token(payload) when is_map(payload) do
    Map.get(payload, :token) || Map.get(payload, "token")
  end

  defp extract_token(_), do: nil

  defp parse_scopes([single_role])
       when single_role in [
              "admin",
              "studio",
              "service",
              "player",
              "guest",
              :admin,
              :studio,
              :service,
              :player,
              :guest
            ] do
    Roles.scopes_for_role(single_role)
  end

  defp parse_scopes(scopes) when is_list(scopes) do
    Enum.map(scopes, &to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_scopes(role) when is_atom(role) do
    Roles.scopes_for_role(role)
  end

  defp parse_scopes(scopes) when is_binary(scopes) do
    trimmed = String.trim(scopes)

    if trimmed in ["admin", "studio", "service", "player", "guest"] do
      Roles.scopes_for_role(trimmed)
    else
      trimmed
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end
  end

  defp parse_scopes(_), do: Roles.scopes_for_role("player")
end
