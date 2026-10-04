defmodule Exoforge.Entity.SnapshotStore do
  @moduledoc """
  Database-backed snapshot persistence for entities.

  Stores each entity's state as a key-value document in the plugin's isolated
  namespace, through the `:database` contract (never a concrete plugin module).
  """
  @behaviour Exoforge.Entity.Store

  alias Exoforge.ActionDispatcher

  @table "entity_snapshots"

  @impl true
  def load({plugin, type, id}) do
    case db(plugin, %{action: :get, table: @table, id: key(type, id)}) do
      {:ok, %{rows: [record | _]}} -> {:ok, Map.get(record, "state", record)}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def save({plugin, type, id}, state) do
    payload = if is_map(state), do: state, else: %{"state" => state}

    case db(plugin, %{action: :put, table: @table, id: key(type, id), data: payload}) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @impl true
  def delete({plugin, type, id}) do
    case db(plugin, %{action: :delete, table: @table, id: key(type, id)}) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp key(type, id), do: "#{type}:#{id}"

  defp db(plugin, operation) do
    ActionDispatcher.dispatch(:database, :execute, %{plugin: plugin, operation: operation})
  end
end
