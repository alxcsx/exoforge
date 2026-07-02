defmodule Exoforge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Exoforge.Domain.ExoModuleRegistry
    ]

    opts = [strategy: :one_for_one, name: Exoforge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
