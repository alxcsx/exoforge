defmodule Exoforge.ExtensionBootstrapper do
  @moduledoc """
  Extension lifecycle bootstrapper delegating to PluginBootstrapper.
  """

  defdelegate boot, to: Exoforge.PluginBootstrapper
  defdelegate reload_all, to: Exoforge.PluginBootstrapper
  defdelegate boot_extension(manifest), to: Exoforge.PluginBootstrapper, as: :boot_plugin
  defdelegate unload_extension(id), to: Exoforge.PluginBootstrapper, as: :unload_plugin
end
