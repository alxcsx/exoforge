defmodule Exoforge.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Exoforge.Std.Http.Router
  alias Exoforge.Std.Http
  alias Exoforge.Std.Database.Manager, as: DbManager

  @opts Router.init([])

  defmodule MockAdminService do
    use Exoforge.Extension

    defaction secret_op(_payload), scope: :admin do
      {:ok, %{secret: "classified"}}
    end
  end

  defmodule MockErrorService do
    use Exoforge.Extension

    defaction fail_tuple(_payload), scope: :global do
      Exoforge.ExtensionLogs.append(:mock_error, 3, "internal detail for the rid")
      {:error, {:invalid_png, "Not a PNG image."}}
    end

    defaction fail_map(_payload), scope: :global do
      {:error, %{"code" => "invalid_png", "message" => "Not a PNG image."}}
    end
  end

  defmodule MockWebhookService do
    use Exoforge.Extension

    defwebhook stripe(payload) do
      body = payload["body"] || ""
      headers = payload["headers"] || %{}
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

    defwebhook ping(_payload) do
      {:ok, %{pong: true}}
    end
  end

  setup do
    Exoforge.ExtensionCase.allow_dev_tokens()
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)
    Exoforge.ExtensionCase.register_auth(Exoforge.Std.Auth)

    Exoforge.ExtensionCase.register_extension(Exoforge.Std.FileBucket,
      id: :exoforge_std_file_bucket,
      provides: [Exoforge.Std.Services.FileBucket]
    )

    Exoforge.ExtensionCase.register_extension(Exoforge.Std.Http,
      id: :exoforge_std_http,
      provides: [Exoforge.Std.Services.Http],
      dependencies: [Exoforge.Std.Services.Auth]
    )

    Exoforge.ExtensionCase.register_extension(MockAdminService, id: :mock_admin)
    Exoforge.ExtensionCase.register_extension(MockErrorService, id: :mock_error)
    Exoforge.ExtensionCase.register_extension(MockWebhookService, id: :mock_webhook)
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

    test "a player's action error keeps the code and message, and never the server logs" do
      {:ok, player} = Exoforge.Std.Auth.issue_token("ply_err", ["player"])

      conn =
        conn(:post, "/api/mock_error/fail_tuple", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{player}")
        |> put_req_header("x-exoforge-rid", "r_player_err")
        |> Router.call(@opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
      assert body["error"] == "invalid_png"
      assert body["message"] == "Not a PNG image."
      assert body["rid"] == "r_player_err"
      refute Map.has_key?(body, "logs")
    end

    test "a staff action error carries the code, the message and the logs" do
      conn =
        conn(:post, "/api/mock_error/fail_tuple", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer dev:admin")
        |> put_req_header("x-exoforge-rid", "r_staff_err")
        |> Router.call(@opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "invalid_png"
      assert body["message"] == "Not a PNG image."
      assert Enum.any?(body["logs"], &(&1 =~ "internal detail for the rid"))
    end

    test "a native extension's {code, message} error is mapped, not inspected" do
      {:ok, player} = Exoforge.Std.Auth.issue_token("ply_err_map", ["player"])

      conn =
        conn(:post, "/api/mock_error/fail_map", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{player}")
        |> Router.call(@opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "invalid_png"
      assert body["message"] == "Not a PNG image."
      refute body["error"] =~ "{:"
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

    test "an HTTP action is attributed to the account behind its token" do
      Exoforge.ActionTrace.enable()

      on_exit(fn -> Exoforge.ExtensionCase.reset_action_trace() end)

      conn =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer dev:admin")
        |> put_req_header("x-exoforge-rid", "r_http_1")
        |> Router.call(@opts)

      assert conn.status == 200
      assert get_resp_header(conn, "x-exoforge-rid") == ["r_http_1"]
      assert Jason.decode!(conn.resp_body)["rid"] == "r_http_1"

      # A caller passes a token, not a name: the route has to say who it was.
      samples = Exoforge.ActionTrace.samples("mock_admin.secret_op").samples
      assert Enum.any?(samples, &(&1.caller == "admin" and &1.rid == "r_http_1"))
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

    test "an expired bearer token is reported as token_expired, and auth.refresh renews it" do
      # An access token that has already run out, next to a refresh token that has not.
      Application.put_env(:exoforge, :auth, access_token_ttl: -1)
      on_exit(fn -> Application.delete_env(:exoforge, :auth) end)

      _ =
        Exoforge.Std.Auth.upsert_account(
          "exp_http",
          "exp_http@exoforge.test",
          "pw",
          ["admin"]
        )

      login =
        conn(:post, "/api/auth/login", Jason.encode!(%{email: "exp_http@exoforge.test", password: "pw"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      session = Jason.decode!(login.resp_body)["data"]
      assert is_binary(session["refresh_token"])

      expired =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{session["token"]}")
        |> Router.call(@opts)

      assert expired.status == 401
      assert Jason.decode!(expired.resp_body)["error"]["code"] == "token_expired"

      # New tokens are ordinary again; the client's refresh is a public call, so an expired bearer
      # in the header is not what authorizes it - the refresh token in the body is.
      Application.put_env(:exoforge, :auth, [])

      refreshed =
        conn(:post, "/api/auth/refresh", Jason.encode!(%{token: session["refresh_token"]}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert refreshed.status == 200
      renewed = Jason.decode!(refreshed.resp_body)["data"]
      assert is_binary(renewed["token"])
      assert renewed["refresh_token"] != session["refresh_token"]

      again =
        conn(:post, "/api/mock_admin/secret_op", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{renewed["token"]}")
        |> Router.call(@opts)

      assert again.status == 200
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

      # Download/serve the file (staff)
      get_conn =
        conn(:get, "/api/files/assets/#{file["id"]}")
        |> put_req_header("authorization", "Bearer dev:admin")
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

  describe "File Bucket access" do
    setup do
      {:ok, player} = Exoforge.Std.Auth.issue_token("ply_files", ["player"])

      {:ok, %{file: file}} =
        Exoforge.ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
          "bucket" => "levels",
          "filename" => "level.png",
          "content" => "png-bytes"
        })

      %{player: player, stored: file}
    end

    test "a player cannot upload raw files", %{player: player} do
      conn =
        conn(:post, "/api/files/upload", Jason.encode!(%{"bucket" => "levels", "filename" => "x.txt", "content" => "x"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{player}")
        |> Router.call(@opts)

      assert conn.status == 403
    end

    test "a player cannot reach the raw file actions", %{player: player} do
      for action <- ["upload_file", "read_file", "list_files", "delete_file"] do
        conn =
          conn(:post, "/api/file_bucket/#{action}", Jason.encode!(%{"bucket" => "levels", "filename" => "h.txt", "path" => "/etc/hosts"}))
          |> put_req_header("content-type", "application/json")
          |> put_req_header("authorization", "Bearer #{player}")
          |> Router.call(@opts)

        assert conn.status == 403, "#{action} returned #{conn.status}: #{conn.resp_body}"
      end
    end

    test "a stored file is not served without a token or signature", %{player: player, stored: file} do
      assert conn(:get, file["url"]) |> Router.call(@opts) |> Map.get(:status) == 403

      as_player = conn(:get, file["url"]) |> put_req_header("authorization", "Bearer #{player}") |> Router.call(@opts)
      assert as_player.status == 403
    end

    test "a signed URL serves exactly that file", %{stored: file} do
      {:ok, %{url: url}} =
        Exoforge.ActionDispatcher.dispatch_internal(:file_bucket, :signed_url, %{"bucket" => "levels", "id" => file["id"]})

      ok = conn(:get, url) |> Router.call(@opts)
      assert ok.status == 200
      assert ok.resp_body == "png-bytes"

      tampered = conn(:get, String.replace(url, "sig=", "sig=x")) |> Router.call(@opts)
      assert tampered.status == 403
    end
  end

  describe "CORS configuration and preflight" do
    test "returns 204 on OPTIONS preflight with CORS headers" do
      conn =
        conn(:options, "/api/status")
        |> put_req_header("origin", "https://game.example.com")
        |> put_req_header("access-control-request-method", "POST")
        |> put_req_header("access-control-request-headers", "authorization,content-type")
        |> Router.call(@opts)

      assert conn.status == 204
      headers = Map.new(conn.resp_headers)
      assert headers["access-control-allow-origin"] == "https://game.example.com"
      assert headers["access-control-allow-credentials"] == "true"
      assert headers["access-control-allow-methods"] =~ "POST"
    end

    test "attaches CORS headers to normal GET responses" do
      conn =
        conn(:get, "/api/status")
        |> put_req_header("authorization", "Bearer dev:admin")
        |> put_req_header("origin", "https://game.example.com")
        |> Router.call(@opts)

      assert conn.status == 200
      headers = Map.new(conn.resp_headers)
      assert headers["access-control-allow-origin"] == "https://game.example.com"
    end

    test "get_cors_config and set_cors_config dynamically update CORS behavior" do
      {:ok, initial_config} = Http.get_cors_config()
      assert is_map(initial_config)
      assert initial_config["mode"] == "relaxed"

      # Update to whitelist mode
      {:ok, updated} =
        Http.set_cors_config(%{
          "mode" => "whitelist",
          "allowed_origins" => ["https://allowed.example.com"],
          "allow_credentials" => true
        })

      assert updated["mode"] == "whitelist"
      assert updated["allowed_origins"] == "https://allowed.example.com"

      # Allowed origin should get headers
      allowed_conn =
        conn(:options, "/api/status")
        |> put_req_header("origin", "https://allowed.example.com")
        |> Router.call(@opts)

      allowed_headers = Map.new(allowed_conn.resp_headers)
      assert allowed_headers["access-control-allow-origin"] == "https://allowed.example.com"

      # Disallowed origin should NOT get access-control-allow-origin header
      disallowed_conn =
        conn(:options, "/api/status")
        |> put_req_header("origin", "https://evil.example.com")
        |> Router.call(@opts)

      disallowed_headers = Map.new(disallowed_conn.resp_headers)
      refute Map.has_key?(disallowed_headers, "access-control-allow-origin")

      # Restore to relaxed mode
      {:ok, _} =
        Http.set_cors_config(%{
          "mode" => "relaxed",
          "allow_credentials" => true
        })
    end
  end
end
