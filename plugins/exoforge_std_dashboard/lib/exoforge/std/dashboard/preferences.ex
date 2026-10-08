defmodule Exoforge.Std.Dashboard.Preferences do
  @moduledoc """
  Per-account Studio preferences, stored through the resource store.

  The backing table is declared by the `studio_preference` resource in the
  `:dashboard` contract (`source: {:table, "studio_preferences"}`), so the
  resource store owns its DDL and CRUD — no hand-written SQL here.
  """
  alias Exoforge.ActionDispatcher

  @resource "studio_preference"

  @doc "Returns the pinned extension ids for an account."
  def pinned(player_id) when is_binary(player_id) and player_id != "" do
    case store(:get, %{resource: @resource, id: player_id}) do
      {:ok, %{row: row}} ->
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
    # The result is returned rather than dropped. Discarding it meant a write that failed - a table
    # with no unique key, say - looked exactly like one that worked.
    store(:upsert, %{
      resource: @resource,
      attributes: %{
        "player_id" => player_id,
        "data" => Jason.encode!(Enum.map(pinned, &to_string/1))
      }
    })
  end

  def put_pinned(_player_id, _pinned), do: :ok

  defp store(action, payload), do: ActionDispatcher.dispatch(:resource_store, action, payload)
end
