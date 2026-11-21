defmodule Exoforge.Std.Auth do
  @moduledoc """
  Standard authentication and authorization extension for Exoforge.
  Provides the :auth service contract.
  Relies on the :database service for isolated persistence of tokens and scopes.

  A credential is `exo_<kind>_<token_id>.<secret>` - the id names the row, the secret is never
  stored, only its SHA-256. Kinds: `ses` (player access, short-lived), `ref` (single-use refresh,
  rotating) and `svc` (tooling, no refresh). Every row carries an expiry, so a credential that is
  forgotten still stops working, and every row can be revoked by id.
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

  # A token is `exo_<kind>_<token_id>.<secret>`: the id is the lookup key and is stored beside the
  # row it names, the secret never is. The suffix says what the credential is for, so a refresh
  # token presented as a bearer token is refused by kind rather than by luck.
  @token_prefix "exo"

  @token_columns [
    {"token_id", "text"},
    {"user_id", "text"},
    {"kind", "text"},
    {"secret_hash", "text"},
    {"expires_at", "text"},
    {"created_at", "text"},
    {"last_used_at", "text"},
    {"revoked_at", "text"},
    {"family_id", "text"},
    {"device_id", "text"}
  ]

  # Lifetimes in seconds. An access token is short because it travels on every request and a client
  # can renew it; the refresh token is the long-lived credential and is single-use. A service token
  # has no refresh and a term long enough to be pasted into a server's configuration.
  @access_ttl 3_600
  @refresh_ttl 2_592_000
  @service_ttl 7_776_000
  @max_sessions 10

  # Writing `last_used_at` on every request would be a write per call for a field people read
  # occasionally; once a minute is the resolution the listing needs.
  @touch_interval_seconds 60

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
      execute("CREATE TABLE IF NOT EXISTS #{@tokens_table} (#{Enum.map_join(@token_columns, ", ", fn {name, type} -> "#{name} #{type}" end)})")

    _ =
      execute("CREATE TABLE IF NOT EXISTS #{@players_table} (id text, player_id text, scopes text)")

    _ =
      execute("CREATE TABLE IF NOT EXISTS #{@accounts_table} (id text, player_id text, email text, password_hash text, scopes text)")

    # `CREATE TABLE IF NOT EXISTS` does not add a column to a table that already exists, so databases
    # that predate this one are brought forward here rather than by a schema reset.
    ensure_column(@players_table, "disposable", "integer DEFAULT 0")

    # One inspection per table, not one per column: this runs on every boot and from the actions
    # that need the schema.
    token_columns = table_columns(@tokens_table)
    ensure_token_columns(token_columns)
    migrate_legacy_tokens(token_columns)

    _ =
      ActionDispatcher.dispatch_internal(:lldb, :run_migrations, %{
        namespace: :auth,
        migrations: [
          %{
            version: 1,
            name: "lookup keys",
            sql: [
              "DELETE FROM tokens a USING tokens b WHERE a.token_id = b.token_id AND a.ctid > b.ctid",
              "DELETE FROM accounts a USING accounts b WHERE a.id = b.id AND a.ctid > b.ctid",
              "DELETE FROM players a USING players b WHERE a.id = b.id AND a.ctid > b.ctid",
              "CREATE UNIQUE INDEX IF NOT EXISTS tokens_token_id_key ON tokens (token_id)",
              "CREATE INDEX IF NOT EXISTS tokens_user_id ON tokens (user_id)",
              "CREATE UNIQUE INDEX IF NOT EXISTS accounts_id_key ON accounts (id)",
              "CREATE UNIQUE INDEX IF NOT EXISTS accounts_email_key ON accounts (email)",
              "CREATE UNIQUE INDEX IF NOT EXISTS players_id_key ON players (id)"
            ]
          }
        ]
      })

    :ok
  end

  defp execute(sql, args \\ []) do
    ActionDispatcher.dispatch_internal(:database, :execute, %{
      plugin: :auth,
      operation: sql,
      arguments: args
    })
  end

  defp ensure_column(table, column, definition) do
    unless column_exists?(table, column) do
      _ = execute("ALTER TABLE #{table} ADD COLUMN #{column} #{definition}")
    end
  end

  defp ensure_token_columns(existing) do
    Enum.each(@token_columns, fn {name, type} ->
      unless name in existing do
        _ = execute("ALTER TABLE #{@tokens_table} ADD COLUMN #{name} #{type}")
      end
    end)

    :ok
  end

  defp table_columns(table) do
    # Column inspection is the adapter's dialect, not a PRAGMA here (M33 Fix 9): PostgreSQL does
    # not answer `PRAGMA table_info`, so the check read "no such column" there forever.
    case ActionDispatcher.dispatch_internal(:database, :table_columns, %{
           plugin: :auth,
           table: table
         }) do
      {:ok, %{columns: columns}} -> Enum.map(columns, &to_string/1)
      _ -> []
    end
  end

  defp column_exists?(table, column), do: to_string(column) in table_columns(table)

  # Rows written before tokens were hashed carry the credential itself in `token`, with the
  # account's scopes copied beside it. They are hashed in place - the old string is the secret,
  # and the row keeps working - and given the refresh lifetime so they age out instead of living
  # forever. Nothing is invalidated by the upgrade.
  defp migrate_legacy_tokens(columns) do
    if "token" in columns do
      now = now_iso()
      expires = iso_after(@refresh_ttl)

      _ =
        case execute("SELECT token, player_id FROM #{@tokens_table} WHERE token IS NOT NULL AND token != '' AND token_id IS NULL") do
          {:ok, %{rows: rows}} ->
            Enum.each(rows, fn row ->
              token = row["token"] || row[:token]
              player_id = row["player_id"] || row[:player_id]

              # The id is derived, not stored: a legacy token's lookup key is the hash of the
              # token itself, so no column holds the credential.
              hashed = hash_secret(token)

              _ =
                execute(
                  "UPDATE #{@tokens_table} SET token_id = $1, user_id = $2, kind = $3, secret_hash = $4, expires_at = $5, created_at = $6, token = '' WHERE token = $7",
                  [hashed, player_id, "legacy", hashed, expires, now, token]
                )
            end)

          _ ->
            :ok
        end
    end

    :ok
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

        {:ok, %{user_id: "guest_anon", player_id: "guest_anon", scopes: scopes, role: role(scopes)}}

      true ->
        verify_token(token)
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

            device_id = Map.get(payload, :device_id) || Map.get(payload, "device_id")

            case start_session(player_id, device_id) do
              {:ok, session} ->
                Exoforge.EventDispatcher.broadcast(
                  :"auth.login",
                  %{player_id: player_id, role: to_string(role(scopes))},
                  topic: "auth"
                )

                {:ok,
                 %{
                   player_id: player_id,
                   token: session.token,
                   refresh_token: session.refresh_token,
                   expires_in: session.expires_in,
                   scopes: scopes,
                   role: role(scopes)
                 }}

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
    register_unprotected(payload)
  end

  @impl true
  defaction create_player(payload), scope: :global do
    register_unprotected(payload)
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

            case anonymous_token(player_id, device_id) do
              {:ok, result} ->
                Exoforge.EventDispatcher.broadcast(:"auth.anonymous", %{player_id: player_id}, topic: "auth")

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
      user_id_from(payload)

    expires_in = int_value(Map.get(payload, :expires_in) || Map.get(payload, "expires_in"), nil)

    cond do
      is_nil(user_id) or user_id == "" ->
        {:error, :invalid_player}

      # A token is a credential for an account. Minting one for an id nobody holds would create a
      # second, invisible identity that owns nothing and cannot be managed.
      not user_exists?(user_id) ->
        {:error, :unknown_user}

      true ->
        # Scopes are the account's, read when the token authenticates: `scopes` in the payload is
        # accepted for older callers and ignored, so a token cannot carry a role its account lost.
        case new_token("svc", user_id, expires_in || service_ttl(), nil, nil) do
          {:ok, token} ->
            {:ok,
             %{
               token: token.token,
               token_id: token.token_id,
               user_id: user_id,
               player_id: user_id,
               expires_at: token.expires_at,
               expires_in: token.expires_in
             }}

          error ->
            error
        end
    end
  end

  @doc """
  Exchanges a refresh token for a fresh pair.

  The presented refresh token is rotated: it is revoked, and its replacement belongs to the same
  family. Presenting a rotated token again means the credential leaked, so the whole family - the
  access token that was issued beside it and every descendant - is revoked.
  """
  @impl true
  defaction refresh(payload), scope: :global do
    token = extract_token(payload)

    with {:ok, token_id, secret} <- parse_refresh_token(token),
         %{} = row <- fetch_token(token_id) do
      cond do
        not secret_matches?(secret, row["secret_hash"] || row[:secret_hash]) ->
          {:error, :invalid_token}

        row["revoked_at"] || row[:revoked_at] ->
          _ = revoke_family(row["family_id"] || row[:family_id])
          _ = Exoforge.Std.Auth.Cache.flush()
          {:error, :invalid_token}

        expired?(row) ->
          {:error, :token_expired}

        true ->
          user_id = to_string(row["user_id"] || row[:user_id])
          family_id = row["family_id"] || row[:family_id]
          device_id = row["device_id"] || row[:device_id]

          _ = revoke_row(token_id)

          with {:ok, access} <- new_token("ses", user_id, access_ttl(), family_id, device_id),
               {:ok, rotated} <- new_token("ref", user_id, refresh_ttl(), family_id, device_id) do
            {:ok,
             %{
               player_id: user_id,
               user_id: user_id,
               token: access.token,
               refresh_token: rotated.token,
               expires_in: access.expires_in,
               refresh_expires_in: rotated.expires_in
             }}
          end
      end
    else
      _ -> {:error, :invalid_token}
    end
  end

  @impl true
  defaction list_tokens(payload), scope: Exoforge.Auth.Roles.admin() do
    user_id = user_id_from(payload)

    {sql, args} =
      if is_nil(user_id) or user_id == "" do
        {"SELECT * FROM #{@tokens_table} ORDER BY created_at", []}
      else
        {"SELECT * FROM #{@tokens_table} WHERE user_id = $1 ORDER BY created_at", [user_id]}
      end

    tokens = sql |> run_query(args) |> Enum.map(&token_summary/1)

    {:ok, %{tokens: tokens, count: length(tokens)}}
  end

  @impl true
  defaction revoke_token(payload), scope: Exoforge.Auth.Roles.admin() do
    token_id = Map.get(payload, :token_id) || Map.get(payload, "token_id")
    row = if is_nil(token_id) or token_id == "", do: nil, else: fetch_token(token_id)

    cond do
      # A token that is already revoked is not a token any more; reporting it as missing is what
      # lets a caller tell "revoked now" from "there was nothing to revoke".
      is_nil(row) or revoked?(row) ->
        {:error, :token_not_found}

      true ->
        # Revoking one credential of a session revokes the session: leaving the refresh token alive
        # would let the client it belongs to mint a replacement for the access token just killed.
        revoke_family(row["family_id"] || row[:family_id], token_id)
        _ = Exoforge.Std.Auth.Cache.flush()
        {:ok, %{token_id: token_id, status: "revoked"}}
    end
  end

  @doc """
  Deletes expired and revoked token rows. Called by the cron extension.

  The rows are the only record that a rotated refresh token was used, so replay detection is
  bounded by the purge interval: an old token replayed after its row is gone is refused as
  unknown, not as a leak. That is the cost of not keeping credentials' history forever.
  """
  @impl true
  defaction purge_tokens(), scope: :server do
    init_schema()
    now = now_iso()

    purged =
      case run_query(
             "SELECT COUNT(*) AS n FROM #{@tokens_table} WHERE revoked_at IS NOT NULL OR (expires_at IS NOT NULL AND expires_at <= $1)",
             [now]
           ) do
        [row | _] -> int_value(row["n"] || row[:n], 0)
        [] -> 0
      end

    _ =
      execute(
        "DELETE FROM #{@tokens_table} WHERE revoked_at IS NOT NULL OR (expires_at IS NOT NULL AND expires_at <= $1)",
        [now]
      )

    {:ok, %{purged: purged}}
  end

  @impl true
  defaction list_users(payload), scope: Exoforge.Auth.Roles.studio() do
    init_schema()

    ids_filter = user_ids_where(payload)

    union =
      "SELECT player_id FROM #{@players_table} UNION SELECT player_id FROM #{@accounts_table} UNION SELECT user_id AS player_id FROM #{@tokens_table}"

    {ids, total} = page_user_ids(union, ids_filter, payload)

    players_rows = rows_in(@players_table, ids)
    tokens_rows = rows_in(@tokens_table, ids, "user_id")
    accounts_rows = rows_in(@accounts_table, ids)

    tokens_by_player =
      Enum.group_by(tokens_rows, fn row ->
        to_string(Map.get(row, "user_id") || Map.get(row, :user_id))
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

        active_tokens =
          tokens
          |> Enum.reject(fn t -> t["revoked_at"] || t[:revoked_at] end)
          |> Enum.reject(fn t -> expired?(t) end)
          |> Enum.map(&token_summary/1)

        %{
          "user_id" => pid,
          "player_id" => pid,
          "name" => Map.get(acc_row, "name") || Map.get(acc_row, :name) || pid,
          "email" => email,
          "scopes" => scopes,
          "tokens_count" => length(active_tokens),
          "active_tokens" => active_tokens,
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
              parse_scopes(Map.get(acc_row, "scopes") || Map.get(acc_row, :scopes) || Roles.player())

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

        # authenticate reads the account's scopes, so there is nothing to rewrite in the token rows:
        # a role change takes effect at the next authentication, for every token the account holds.
        # The cache still has to go, because it holds the answer it gave yesterday.
        _ = Exoforge.Std.Auth.Cache.flush()
        {:ok, %{user_id: pid, player_id: pid, scopes: scopes}}
    end
  end

  @doc """
  Removes every account a test or a demo created.

  A player is disposable because it said so: `auth.anonymous` or `auth.register` with
  `disposable: true`. Nothing is inferred from a name or a scope, so a purge on a live server
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
      _ = Exoforge.Std.Auth.Cache.flush()
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
            operation: "DELETE FROM #{@tokens_table} WHERE user_id = $1",
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

        # The account's stored cluster events are personal data too. Best-effort: an instance
        # without the observability extension still deletes the account. Cold archive files are
        # not rewritten here (documented ceiling).
        _ = ActionDispatcher.dispatch_internal(:observability, :purge_events, %{origin: pid})

        # A deleted account's cached tokens would otherwise keep authenticating.
        _ = Exoforge.Std.Auth.Cache.flush()
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

  defp anonymous_token(player_id, device_id) do
    scopes = [Roles.player()]

    case start_session(player_id, device_id) do
      {:ok, session} ->
        {:ok,
         %{
           player_id: player_id,
           token: session.token,
           refresh_token: session.refresh_token,
           expires_in: session.expires_in,
           scopes: scopes,
           role: role(scopes)
         }}

      error ->
        error
    end
  end

  defp remove_disposable(ids) do
    Enum.each(ids, fn player_id ->
      _ = execute("DELETE FROM #{@tokens_table} WHERE user_id = $1", [player_id])

      Enum.each([@accounts_table, @players_table], fn table ->
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
        Exoforge.EventDispatcher.broadcast(:"auth.anonymous", %{player_id: result.player_id}, topic: "auth")

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

    # `set_player_scopes` also records the disposable marker; a password registration reaches it
    # through `upsert_account`, which does not know about it.
    _ = set_player_scopes(user_id, scopes, disposable)

    case start_session(user_id, device_id_str) do
      {:ok, session} ->
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
              %{player_id: user_id, email: email, role: to_string(role(scopes))},
              topic: "auth"
            )

            {:ok,
             %{
               user_id: user_id,
               player_id: user_id,
               token: session.token,
               refresh_token: session.refresh_token,
               expires_in: session.expires_in,
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

  # Register upserts the account it names, and the transport names the caller's own id when the
  # payload doesn't: an admin creating a user without an id used to overwrite the administrator.
  # The administrator is reconciled from config, never through a user action.
  defp register_unprotected(payload) do
    target = Map.get(payload, :user_id) || Map.get(payload, "user_id") || Map.get(payload, :player_id) || Map.get(payload, "player_id")

    if target && protected_account?(target),
      do: {:error, :protected_admin_account},
      else: do_register_player(payload)
  end

  @doc """
  Instance reset: deletes every account and player that is not the administrator or another
  admin/studio account, and every service token and token of a deleted account. Returns
  `%{removed: n, kept: [player_id]}`.
  """
  def wipe_accounts do
    init_schema()
    keep_scopes = [to_string(Roles.admin()), to_string(Roles.studio())]

    keep_sql =
      Enum.map_join(keep_scopes, " OR ", fn s -> "scopes LIKE '%#{String.replace(s, "'", "")}%'" end)

    kept =
      case execute("SELECT player_id FROM #{@accounts_table} WHERE player_id = $1 OR #{keep_sql}", [@admin_id]) do
        {:ok, %{rows: rows}} -> rows |> Enum.map(&(&1["player_id"])) |> Enum.reject(&is_nil/1) |> Enum.uniq()
        _ -> []
      end

    kept = Enum.uniq([@admin_id | kept])

    all_ids =
      case execute("SELECT player_id FROM #{@players_table} UNION SELECT player_id FROM #{@accounts_table}") do
        {:ok, %{rows: rows}} -> rows |> Enum.map(&(&1["player_id"])) |> Enum.reject(&is_nil/1)
        _ -> []
      end

    doomed = all_ids -- kept

    Enum.each(doomed, fn id ->
      _ = execute("DELETE FROM #{@players_table} WHERE player_id = $1", [id])
      _ = execute("DELETE FROM #{@accounts_table} WHERE player_id = $1", [id])
      _ = execute("DELETE FROM #{@tokens_table} WHERE user_id = $1", [id])
    end)

    _ = execute("DELETE FROM #{@tokens_table} WHERE kind = 'svc'")
    _ = Exoforge.Std.Auth.Cache.flush()
    %{removed: length(doomed), kept: kept}
  end

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

        Logger.info("[Auth] Administrator account #{@admin_id} reconciled for #{String.downcase(email)}")

        :ok

      _ ->
        remove_account(@admin_id)
    end
  end

  # Deleting rows is not enough: `authenticate` answers from the token cache before it looks at the
  # tokens table, so a removed account's sessions have to leave the cache too.
  defp remove_account(player_id) do
    _ = execute("DELETE FROM #{@tokens_table} WHERE user_id = $1", [player_id])

    for table <- [@players_table, @accounts_table] do
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

  @doc """
  Issues and stores a service token for a player, for in-process callers.

  The action of the same name (`issue_token/1`) also refuses an id nobody holds; this facade is
  the kernel-side door tests and tooling already knock on, so it records the account first.
  """
  def issue_token(player_id, scopes) when is_list(scopes) do
    init_schema()
    _ = set_player_scopes(player_id, scopes)

    case new_token("svc", to_string(player_id), service_ttl(), nil, nil) do
      {:ok, token} -> {:ok, token.token}
      error -> error
    end
  end

  defp start_session(player_id, device_id) do
    player_id = to_string(player_id)
    device_id = blank_to_nil(device_id)

    # A login for a device replaces that device's session: two live sessions for one device are
    # the same credential held twice, and one of them is always stale.
    replaced = revoke_device_sessions(player_id, device_id)
    evicted = enforce_session_cap(player_id)

    # A revoked row still authenticates from the cache, which holds the answer it gave before the
    # revocation. Clearing it is what makes "revoked" mean revoked, not "revoked at next flush".
    if replaced or evicted do
      _ = Exoforge.Std.Auth.Cache.flush()
    end

    family_id = random_string(12)

    with {:ok, access} <- new_token("ses", player_id, access_ttl(), family_id, device_id),
         {:ok, refresh} <- new_token("ref", player_id, refresh_ttl(), family_id, device_id) do
      {:ok,
       %{
         token: access.token,
         token_id: access.token_id,
         refresh_token: refresh.token,
         expires_in: access.expires_in,
         refresh_expires_in: refresh.expires_in,
         family_id: family_id
       }}
    end
  end

  defp new_token(kind, user_id, ttl, family_id, device_id) do
    token_id = random_string(12)
    secret = random_string(32)
    # Creation is ordered (the session cap evicts the oldest), so it keeps the clock's resolution
    # rather than rounding three logins in the same second into a tie.
    created_at = DateTime.utc_now() |> DateTime.to_iso8601()
    expires_at = iso_after(ttl)

    case execute(
           "INSERT INTO #{@tokens_table} (token_id, user_id, kind, secret_hash, expires_at, created_at, family_id, device_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
           [
             token_id,
             user_id,
             kind,
             hash_secret(secret),
             expires_at,
             created_at,
             family_id,
             device_id
           ]
         ) do
      {:ok, _} ->
        {:ok,
         %{
           token: "#{@token_prefix}_#{kind}_#{token_id}.#{secret}",
           token_id: token_id,
           expires_at: expires_at,
           expires_in: ttl,
           kind: kind
         }}

      error ->
        error
    end
  end

  # The oldest sessions go first: the cap exists so one account cannot accumulate credentials
  # forever, and a stale session is the one worth dropping.
  defp enforce_session_cap(user_id) do
    max = max_sessions()

    families =
      run_query(
        "SELECT family_id, MIN(created_at) AS created FROM #{@tokens_table} WHERE user_id = $1 AND kind = 'ref' AND revoked_at IS NULL AND expires_at > $2 GROUP BY family_id ORDER BY created ASC",
        [user_id, now_iso()]
      )
      |> Enum.map(fn row -> row["family_id"] || row[:family_id] end)

    excess = length(families) - (max - 1)

    if excess > 0 do
      families |> Enum.take(excess) |> Enum.each(&revoke_family/1)
      true
    else
      false
    end
  end

  defp revoke_device_sessions(_user_id, nil), do: false

  defp revoke_device_sessions(user_id, device_id) do
    _ =
      execute(
        "UPDATE #{@tokens_table} SET revoked_at = $1 WHERE user_id = $2 AND device_id = $3 AND revoked_at IS NULL",
        [now_iso(), user_id, device_id]
      )

    true
  end

  defp revoke_family(family_id, fallback_token_id \\ nil)

  defp revoke_family(nil, token_id) when not is_nil(token_id), do: revoke_row(token_id)
  defp revoke_family(nil, _token_id), do: :ok

  defp revoke_family(family_id, _fallback_token_id) do
    _ =
      execute(
        "UPDATE #{@tokens_table} SET revoked_at = $1 WHERE family_id = $2 AND revoked_at IS NULL",
        [now_iso(), family_id]
      )

    :ok
  end

  defp revoke_row(token_id) do
    _ =
      execute("UPDATE #{@tokens_table} SET revoked_at = $1 WHERE token_id = $2 AND revoked_at IS NULL", [
        now_iso(),
        token_id
      ])

    :ok
  end

  defp touch_token(nil), do: :ok

  defp touch_token(token_id) do
    _ =
      execute("UPDATE #{@tokens_table} SET last_used_at = $1 WHERE token_id = $2", [
        now_iso(),
        token_id
      ])

    :ok
  end

  defp fetch_token(nil), do: nil

  defp fetch_token(token_id) do
    case run_query("SELECT * FROM #{@tokens_table} WHERE token_id = $1", [token_id]) do
      [row | _] -> row
      [] -> nil
    end
  end

  # A refresh token is only ever a refresh token. The kind is in the string, so a caller cannot
  # present one to `authenticate` and get a session out of it.
  defp parse_refresh_token(token) when is_binary(token) do
    case parse_token(token) do
      {:ok, "ref", token_id, secret} -> {:ok, token_id, secret}
      _ -> :error
    end
  end

  defp parse_refresh_token(_), do: :error

  defp parse_token(token) when is_binary(token) do
    with "exo_" <> rest <- token,
         [kind, rest] <- String.split(rest, "_", parts: 2),
         [token_id, secret] <- String.split(rest, ".", parts: 2),
         true <- kind in ["ses", "ref", "svc"] and token_id != "" and secret != "" do
      {:ok, kind, token_id, secret}
    else
      _ -> :legacy
    end
  end

  defp parse_token(_), do: :legacy

  defp secret_matches?(secret, hash) when is_binary(secret) and is_binary(hash) do
    expected = hash_secret(secret)
    byte_size(expected) == byte_size(hash) and :crypto.hash_equals(expected, hash)
  end

  defp secret_matches?(_secret, _hash), do: false

  defp hash_secret(secret), do: :crypto.hash(:sha256, secret) |> Base.encode64()

  defp random_string(bytes), do: :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)

  defp expired?(row) do
    expired_at?(Map.get(row, "expires_at") || Map.get(row, :expires_at))
  end

  defp revoked?(nil), do: false
  defp revoked?(row), do: not is_nil(row["revoked_at"] || row[:revoked_at])

  defp expired_at?(nil), do: false
  defp expired_at?(expires_at) when is_binary(expires_at), do: expires_at <= now_iso()
  defp expired_at?(_), do: false

  defp now_iso, do: iso(DateTime.utc_now())

  defp iso_after(seconds), do: iso(DateTime.add(DateTime.utc_now(), seconds, :second))

  defp iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: to_string(value)

  defp token_summary(row) do
    %{
      "token_id" => row["token_id"] || row[:token_id],
      "kind" => row["kind"] || row[:kind],
      "created_at" => row["created_at"] || row[:created_at],
      "last_used_at" => row["last_used_at"] || row[:last_used_at],
      "expires_at" => row["expires_at"] || row[:expires_at],
      "revoked_at" => row["revoked_at"] || row[:revoked_at],
      "device_id" => row["device_id"] || row[:device_id]
    }
  end

  defp user_id_from(payload) do
    Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
      Map.get(payload, :player_id) || Map.get(payload, "player_id")
  end

  defp user_exists?(user_id) do
    Enum.any?([@players_table, @accounts_table], fn table ->
      case run_query("SELECT player_id FROM #{table} WHERE player_id = $1", [user_id]) do
        [_ | _] -> true
        _ -> false
      end
    end)
  end

  defp account_scopes(user_id) do
    Enum.find_value([@players_table, @accounts_table], [Roles.player()], fn table ->
      case run_query("SELECT scopes FROM #{table} WHERE player_id = $1", [user_id]) do
        [row | _] ->
          parse_scopes(Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player())

        _ ->
          nil
      end
    end)
  end

  defp access_ttl, do: setting(:access_token_ttl, @access_ttl)
  defp refresh_ttl, do: setting(:refresh_token_ttl, @refresh_ttl)
  defp service_ttl, do: setting(:service_token_ttl, @service_ttl)
  defp max_sessions, do: setting(:max_sessions, @max_sessions)

  defp setting(key, default) do
    case Application.get_env(:exoforge, :auth, []) do
      config when is_map(config) -> Map.get(config, key, default)
      config when is_list(config) -> Keyword.get(config, key, default)
      _ -> default
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

  defp rows_in(table, ids), do: rows_in(table, ids, "player_id")

  defp rows_in(_table, [], _column), do: []

  defp rows_in(table, ids, column) do
    placeholders = Enum.map_join(1..length(ids), ", ", &"$#{&1}")
    run_query("SELECT * FROM #{table} WHERE #{column} IN (#{placeholders})", ids)
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

  defp verify_token(token) do
    case Exoforge.Std.Auth.Cache.get(token) do
      {:ok, result, used_at} ->
        cond do
          # The cache holds the answer, not a permanent one: the row's lifetime still applies to
          # every request, or a client that authenticated once would never be told its access
          # token died.
          expired_at?(result[:expires_at]) ->
            Exoforge.Std.Auth.Cache.delete(token)
            {:error, :token_expired}

          System.system_time(:second) - used_at > @touch_interval_seconds ->
            _ = touch_token(result.token_id)
            Exoforge.Std.Auth.Cache.put(token, result, System.system_time(:second))
            {:ok, result}

          true ->
            {:ok, result}
        end

      :error ->
        verify_stored_token(token)
    end
  end

  defp verify_stored_token(token) do
    {token_id, secret} =
      case parse_token(token) do
        {:ok, _kind, token_id, secret} -> {token_id, secret}
        # A token written before the prefixed format was hashed in place; its derived id is the
        # same hash, so the row is found without the credential ever being stored.
        :legacy -> {hash_secret(token), token}
      end

    case fetch_token(token_id) do
      nil ->
        {:error, :invalid_token}

      row ->
        cond do
          # The secret is checked before the row's state, so a wrong secret cannot learn from the
          # answer whether an expired or revoked row exists.
          not secret_matches?(secret, row["secret_hash"] || row[:secret_hash]) ->
            {:error, :invalid_token}

          row["revoked_at"] || row[:revoked_at] ->
            {:error, :invalid_token}

          expired?(row) ->
            {:error, :token_expired}

          row["kind"] == "ref" ->
            {:error, :invalid_token}

          true ->
            user_id = to_string(row["user_id"] || row[:user_id])
            scopes = account_scopes(user_id)

            result = %{
              user_id: user_id,
              player_id: user_id,
              scopes: scopes,
              role: role(scopes),
              token_id: to_string(row["token_id"] || row[:token_id]),
              kind: row["kind"] || row[:kind],
              expires_at: row["expires_at"] || row[:expires_at]
            }

            Exoforge.Std.Auth.Cache.put(token, result, System.system_time(:second))
            _ = touch_token(result.token_id)
            {:ok, result}
        end
    end
  end

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
  @moduledoc """
  The answer `authenticate` gave for a token, kept until the account's scopes change.

  The entry also carries when it was last written, so `last_used_at` can be kept current without
  a database write on every request. Expiry is not cached away: the result carries the row's
  `expires_at` and every hit compares it.
  """

  use GenServer

  @table :exoforge_auth_tokens

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(token) do
    case :ets.lookup(@table, token) do
      [{^token, result, used_at}] -> {:ok, result, used_at}
      [{^token, result}] -> {:ok, result, 0}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  def put(token, result, used_at \\ 0) do
    try do
      :ets.insert(@table, {token, result, used_at})
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  def delete(token) do
    try do
      :ets.delete(@table, token)
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
