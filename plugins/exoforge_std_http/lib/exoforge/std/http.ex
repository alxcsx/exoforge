defmodule Exoforge.Std.Http do
  @moduledoc """
  Standard HTTP REST ingress plugin for Exoforge.
  Provides the :http service contract.
  Mounts Bandit HTTP server and routes incoming HTTP requests to contract actions.
  """
  use Exoforge.Plugin, provides: [:http]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Auth],
    category: "Ingress",
    system: true,
    dashboard_view: %{id: :http, title: "HTTP Ingress", icon: "🌐"}
  }

  def children do
    port = Exoforge.Endpoints.http_port()

    if Exoforge.Config.start_gateway?(),
      do: [{Bandit, plug: Exoforge.Std.Http.Router, port: port, scheme: :http}],
      else: []
  end

  @impl true
  defaction status() do
    {:ok, %{status: "ok", port: Exoforge.Endpoints.http_port()}}
  end
end
