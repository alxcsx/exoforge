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
  end

  live_session :default do
    scope "/", Exoforge.Std.Dashboard do
      pipe_through(:browser)

      live("/", StudioLive, :index)
      live("/tab/:tab", StudioLive, :tab)
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

  # Transparently initialize test session for direct Plug.Test invocations
  defp ensure_session(conn, _opts) do
    if Map.has_key?(conn.private, :plug_session) do
      conn
    else
      Plug.Test.init_test_session(conn, %{})
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
