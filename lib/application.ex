defmodule Exoforge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Exoforge.EventDispatcher,
      Exoforge.WorkerRegistry,
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
