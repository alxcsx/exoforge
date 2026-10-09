defmodule Exoforge.Drivers.Runtime.PluginProtocolTest do
  use ExUnit.Case, async: true

  alias Exoforge.Drivers.Runtime.PluginProtocol

  # The golden frame. The SDK's `HandshakeTests` pins the plugin's answer to it, and Agents.MD
  # ("The plugin wire protocol") is the spec both sides point at. Changing one without the others
  # is what this fails on.
  test "the host hello is the frame the spec describes" do
    assert Jason.decode!(PluginProtocol.hello_frame()) == %{
             "type" => "hello",
             "protocol" => 1,
             "host" => "exoforge",
             "capabilities" => ["action_result", "host_call", "host_log"]
           }
  end

  test "accepts a plugin that speaks the protocol and handles what the host sends" do
    assert {:ok, %{protocol: 1, capabilities: ["action", "event", "host_call_result"]}} =
             PluginProtocol.accept_hello(%{
               "protocol" => 1,
               "capabilities" => ["action", "event", "host_call_result"]
             })
  end

  test "refuses a plugin that speaks another protocol" do
    assert {:refuse, {:protocol_mismatch, 2}} =
             PluginProtocol.accept_hello(%{"protocol" => 2, "capabilities" => ["action", "event"]})
  end

  test "refuses a plugin that cannot handle a frame the host will send" do
    assert {:refuse, {:missing_capabilities, ["event"]}} =
             PluginProtocol.accept_hello(%{"protocol" => 1, "capabilities" => ["action"]})
  end

  test "refuses a hello with no capabilities at all" do
    assert {:refuse, {:missing_capabilities, ["action", "event"]}} =
             PluginProtocol.accept_hello(%{"protocol" => 1})
  end

  test "refuses a malformed hello rather than guessing" do
    assert {:refuse, {:protocol_mismatch, nil}} = PluginProtocol.accept_hello(%{})

    assert {:refuse, {:missing_capabilities, ["action", "event"]}} =
             PluginProtocol.accept_hello(%{"protocol" => 1, "capabilities" => "action"})
  end

  test "refusal messages name what to fix" do
    assert PluginProtocol.refusal({:protocol_mismatch, 2}) =~ "protocol 2"
    assert PluginProtocol.refusal({:missing_capabilities, ["event"]}) =~ "event"
    assert PluginProtocol.refusal(:no_handshake) =~ "handshake"
  end
end
