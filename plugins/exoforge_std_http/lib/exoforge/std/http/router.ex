defmodule Exoforge.Std.Http.Router do
  @moduledoc """
  Plug router for Exoforge HTTP REST ingress.
  Exposes generic REST endpoints derived from registered service contracts.
  Enforces authentication scopes where required via the :auth service.
  """
  use Plug.Router
  require Logger

  alias Exoforge.ActionDispatcher

  plug(Plug.Logger)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:authorize_ingress)
  plug(:dispatch)

  get "/" do
    send_landing(conn)
  end

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  get "/api/status" do
    send_json(conn, 200, %{status: "ok", service: "exoforge_std_http"})
  end

  get "/api/routes" do
    # Fetch registered plugins and their actions
    routes =
      try do
        :ets.tab2list(:exo_services_mem)
        |> Enum.map(fn {{svc, _ctx}, manifest} ->
          %{
            service: to_string(svc),
            plugin_id: to_string(manifest.id),
            entry_point: to_string(manifest.entry_point)
          }
        end)
        |> Enum.uniq_by(& &1.service)
      rescue
        _ -> []
      end

    send_json(conn, 200, %{routes: routes})
  end

  get "/api/openapi.json" do
    spec = Exoforge.Std.Http.OpenAPI.generate()
    send_json(conn, 200, spec)
  end

  get "/api/docs" do
    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Exoforge API Documentation</title>
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui.css" />
      <style>
        body { margin: 0; background: #fafafa; }
        .topbar { display: none; }
      </style>
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js" crossorigin></script>
      <script>
        window.onload = () => {
          const urlParams = new URLSearchParams(window.location.search);
          const cookieMatch = document.cookie.match(/(?:^|;\s*)#{hd(Exoforge.Auth.Request.cookie_names())}=([^;]+)/);
          const token = urlParams.get('token') || (cookieMatch ? decodeURIComponent(cookieMatch[1].trim()) : null);
          const specUrl = token ? ('/api/openapi.json?token=' + encodeURIComponent(token)) : '/api/openapi.json';
          const ui = SwaggerUIBundle({
            url: specUrl,
            dom_id: '#swagger-ui',
            presets: [
              SwaggerUIBundle.presets.apis
            ],
            layout: "BaseLayout",
            deepLinking: true,
            onComplete: () => {
              if (token) {
                ui.preauthorizeApiKey("bearerAuth", token);
              }
            },
            requestInterceptor: (req) => {
              if (token && !req.headers["authorization"] && !req.headers["Authorization"]) {
                req.headers["Authorization"] = "Bearer " + token;
              }
              return req;
            }
          });
          window.ui = ui;
        };
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  post "/api/:service/:action" do
    raw_payload =
      case conn.body_params do
        p when is_map(p) -> Map.delete(p, "_auth") |> Map.delete(:_auth)
        other -> other
      end

    public? = public_action?(service, action)

    case authenticate_token(token_from_request(conn)) do
      {:ok, auth_info} ->
        dispatch_http(
          conn,
          service,
          action,
          with_identity(raw_payload, auth_info),
          auth_info.scopes
        )

      :error when public? ->
        dispatch_http(conn, service, action, raw_payload, [])

      :error ->
        unauthenticated(conn)
    end
  end

  defp dispatch_http(conn, service, action, payload, caller_scopes) do
    t0 = System.monotonic_time(:microsecond)
    result = ActionDispatcher.dispatch(service, action, payload, caller_scopes: caller_scopes)
    latency_us = System.monotonic_time(:microsecond) - t0

    case result do
      {:ok, result} ->
        Logger.info("[HTTP:Action] #{service}.#{action} -> 200 OK (#{latency_us}µs)")
        send_json(conn, 200, %{status: "ok", data: result})

      :ok ->
        Logger.info("[HTTP:Action] #{service}.#{action} -> 200 OK (#{latency_us}µs)")
        send_json(conn, 200, %{status: "ok"})

      {:error, :service_not_found} ->
        Logger.warning("[HTTP:Action] #{service}.#{action} -> 404 service_not_found (#{latency_us}µs)")
        send_json(conn, 404, %{status: "error", error: "service_not_found"})

      {:error, {:action_not_found, _}} ->
        Logger.warning("[HTTP:Action] #{service}.#{action} -> 404 action_not_found (#{latency_us}µs)")
        send_json(conn, 404, %{status: "error", error: "action_not_found"})

      {:error, :unauthorized} ->
        Logger.warning("[HTTP:Action] #{service}.#{action} -> 401 unauthorized (#{latency_us}µs)")
        send_json(conn, 401, %{status: "error", error: "unauthorized"})

      {:error, :forbidden_scope} ->
        Logger.warning("[HTTP:Action] #{service}.#{action} -> 403 forbidden_scope (#{latency_us}µs)")
        send_json(conn, 403, %{status: "error", error: "forbidden_scope"})

      {:error, reason} ->
        Logger.warning("[HTTP:Action] #{service}.#{action} -> 400 error: #{inspect(reason)} (#{latency_us}µs)")
        send_json(conn, 400, %{status: "error", error: inspect(reason)})
    end
  end

  # Actions that mint or verify an account are reachable without a token.
  defp public_action?(service, action) do
    service == "auth" and action in ["login", "register", "authenticate", "create_player", "anonymous"]
  end

  defp authenticate_token(nil), do: :error

  defp authenticate_token(token) do
    case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}) do
      {:ok, %{player_id: _pid, scopes: _scopes} = auth_info} -> {:ok, auth_info}
      _ -> :error
    end
  end

  defp with_identity(raw_payload, auth_info) when is_map(raw_payload) do
    raw_payload
    |> Map.put("player_id", auth_info.player_id)
    |> Map.put("_auth", auth_info)
  end

  defp with_identity(raw_payload, _auth_info), do: raw_payload

  match _ do
    send_json(conn, 404, %{status: "error", error: "not_found"})
  end

  ## Helpers

  # `/health` is public for container/orchestrator probes; action dispatch
  # authenticates in its own handler; every informational route (docs, routes,
  # status, landing) requires a studio or admin account.
  defp authorize_ingress(conn, _opts) do
    cond do
      conn.request_path == "/health" ->
        conn

      conn.method == "POST" and String.starts_with?(conn.request_path, "/api/") ->
        conn

      true ->
        case authenticate_request(conn) do
          {:ok, auth} ->
            if Exoforge.Auth.Roles.rank_of(auth.scopes) >= 2 do
              Plug.Conn.assign(conn, :auth, auth)
            else
              forbidden(conn)
            end

          :error ->
            unauthenticated(conn)
        end
    end
  end

  defp authenticate_request(conn) do
    authenticate_token(token_from_request(conn))
  end

  # Transports receive the request in their own shape; the token rules themselves are shared.
  defp token_from_request(conn) do
    conn = Plug.Conn.fetch_cookies(Plug.Conn.fetch_query_params(conn))
    Exoforge.Auth.Request.token(conn.req_headers, conn.query_params, conn.req_cookies)
  end

  defp unauthenticated(conn) do
    conn
    |> send_json(401, %{
      status: "error",
      error: "unauthenticated",
      message: "A valid bearer token is required. Use POST /api/auth/login or /api/auth/register."
    })
    |> Plug.Conn.halt()
  end

  defp forbidden(conn) do
    conn
    |> send_json(403, %{
      status: "error",
      error: "forbidden_scope",
      message: "A studio or admin account is required for this resource."
    })
    |> Plug.Conn.halt()
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp send_landing(conn) do
    accept = get_req_header(conn, "accept")
    is_html = Enum.any?(accept, &String.contains?(&1, "text/html"))

    if is_html do
      studio_url = Exoforge.Endpoints.studio_url()

      html = """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        <title>Exoforge REST API Gateway</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0b0f19; color: #f1f5f9; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 1rem; box-sizing: border-box; }
          .card { background: #131b2e; border: 1px solid #1e293b; border-radius: 14px; padding: 2.5rem; max-width: 540px; width: 100%; box-shadow: 0 20px 25px -5px rgba(0,0,0,0.5); }
          .badge { display: inline-flex; align-items: center; gap: 6px; background: #10b98120; color: #10b981; font-size: 0.75rem; font-weight: 600; padding: 4px 10px; border-radius: 9999px; border: 1px solid #10b98140; margin-bottom: 1rem; }
          .badge-dot { width: 6px; height: 6px; background: #10b981; border-radius: 50%; }
          h1 { font-size: 1.5rem; margin: 0 0 0.5rem 0; font-weight: 700; color: #ffffff; }
          p { color: #94a3b8; font-size: 0.95rem; line-height: 1.6; margin: 0 0 1.5rem 0; }
          .info-box { background: #090d16; border: 1px solid #1e293b; border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem; }
          .info-row { display: flex; justify-content: space-between; align-items: center; padding: 0.4rem 0; font-size: 0.875rem; border-bottom: 1px solid #1e293b50; }
          .info-row:last-child { border-bottom: none; }
          .label { color: #64748b; font-weight: 500; }
          .value { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: #38bdf8; }
          .actions { display: flex; gap: 0.75rem; flex-wrap: wrap; }
          .btn-primary { background: #7c3aed; color: #ffffff; text-decoration: none; font-weight: 600; font-size: 0.875rem; padding: 0.65rem 1.25rem; border-radius: 8px; transition: background 0.15s; }
          .btn-primary:hover { background: #6d28d9; }
          .btn-secondary { background: #1e293b; color: #cbd5e1; text-decoration: none; font-weight: 500; font-size: 0.875rem; padding: 0.65rem 1.25rem; border-radius: 8px; border: 1px solid #334155; }
          .btn-secondary:hover { background: #334155; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="badge"><span class="badge-dot"></span> Active &amp; Listening</div>
          <h1>Exoforge REST API Gateway</h1>
          <p>Standard HTTP REST ingress for contract action dispatch, status queries, and route discovery.</p>
          <div class="info-box">
            <div class="info-row"><span class="label">API Docs (Swagger)</span><span class="value"><a href="/api/docs" style="color: #38bdf8; text-decoration: none;">/api/docs</a></span></div>
            <div class="info-row"><span class="label">OpenAPI 3.0 Spec</span><span class="value"><a href="/api/openapi.json" style="color: #38bdf8; text-decoration: none;">/api/openapi.json</a></span></div>
            <div class="info-row"><span class="label">Dispatch Action</span><span class="value">POST /api/:service/:action</span></div>
            <div class="info-row"><span class="label">Service Routes</span><span class="value"><a href="/api/routes" style="color: #38bdf8; text-decoration: none;">/api/routes</a></span></div>
            <div class="info-row"><span class="label">Status</span><span class="value"><a href="/api/status" style="color: #38bdf8; text-decoration: none;">/api/status</a></span></div>
            <div class="info-row"><span class="label">Health Check</span><span class="value"><a href="/health" style="color: #38bdf8; text-decoration: none;">/health</a></span></div>
          </div>
          <div class="actions">
            <a href="#{studio_url}" class="btn-primary">Open Game Studio (Port #{Exoforge.Endpoints.dashboard_port()}) &rarr;</a>
            <a href="/api/docs" class="btn-secondary">Interactive Swagger Docs</a>
          </div>
        </div>
      </body>
      </html>
      """

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, html)
    else
      send_json(conn, 200, %{
        service: "exoforge_std_http",
        status: "ok",
        gateway: "rest",
        endpoints: %{
          docs: "/api/docs",
          openapi: "/api/openapi.json",
          routes: "/api/routes",
          status: "/api/status",
          health: "/health",
          dispatch: "POST /api/:service/:action"
        },
        studio_url: Exoforge.Endpoints.studio_url(),
        message:
          "Exoforge HTTP REST Gateway is active. Query /api/routes for available routes, visit /api/docs for Swagger UI, or visit Game Studio at port #{Exoforge.Endpoints.dashboard_port()}."
      })
    end
  end


end
