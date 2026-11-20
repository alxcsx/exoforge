defmodule Exoforge.Std.TransportTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Transport

  defmodule Versioning do
    use Exoforge.Extension

    defaction(resolve(%{version: "blocked"}), do: {:ok, %{status: :blocked}})
    defaction(resolve(%{version: "boom"}), do: {:error, :database_down})
    defaction(resolve(%{version: version}), do: {:ok, %{status: :live, version: version}})
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    if :ets.whereis(:exoforge_game_version_cache) != :undefined, do: :ets.delete_all_objects(:exoforge_game_version_cache)
    :ok
  end

  describe "check/1" do
    test "accepts a missing version" do
      assert {:ok, nil} = Transport.check(nil)
    end

    test "skips checking when versioning is not registered" do
      assert {:ok, nil} = Transport.check("no-service")
    end

    test "rejects a blocked version" do
      Exoforge.ExtensionCase.register_extension(Versioning, id: :versioning, provides: [:versioning])
      assert {:error, :upgrade_required} = Transport.check("blocked")
    end

    test "an expired cache entry is asked for again, not returned as the answer" do
      Exoforge.ExtensionCase.register_extension(Versioning, id: :versioning, provides: [:versioning])
      assert {:ok, %{status: :live}} = Transport.check("live")

      # age the entry past its expiry
      :ets.insert(:exoforge_game_version_cache, {"live", System.monotonic_time(:millisecond) - 1, {:ok, :stale}})

      assert {:ok, %{version: "live", status: :live}} = Transport.check("live")
    end

    test "a failure to ask lets the call through and is not cached" do
      Exoforge.ExtensionCase.register_extension(Versioning, id: :versioning, provides: [:versioning])
      assert {:ok, nil} = Transport.check("boom")
      assert :ets.lookup(:exoforge_game_version_cache, "boom") == []
    end

    test "returns the live version and status" do
      Exoforge.ExtensionCase.register_extension(Versioning, id: :versioning, provides: [:versioning])
      assert {:ok, %{version: "live", status: :live}} = Transport.check("live")
    end
  end

  describe "normalize_action_request/1" do
    test "normalizes valid string-keyed request" do
      req = %{
        "service" => "test_service",
        "action" => "ping",
        "payload" => %{"message" => "hello"},
        "id" => "req_42"
      }

      assert {:ok, service, "ping", %{"message" => "hello"}, "req_42"} =
               Transport.normalize_action_request(req)

      assert service in [:test_service, "test_service"] or is_atom(service)
    end

    test "normalizes valid atom-keyed request" do
      req = %{
        service: :test_service,
        action: :ping,
        payload: %{msg: "hi"},
        id: "abc"
      }

      assert {:ok, :test_service, "ping", %{msg: "hi"}, "abc"} =
               Transport.normalize_action_request(req)
    end

    test "fails on missing service" do
      req = %{"action" => "ping"}
      assert {:error, msg} = Transport.normalize_action_request(req)
      assert msg =~ "Missing required 'service'"
    end

    test "fails on missing action" do
      req = %{"service" => "test_service"}
      assert {:error, msg} = Transport.normalize_action_request(req)
      assert msg =~ "Missing required 'action'"
    end

    test "fails on non-map input" do
      assert {:error, _} = Transport.normalize_action_request("not a map")
    end
  end

  describe "public_action?/2" do
    test "allows unauthenticated auth actions" do
      assert Transport.public_action?(:auth, :login)
      assert Transport.public_action?("auth", "login")
      assert Transport.public_action?(:auth, :register)
      assert Transport.public_action?("auth", "anonymous")
      assert Transport.public_action?(:auth, :create_player)
    end

    test "rejects non-auth or private actions" do
      refute Transport.public_action?(:player_data, :get)
      refute Transport.public_action?(:auth, :profile)
      refute Transport.public_action?(:game, :submit_score)
    end
  end

  describe "sanitize_payload/2" do
    test "strips _auth and stamps verified player_id" do
      raw = %{"score" => 100, "_auth" => %{fake: true}, "player_id" => "imposter"}
      auth = %{player_id: "verified_user", scopes: ["player"]}

      sanitized = Transport.sanitize_payload(raw, auth)
      assert sanitized["player_id"] == "verified_user"
      refute Map.has_key?(sanitized, "_auth")
      assert sanitized["score"] == 100
    end

    test "allows admin/studio to target explicit player_id" do
      raw = %{"score" => 100, "player_id" => "target_user"}
      auth = %{player_id: "admin_user", scopes: ["admin"]}

      sanitized = Transport.sanitize_payload(raw, auth)
      assert sanitized["player_id"] == "target_user"
    end

    test "allows a service account to report for the player it names" do
      raw = %{"enemy" => "slime", "player_id" => "target_user"}
      auth = %{player_id: "usr_game_server", scopes: ["service"]}

      assert Transport.sanitize_payload(raw, auth)["player_id"] == "target_user"
    end
  end

  describe "format_action_result/3" do
    test "formats ok result with id" do
      result = Transport.format_action_result("req_1", :ok, %{value: 42})

      assert result == %{
               "id" => "req_1",
               "type" => "action_result",
               "status" => "ok",
               "data" => %{value: 42}
             }
    end

    test "formats error result with code and message" do
      result = Transport.format_action_result("req_2", :error, {:not_found, "Item not found"})

      assert result == %{
               "id" => "req_2",
               "type" => "action_result",
               "status" => "error",
               "error" => %{
                 "code" => "not_found",
                 "message" => "Item not found",
                 "details" => %{}
               }
             }
    end

    test "formats binary error" do
      result = Transport.format_action_result(nil, :error, "Something exploded")

      assert result == %{
               "type" => "action_result",
               "status" => "error",
               "error" => %{
                 "code" => "action_failed",
                 "message" => "Something exploded",
                 "details" => %{}
               }
             }
      refute Map.has_key?(result, "id")
    end
  end

  describe "action_error/1" do
    test "keeps a native extension's code and message map" do
      assert Transport.action_error(%{"code" => "invalid_png", "message" => "Not a PNG image."}) ==
               %{"code" => "invalid_png", "message" => "Not a PNG image.", "details" => %{}}
    end

    test "keeps the details a native extension reported" do
      assert Transport.action_error(%{
               "code" => "quota_exceeded",
               "message" => "Too many uploads.",
               "details" => %{"limit" => 10}
             }) == %{
               "code" => "quota_exceeded",
               "message" => "Too many uploads.",
               "details" => %{"limit" => 10}
             }
    end

    test "keeps an atom-keyed code and message map" do
      assert Transport.action_error(%{code: :invalid_png, message: "Not a PNG image."}) ==
               %{"code" => "invalid_png", "message" => "Not a PNG image.", "details" => %{}}
    end

    test "keeps a defaction code and message tuple" do
      assert Transport.action_error({:invalid_png, "Not a PNG image."}) ==
               %{"code" => "invalid_png", "message" => "Not a PNG image.", "details" => %{}}
    end

    test "a bare atom is its own code and message" do
      assert Transport.action_error(:bad_signature) ==
               %{"code" => "bad_signature", "message" => "bad_signature", "details" => %{}}
    end

    test "a bare binary is the message of an action_failed error" do
      assert Transport.action_error("boom") == %{
               "code" => "action_failed",
               "message" => "boom",
               "details" => %{}
             }
    end

    test "a missing action names it in the details" do
      error = Transport.action_error({:action_not_found, :ping})

      assert error["code"] == "action_not_found"
      assert error["details"] == %{"action" => "ping"}
      assert error["message"] =~ "ping"
    end

    test "a scope refusal moves the required and caller scopes into the details" do
      error = Transport.action_error({:forbidden_scope, %{required: :server, caller_scopes: [:player]}})

      assert error == %{
               "code" => "forbidden_scope",
               "message" => "Scope authorization failed",
               "details" => %{"required_scope" => "server", "caller_scopes" => ["player"]}
             }
    end

    test "a refusal that knows its reason carries it in the details" do
      error = Transport.action_error({:forbidden_scope, %{required: :studio, caller_scopes: ["player"], reason: :resource_not_player_readable}})

      assert error["details"] == %{
               "required_scope" => "studio",
               "caller_scopes" => ["player"],
               "reason" => "resource_not_player_readable"
             }
    end

    test "a bare scope refusal still answers in the nested shape" do
      assert Transport.action_error(:forbidden_scope) == %{
               "code" => "forbidden_scope",
               "message" => "Scope authorization failed",
               "details" => %{}
             }
    end
  end

  describe "error_body/2" do
    test "wraps the error with the status and the request id" do
      assert Transport.error_body({:not_found, "Item not found"}, "r_1") == %{
               "status" => "error",
               "error" => %{
                 "code" => "not_found",
                 "message" => "Item not found",
                 "details" => %{}
               },
               "rid" => "r_1"
             }
    end

    test "omits the rid when the request has none" do
      assert Transport.error_body(:unauthorized) == %{
               "status" => "error",
               "error" => %{
                 "code" => "unauthorized",
                 "message" => "unauthorized",
                 "details" => %{}
               }
             }
    end
  end

  describe "http_status/1" do
    test "maps each refusal to the status HTTP already answered with" do
      assert Transport.http_status(:service_not_found) == 404
      assert Transport.http_status({:action_not_found, :ping}) == 404
      assert Transport.http_status(:unauthorized) == 401
      assert Transport.http_status(:forbidden_scope) == 403
      assert Transport.http_status({:forbidden_scope, %{required: :admin}}) == 403
      assert Transport.http_status({:invalid_png, "Not a PNG image."}) == 400
      assert Transport.http_status("boom") == 400
    end
  end

  describe "staff_scopes?/1" do
    test "admin and studio are staff; player and webhook are not" do
      assert Transport.staff_scopes?(["admin"])
      assert Transport.staff_scopes?([:studio])
      refute Transport.staff_scopes?(["player"])
      refute Transport.staff_scopes?(["webhook", "global"])
      refute Transport.staff_scopes?([])
    end
  end
end
