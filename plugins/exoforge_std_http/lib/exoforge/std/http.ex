defmodule Exoforge.Std.Http do
  @moduledoc """
  Standard HTTP REST ingress plugin for Exoforge.
  Provides the :http service contract.
  Mounts Bandit HTTP server and routes incoming HTTP requests to contract actions.
  """
  use Exoforge.Plugin, provides: [:http]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Auth],
    title: "HTTP Ingress",
    icon: "🌐",
    category: "Ingress",
    system: true,
    dashboard_view: nil,
    ui_hooks: %{
      settings: [
        %{
          id: :http,
          title: "HTTP & CORS",
          icon: "🌐",
          order: 28
        }
      ]
    }
  }

  def on_init(_manifest) do
    Exoforge.Std.Http.Cors.init()
    :ok
  end

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

  defaction get_cors_config() do
    {:ok, Exoforge.Std.Http.Cors.get_config()}
  end

  defaction set_cors_config(payload), scope: Exoforge.Auth.Roles.studio() do
    Exoforge.Std.Http.Cors.set_config(payload)
  end
end
