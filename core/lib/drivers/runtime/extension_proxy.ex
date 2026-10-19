defmodule Exoforge.Drivers.Runtime.ExtensionProxy do
  @moduledoc """
  Standardized alias for Exoforge.Drivers.Runtime.PluginProxy.
  """
  defdelegate prepare(manifest, runner, module_name), to: Exoforge.Drivers.Runtime.PluginProxy
  defdelegate ensure(manifest, runner, module_name), to: Exoforge.Drivers.Runtime.PluginProxy
end
