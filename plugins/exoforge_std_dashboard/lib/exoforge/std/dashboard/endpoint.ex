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
  plug(Plug.Session, @session_options)
  plug(Exoforge.Std.Dashboard.Router)
end
