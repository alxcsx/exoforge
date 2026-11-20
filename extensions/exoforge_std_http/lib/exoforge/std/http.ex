defmodule Exoforge.Std.Http do
  @moduledoc """
  Standard HTTP REST ingress plugin for Exoforge.
  Provides the :http service contract.
  Mounts Bandit HTTP server and routes incoming HTTP requests to contract actions.

  External callers and the Unity SDK use it for request/response access to every service; staying an extension keeps the REST surface swappable and lets CORS policy change without touching clients.

  ### How it works
  - `children/0` starts Bandit with `Exoforge.Std.Http.Router` on `Exoforge.Endpoints.http_port/0`, and only when `Exoforge.Config.start_gateway?/0` is true.
  - `on_init/1` initializes CORS: an ETS table caches the policy, and settings persist in the http_settings table created through `:lldb`.
  - The router serves `/health`, `/api/status`, `/api/routes`, `/api/openapi.json` and a Swagger UI at `/api/docs`, answers OPTIONS with 204, and parses bodies up to 100 MB.
  - POST /api/:service/:action authenticates the bearer token, honours the x-exoforge-game-version header through `Exoforge.Std.Transport.check/1`, and dispatches with the caller's scopes.
  - /api/webhooks/:service/:action calls the named action as a webhook caller with the raw body, parsed JSON, headers and query.
  - `Exoforge.Std.Http.Cors` applies relaxed, whitelist or strict mode with credentials and max-age, and staff can replace the policy through the service contract.

  ### Depends on
  `:auth`; it also calls `:file_bucket`, `:database` and `:lldb` while serving files and reading CORS settings.
  """
  use Exoforge.Extension, provides: [:http]
  @behaviour Exoforge.Contracts.Transport

  @manifest %{
    dependencies: [Exoforge.Std.Services.Auth],
    title: "HTTP Ingress",
    icon: "🌐",
    category: "Network",
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

  @impl Exoforge.Contracts.Transport
  def transport_id, do: :http

  @impl Exoforge.Contracts.Transport
  def transport_type, do: :stateless

  @impl Exoforge.Contracts.Transport
  def dispatch_action(service, action, payload, context) do
    Exoforge.Std.Transport.dispatch(service, action, payload, context)
  end

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
  defaction status(), scope: :global do
    {:ok, %{status: "ok", port: Exoforge.Endpoints.http_port()}}
  end

  defaction get_cors_config(), scope: :global do
    {:ok, Exoforge.Std.Http.Cors.get_config()}
  end

  defaction set_cors_config(payload), scope: Exoforge.Auth.Roles.studio() do
    Exoforge.Std.Http.Cors.set_config(payload)
  end
end
