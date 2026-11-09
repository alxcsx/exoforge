defmodule Exoforge.Std.Auth do
  @moduledoc """
  Standard authentication and authorization plugin for Exoforge.
  Provides the :auth service contract.
  Relies on the :database service for isolated persistence of tokens and scopes.
  """
  use Exoforge.Extension, provides: [:auth]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.PlayerData],
    title: "Users & Auth",
    icon: "🛡️",
    category: "Players",
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

  def children do
    [
      Exoforge.Std.Auth.Cache
    ]
  end

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
      ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :auth,
        operation:
          "CREATE TABLE IF NOT EXISTS #{@tokens_table} (id text, token text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :auth,
        operation:
          "CREATE TABLE IF NOT EXISTS #{@players_table} (id text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :auth,
        operation:
          "CREATE TABLE IF NOT EXISTS #{@accounts_table} (id text, player_id text, email text, password_hash text, scopes text)"
      })

    # `CREATE TABLE IF NOT EXISTS` does not add a column to a table that already exists, so databases
    # that predate this one are brought forward here rather than by a schema reset.
    unless column_exists?(@players_table, "disposable") do
      _ =
        ActionDispatcher.dispatch_internal(:database, :execute, %{
          plugin: :auth,
          operation: "ALTER TABLE #{@players_table} ADD COLUMN disposable integer DEFAULT 0"
        })
    end

    :ok
  end

  defp column_exists?(table, column) do
    # Column inspection is the adapter's dialect, not a PRAGMA here (M33 Fix 9): PostgreSQL does
    # not answer `PRAGMA table_info`, so the check read "no such column" there forever.
    case ActionDispatcher.dispatch_internal(:database, :table_columns, %{
           plugin: :auth,
           table: table
         }) do
      {:ok, %{columns: columns}} -> to_string(column) in columns
      _ -> false
    end
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction authenticate(payload), scope: :global do
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

        {:ok,
         %{user_id: "guest_anon", player_id: "guest_anon", scopes: scopes, role: role(scopes)}}

      true ->
        case Exoforge.Std.Auth.Cache.get(token) do
          {:ok, cached_result} ->
            {:ok, cached_result}

          :error ->
            query = "SELECT * FROM #{@tokens_table} WHERE token = $1"

            case ActionDispatcher.dispatch_internal(:database, :execute, %{
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
                result = %{user_id: uid, player_id: uid, scopes: scopes, role: role(scopes)}
                Exoforge.Std.Auth.Cache.put(token, result)
                {:ok, result}

              {:ok, %{rows: []}} ->
                {:error, :invalid_token}

              {:error, _reason} ->
                {:error, :invalid_token}
            end
        end
    end
  end

  @impl true
  defaction login(payload), scope: :global do
    identifier =
      Map.get(payload, :email) || Map.get(payload, "email") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    password = Map.get(payload, :password) || Map.get(payload, "password")

    if is_nil(identifier) or identifier == "" or is_nil(password) or password == "" do
      {:error, :invalid_credentials}
    else
      clean_id = String.downcase(to_string(identifier))
      query = "SELECT * FROM #{@accounts_table} WHERE email = $1 OR player_id = $2"

      case ActionDispatcher.dispatch_internal(:database, :execute, %{
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

            scopes =
              parse_scopes(
                Map.get(matching_row, "scopes") || Map.get(matching_row, :scopes) ||
                  Roles.player()
              )

            case generate_and_store_token(player_id, scopes) do
              {:ok, token} ->
                Exoforge.EventDispatcher.broadcast(
                  :"auth.login",
                  %{player_id: player_id, role: to_string(role(scopes))}, topic: "auth")

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

  @impl true
  defaction verify_scope(payload), scope: :global do
    user_id =
      Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
        Map.get(payload, :player_id) || Map.get(payload, "player_id")

    required = Map.get(payload, :required_scope) || Map.get(payload, "required_scope")

    cond do
      is_nil(user_id) or is_nil(required) ->
        {:error, :unauthorized}

      # dev_admin_* ids only exist while dev tokens do (M33 Fix 4): in production, where
      # `allow_dev_tokens?` is false, the prefix must not answer yes to anything.
      String.starts_with?(user_id, @dev_admin_prefix) and Exoforge.Config.allow_dev_tokens?() ->
        {:ok, %{authorized: true}}

      true ->
        scopes =
          case ActionDispatcher.dispatch_internal(:database, :execute, %{
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
  defaction register(payload), scope: :global do
    do_register_player(payload)
  end

  @impl true
  defaction create_player(payload), scope: :global do
    do_register_player(payload)
  end

  @doc """
  Creates or resumes an anonymous player session.

  Supply `player_id` to reissue a token for an existing player (a returning device);
  otherwise a new player is registered using the optional display `name`.
  """
  @impl true
  defaction anonymous(payload), scope: :global do
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
            device_id =
              Map.get(payload, :device_id) || Map.get(payload, "device_id") ||
                if String.starts_with?(player_id, "did_"), do: player_id, else: nil

            attach_device_id(player_id, device_id)

            case anonymous_token(player_id) do
              {:ok, result} ->
                Exoforge.EventDispatcher.broadcast(:"auth.anonymous", %{player_id: player_id},
                  topic: "auth"
                )

                {:ok, Map.put(result, :name, player_name(player_id))}

              error ->
                error
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

          case ActionDispatcher.dispatch_internal(:database, :execute, %{
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

    ids_filter = user_ids_where(payload)

    union =
      "SELECT player_id FROM #{@players_table} UNION SELECT player_id FROM #{@accounts_table} UNION SELECT player_id FROM #{@tokens_table}"

    {ids, total} = page_user_ids(union, ids_filter, payload)

    players_rows = rows_in(@players_table, ids)
    tokens_rows = rows_in(@tokens_table, ids)
    accounts_rows = rows_in(@accounts_table, ids)

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

    users =
      Enum.map(ids, fn pid ->
        p_row = Map.get(players_by_id, pid, %{})
        acc_row = Map.get(accounts_by_id, pid, %{})

        raw_scopes =
          Map.get(p_row, "scopes") || Map.get(p_row, :scopes) ||
            Map.get(acc_row, "scopes") || Map.get(acc_row, :scopes) || Roles.player()

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
          "is_protected" => protected_account?(pid)
        }
      end)

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

      protected_account?(user_id) ->
        {:error, :protected_admin_account}

      is_nil(password) or password == "" ->
        {:error, :invalid_password}

      true ->
        init_schema()
        pid = to_string(user_id)

        acc_by_pid =
          case ActionDispatcher.dispatch_internal(:database, :execute, %{
                 plugin: :auth,
                 operation: "SELECT * FROM #{@accounts_table} WHERE player_id = $1",
                 arguments: [pid]
               }) do
            {:ok, %{rows: [r | _]}} -> r
            _ -> nil
          end

        acc_row =
          acc_by_pid ||
            case ActionDispatcher.dispatch_internal(:database, :execute, %{
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
              parse_scopes(
                Map.get(acc_row, "scopes") || Map.get(acc_row, :scopes) || Roles.player()
              )

            _ = upsert_account(actual_pid, email, password, scopes)
            {:ok, %{user_id: actual_pid, player_id: actual_pid, status: "password_reset"}}

          nil ->
            pquery = "SELECT * FROM #{@players_table} WHERE player_id = $1"

            case ActionDispatcher.dispatch_internal(:database, :execute, %{
                   plugin: :auth,
                   operation: pquery,
                   arguments: [pid]
                 }) do
              {:ok, %{rows: [prow | _]}} ->
                scopes =
                  parse_scopes(
                    Map.get(prow, "scopes") || Map.get(prow, :scopes) || Roles.player()
                  )

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

      protected_account?(user_id) ->
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
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "UPDATE #{@accounts_table} SET scopes = $1 WHERE player_id = $2",
            arguments: [scopes_str, pid]
          })

        _ =
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "UPDATE #{@accounts_table} SET scopes = $1 WHERE email = $2",
            arguments: [scopes_str, pid]
          })

        _ =
          ActionDispatcher.dispatch_internal(:database, :execute, %{
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
      case ActionDispatcher.dispatch_internal(:database, :execute, %{
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

      protected_account?(user_id) ->
        {:error, :protected_admin_account}

      true ->
        init_schema()
        pid = to_string(user_id)

        _ =
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@players_table} WHERE player_id = $1",
            arguments: [pid]
          })

        _ =
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@tokens_table} WHERE player_id = $1",
            arguments: [pid]
          })

        _ =
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@accounts_table} WHERE player_id = $1",
            arguments: [pid]
          })

        _ =
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{@accounts_table} WHERE email = $1",
            arguments: [pid]
          })

        # Retain player record without user linkage for data retention and telemetry compliance
        _ = ActionDispatcher.dispatch_internal(:player_data, :retain_player, %{player_id: pid})

        {:ok, %{user_id: pid, player_id: pid, status: "deleted"}}
    end
  end

  # Anonymous accounts start unnamed; the client prompts for a display name afterwards.
  defp rename_player(player_id, name) do
    case ActionDispatcher.dispatch_internal(:player_data, :update_player, %{
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
          ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :auth,
            operation: "DELETE FROM #{table} WHERE player_id = $1",
            arguments: [player_id]
          })
      end)

      # The rest of a player's data belongs to other plugins; asked to clean up after itself, a
      # disposable player should not leave a profile and a leaderboard row behind.
      _ =
        ActionDispatcher.dispatch_internal(:player_data, :delete_player, %{player_id: player_id})
    end)
  end

  defp register_unnamed(payload) do
    case do_register_player(payload, allow_empty_name: true) do
      {:ok, %{player: profile} = result} ->
        Exoforge.EventDispatcher.broadcast(:"auth.anonymous", %{player_id: result.player_id},
          topic: "auth"
        )

        {:ok, Map.put(result, :name, Map.get(profile, "name") || "")}

      error ->
        error
    end
  end

  defp player_name(player_id) do
    case ActionDispatcher.dispatch_internal(:player_data, :get_player, %{player_id: player_id}) do
      {:ok, %{player: profile}} -> Map.get(profile, "name") || Map.get(profile, :name)
      _ -> nil
    end
  end

  defp attach_device_id(_player_id, nil), do: :ok
  defp attach_device_id(_player_id, ""), do: :ok

  defp attach_device_id(player_id, device_id) do
    did = to_string(device_id)

    case ActionDispatcher.dispatch_internal(:player_data, :get_player, %{player_id: player_id}) do
      {:ok, %{player: profile}} ->
        existing_devices = Map.get(profile, "device_ids") || []
        current_did = Map.get(profile, "device_id")

        if did in existing_devices and current_did == did do
          :ok
        else
          new_devices = Enum.uniq(existing_devices ++ [did])
          existing_attrs = Map.get(profile, "attributes") || []

          updated_attrs =
            Enum.reject(existing_attrs, fn attr ->
              (Map.get(attr, "key") || Map.get(attr, :key)) == "device_id"
            end) ++ [%{"key" => "device_id", "value" => did}]

          updated_data = %{
            "device_id" => did,
            "device_ids" => new_devices,
            "attributes" => updated_attrs
          }

          _ =
            ActionDispatcher.dispatch_internal(:player_data, :update_player, %{
              player_id: player_id,
              data: updated_data
            })

          :ok
        end

      _ ->
        :ok
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

    raw_device_id =
      Map.get(payload, :device_id) || Map.get(payload, "device_id") ||
        if is_binary(user_id) and String.starts_with?(user_id, "did_"), do: user_id, else: nil

    device_id_str =
      if raw_device_id && raw_device_id != "", do: to_string(raw_device_id), else: nil

    if raw_password && raw_password != "" do
      _ = upsert_account(user_id, email, raw_password, scopes)
    end

    case generate_and_store_token(user_id, scopes, disposable) do
      {:ok, token} ->
        base_attrs = [
          %{"key" => "locale", "value" => "en_US"},
          %{
            "key" => "registered_at",
            "value" => Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")
          }
        ]

        attrs =
          if device_id_str do
            base_attrs ++ [%{"key" => "device_id", "value" => device_id_str}]
          else
            base_attrs
          end

        profile = %{
          "user_id" => user_id,
          "player_id" => user_id,
          "name" => name,
          "email" => email,
          "total_spent" => "$0.00",
          "time_in_game" => "0m",
          "status" => "Active",
          "device_id" => device_id_str,
          "device_ids" => if(device_id_str, do: [device_id_str], else: []),
          "attributes" => attrs
        }

        # Hook into player_data canonical profile store, linking player to user
        case ActionDispatcher.dispatch_internal(:player_data, :create_player, %{
               player_id: user_id,
               user_id: user_id,
               profile: profile
             }) do
          {:error, reason} ->
            {:error, reason}

          _ ->
            Exoforge.EventDispatcher.broadcast(
              :"auth.register",
              %{player_id: user_id, email: email, role: to_string(role(scopes))}, topic: "auth")

            {:ok,
             %{
               user_id: user_id,
               player_id: user_id,
               token: token,
               scopes: scopes,
               player: profile
             }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  True for the account user actions may not delete, re-scope, or re-password.

  Only the administrator is protected, and it is recognized by its constant id — not by the
  current environment, so the protection does not blink on and off while a boot reconciles the
  credentials.
  """
  def protected_account?(player_id), do: to_string(player_id) == @admin_id

  @doc "True when the account has a password, so `anonymous` may not reissue its token."
  def password_protected?(player_id) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
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

  ## ---- ADMIN ACCOUNT ----

  @doc """
  Reconciles the administrator account with the environment. Called on boot.

  The administrator is an ordinary account, not a special case: `id` is the constant `"admin"`,
  the credentials come from `config :exoforge, :admin` (or EXOFORGE_ADMIN_EMAIL /
  EXOFORGE_ADMIN_PASSWORD), and when those are configured it is created or updated like any other
  account. When they are not configured it is removed, together with its tokens: a credential that
  is no longer set must not keep working. The id, not the email, is what survives — a removed and
  re-configured administrator comes back as the same player. The one privilege it retains is that
  user actions cannot delete or re-scope it (`protected_account?/1`).
  """
  def ensure_admin_account do
    case credentials(:admin, "EXOFORGE_ADMIN_EMAIL", "EXOFORGE_ADMIN_PASSWORD") do
      {email, password}
      when is_binary(email) and email != "" and is_binary(password) and password != "" ->
        _ = upsert_account(@admin_id, email, password, [Roles.admin()])

        Logger.info(
          "[Auth] Administrator account #{@admin_id} reconciled for #{String.downcase(email)}"
        )

        :ok

      _ ->
        remove_account(@admin_id)
    end
  end

  # Deleting rows is not enough: `authenticate` answers from the token cache before it looks at the
  # tokens table, so a removed account's sessions have to leave the cache too.
  defp remove_account(player_id) do
    for table <- [@players_table, @accounts_table, @tokens_table] do
      _ =
        ActionDispatcher.dispatch_internal(:database, :execute, %{
          plugin: :auth,
          operation: "DELETE FROM #{table} WHERE player_id = $1",
          arguments: [player_id]
        })
    end

    _ = Exoforge.Std.Auth.Cache.flush()
    :ok
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
      ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM #{@accounts_table} WHERE email = $1 OR player_id = $2",
        arguments: [email, player_id]
      })

    _ =
      ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :auth,
        operation:
          "INSERT INTO #{@accounts_table} (id, player_id, email, password_hash, scopes) VALUES ($1, $2, $3, $4, $5)",
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

    case ActionDispatcher.dispatch_internal(:database, :execute, %{
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
      ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM #{@players_table} WHERE player_id = $1",
        arguments: [player_id]
      })

    insert_query =
      "INSERT INTO #{@players_table} (id, player_id, scopes, disposable) VALUES ($1, $2, $3, $4)"

    ActionDispatcher.dispatch_internal(:database, :execute, %{
      plugin: :auth,
      operation: insert_query,
      arguments: [player_id, player_id, scopes_str, marked]
    })
  end

  defp stored_disposable(player_id) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: :auth,
           operation: "SELECT disposable FROM #{@players_table} WHERE player_id = $1",
           arguments: [player_id]
         }) do
      {:ok, %{rows: [row | _]}} -> row["disposable"] || row[:disposable] || 0
      _ -> 0
    end
  end

  defp as_flag(value), do: if(value in [true, "true", "1", 1], do: 1, else: 0)

  # Paging and filtering belong in the query, not to the caller: the directory can hold thousands
  # of players, and a page of an unordered in-memory list is a page of a different list every call.
  defp user_ids_where(payload) do
    search = payload |> param_value([:search, "search"]) |> to_string() |> String.trim()
    scope = payload |> param_value([:scope, "scope"]) |> to_string()

    {clauses, args} =
      [search: search, scope: if(scope in ["", "all"], do: "", else: scope)]
      |> Enum.reject(fn {_kind, value} -> value == "" end)
      |> Enum.map(fn
        {:search, value} -> {&search_clause/1, "%#{String.downcase(value)}%"}
        {:scope, value} -> {&scope_exists_clause/1, "%#{value}%"}
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{build, arg}, index} -> {build.("$#{index}"), arg} end)
      |> Enum.unzip()

    sql = if clauses == [], do: "", else: " WHERE " <> Enum.join(clauses, " AND ")
    %{sql: sql, args: args}
  end

  # Matches the id itself or the account's email, so a search works with whichever one the caller
  # remembers.
  defp search_clause(placeholder) do
    "(LOWER(ids.player_id) LIKE #{placeholder} OR " <>
      "LOWER(COALESCE((SELECT MAX(acct.email) FROM #{@accounts_table} acct " <>
      "WHERE acct.player_id = ids.player_id), '')) LIKE #{placeholder})"
  end

  # Scopes are stored as a comma-joined list, so membership is a LIKE over the row (and over both
  # tables that can carry them).
  defp scope_exists_clause(placeholder) do
    "(EXISTS (SELECT 1 FROM #{@players_table} p WHERE p.player_id = ids.player_id AND p.scopes LIKE #{placeholder}) OR " <>
      "EXISTS (SELECT 1 FROM #{@accounts_table} a WHERE a.player_id = ids.player_id AND a.scopes LIKE #{placeholder}))"
  end

  defp page_user_ids(union, ids_filter, payload) do
    limit = int_value(param_value(payload, [:limit, "limit"]), nil)
    offset = max(int_value(param_value(payload, [:offset, "offset"]), 0), 0)

    total =
      case run_query("SELECT COUNT(*) AS n FROM (#{union}) ids#{ids_filter.sql}", ids_filter.args) do
        [row | _] -> int_value(row["n"] || row[:n], 0)
        [] -> 0
      end

    page_sql =
      if is_integer(limit) and limit > 0 do
        " ORDER BY player_id LIMIT #{limit} OFFSET #{offset}"
      else
        " ORDER BY player_id"
      end

    ids =
      "SELECT player_id FROM (#{union}) ids#{ids_filter.sql}#{page_sql}"
      |> run_query(ids_filter.args)
      |> Enum.map(&to_string(&1["player_id"] || &1[:player_id]))

    {ids, total}
  end

  defp rows_in(_table, []), do: []

  defp rows_in(table, ids) do
    placeholders = Enum.map_join(1..length(ids), ", ", &"$#{&1}")
    run_query("SELECT * FROM #{table} WHERE player_id IN (#{placeholders})", ids)
  end

  defp run_query(sql, args) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: :auth,
           operation: sql,
           arguments: args
         }) do
      {:ok, %{rows: rows}} when is_list(rows) -> rows
      _ -> []
    end
  end

  defp param_value(payload, keys) when is_map(payload) do
    Enum.find_value(keys, fn key -> Map.get(payload, key) end)
  end

  defp param_value(_, _), do: nil

  defp int_value(nil, default), do: default
  defp int_value(value, _default) when is_integer(value), do: value

  defp int_value(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp int_value(_value, default), do: default

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

defmodule Exoforge.Std.Auth.Cache do
  use GenServer

  @table :exoforge_auth_tokens

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(token) do
    case :ets.lookup(@table, token) do
      [{^token, result}] -> {:ok, result}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  def put(token, result) do
    try do
      :ets.insert(@table, {token, result})
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  def flush do
    try do
      :ets.delete_all_objects(@table)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
