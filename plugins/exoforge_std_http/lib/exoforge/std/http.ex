defmodule Exoforge.Std.Http do
  @moduledoc """
  Standard HTTP REST ingress plugin for Exoforge.
  Provides the :http service contract.
  Mounts Bandit HTTP server and routes incoming HTTP requests to contract actions.
  """
  use Exoforge.Plugin, provides: [:http]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Auth]
  }

  def children do
    port = Application.get_env(:exoforge, :http_port, 4001)

    [
      {Bandit, plug: Exoforge.Std.Http.Router, port: port, scheme: :http}
    ]
  end

  @impl true
  defaction status() do
    port = Application.get_env(:exoforge, :http_port, 4001)
    {:ok, %{status: "ok", port: port}}
  end
end
