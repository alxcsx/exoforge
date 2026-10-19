defmodule Exoforge.Drivers.Runtime.ExtensionProtocol do
  @moduledoc """
  Standardized alias for Exoforge.Drivers.Runtime.PluginProtocol.
  """
  defdelegate protocol, to: Exoforge.Drivers.Runtime.PluginProtocol
  defdelegate host_capabilities, to: Exoforge.Drivers.Runtime.PluginProtocol
  defdelegate plugin_capabilities, to: Exoforge.Drivers.Runtime.PluginProtocol
  defdelegate handshake_timeout_ms, to: Exoforge.Drivers.Runtime.PluginProtocol
  defdelegate hello_frame, to: Exoforge.Drivers.Runtime.PluginProtocol
  defdelegate accept_hello(frame), to: Exoforge.Drivers.Runtime.PluginProtocol
end
