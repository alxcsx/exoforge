defmodule Exoforge.Std.TransportTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.Transport

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
                 "message" => "Item not found"
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
                 "message" => "Something exploded"
               }
             }
      refute Map.has_key?(result, "id")
    end
  end
end
