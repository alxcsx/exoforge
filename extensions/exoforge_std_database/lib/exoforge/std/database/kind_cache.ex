defmodule Exoforge.Std.Database.KindCache do
  @moduledoc """
  What kind of table each `{namespace, table}` is, remembered briefly.

  Telling a document table from a typed one takes a catalog query, and a document table that is
  not known to exist costs a `CREATE TABLE IF NOT EXISTS` and a transaction on every write. Both are
  worth paying once, not per call. Entries expire after a few seconds, so a table the driver layer
  changes behind this cache (a schema apply, a reset) is seen again soon; the paths that change a table
  here forget it at once.

  Without the process (a test that does not start the extension) every lookup misses and nothing breaks.
  """
  use GenServer

  @table __MODULE__
  @ttl_ms 5_000

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end

  @doc "The remembered kind of a table, or `:miss`."
  def get(namespace, table) do
    case :ets.lookup(@table, key(namespace, table)) do
      [{_, kind, expires}] -> if expires > now(), do: {:ok, kind}, else: :miss
      _ -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  def put(namespace, table, kind) do
    :ets.insert(@table, {key(namespace, table), kind, now() + @ttl_ms})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Forgets one table, or every table of a namespace."
  def forget(namespace, table \\ :all)

  def forget(namespace, :all) do
    ns = to_string(namespace)
    :ets.match_delete(@table, {{ns, :_}, :_, :_})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def forget(namespace, table) do
    :ets.delete(@table, key(namespace, table))
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp key(namespace, table), do: {to_string(namespace), to_string(table)}
  defp now, do: System.monotonic_time(:millisecond)
end
