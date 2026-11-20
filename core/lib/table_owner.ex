defmodule Exoforge.TableOwner do
  @moduledoc """
  Owns the kernel's shared ETS tables.

  An ETS table dies with the process that created it, and the extension log buffer, the usage counters, the
  failure groups and the action trace must outlive every request and every extension: a runner restart that took an
  extension's own usage with it would erase exactly the history that says it restarted, and a table made by the
  request that recorded the first failure disappeared when that request ended. The owner is started on demand and does nothing
  but hold them for the node's lifetime.
  """
  use GenServer

  @doc """
  Ensures the owner is running and the tables exist. Idempotent, and safe to call concurrently:
  the `:ready` call cannot return before `init/1` has created both tables.
  """
  def ensure_started do
    pid =
      case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, :ready)
    :ok
  end

  @impl true
  def init(:ok) do
    Exoforge.ExtensionLogs.init_table()
    Exoforge.Metering.init_table()
    Exoforge.ErrorGroups.create_table()
    Exoforge.ActionTrace.create_tables()
    {:ok, nil}
  end

  @impl true
  def handle_call(:ready, _from, state), do: {:reply, :ok, state}
end
