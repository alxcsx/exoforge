defmodule Exoforge.Entity.MemoryStore do
  @moduledoc """
  In-memory ETS-backed entity persistence store for testing and ephemeral entities.
  """
  @behaviour Exoforge.Entity.Store

  @table :exo_entity_memory_store

  def init_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        @table
    end
  end

  @impl true
  def load(key) do
    init_table()

    case :ets.lookup(@table, key) do
      [{^key, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def save(key, state) do
    init_table()
    :ets.insert(@table, {key, state})
    :ok
  end

  @impl true
  def delete(key) do
    init_table()
    :ets.delete(@table, key)
    :ok
  end

  def clear do
    init_table()
    :ets.delete_all_objects(@table)
    :ok
  end
end
