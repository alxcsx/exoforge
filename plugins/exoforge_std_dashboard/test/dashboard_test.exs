defmodule Exoforge.DashboardTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Exoforge.Std.Dashboard.Router
  alias Exoforge.PluginRegistry
  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.Manager, as: DbManager

  @opts Router.init([])

  setup do
    Application.put_env(:exoforge, :allow_dev_tokens, true)
    Application.put_env(:exoforge, :require_admin_auth, false)

    on_exit(fn ->
      Application.delete_env(:exoforge, :allow_dev_tokens)
      Application.delete_env(:exoforge, :require_admin_auth)
    end)

    PluginRegistry.initialize_ets()
    start_supervised!({DbManager, [driver: :sandbox]})

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_dashboard,
      name: "exoforge_std_dashboard",
      version: "0.1.0",
      entry_point: Exoforge.Std.Dashboard,
      provides: [Exoforge.Std.Services.DashboardView],
      dependencies: [Exoforge.Std.Services.Database]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_auth,
      name: "exoforge_std_auth",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [Exoforge.Std.Services.Auth],
      dependencies: [Exoforge.Std.Services.Database]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_player_data,
      name: "exoforge_std_player_data",
      version: "0.1.0",
      entry_point: Exoforge.Std.PlayerData,
      provides: [Exoforge.Std.Services.PlayerData],
      dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth]
    })

    unless Process.whereis(Exoforge.EventDispatcher.registry_name()) do
      start_supervised!(Exoforge.EventDispatcher)
    end

    unless Process.whereis(Exoforge.Std.Dashboard.PubSub) do
      start_supervised!({Phoenix.PubSub, name: Exoforge.Std.Dashboard.PubSub})
    end

    start_supervised!(Exoforge.Std.Dashboard.Endpoint)

    :ok
  end

  describe "Dashboard HTTP Endpoints" do
    test "GET /health returns 200 ok" do
      conn = conn(:get, "/health") |> Router.call(@opts)
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
    end

    test "GET / renders HTML dashboard" do
      conn =
        conn(:get, "/")
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })
        |> Router.call(@opts)

      assert conn.status == 200
      assert String.contains?(conn.resp_body, "EXOFORGE")
      assert String.contains?(conn.resp_body, "exoforge_std_database")
    end

    test "GET / redirects unauthenticated browsers to /login" do
      conn = conn(:get, "/") |> Router.call(@opts)
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/login"]
    end

    test "GET /login renders the sign-in form" do
      conn = conn(:get, "/login") |> Router.call(@opts)
      assert conn.status == 200
      assert String.contains?(conn.resp_body, "Sign in")
    end

    test "GET and POST resource rows handles player profiles" do
      conn =
        conn(:post, "/api/resources/players/rows", %{
          "player_id" => "p_studio_1",
          "profile" => %{"name" => "Valiant", "level" => 5}
        })
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["data"]["player"]["name"] == "Valiant"

      get_conn = conn(:get, "/api/resources/players/rows") |> Router.call(@opts)
      assert get_conn.status == 200
      get_body = Jason.decode!(get_conn.resp_body)
      assert is_list(get_body["rows"])
    end

    test "GET /api/overview returns system summary" do
      conn = conn(:get, "/api/overview") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "running"
      assert body["plugins_count"] >= 2
    end

    test "GET /api/extensions returns registered extensions and metadata" do
      conn = conn(:get, "/api/extensions") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["count"] >= 3
      assert is_list(body["extensions"])
    end

    test "GET /api/resources and /api/resources/:name/drawers" do
      conn = conn(:get, "/api/resources") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["count"] >= 1
      assert Enum.any?(body["resources"], fn r -> r["resource"]["name"] == "players" end)

      detail_conn = conn(:get, "/api/resources/players") |> Router.call(@opts)
      assert detail_conn.status == 200
      detail_body = Jason.decode!(detail_conn.resp_body)
      assert detail_body["resource"]["primary_key"] == "player_id"

      drawers_conn = conn(:get, "/api/resources/players/drawers") |> Router.call(@opts)
      assert drawers_conn.status == 200
      drawers_body = Jason.decode!(drawers_conn.resp_body)
      assert drawers_body["count"] >= 5
    end

    test "POST /api/dispatch allows testing actions with valid auth" do
      conn =
        conn(:post, "/api/dispatch", %{
          "service" => "lldb",
          "action" => "health_check",
          "payload" => %{}
        })
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer dev:admin")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["caller"] == "admin"
    end

    test "POST /api/dispatch rejects invalid token with 401" do
      conn =
        conn(:post, "/api/dispatch", %{
          "service" => "lldb",
          "action" => "health_check",
          "payload" => %{}
        })
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer invalid-token-xyz")
        |> Router.call(@opts)

      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
    end

    test "POST /api/dispatch rejects non-admin token with 403" do
      conn =
        conn(:post, "/api/dispatch", %{
          "service" => "lldb",
          "action" => "health_check",
          "payload" => %{}
        })
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer guest")
        |> Router.call(@opts)

      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
    end

    test "GET /api/overview gates non-admin and invalid tokens" do
      bad_conn =
        conn(:get, "/api/overview")
        |> put_req_header("authorization", "Bearer bad_token")
        |> Router.call(@opts)

      assert bad_conn.status == 401

      forbidden_conn =
        conn(:get, "/api/overview")
        |> put_req_header("authorization", "Bearer guest")
        |> Router.call(@opts)

      assert forbidden_conn.status == 403
    end

    test "GET /api/resources gates non-admin and invalid tokens" do
      bad_conn =
        conn(:get, "/api/resources")
        |> put_req_header("authorization", "Bearer bad_token")
        |> Router.call(@opts)

      assert bad_conn.status == 401

      forbidden_conn =
        conn(:get, "/api/resources")
        |> put_req_header("authorization", "Bearer guest")
        |> Router.call(@opts)

      assert forbidden_conn.status == 403
    end

    test "dashboard_view contract actions" do
      assert {:ok, %{mount: _}} =
               ActionDispatcher.dispatch(:dashboard_view, :get_dashboard_mount, %{view_id: :main})

      assert {:ok, %{data: data}} =
               ActionDispatcher.dispatch(:dashboard_view, :get_dashboard_data, %{view_id: :main})

      assert data.plugins_count >= 2
    end

    test "studio session can read APIs but cannot dispatch admin actions" do
      read =
        conn(:get, "/api/overview")
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "studio",
          "admin_scopes" => ["studio"]
        })
        |> Router.call(@opts)

      assert read.status == 200

      dispatch =
        conn(:post, "/api/dispatch", %{
          "service" => "lldb",
          "action" => "health_check",
          "payload" => %{}
        })
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "studio",
          "admin_scopes" => ["studio"]
        })
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert dispatch.status == 403
    end
  end
end
