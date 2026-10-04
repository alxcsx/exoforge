defmodule Exoforge.Std.Dashboard.Endpoint do
  @moduledoc """
  Phoenix Endpoint for the Exoforge Game Producer & Designer Studio.
  Backed by Bandit as HTTP and WebSocket adapter.
  """
  use Phoenix.Endpoint, otp_app: :exoforge_std_dashboard

  @session_options [
    store: :cookie,
    key: "_exoforge_dashboard_key",
    signing_salt: "exoforge_dashboard_salt_987",
    same_site: "Lax",
    http_only: true,
    # Persist the login across tabs, reloads, and LiveView reconnects.
    max_age: 60 * 60 * 24 * 30
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Marks the auth cookie `Secure` only when the request actually arrived over
  # HTTPS (directly or via a TLS-terminating proxy), so plain-HTTP local runs
  # still work while real deployments never leak the cookie over HTTP.
  defp session(conn, _opts) do
    opts = Keyword.put(@session_options, :secure, secure_request?(conn))
    Plug.Session.call(conn, Plug.Session.init(opts))
  end

  defp secure_request?(conn) do
    conn.scheme == :https or forwarded_proto(conn) == "https"
  end

  defp forwarded_proto(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
      [proto | _] -> proto |> String.split(",") |> List.first() |> String.trim() |> String.downcase()
      [] -> nil
    end
  end

  plug(Plug.Static,
    at: "/",
    from: :exoforge_std_dashboard,
    gzip: false,
    only: ~w(vendor favicon.ico)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(:session)
  plug(Exoforge.Std.Dashboard.Router)
end
