defmodule Exoforge.Std.Dashboard.Preferences do
  @moduledoc """
  Per-account Studio preferences, persisted in the dashboard plugin's isolated
  database namespace. Currently records the pinned extensions shown in the top
  navigation bar.
  """
  alias Exoforge.ActionDispatcher

  @plugin :exoforge_std_dashboard
  @table "studio_preferences"

  @doc "Creates the preferences table in the dashboard's isolated database."
  def ensure_schema do
    _ = db("CREATE TABLE IF NOT EXISTS #{@table} (player_id text, data text)")
    :ok
  end

  @doc "Returns the pinned extension ids for an account."
  def pinned(player_id) when is_binary(player_id) and player_id != "" do
    case db("SELECT data FROM #{@table} WHERE player_id = $1", [player_id]) do
      {:ok, %{rows: [row | _]}} ->
        raw = Map.get(row, "data") || Map.get(row, :data) || "[]"

        case Jason.decode(raw) do
          {:ok, list} when is_list(list) -> Enum.map(list, &to_string/1)
          _ -> []
        end

      _ ->
        []
    end
  end

  def pinned(_player_id), do: []

  @doc "Persists the pinned extension ids for an account."
  def put_pinned(player_id, pinned)
      when is_binary(player_id) and player_id != "" and is_list(pinned) do
    _ = db("DELETE FROM #{@table} WHERE player_id = $1", [player_id])

    _ =
      db("INSERT INTO #{@table} (player_id, data) VALUES ($1, $2)", [
        player_id,
        Jason.encode!(Enum.map(pinned, &to_string/1))
      ])

    :ok
  end

  def put_pinned(_player_id, _pinned), do: :ok

  defp db(operation, arguments \\ []) do
    ActionDispatcher.dispatch(:database, :execute, %{
      plugin: @plugin,
      operation: operation,
      arguments: arguments
    })
  end
end
