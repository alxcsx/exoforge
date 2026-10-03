defmodule Exoforge.Std.Auth do
  @moduledoc """
  Standard authentication and authorization plugin for Exoforge.
  Provides the :auth service contract.
  Relies on the :database service for isolated persistence of tokens and scopes.
  """
  use Exoforge.Plugin, provides: [:auth]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database],
    category: "Identity",
    dashboard_view: %{
      id: :auth,
      title: "Users & Auth",
      icon: "🛡️"
    }
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Auth.Roles

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
        operation:
          "CREATE TABLE IF NOT EXISTS #{@tokens_table} (id text, token text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation:
          "CREATE TABLE IF NOT EXISTS #{@players_table} (id text, player_id text, scopes text)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation:
          "CREATE TABLE IF NOT EXISTS #{@accounts_table} (id text, player_id text, email text, password_hash text, scopes text)"
      })

    :ok
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
        player_id = String.replace_prefix(token, "dev:", "")
        scopes = [Roles.player(), Roles.admin()]
        {:ok, %{player_id: player_id, scopes: scopes, role: role(scopes)}}

      token == Roles.guest() ->
        scopes = [Roles.guest()]
        {:ok, %{player_id: "guest_anon", scopes: scopes, role: role(scopes)}}

      true ->
        query = "SELECT * FROM #{@tokens_table} WHERE token = $1"

        case ActionDispatcher.dispatch(:database, :execute, %{
               plugin: :auth,
               operation: query,
               arguments: [token]
             }) do
          {:ok, %{rows: [row | _]}} ->
            player_id = Map.get(row, "player_id") || Map.get(row, :player_id)
            raw_scopes = Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player()
            scopes = parse_scopes(raw_scopes)
            {:ok, %{player_id: player_id, scopes: scopes, role: role(scopes)}}

          {:ok, %{rows: []}} ->
            {:error, :invalid_token}

          {:error, _reason} ->
            {:error, :invalid_token}
        end
    end
  end

  @impl true
  defaction login(payload) do
    email = Map.get(payload, :email) || Map.get(payload, "email")
    password = Map.get(payload, :password) || Map.get(payload, "password")

    if is_nil(email) or email == "" or is_nil(password) or password == "" do
      {:error, :invalid_credentials}
    else
      query = "SELECT * FROM #{@accounts_table} WHERE email = $1"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :auth,
             operation: query,
             arguments: [String.downcase(to_string(email))]
           }) do
        {:ok, %{rows: [row | _]}} ->
          player_id = Map.get(row, "player_id") || Map.get(row, :player_id)
          hash = Map.get(row, "password_hash") || Map.get(row, :password_hash)
          scopes = parse_scopes(Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player())

          if verify_password(password, hash) do
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

  @impl true
  defaction verify_scope(payload) do
    player_id = Map.get(payload, :player_id) || Map.get(payload, "player_id")
    required = Map.get(payload, :required_scope) || Map.get(payload, "required_scope")

    cond do
      is_nil(player_id) or is_nil(required) ->
        {:error, :unauthorized}

      player_id == @admin_id or String.starts_with?(player_id, @dev_admin_prefix) ->
        {:ok, %{authorized: true}}

      true ->
        scopes =
          case ActionDispatcher.dispatch(:database, :execute, %{
                 plugin: :auth,
                 operation: "SELECT * FROM #{@players_table} WHERE player_id = $1",
                 arguments: [player_id]
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

  @impl true
  defaction issue_token(payload) do
    player_id = Map.get(payload, :player_id) || Map.get(payload, "player_id")
    raw_scopes = Map.get(payload, :scopes) || Map.get(payload, "scopes")

    if is_nil(player_id) or player_id == "" do
      {:error, :invalid_player}
    else
      scopes =
        if is_nil(raw_scopes) do
          query = "SELECT * FROM #{@players_table} WHERE player_id = $1"

          case ActionDispatcher.dispatch(:database, :execute, %{
                 plugin: :auth,
                 operation: query,
                 arguments: [player_id]
               }) do
            {:ok, %{rows: [row | _]}} ->
              parse_scopes(Map.get(row, "scopes") || Map.get(row, :scopes) || Roles.player())

            _ ->
              [Roles.player()]
          end
        else
          parse_scopes(raw_scopes)
        end

      case generate_and_store_token(player_id, scopes) do
        {:ok, token} -> {:ok, %{token: token, player_id: player_id}}
        error -> error
      end
    end
  end

  @impl true
  defaction list_users(_payload) do
    init_schema()

    players_query = "SELECT * FROM #{@players_table}"
    tokens_query = "SELECT * FROM #{@tokens_table}"

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

    tokens_by_player =
      Enum.group_by(tokens_rows, fn row ->
        to_string(Map.get(row, "player_id") || Map.get(row, :player_id))
      end)

    players_by_id =
      Enum.reduce(players_rows, %{}, fn row, acc ->
        pid = to_string(Map.get(row, "player_id") || Map.get(row, :player_id))
        Map.put(acc, pid, row)
      end)

    all_player_ids =
      (Map.keys(players_by_id) ++ Map.keys(tokens_by_player))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    users =
      Enum.map(all_player_ids, fn pid ->
        p_row = Map.get(players_by_id, pid, %{})
        raw_scopes = Map.get(p_row, "scopes") || Map.get(p_row, :scopes) || Roles.player()
        scopes = parse_scopes(raw_scopes)
        tokens = Map.get(tokens_by_player, pid, [])

        token_strings =
          Enum.map(tokens, fn t ->
            to_string(Map.get(t, "token") || Map.get(t, :token))
          end)

        %{
          "player_id" => pid,
          "scopes" => scopes,
          "tokens_count" => length(tokens),
          "active_tokens" => token_strings,
          "status" => "Active"
        }
      end)

    {:ok, %{users: users, count: length(users)}}
  end

  defp do_register_player(payload) do
    init_schema()

    raw_pid = Map.get(payload, :player_id) || Map.get(payload, "player_id")

    player_id =
      if raw_pid && raw_pid != "",
        do: to_string(raw_pid),
        else: "p_#{System.unique_integer([:positive])}"

    raw_name =
      Map.get(payload, :name) || Map.get(payload, "name") ||
        Map.get(payload, :username) || Map.get(payload, "username")

    name = if raw_name && raw_name != "", do: to_string(raw_name), else: "Player_#{player_id}"

    raw_email = Map.get(payload, :email) || Map.get(payload, "email")

    email =
      if raw_email && raw_email != "",
        do: to_string(raw_email),
        else: "#{player_id}@player.exoforge.io"

    raw_scopes = Map.get(payload, :scopes) || Map.get(payload, "scopes") || [Roles.player()]
    scopes = parse_scopes(raw_scopes)

    case generate_and_store_token(player_id, scopes) do
      {:ok, token} ->
        profile = %{
          "player_id" => player_id,
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

        # Hook into player_data canonical profile store
        _ =
          ActionDispatcher.dispatch(:player_data, :create_player, %{
            player_id: player_id,
            profile: profile
          })

        {:ok, %{player_id: player_id, token: token, scopes: scopes, player: profile}}

      {:error, reason} ->
        {:error, reason}
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
      {email, password} when is_binary(email) and is_binary(password) ->
        _ = upsert_account(@admin_id, email, password, [Roles.admin()])
        :ok

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
    init_schema()
    email = String.downcase(to_string(email))

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM #{@accounts_table} WHERE email = $1",
        arguments: [email]
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation:
          "INSERT INTO #{@accounts_table} (id, player_id, email, password_hash, scopes) VALUES ($1, $2, $3, $4, $5)",
        arguments: [email, player_id, email, hash_password(password), Enum.join(scopes, ",")]
      })

    _ = set_player_scopes(player_id, scopes)
    {:ok, %{player_id: player_id, email: email, scopes: scopes}}
  end

  defp credentials(config_key, env_email, env_password) do
    config = Application.get_env(:exoforge, config_key, [])

    # Environment overrides config, so direnv / deployment vars win locally.
    email = System.get_env(env_email) || config[:email]
    password = System.get_env(env_password) || config[:password]

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

  defp generate_and_store_token(player_id, scopes) do
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
        # Also record/update the player's primary scopes
        _ = set_player_scopes(player_id, scopes)
        {:ok, token}

      error ->
        error
    end
  end

  @doc "Registers or updates scopes for a player."
  def set_player_scopes(player_id, scopes) do
    init_schema()
    scopes_str = Enum.join(scopes, ",")

    # Delete previous entry if exists
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :auth,
        operation: "DELETE FROM #{@players_table} WHERE player_id = $1",
        arguments: [player_id]
      })

    insert_query = "INSERT INTO #{@players_table} (id, player_id, scopes) VALUES ($1, $2, $3)"

    ActionDispatcher.dispatch(:database, :execute, %{
      plugin: :auth,
      operation: insert_query,
      arguments: [player_id, player_id, scopes_str]
    })
  end

  ## ---- PRIVATE HELPERS ----

  defp extract_token(payload) when is_binary(payload), do: payload

  defp extract_token(payload) when is_map(payload) do
    Map.get(payload, :token) || Map.get(payload, "token")
  end

  defp extract_token(_), do: nil

  defp parse_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)

  defp parse_scopes(scopes) when is_binary(scopes) do
    scopes
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_scopes(_), do: [Roles.player()]
end
