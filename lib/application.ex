defmodule Exoforge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Exoforge.Dispatcher,
      Exoforge.WorkerRegistry,
      Exoforge.PluginRegistry,
      Exoforge.PluginSupervisor,
      Exoforge.PluginBootstrapper
    ]

    opts = [strategy: :one_for_one, name: Exoforge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
