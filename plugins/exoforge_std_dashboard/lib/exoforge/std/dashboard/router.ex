defmodule Exoforge.Std.Dashboard.Router do
  @moduledoc """
  Phoenix Router for the Exoforge Game Producer & Designer Studio.
  Routes browser requests to Phoenix LiveView (StudioLive and ResourceLive)
  and REST/SSE requests to ApiController.
  """
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:ensure_endpoint)
    plug(:ensure_session)
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Exoforge.Std.Dashboard.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:sync_auth_cookie)
  end

  pipeline :public_api do
    plug(:accepts, ["json"])
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:ensure_session)
    plug(:fetch_session)

    plug(Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason
    )

    plug(:verify_studio_access)
  end

  scope "/", Exoforge.Std.Dashboard do
    pipe_through(:browser)

    get("/login", LoginController, :show)
    post("/login", ApiController, :login)
    get("/logout", ApiController, :logout)
  end

  live_session :studio, on_mount: {Exoforge.Std.Dashboard.AuthHook, :require_studio} do
    scope "/", Exoforge.Std.Dashboard do
      pipe_through(:browser)

      live("/", StudioLive, :index)
      live("/extensions", StudioLive, :apps)
      live("/tab/:tab", StudioLive, :tab)
      live("/extensions/:tab", StudioLive, :tab)
      live("/resources/:name", ResourceLive, :index)
    end
  end

  scope "/", Exoforge.Std.Dashboard do
    pipe_through(:public_api)

    get("/health", ApiController, :health)
  end

  scope "/", Exoforge.Std.Dashboard do
    pipe_through(:api)

    get("/api/overview", ApiController, :overview)
    get("/api/resources/:name/rows", ApiController, :resource_rows)
    post("/api/resources/:name/rows", ApiController, :create_resource_row)
    get("/api/extensions", ApiController, :extensions)
    get("/api/resources", ApiController, :resources)
    get("/api/resources/:name", ApiController, :resource_detail)
    get("/api/resources/:name/drawers", ApiController, :drawers)
    post("/api/dispatch", ApiController, :dispatch_action)
    get("/api/events", ApiController, :events)
  end

  defp ensure_endpoint(conn, _opts) do
    Plug.Conn.put_private(conn, :phoenix_endpoint, Exoforge.Std.Dashboard.Endpoint)
  end

  # Gate every Studio API endpoint behind a studio/admin session or token.
  defp verify_studio_access(conn, _opts) do
    case Exoforge.Std.Dashboard.ApiController.verify_studio_auth(conn) do
      {:ok, auth} ->
        Plug.Conn.assign(conn, :auth_ctx, auth)

      {:error, :forbidden} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(403, Jason.encode!(%{status: "error", error: "forbidden_scope"}))
        |> Plug.Conn.halt()

      {:error, _} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{status: "error", error: "unauthenticated"}))
        |> Plug.Conn.halt()
    end
  end

  # Transparently initialize test session for direct Plug.Test invocations
  defp ensure_session(conn, _opts) do
    if Map.has_key?(conn.private, :plug_session) do
      conn
    else
      Plug.Test.init_test_session(conn, %{})
    end
  end

  # Synchronize auth token to cross-port cookie for Swagger UI (:4001) and WebSocket (:4000)
  defp sync_auth_cookie(conn, _opts) do
    conn = Plug.Conn.fetch_query_params(conn)

    logged_out? =
      get_session(conn, "logged_out") == true or conn.query_params["logged_out"] == "true"

    token =
      unless logged_out? do
        get_session(conn, "auth_token")
      end

    if token do
      Plug.Conn.put_resp_cookie(conn, "exo_auth_token", token,
        path: "/",
        same_site: "Lax",
        http_only: false
      )
    else
      conn
    end
  end

  ## ---- PUBLIC DATA COLLECTOR (Backward-compatibility) ----

  def build_overview_data do
    plugins =
      try do
        :ets.tab2list(:exo_plugins_mem)
        |> Enum.map(fn {_id, m} ->
          %{
            id: to_string(m.id),
            name: to_string(m.name),
            version: to_string(m.version),
            type: to_string(m.type),
            entry_point: to_string(m.entry_point),
            provides: Enum.map(m.provides || [], &to_string/1),
            dependencies: Enum.map(m.dependencies || [], &to_string/1)
          }
        end)
      rescue
        _ -> []
      end

    db_health =
      case Exoforge.ActionDispatcher.dispatch(:lldb, :health_check, %{}) do
        {:ok, health} -> health
        _ -> %{status: "unknown"}
      end

    resources =
      try do
        Exoforge.PluginRegistry.all_resources()
      rescue
        _ -> []
      end

    extensions =
      try do
        Exoforge.PluginRegistry.dashboard_extensions()
      rescue
        _ -> []
      end

    %{
      status: "running",
      kernel: "Exoforge Core",
      plugins_count: length(plugins),
      plugins: plugins,
      extensions: extensions,
      resources: resources,
      resources_count: length(resources),
      database: db_health,
      timestamp: System.system_time(:millisecond)
    }
  end
end
