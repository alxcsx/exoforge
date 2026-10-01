defmodule Exoforge.Std.PlayerData do
  @moduledoc """
  Standard player profile and state storage plugin for Exoforge.
  Provides the :player_data service contract.
  Persists data into its own isolated database via :database,
  and emits lifecycle events :player_created and :player_deleted.
  """
  use Exoforge.Plugin, provides: [:player_data]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth]
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
        operation: "CREATE TABLE IF NOT EXISTS players (id text, player_id text, profile text, state text)"
      })

    :ok
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction get_player(payload) do
    player_id = extract_player_id(payload)

    if is_nil(player_id) or player_id == "" do
      {:error, :player_not_found}
    else
      query = "SELECT * FROM players WHERE player_id = $1"

      case ActionDispatcher.dispatch(:database, :execute, %{plugin: :player_data, operation: query, arguments: [player_id]}) do
        {:ok, %{rows: [row | _]}} ->
          player = decode_player_row(row)
          {:ok, %{player: player}}

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

      case ActionDispatcher.dispatch(:database, :execute, %{plugin: :player_data, operation: query, arguments: [player_id]}) do
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

  @doc "Action to create a new player profile and emit :player_created lifecycle event."
  defaction create_player(payload) do
    player_id = extract_player_id(payload)
    profile = Map.get(payload, :profile) || Map.get(payload, "profile", %{})

    if is_nil(player_id) or player_id == "" do
      {:error, :invalid_attributes}
    else
      init_schema()
      now = System.system_time(:millisecond)
      profile_with_id = Map.put(profile, "player_id", player_id)
      profile_json = Jason.encode!(profile_with_id)

      insert_query = "INSERT INTO players (id, player_id, profile, state) VALUES ($1, $2, $3, $4)"

      case ActionDispatcher.dispatch(:database, :execute, %{
             plugin: :player_data,
             operation: insert_query,
             arguments: [player_id, player_id, profile_json, "active"]
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
          # Emit player_deleted lifecycle event
          player_deleted(player_id, now)
          {:ok, %{status: "deleted", player_id: player_id}}

        {:error, reason} ->
          {:error, reason}
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

    case raw_profile do
      str when is_binary(str) ->
        case Jason.decode(str) do
          {:ok, decoded} -> decoded
          _ -> %{"player_id" => player_id}
        end

      map when is_map(map) ->
        map

      _ ->
        %{"player_id" => player_id}
    end
  end
end
