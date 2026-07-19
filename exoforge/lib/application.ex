defmodule Exoforge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    loader_config = Application.get_env(:exoforge, :module_loader)
    driver = Keyword.get(loader_config, :driver)
    path = Keyword.get(loader_config, :scan_path)

    children = [
      Exoforge.Domain.ExoModuleRegistry,
      Task.child_spec(fn -> Exoforge.Domain.ModuleBootstrapper.run(driver, path) end)
    ]

    opts = [strategy: :one_for_one, name: Exoforge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
