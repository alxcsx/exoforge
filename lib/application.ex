defmodule Exoforge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    cluster_children =
      if topologies != [] and Code.ensure_loaded?(Cluster.Supervisor) do
        [{Cluster.Supervisor, [topologies, [name: Exoforge.ClusterSupervisor]]}]
      else
        []
      end

    children =
      cluster_children ++
        [
          %{id: :exo_cluster_pg, start: {:pg, :start_link, [:exo_cluster_pg]}},
          Exoforge.EventDispatcher,
          Exoforge.WorkerRegistry,
          Exoforge.PluginRegistry,
          Exoforge.DrawerRegistry,
          Exoforge.Entities.registry_spec(),
          Exoforge.Entities.supervisor_spec(),
          Exoforge.PluginSupervisor
        ]

    opts = [strategy: :one_for_one, name: Exoforge.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # raises on missing deps / dependency cycles -> app fails to start loudly
      Exoforge.PluginBootstrapper.boot()
      {:ok, pid}
    end
  end
end
