defmodule Exoforge.Drivers.Runtime.ExtensionProtocolTest do
  use ExUnit.Case, async: true

  alias Exoforge.Drivers.Runtime.ExtensionProtocol

  # The golden frame. The SDK's `HandshakeTests` pins the extension's answer to it, and Agents.MD
  # ("The extension wire protocol") is the spec both sides point at. Changing one without the others
  # is what this fails on.
  test "the host hello is the frame the spec describes" do
    assert Jason.decode!(ExtensionProtocol.hello_frame()) == %{
             "type" => "hello",
             "protocol" => 1,
             "host" => "exoforge",
             "capabilities" => ["action_result", "host_call", "host_log", "lifecycle_result"]
           }
  end

  test "the host hello advertises a known database dialect when provided" do
    for dialect <- [:postgres, "postgres"] do
      assert Jason.decode!(ExtensionProtocol.hello_frame(dialect: dialect)) == %{
               "type" => "hello",
               "protocol" => 1,
               "host" => "exoforge",
               "capabilities" => ["action_result", "host_call", "host_log", "lifecycle_result"],
               "dialect" => "postgres"
             }
    end

    for dialect <- [:sqlite, "sqlite"] do
      assert Jason.decode!(ExtensionProtocol.hello_frame(dialect: dialect)) == %{
               "type" => "hello",
               "protocol" => 1,
               "host" => "exoforge",
               "capabilities" => ["action_result", "host_call", "host_log", "lifecycle_result"],
               "dialect" => "sqlite"
             }
    end
  end

  test "the host hello omits dialect when nil or unrecognized" do
    for dialect <- [nil, :unknown, :other] do
      decoded = Jason.decode!(ExtensionProtocol.hello_frame(dialect: dialect))
      refute Map.has_key?(decoded, "dialect")
      assert decoded["protocol"] == 1
    end
  end

  test "accepts an extension that speaks the protocol and handles what the host sends" do
    assert {:ok, %{protocol: 1, capabilities: ["action", "event", "host_call_result"], lifecycle: false}} =
             ExtensionProtocol.accept_hello(%{
               "protocol" => 1,
               "capabilities" => ["action", "event", "host_call_result"]
             })
  end

  test "accepts the optional lifecycle capability without requiring it" do
    assert {:ok, %{lifecycle: true}} =
             ExtensionProtocol.accept_hello(%{
               "protocol" => 1,
               "capabilities" => ["action", "event", "host_call_result", "lifecycle"]
             })
  end

  test "lifecycle frames carry an id and an explicit result" do
    assert Jason.decode!(ExtensionProtocol.lifecycle_frame(7)) == %{"type" => "lifecycle", "id" => 7}

    assert :ok = ExtensionProtocol.accept_lifecycle_result(%{"status" => "ok"})

    assert {:error, %{code: "startup_failed", message: "boom"}} =
             ExtensionProtocol.accept_lifecycle_result(%{
               "status" => "error",
               "error" => %{"code" => "startup_failed", "message" => "boom"}
             })

    assert {:error, %{code: "startup_failed"}} = ExtensionProtocol.accept_lifecycle_result(%{})
  end

  test "refuses an extension that speaks another protocol" do
    assert {:refuse, {:protocol_mismatch, 2}} =
             ExtensionProtocol.accept_hello(%{"protocol" => 2, "capabilities" => ["action", "event"]})
  end

  test "refuses an extension that cannot handle a frame the host will send" do
    assert {:refuse, {:missing_capabilities, ["event"]}} =
             ExtensionProtocol.accept_hello(%{"protocol" => 1, "capabilities" => ["action"]})
  end

  test "refuses a hello with no capabilities at all" do
    assert {:refuse, {:missing_capabilities, ["action", "event"]}} =
             ExtensionProtocol.accept_hello(%{"protocol" => 1})
  end

  test "refuses a malformed hello rather than guessing" do
    assert {:refuse, {:protocol_mismatch, nil}} = ExtensionProtocol.accept_hello(%{})

    assert {:refuse, {:missing_capabilities, ["action", "event"]}} =
             ExtensionProtocol.accept_hello(%{"protocol" => 1, "capabilities" => "action"})
  end

  test "refusal messages name what to fix" do
    assert ExtensionProtocol.refusal({:protocol_mismatch, 2}) =~ "protocol 2"
    assert ExtensionProtocol.refusal({:missing_capabilities, ["event"]}) =~ "event"
    assert ExtensionProtocol.refusal(:no_handshake) =~ "handshake"
  end
end
