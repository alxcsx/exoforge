defmodule Exoforge.Std.Http.Router do
  @moduledoc """
  Plug router for Exoforge HTTP REST ingress.
  Exposes generic REST endpoints derived from registered service contracts.
  Enforces authentication scopes where required via the :auth service.
  """
  use Plug.Router

  alias Exoforge.ActionDispatcher

  plug :match
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  plug :dispatch

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
          window.ui = SwaggerUIBundle({
            url: '/api/openapi.json',
            dom_id: '#swagger-ui',
            presets: [
              SwaggerUIBundle.presets.apis
            ],
            layout: "BaseLayout",
            deepLinking: true
          });
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
    auth_header = get_req_header(conn, "authorization") |> List.first()
    raw_payload =
      case conn.body_params do
        p when is_map(p) -> Map.delete(p, "_auth") |> Map.delete(:_auth)
        other -> other
      end

    # If auth header is provided, attach identity and extract scopes
    {payload_with_auth, caller_scopes} =
      case extract_token(auth_header) do
        nil ->
          {raw_payload, []}

        token ->
          case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}) do
            {:ok, %{player_id: player_id, scopes: scopes} = auth_info} ->
              payload =
                if is_map(raw_payload) do
                  raw_payload
                  |> Map.put("player_id", player_id)
                  |> Map.put("_auth", auth_info)
                else
                  raw_payload
                end

              {payload, scopes}

            _ ->
              {raw_payload, []}
          end
      end

    case ActionDispatcher.dispatch(service, action, payload_with_auth, caller_scopes: caller_scopes) do
      {:ok, result} ->
        send_json(conn, 200, %{status: "ok", data: result})

      :ok ->
        send_json(conn, 200, %{status: "ok"})

      {:error, :service_not_found} ->
        send_json(conn, 404, %{status: "error", error: "service_not_found"})

      {:error, {:action_not_found, _}} ->
        send_json(conn, 404, %{status: "error", error: "action_not_found"})

      {:error, :unauthorized} ->
        send_json(conn, 401, %{status: "error", error: "unauthorized"})

      {:error, :forbidden_scope} ->
        send_json(conn, 403, %{status: "error", error: "forbidden_scope"})

      {:error, reason} ->
        send_json(conn, 400, %{status: "error", error: inspect(reason)})
    end
  end

  match _ do
    send_json(conn, 404, %{status: "error", error: "not_found"})
  end

  ## Helpers

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp extract_token(nil), do: nil

  defp extract_token("Bearer " <> token), do: String.trim(token)
  defp extract_token("bearer " <> token), do: String.trim(token)
  defp extract_token(token) when is_binary(token), do: String.trim(token)

  defp send_landing(conn) do
    accept = get_req_header(conn, "accept")
    is_html = Enum.any?(accept, &String.contains?(&1, "text/html"))

    if is_html do
      studio_url = get_studio_url()

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
            <a href="#{studio_url}" class="btn-primary">Open Game Studio (Port 4005) &rarr;</a>
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
        studio_url: get_studio_url(),
        message: "Exoforge HTTP REST Gateway is active. Query /api/routes for available routes, visit /api/docs for Swagger UI, or visit Game Studio at port 4005."
      })
    end
  end

  defp get_studio_url do
    port =
      Application.get_env(:exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint, [])
      |> Keyword.get(:http, [])
      |> Keyword.get(:port, 4005)

    host =
      Application.get_env(:exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint, [])
      |> Keyword.get(:url, [])
      |> Keyword.get(:host, "localhost")

    "http://#{host}:#{port}"
  end
end
