defmodule Exoforge.Entities.Adapters.Horde do
  @moduledoc """
  Distributed cluster adapter for stateful entity actors using `Horde.Registry` and `Horde.DynamicSupervisor`.
  Features:
  - Distributed delta-CRDT process registry replicated across all BEAM cluster nodes
  - Guarantees cluster-wide uniqueness: exactly one active writer actor per entity id
  - Distributed supervision with automatic failover and node rebalancing
  - Seamless location transparency across the cluster
  """
  @behaviour Exoforge.Entities.Adapter

  @registry Exoforge.EntityRegistry
  @supervisor Exoforge.EntitySupervisor

  def registry_name, do: Application.get_env(:exoforge, :horde_registry, @registry)
  def supervisor_name, do: Application.get_env(:exoforge, :horde_supervisor, @supervisor)

  @impl true
  def registry_spec(opts \\ []) do
    name = Keyword.get(opts, :name, registry_name())
    members = Keyword.get(opts, :members, :auto)
    {Horde.Registry, [keys: :unique, name: name, members: members]}
  end

  @impl true
  def supervisor_spec(opts \\ []) do
    name = Keyword.get(opts, :name, supervisor_name())
    members = Keyword.get(opts, :members, :auto)
    {Horde.DynamicSupervisor, [name: name, strategy: :one_for_one, members: members]}
  end

  @impl true
  def via_tuple(plugin, type, id) do
    {:via, Horde.Registry, {registry_name(), {plugin, type, id}}}
  end

  @impl true
  def whereis(plugin, type, id) do
    case Horde.Registry.lookup(registry_name(), {plugin, type, id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def start_child(child_spec) do
    Horde.DynamicSupervisor.start_child(supervisor_name(), child_spec)
  end

  @impl true
  def terminate_child(pid) do
    Horde.DynamicSupervisor.terminate_child(supervisor_name(), pid)
  end

  @impl true
  def count do
    Horde.Registry.count(registry_name())
  end

  @doc """
  Updates the active Horde cluster members across the Registry and DynamicSupervisor.
  """
  def set_members(nodes) when is_list(nodes) do
    reg_members = Enum.map(nodes, fn node -> {registry_name(), node} end)
    sup_members = Enum.map(nodes, fn node -> {supervisor_name(), node} end)

    Horde.Cluster.set_members(registry_name(), reg_members)
    Horde.Cluster.set_members(supervisor_name(), sup_members)
  end

  @doc """
  Retrieves the current Horde cluster members.
  """
  def members do
    Horde.Cluster.members(registry_name())
  end
end
