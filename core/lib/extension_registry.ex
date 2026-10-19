defmodule Exoforge.ExtensionRegistry do
  @moduledoc """
  Extension registry interface delegating to PluginRegistry.
  """

  defdelegate start_link(opts \\ []), to: Exoforge.PluginRegistry
  defdelegate initialize_ets, to: Exoforge.PluginRegistry
  defdelegate register(manifest), to: Exoforge.PluginRegistry
  defdelegate unregister(manifest_id), to: Exoforge.PluginRegistry
  defdelegate fetch_service(type, context \\ :global), to: Exoforge.PluginRegistry
  defdelegate fetch_manifest(manifest_id), to: Exoforge.PluginRegistry
  defdelegate fetch_by_module(module), to: Exoforge.PluginRegistry
  defdelegate all_manifests, to: Exoforge.PluginRegistry
  defdelegate all_resources, to: Exoforge.PluginRegistry
  defdelegate manifest_services(manifest), to: Exoforge.PluginRegistry
  defdelegate fetch_resource(resource_name), to: Exoforge.PluginRegistry
  defdelegate fetch_resource_rows(resource_name, caller_scopes \\ :internal), to: Exoforge.PluginRegistry
  defdelegate sanitize_for_json(data), to: Exoforge.PluginRegistry
  defdelegate clean_service_name(name), to: Exoforge.PluginRegistry
end
