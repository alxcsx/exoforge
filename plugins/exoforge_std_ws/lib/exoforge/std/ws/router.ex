defmodule Exoforge.Std.Ws.Router do
  @moduledoc """
  HTTP and WebSocket router for the exoforge_std_ws plugin.
  """
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  get "/" do
    send_landing(conn)
  end

  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", plugin: "exoforge_std_ws"}))
  end

  get "/ws" do
    upgrade =
      get_req_header(conn, "upgrade")
      |> List.first()
      |> to_string()
      |> String.downcase()

    if upgrade == "websocket" do
      conn
      |> WebSockAdapter.upgrade(Exoforge.Std.Ws.SocketHandler, [], timeout: 60_000)
      |> halt()
    else
      send_upgrade_required(conn)
    end
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
  end

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
        <title>Exoforge WebSocket Gateway</title>
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
          <h1>Exoforge WebSocket Gateway</h1>
          <p>Real-time bi-directional WebSocket ingress for game clients (Unity C# SDK, WebSockets). Connect client sockets to <code>/ws</code>.</p>
          <div class="info-box">
            <div class="info-row"><span class="label">WebSocket URL</span><span class="value">ws://localhost:4000/ws</span></div>
            <div class="info-row"><span class="label">Protocol</span><span class="value">JSON Framed (Action/Event)</span></div>
            <div class="info-row"><span class="label">Health Check</span><span class="value"><a href="/health" style="color: #38bdf8; text-decoration: none;">/health</a></span></div>
          </div>
          <div class="actions">
            <a href="#{studio_url}" class="btn-primary">Open Game Studio (Port 4005) &rarr;</a>
            <a href="http://localhost:4001" class="btn-secondary">REST API (Port 4001)</a>
          </div>
        </div>
      </body>
      </html>
      """

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, html)
    else
      data = %{
        service: "exoforge_std_ws",
        status: "ok",
        gateway: "websocket",
        ws_endpoint: "/ws",
        health_endpoint: "/health",
        studio_url: get_studio_url(),
        message: "Exoforge WebSocket Gateway is active. Connect game clients to /ws or visit Game Studio at port 4005."
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(data))
    end
  end

  defp send_upgrade_required(conn) do
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
        <title>WebSocket Upgrade Required</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0b0f19; color: #f1f5f9; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 1rem; box-sizing: border-box; }
          .card { background: #131b2e; border: 1px solid #1e293b; border-radius: 14px; padding: 2.5rem; max-width: 540px; width: 100%; box-shadow: 0 20px 25px -5px rgba(0,0,0,0.5); }
          h1 { font-size: 1.35rem; margin: 0 0 0.5rem 0; color: #f59e0b; }
          p { color: #94a3b8; font-size: 0.95rem; line-height: 1.6; margin: 0 0 1.5rem 0; }
          .code { background: #090d16; border: 1px solid #1e293b; border-radius: 8px; padding: 0.75rem 1rem; font-family: monospace; font-size: 0.875rem; color: #38bdf8; margin-bottom: 1.5rem; }
          .actions { display: flex; gap: 0.75rem; flex-wrap: wrap; }
          .btn-primary { background: #7c3aed; color: #ffffff; text-decoration: none; font-weight: 600; font-size: 0.875rem; padding: 0.65rem 1.25rem; border-radius: 8px; display: inline-block; }
          .btn-secondary { background: #1e293b; color: #cbd5e1; text-decoration: none; font-weight: 500; font-size: 0.875rem; padding: 0.65rem 1.25rem; border-radius: 8px; border: 1px solid #334155; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>WebSocket Upgrade Required (426)</h1>
          <p>The <code>/ws</code> endpoint requires an active WebSocket connection. Connect using a WebSocket client or the Exoforge C# / Unity SDK.</p>
          <div class="code">ws://localhost:4000/ws</div>
          <div class="actions">
            <a href="#{studio_url}" class="btn-primary">Open Game Studio (Port 4005) &rarr;</a>
            <a href="/" class="btn-secondary">&larr; Back to Gateway Info</a>
          </div>
        </div>
      </body>
      </html>
      """

      conn
      |> put_resp_header("upgrade", "websocket")
      |> put_resp_content_type("text/html")
      |> send_resp(426, html)
    else
      conn
      |> put_resp_header("upgrade", "websocket")
      |> put_resp_content_type("application/json")
      |> send_resp(426, Jason.encode!(%{
        error: "upgrade_required",
        message: "This endpoint requires a WebSocket connection (ws:// or wss://). Connect using a WebSocket client or the Exoforge C# / Unity SDK.",
        websocket_url: "ws://localhost:4000/ws",
        studio_url: get_studio_url()
      }))
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
