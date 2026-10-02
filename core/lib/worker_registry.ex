defmodule Exoforge.WorkerRegistry do
  @registry __MODULE__.Registry

  def child_spec(_opts \\ []) do
    %{
      id: @registry,
      start: {Registry, :start_link, [[keys: :unique, name: @registry]]}
    }
  end

  @doc "tuple for registering a worker in the registry"
  def via_tuple(plugin_id, worker_id) do
    {:via, Registry, {@registry, {plugin_id, worker_id}}}
  end

  @doc "Looks up the PID of a worker by its plugin_id and worker_id."
  def lookup(plugin_id, worker_id) do
    case Registry.lookup(@registry, {plugin_id, worker_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
