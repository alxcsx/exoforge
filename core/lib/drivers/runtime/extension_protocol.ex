defmodule Exoforge.Drivers.Runtime.ExtensionProtocol do
  @moduledoc """
  The host side of the extension wire protocol: version, capabilities, and the handshake rules.

  The protocol is specified once, in `Agents.MD` under "The extension wire protocol", and implemented
  twice - here and in the C# SDK (`ExtensionHost`/`HostBridge`). `extension_protocol_test.exs` pins the
  frame and the accepted and refused cases on this side, and `HandshakeTests.cs` pins the SDK's, so
  a drift is a failing test rather than an extension that dies on deploy.

  A session opens when the host writes `hello` and the extension answers with its own. Everything
  after that is:

      host      -> extension {"type":"action","id":1,"action":"move","payload":{...}}
      extension -> host      {"type":"action_result","id":1,"status":"ok","data":1}
      extension -> host      {"type":"host_call","id":7,"op":"emit_event","args":{...}}
      host      -> extension {"type":"host_call_result","id":7,"result":true}
      extension -> host      {"type":"host_log","level":3,"message":"..."}
      host      -> extension {"type":"event","event":"value_changed","payload":{...}}
  """

  @protocol 1
  @host_capabilities ~w(action_result host_call host_log)
  @extension_capabilities ~w(action event)
  @handshake_timeout_ms 5_000

  @doc "The protocol version this host speaks."
  def protocol, do: @protocol

  @doc "The frame types this host can receive."
  def host_capabilities, do: @host_capabilities

  @doc "The frame types an extension must be able to receive for the host to run it."
  def extension_capabilities, do: @extension_capabilities

  @doc "How long an extension has to answer the hello before it is refused."
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
  Validates an extension's hello.

  Returns `{:ok, handshake}` or `{:refuse, reason}`. A refusal is permanent: no amount of retrying
  changes what an extension is, so the runner says why once and stops.
  """
  def accept_hello(%{"protocol" => protocol, "capabilities" => capabilities})
      when is_list(capabilities) do
    missing = @extension_capabilities -- capabilities

    cond do
      protocol != @protocol -> {:refuse, {:protocol_mismatch, protocol}}
      missing != [] -> {:refuse, {:missing_capabilities, missing}}
      true -> {:ok, %{protocol: protocol, capabilities: capabilities}}
    end
  end

  def accept_hello(%{"protocol" => protocol}) when protocol == @protocol do
    {:refuse, {:missing_capabilities, @extension_capabilities}}
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
