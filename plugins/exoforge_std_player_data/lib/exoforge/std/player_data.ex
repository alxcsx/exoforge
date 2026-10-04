defmodule Exoforge.Std.PlayerData do
  @moduledoc """
  Standard player profile and state storage plugin for Exoforge.
  Provides the :player_data service contract.
  Persists data into its own isolated database via :database,
  supports user linking, data retention/orphaned player accessibility,
  key-value JSON storage, and emits lifecycle events :player_created and :player_deleted.
  """
  use Exoforge.Plugin, provides: [:player_data]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database],
    category: "Data",
    dashboard_view: %{id: :player_data, title: "Players", icon: "👤"},
    ui_hooks: %{
      player_inspect: [
        %{id: :kv_store, title: "Key-Value Database", icon: "🔑", order: 10},
        %{id: :profile, title: "Profile (Raw JSON)", icon: "👤", order: 20}
      ]
    }
  }

  alias Exoforge.ActionDispatcher

  def on_init(_manifest) do
    init_schema()
    :ok
  end

  @doc "Initializes the required tables in the isolated player_data database."
  def init_schema do
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :player_data,
        operation:
          "CREATE TABLE IF NOT EXISTS players (id text, player_id text, user_id text, profile text, state text)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :player_data,
        operation:
          "CREATE TABLE IF NOT EXISTS player_kv (id text, player_id text, key text, value text, updated_at integer)"
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :player_data,
        operation: "CREATE INDEX IF NOT EXISTS idx_player_kv_prefix ON player_kv (player_id, key)"
      })

    :ok
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction get_player(payload) do
    player_id = extract_player_id(payload)

    allow_retained =
      Map.get(payload, :allow_retained, false) ||
        Map.get(payload, "allow_retained", false) ||
        Map.get(payload, :internal, false) ||
        Map.get(payload, "internal", false)

    if is_nil(player_id) or player_id == "" do
      {:error, :player_not_found}
    else
      query = "SELECT * FROM players WHERE player_id = $1"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: query,
             arguments: [player_id]
           }) do
        {:ok, %{rows: [row | _]}} ->
          player = decode_player_row(row)

          user_id =
            Map.get(row, "user_id") || Map.get(row, :user_id) || Map.get(player, "user_id")

          state = Map.get(row, "state") || Map.get(row, :state) || "active"
          is_retained = is_nil(user_id) or user_id == "" or state == "retained"

          if is_retained and not allow_retained do
            {:error, :player_not_accessible}
          else
            {:ok, %{player: player}}
          end

        {:ok, %{rows: []}} ->
          {:error, :player_not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  defaction update_player(payload) do
    player_id = extract_player_id(payload)
    data = Map.get(payload, :data) || Map.get(payload, "data", %{})

    if is_nil(player_id) or player_id == "" do
      {:error, :player_not_found}
    else
      query = "SELECT * FROM players WHERE player_id = $1"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: query,
             arguments: [player_id]
           }) do
        {:ok, %{rows: [existing_row | _]}} ->
          existing = decode_player_row(existing_row)
          updated = Map.merge(existing, data)
          profile_json = Jason.encode!(updated)

          update_query = "UPDATE players SET profile = $1 WHERE player_id = $2"

          _ =
            ActionDispatcher.dispatch(:database, :execute, %{
              plugin: :player_data,
              operation: update_query,
              arguments: [profile_json, player_id]
            })

          {:ok, %{player: updated}}

        {:ok, %{rows: []}} ->
          {:error, :player_not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  @doc "Action to create a new player profile and emit :player_created lifecycle event."
  defaction create_player(payload) do
    player_id = extract_player_id(payload)
    profile = Map.get(payload, :profile) || Map.get(payload, "profile", %{})

    if is_nil(player_id) or player_id == "" do
      {:error, :invalid_attributes}
    else
      init_schema()
      now = System.system_time(:millisecond)

      raw_uid =
        Map.get(payload, :user_id) || Map.get(payload, "user_id") ||
          Map.get(profile, "user_id")

      # If user_id is explicitly passed, respect it (can be nil/empty for retained).
      # If omitted entirely, default to player_id to link valid players.
      user_id =
        cond do
          Map.has_key?(payload, :user_id) or Map.has_key?(payload, "user_id") ->
            if raw_uid && raw_uid != "", do: to_string(raw_uid), else: ""

          raw_uid && raw_uid != "" ->
            to_string(raw_uid)

          true ->
            player_id
        end

      state = if user_id == "", do: "retained", else: "active"

      profile_with_id =
        profile
        |> Map.put("player_id", player_id)
        |> Map.put("user_id", if(user_id != "", do: user_id, else: nil))

      profile_json = Jason.encode!(profile_with_id)

      insert_query =
        "INSERT INTO players (id, player_id, user_id, profile, state) VALUES ($1, $2, $3, $4, $5)"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: insert_query,
             arguments: [player_id, player_id, user_id, profile_json, state]
           }) do
        {:ok, _} ->
          # Emit player_created lifecycle event
          player_created(player_id, now)
          {:ok, %{player: profile_with_id}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  @doc "Action to retain/unlink a player profile when user account is deleted."
  defaction retain_player(payload) do
    player_id = extract_player_id(payload)

    if is_nil(player_id) or player_id == "" do
      {:error, :player_not_found}
    else
      init_schema()
      query = "SELECT * FROM players WHERE player_id = $1"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: query,
             arguments: [player_id]
           }) do
        {:ok, %{rows: [row | _]}} ->
          existing = decode_player_row(row)

          # Strip PII while retaining stats and metrics for analytics
          retained_profile =
            existing
            |> Map.put("user_id", nil)
            |> Map.put("email", nil)
            |> Map.put("name", "Retained Player")

          profile_json = Jason.encode!(retained_profile)

          update_query =
            "UPDATE players SET user_id = $1, state = $2, profile = $3 WHERE player_id = $4"

          _ =
            ActionDispatcher.dispatch(:database, :execute, %{
              plugin: :player_data,
              operation: update_query,
              arguments: ["", "retained", profile_json, player_id]
            })

          {:ok, %{player_id: player_id, status: "retained"}}

        _ ->
          {:error, :player_not_found}
      end
    end
  end

  @impl true
  @doc "Action to list all registered player profiles with optional filtering (all, valid, orphaned)."
  defaction list_players(payload) do
    init_schema()
    filter = Map.get(payload, :filter) || Map.get(payload, "filter") || "all"
    query = "SELECT * FROM players"

    case ActionDispatcher.dispatch(:database, :execute, %{plugin: :player_data, operation: query}) do
      {:ok, %{rows: rows}} when is_list(rows) ->
        normalized = normalize_player_rows(rows)
        filtered = apply_player_filter(normalized, filter)
        {:ok, %{players: filtered, rows: filtered}}

      {:ok, rows} when is_list(rows) ->
        normalized = normalize_player_rows(rows)
        filtered = apply_player_filter(normalized, filter)
        {:ok, %{players: filtered, rows: filtered}}

      _ ->
        {:ok, %{players: [], rows: []}}
    end
  end

  @impl true
  @doc "Action to delete a player profile and emit :player_deleted lifecycle event."
  defaction delete_player(payload) do
    player_id = extract_player_id(payload)

    if is_nil(player_id) or player_id == "" do
      {:error, :player_not_found}
    else
      now = System.system_time(:millisecond)
      delete_query = "DELETE FROM players WHERE player_id = $1"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: delete_query,
             arguments: [player_id]
           }) do
        {:ok, _} ->
          # Clean up fine-grained KV entries as well
          _ =
            ActionDispatcher.dispatch(:database, :execute, %{
              plugin: :player_data,
              operation: "DELETE FROM player_kv WHERE player_id = $1",
              arguments: [player_id]
            })

          # Emit player_deleted lifecycle event
          player_deleted(player_id, now)
          {:ok, %{status: "deleted", player_id: player_id}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## ---- KEY-VALUE STATE ACTIONS ----

  @impl true
  @doc "Retrieves a fine-grained key-value JSON state entry or prefix sub-tree for a player."
  defaction get_data(payload) do
    player_id = extract_player_id(payload)
    key = Map.get(payload, :key) || Map.get(payload, "key")
    prefix = Map.get(payload, :prefix) || Map.get(payload, "prefix")

    cond do
      is_nil(player_id) or player_id == "" ->
        {:error, :player_not_found}

      prefix && prefix != "" ->
        get_all_data(payload)

      is_nil(key) or key == "" ->
        {:error, :key_not_found}

      true ->
        init_schema()
        id = "#{player_id}:#{key}"
        query = "SELECT * FROM player_kv WHERE id = $1"

        case ActionDispatcher.dispatch(:database, :execute, %{
               plugin: :player_data,
               operation: query,
               arguments: [id]
             }) do
          {:ok, %{rows: [row | _]}} ->
            raw_val = Map.get(row, "value") || Map.get(row, :value)
            decoded = decode_json_val(raw_val)
            {:ok, %{key: key, value: decoded}}

          _ ->
            {:error, :key_not_found}
        end
    end
  end

  @impl true
  @doc "Sets a fine-grained key-value JSON state entry for a player."
  defaction set_data(payload) do
    player_id = extract_player_id(payload)
    key = Map.get(payload, :key) || Map.get(payload, "key")
    value = Map.get(payload, :value, Map.get(payload, "value"))

    cond do
      is_nil(player_id) or player_id == "" ->
        {:error, :player_not_found}

      is_nil(key) or key == "" ->
        {:error, :invalid_attributes}

      true ->
        init_schema()
        id = "#{player_id}:#{key}"
        now = System.system_time(:millisecond)
        encoded_val = if is_binary(value), do: value, else: Jason.encode!(value)

        # Upsert: check if key exists
        check_query = "SELECT * FROM player_kv WHERE id = $1"

        case ActionDispatcher.dispatch(:database, :execute, %{
               plugin: :player_data,
               operation: check_query,
               arguments: [id]
             }) do
          {:ok, %{rows: [_existing | _]}} ->
            update_query = "UPDATE player_kv SET value = $1, updated_at = $2 WHERE id = $3"

            _ =
              ActionDispatcher.dispatch(:database, :execute, %{
                plugin: :player_data,
                operation: update_query,
                arguments: [encoded_val, now, id]
              })

            {:ok, %{key: key, value: value}}

          _ ->
            insert_query =
              "INSERT INTO player_kv (id, player_id, key, value, updated_at) VALUES ($1, $2, $3, $4, $5)"

            _ =
              ActionDispatcher.dispatch(:database, :execute, %{
                plugin: :player_data,
                operation: insert_query,
                arguments: [id, player_id, key, encoded_val, now]
              })

            {:ok, %{key: key, value: value}}
        end
    end
  end

  @impl true
  @doc "Deletes a fine-grained key-value JSON state entry for a player."
  defaction delete_data(payload) do
    player_id = extract_player_id(payload)
    key = Map.get(payload, :key) || Map.get(payload, "key")

    cond do
      is_nil(player_id) or player_id == "" ->
        {:error, :player_not_found}

      is_nil(key) or key == "" ->
        {:error, :key_not_found}

      true ->
        init_schema()
        id = "#{player_id}:#{key}"

        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :player_data,
            operation: "DELETE FROM player_kv WHERE id = $1",
            arguments: [id]
          })

        {:ok, %{key: key, status: "deleted"}}
    end
  end

  @impl true
  @doc "Retrieves all key-value state entries for a player as a map, optionally filtered by key prefix."
  defaction get_all_data(payload) do
    player_id = extract_player_id(payload)
    prefix = Map.get(payload, :prefix) || Map.get(payload, "prefix")

    if is_nil(player_id) or player_id == "" do
      {:error, :player_not_found}
    else
      init_schema()

      {query, args} =
        if prefix && prefix != "" do
          {"SELECT * FROM player_kv WHERE player_id = $1 AND key LIKE $2",
           [player_id, "#{prefix}%"]}
        else
          {"SELECT * FROM player_kv WHERE player_id = $1", [player_id]}
        end

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: query,
             arguments: args
           }) do
        {:ok, %{rows: rows}} when is_list(rows) ->
          data =
            Enum.into(rows, %{}, fn r ->
              k = Map.get(r, "key") || Map.get(r, :key)
              v = Map.get(r, "value") || Map.get(r, :value)
              {to_string(k), decode_json_val(v)}
            end)

          {:ok, %{data: data}}

        _ ->
          {:ok, %{data: %{}}}
      end
    end
  end

  ## ---- PRIVATE HELPERS ----

  defp extract_player_id(payload) when is_map(payload) do
    Map.get(payload, :player_id) || Map.get(payload, "player_id")
  end

  defp extract_player_id(payload) when is_binary(payload), do: payload
  defp extract_player_id(_), do: nil

  defp decode_player_row(row) do
    raw_profile = Map.get(row, "profile") || Map.get(row, :profile)
    player_id = Map.get(row, "player_id") || Map.get(row, :player_id)
    user_id = Map.get(row, "user_id") || Map.get(row, :user_id)

    decoded =
      case raw_profile do
        str when is_binary(str) ->
          case Jason.decode(str) do
            {:ok, dec} -> dec
            _ -> %{"player_id" => player_id}
          end

        map when is_map(map) ->
          map

        _ ->
          %{"player_id" => player_id}
      end

    if user_id && user_id != "", do: Map.put_new(decoded, "user_id", user_id), else: decoded
  end

  defp normalize_player_rows(rows) do
    Enum.map(rows, fn r ->
      profile = decode_player_row(r)
      pid = Map.get(r, "player_id") || Map.get(r, :player_id) || Map.get(profile, "player_id")
      uid = Map.get(r, "user_id") || Map.get(r, :user_id) || Map.get(profile, "user_id")
      raw_state = Map.get(r, "state") || Map.get(r, :state) || "active"
      is_linked = uid != nil and uid != "" and raw_state != "retained"

      %{
        id: pid,
        player_id: pid,
        user_id: if(is_linked, do: uid, else: nil),
        linked: is_linked,
        name: Map.get(profile, "name") || to_string(pid),
        email:
          if(is_linked,
            do: Map.get(profile, "email") || "#{pid}@player.exoforge.io",
            else: "— (Retained / Orphaned)"
          ),
        status: if(is_linked, do: "Active", else: "Retained (No User)"),
        total_spent: Map.get(profile, "total_spent") || "$0.00",
        time_in_game: Map.get(profile, "time_in_game") || "0m",
        profile: profile
      }
    end)
  end

  defp apply_player_filter(players, filter) do
    case filter do
      f when f in ["valid", "active", "linked"] ->
        Enum.filter(players, &(&1.linked == true))

      f when f in ["orphaned", "retained", "unlinked"] ->
        Enum.filter(players, &(&1.linked == false))

      _ ->
        players
    end
  end

  defp decode_json_val(val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, decoded} -> decoded
      _ -> val
    end
  end

  defp decode_json_val(val), do: val
end
