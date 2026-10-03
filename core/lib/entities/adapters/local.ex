defmodule Exoforge.Entities.Adapters.Local do
  @moduledoc """
  Single-node adapter using standard BEAM `Registry` and `DynamicSupervisor`.
  Offers zero latency, zero dependencies, and complete isolation for local development and tests.
  """
  @behaviour Exoforge.Entities.Adapter

  @registry Exoforge.EntityRegistry
  @supervisor Exoforge.EntitySupervisor

  def registry_name, do: @registry
  def supervisor_name, do: @supervisor

  @impl true
  def registry_spec(opts \\ []) do
    name = Keyword.get(opts, :name, @registry)
    {Registry, [keys: :unique, name: name]}
  end

  @impl true
  def supervisor_spec(opts \\ []) do
    name = Keyword.get(opts, :name, @supervisor)
    {DynamicSupervisor, [name: name, strategy: :one_for_one]}
  end

  @impl true
  def via_tuple(plugin, type, id) do
    {:via, Registry, {@registry, {plugin, type, id}}}
  end

  @impl true
  def whereis(plugin, type, id) do
    case Registry.lookup(@registry, {plugin, type, id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def start_child(child_spec) do
    DynamicSupervisor.start_child(@supervisor, child_spec)
  end

  @impl true
  def terminate_child(pid) do
    DynamicSupervisor.terminate_child(@supervisor, pid)
  end

  @impl true
  def count do
    Registry.count(@registry)
  end

  @impl true
  def list_active do
    if Process.whereis(@registry) do
      Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.map(fn {{plugin, type, id}, pid} ->
        info =
          if is_pid(pid) and Process.alive?(pid), do: Process.info(pid, [:memory, :message_queue_len]) || [], else: []

        mem_kb = Float.round(Keyword.get(info, :memory, 0) / 1024, 1)
        queue = Keyword.get(info, :message_queue_len, 0)

        %{
          plugin: plugin,
          type: type,
          id: id,
          pid: inspect(pid),
          memory_kb: mem_kb,
          queue_len: queue
        }
      end)
    else
      []
    end
  end
end
