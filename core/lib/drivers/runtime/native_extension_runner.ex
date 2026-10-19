defmodule Exoforge.Drivers.Runtime.NativeExtensionRunner do
  @moduledoc """
  Standardized alias for Exoforge.Drivers.Runtime.NativePluginRunner.
  """
  @behaviour Exoforge.Contracts.ExtensionRunner

  defdelegate load(manifest), to: Exoforge.Drivers.Runtime.NativePluginRunner
  defdelegate prepare_manifest(manifest), to: Exoforge.Drivers.Runtime.NativePluginRunner
  defdelegate start_link(args), to: Exoforge.Drivers.Runtime.NativePluginRunner
  defdelegate execute_action(manifest_id, action, payload), to: Exoforge.Drivers.Runtime.NativePluginRunner
  defdelegate dispatch_event(manifest_id, event_key, payload, context), to: Exoforge.Drivers.Runtime.NativePluginRunner
end
