defmodule Exoforge.ExtensionRegistry do
  @moduledoc """
  Extension registry interface delegating to PluginRegistry.
  """

  defdelegate register(manifest), to: Exoforge.PluginRegistry
  defdelegate unregister(manifest_id), to: Exoforge.PluginRegistry
  defdelegate fetch_service(type, context \\ :global), to: Exoforge.PluginRegistry
  defdelegate fetch_manifest(manifest_id), to: Exoforge.PluginRegistry
  defdelegate fetch_by_module(module), to: Exoforge.PluginRegistry
  defdelegate all_manifests, to: Exoforge.PluginRegistry
end
