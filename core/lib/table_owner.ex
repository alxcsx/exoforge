defmodule Exoforge.TableOwner do
  @moduledoc """
  Owns the kernel's shared ETS tables.

  An ETS table dies with the process that created it, and both the plugin log buffer and the usage
  counters must outlive every plugin: a runner restart that took a plugin's own usage with it would
  erase exactly the history that says it restarted. The owner is started on demand and does nothing
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
    Exoforge.PluginLogs.init_table()
    Exoforge.Metering.init_table()
    {:ok, nil}
  end

  @impl true
  def handle_call(:ready, _from, state), do: {:reply, :ok, state}
end
