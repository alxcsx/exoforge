defmodule Exoforge.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Exoforge.Std.Http.Router
  alias Exoforge.Std.Http
  alias Exoforge.Std.Database.Manager, as: DbManager

  @opts Router.init([])

  defmodule MockAdminService do
    use Exoforge.Plugin

    defaction secret_op(_payload), scope: :admin do
      {:ok, %{secret: "classified"}}
    end
  end

  defmodule MockWebhookService do
    use Exoforge.Plugin

    defwebhook stripe(body, headers) do
      signature = headers["stripe-signature"] || ""

      if signature == "valid_signature" do
        {:ok, %{verified: true, size: byte_size(body)}}
      else
        {:error, :bad_signature}
      end
    end

    defwebhook challenge(payload) do
      query = payload["query"] || %{}

      if challenge = query["hub.challenge"] do
        {:ok, %{status_code: 200, body: challenge}}
      else
        {:ok, %{status_code: 202, body: "accepted"}}
      end
    end

    defwebhook ping do
      {:ok, %{pong: true}}
    end
  end

  setup do
    Exoforge.PluginCase.allow_dev_tokens()
    Exoforge.PluginCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    Exoforge.PluginCase.register_database(Exoforge.Std.Database)
    Exoforge.PluginCase.register_auth(Exoforge.Std.Auth)
    Exoforge.PluginCase.register_plugin(Exoforge.Std.FileBucket,
      id: :exoforge_std_file_bucket,
      provides: [Exoforge.Std.Services.FileBucket]
    )

    Exoforge.PluginCase.register_plugin(Exoforge.Std.Http,
      id: :exoforge_std_http,
      provides: [Exoforge.Std.Services.Http],
      dependencies: [Exoforge.Std.Services.Auth]
    )

    Exoforge.PluginCase.register_plugin(MockAdminService, id: :mock_admin)
    Exoforge.PluginCase.register_plugin(MockWebhookService, id: :mock_webhook)
    :ok
  end

  describe "HTTP Endpoints" do
    test "GET / returns 200 ok with gateway metadata" do
      conn = conn(:get, "/") |> put_req_header("authorization", "Bearer dev:admin") |> Router.call(@opts)
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
        |> put_req_header("authorization", "Bearer dev:admin")
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
      conn = conn(:get, "/api/status") |> put_req_header("authorization", "Bearer dev:admin") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["service"] == "exoforge_std_http"
    end

    test "GET /api/openapi.json returns valid OpenAPI 3.0 specification" do
      conn = conn(:get, "/api/openapi.json") |> put_req_header("authorization", "Bearer dev:admin") |> Router.call(@opts)
      assert conn.status == 200
      spec = Jason.decode!(conn.resp_body)
      assert spec["openapi"] == "3.0.3"
      assert spec["info"]["title"] =~ "Exoforge"
      assert is_map(spec["paths"])
      assert Map.has_key?(spec["paths"], "/health")
      assert Map.has_key?(spec["paths"], "/api/routes")
    end

    test "GET /api/docs returns interactive Swagger UI page" do
      conn = conn(:get, "/api/docs") |> put_req_header("authorization", "Bearer dev:admin") |> Router.call(@opts)
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
        |> put_req_header("authorization", "Bearer dev:admin")
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
      assert body["error"] == "unauthenticated"
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

    test "studio token can read routes but player token is forbidden" do
      {:ok, studio} = Exoforge.Std.Auth.issue_token("stu_http", ["studio"])
      {:ok, player} = Exoforge.Std.Auth.issue_token("ply_http", ["player"])

      studio_conn =
        conn(:get, "/api/routes")
        |> put_req_header("authorization", "Bearer #{studio}")
        |> Router.call(@opts)

      assert studio_conn.status == 200

      player_conn =
        conn(:get, "/api/routes")
        |> put_req_header("authorization", "Bearer #{player}")
        |> Router.call(@opts)

      assert player_conn.status == 403
    end

    test "studio token cannot run an admin-scoped action" do
      {:ok, studio} = Exoforge.Std.Auth.issue_token("stu_http2", ["studio"])

      conn =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{studio}")
        |> Router.call(@opts)

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["error"] == "forbidden_scope"
    end
  end

  describe "Inbound Webhooks" do
    test "POST /api/webhooks/:service/:action dispatches raw body and headers" do
      body = "{\"event\":\"charge.succeeded\",\"amount\":1000}"

      conn =
        conn(:post, "/api/webhooks/mock_webhook/stripe", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "valid_signature")
        |> Router.call(@opts)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)
      assert data["status"] == "ok"
      assert data["data"]["verified"] == true
      assert data["data"]["size"] == byte_size(body)
    end

    test "POST /api/webhook/:service/:action supports singular route" do
      conn =
        conn(:post, "/api/webhook/mock_webhook/stripe", "raw_payload")
        |> put_req_header("stripe-signature", "valid_signature")
        |> Router.call(@opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["verified"] == true
    end

    test "POST /api/webhooks rejects invalid signature from plugin handler" do
      conn =
        conn(:post, "/api/webhooks/mock_webhook/stripe", "fake_payload")
        |> put_req_header("stripe-signature", "wrong_signature")
        |> Router.call(@opts)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "bad_signature"
    end

    test "GET /api/webhooks responds to verification challenges with custom status and body" do
      conn =
        conn(:get, "/api/webhooks/mock_webhook/challenge?hub.challenge=xyz123")
        |> Router.call(@opts)

      assert conn.status == 200
      assert conn.resp_body == "xyz123"
    end

    test "GET /api/webhooks custom status code without challenge" do
      conn =
        conn(:get, "/api/webhooks/mock_webhook/challenge")
        |> Router.call(@opts)

      assert conn.status == 202
      assert conn.resp_body == "accepted"
    end

    test "POST /api/webhooks 0-arity ping webhook works" do
      conn =
        conn(:post, "/api/webhooks/mock_webhook/ping", "")
        |> Router.call(@opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["pong"] == true
    end

    test "Security: webhooks cannot invoke admin-scoped actions" do
      conn =
        conn(:post, "/api/webhooks/mock_admin/secret_op", "{}")
        |> Router.call(@opts)

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["error"] == "forbidden_scope"
    end
  end

  describe "File Bucket Endpoints" do
    test "POST /api/files/upload with JSON base64 content succeeds and GET serves file" do
      payload = %{
        "bucket" => "assets",
        "filename" => "hello.txt",
        "content" => Base.encode64("Hello World from REST"),
        "content_type" => "text/plain"
      }

      conn =
        conn(:post, "/api/files/upload", Jason.encode!(payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer dev:admin")
        |> Router.call(@opts)

      assert conn.status in [200, 201]
      resp = Jason.decode!(conn.resp_body)
      assert resp["status"] == "ok"
      file = resp["file"]
      assert file["filename"] == "hello.txt"
      assert file["bucket"] == "assets"

      # Download/serve the file
      get_conn =
        conn(:get, "/api/files/assets/#{file["id"]}")
        |> Router.call(@opts)

      assert get_conn.status == 200
      assert get_conn.resp_body == "Hello World from REST"
      assert get_resp_header(get_conn, "content-type") == ["text/plain"]
    end

    test "POST /api/files/upload with multipart form data succeeds" do
      # Create a temp file to simulate Plug.Upload
      tmp_path = Path.join(System.tmp_dir!(), "exo_test_upload.png")
      File.write!(tmp_path, <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)

      upload = %Plug.Upload{
        path: tmp_path,
        filename: "test_image.png",
        content_type: "image/png"
      }

      conn =
        conn(:post, "/api/files/upload", %{"file" => upload, "bucket" => "images"})
        |> put_req_header("authorization", "Bearer dev:admin")
        |> Router.call(@opts)

      assert conn.status in [200, 201]
      resp = Jason.decode!(conn.resp_body)
      assert resp["status"] == "ok"
      file = resp["file"]
      assert file["filename"] == "test_image.png"
      assert file["size_bytes"] == 8

      # Clean up tmp file
      File.rm(tmp_path)
    end
  end
end
