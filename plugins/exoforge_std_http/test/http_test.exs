defmodule Exoforge.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Exoforge.Std.Http.Router
  alias Exoforge.Std.Http
  alias Exoforge.PluginRegistry
  alias Exoforge.Std.Database.Manager, as: DbManager

  @opts Router.init([])

  defmodule MockAdminService do
    use Exoforge.Plugin

    defaction secret_op(_payload), scope: :admin do
      {:ok, %{secret: "classified"}}
    end
  end

  setup do
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
      id: :exoforge_std_auth,
      name: "exoforge_std_auth",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [Exoforge.Std.Services.Auth],
      dependencies: [Exoforge.Std.Services.Database]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_http,
      name: "exoforge_std_http",
      version: "0.1.0",
      entry_point: Exoforge.Std.Http,
      provides: [Exoforge.Std.Services.Http],
      dependencies: [Exoforge.Std.Services.Auth]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :mock_admin,
      name: "mock_admin",
      version: "0.1.0",
      entry_point: MockAdminService
    })

    :ok
  end

  describe "HTTP Endpoints" do
    test "GET / returns 200 ok with gateway metadata" do
      conn = conn(:get, "/") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["service"] == "exoforge_std_http"
      assert body["gateway"] == "rest"
      assert body["endpoints"]["routes"] == "/api/routes"
    end

    test "GET / with Accept: text/html returns HTML landing page" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept", "text/html")
        |> Router.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Exoforge REST API Gateway"
      assert conn.resp_body =~ "/api/routes"
    end

    test "GET /health returns 200 ok" do
      conn = conn(:get, "/health") |> Router.call(@opts)
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
    end

    test "GET /api/status returns 200 with service name" do
      conn = conn(:get, "/api/status") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["service"] == "exoforge_std_http"
    end

    test "GET /api/openapi.json returns valid OpenAPI 3.0 specification" do
      conn = conn(:get, "/api/openapi.json") |> Router.call(@opts)
      assert conn.status == 200
      spec = Jason.decode!(conn.resp_body)
      assert spec["openapi"] == "3.0.3"
      assert spec["info"]["title"] =~ "Exoforge"
      assert is_map(spec["paths"])
      assert Map.has_key?(spec["paths"], "/health")
      assert Map.has_key?(spec["paths"], "/api/routes")
    end

    test "GET /api/docs returns interactive Swagger UI page" do
      conn = conn(:get, "/api/docs") |> Router.call(@opts)
      assert conn.status == 200
      assert conn.resp_body =~ "SwaggerUIBundle"
      assert conn.resp_body =~ "/api/openapi.json"
    end

    test "POST /api/:service/:action dispatches to contract action" do
      # Dispatch to auth.authenticate with dev token
      payload = %{"token" => "dev:tester"}

      conn =
        conn(:post, "/api/auth/authenticate", Jason.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["data"]["player_id"] == "tester"
    end

    test "POST /api/:service/:action returns 404 for unknown service" do
      conn =
        conn(:post, "/api/non_existent/action", "{}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
      assert body["error"] == "service_not_found"
    end

    test "service action status/0 returns port" do
      assert {:ok, %{status: "ok", port: _}} = Http.status()
    end

    test "POST /api/:service/:action rejects unauthenticated call to scoped action with 401" do
      conn =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
      assert body["error"] == "unauthorized"
    end

    test "POST /api/:service/:action rejects insufficient scope with 403" do
      conn =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer guest")
        |> Router.call(@opts)

      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
      assert body["error"] == "forbidden_scope"
    end

    test "POST /api/:service/:action allows authorized admin token with 200" do
      conn =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer dev:admin")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["data"]["secret"] == "classified"
    end
  end
end
