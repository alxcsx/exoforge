defmodule Exoforge.Drivers.Runtime.PluginProtocol do
  @moduledoc """
  The host side of the plugin wire protocol: version, capabilities, and the handshake rules.

  The protocol is specified once, in `Agents.MD` under "The plugin wire protocol", and implemented
  twice - here and in the C# SDK (`PluginHost`/`HostBridge`). `plugin_protocol_test.exs` pins the
  frame and the accepted and refused cases on this side, and `HandshakeTests.cs` pins the SDK's, so
  a drift is a failing test rather than a plugin that dies on deploy.

  A session opens when the host writes `hello` and the plugin answers with its own. Everything
  after that is:

      host  -> plugin   {"type":"action","id":1,"action":"move","payload":{...}}
      plugin -> host    {"type":"action_result","id":1,"status":"ok","data":1}
      plugin -> host    {"type":"host_call","id":7,"op":"emit_event","args":{...}}
      host  -> plugin   {"type":"host_call_result","id":7,"result":true}
      plugin -> host    {"type":"host_log","level":3,"message":"..."}
      host  -> plugin   {"type":"event","event":"value_changed","payload":{...}}
  """

  # Bump only for a change that is not backward compatible. Capabilities are frame types, and a new
  # frame type is a capability to negotiate, not a version to bump.
  @protocol 1
  @host_capabilities ~w(action_result host_call host_log)
  @plugin_capabilities ~w(action event)
  @handshake_timeout_ms 5_000

  @doc "The protocol version this host speaks."
  def protocol, do: @protocol

  @doc "The frame types this host can receive."
  def host_capabilities, do: @host_capabilities

  @doc "The frame types a plugin must be able to receive for the host to run it."
  def plugin_capabilities, do: @plugin_capabilities

  @doc "How long a plugin has to answer the hello before it is refused."
  def handshake_timeout_ms, do: @handshake_timeout_ms

  @doc "The host's opening frame, ready to write to the port as one line."
  def hello_frame do
    Jason.encode!(%{
      type: "hello",
      protocol: @protocol,
      host: "exoforge",
      capabilities: @host_capabilities
    })
  end

  @doc """
  Validates a plugin's hello.

  Returns `{:ok, handshake}` or `{:refuse, reason}`. A refusal is permanent: no amount of retrying
  changes what a plugin is, so the runner says why once and stops.
  """
  def accept_hello(%{"protocol" => protocol, "capabilities" => capabilities})
      when is_list(capabilities) do
    missing = @plugin_capabilities -- capabilities

    cond do
      protocol != @protocol -> {:refuse, {:protocol_mismatch, protocol}}
      missing != [] -> {:refuse, {:missing_capabilities, missing}}
      true -> {:ok, %{protocol: protocol, capabilities: capabilities}}
    end
  end

  def accept_hello(%{"protocol" => protocol}) when protocol == @protocol do
    {:refuse, {:missing_capabilities, @plugin_capabilities}}
  end

  def accept_hello(msg) when is_map(msg) do
    {:refuse, {:protocol_mismatch, Map.get(msg, "protocol")}}
  end

  @doc "A refusal reason as a sentence a developer can act on."
  def refusal({:protocol_mismatch, version}),
    do: "it speaks protocol #{inspect(version)} and the host speaks #{@protocol}"

  def refusal({:missing_capabilities, missing}),
    do: "it does not handle #{Enum.join(missing, ", ")} frames"

  def refusal(:no_handshake), do: "it did not complete the protocol handshake"
end
