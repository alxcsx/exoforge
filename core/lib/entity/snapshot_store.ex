defmodule Exoforge.Entity.SnapshotStore do
  @moduledoc """
  Database-backed snapshot persistence store using Exoforge.Std.Database.
  Persists state snapshots into the plugin-isolated key-value table.
  """
  @behaviour Exoforge.Entity.Store

  @table "entity_snapshots"

  @impl true
  def load({plugin, type, id}) do
    doc_key = "#{type}:#{id}"
    db_mod = Module.concat([Exoforge, Std, Database])

    if Code.ensure_loaded?(db_mod) and function_exported?(db_mod, :get, 3) do
      case apply(db_mod, :get, [plugin, @table, doc_key]) do
        {:ok, %{"state" => state}} -> {:ok, state}
        {:ok, state} when is_map(state) -> {:ok, state}
        {:error, :not_found} -> {:error, :not_found}
        _ -> {:error, :not_found}
      end
    else
      Exoforge.Entity.MemoryStore.load({plugin, type, id})
    end
  end

  @impl true
  def save({plugin, type, id}, state) do
    doc_key = "#{type}:#{id}"
    payload = if is_map(state), do: state, else: %{"state" => state}
    db_mod = Module.concat([Exoforge, Std, Database])

    if Code.ensure_loaded?(db_mod) and function_exported?(db_mod, :put, 4) do
      case apply(db_mod, :put, [plugin, @table, doc_key, payload]) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      Exoforge.Entity.MemoryStore.save({plugin, type, id}, state)
    end
  end

  @impl true
  def delete({plugin, type, id}) do
    doc_key = "#{type}:#{id}"
    db_mod = Module.concat([Exoforge, Std, Database])

    if Code.ensure_loaded?(db_mod) and function_exported?(db_mod, :delete, 3) do
      case apply(db_mod, :delete, [plugin, @table, doc_key]) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      Exoforge.Entity.MemoryStore.delete({plugin, type, id})
    end
  end
end
