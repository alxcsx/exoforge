defmodule Exoforge.Contracts.PluginLoader do
  @moduledoc """
  Plugin Loaders are responsible for desserializing plugin manifests.
  """
  alias Exoforge.Domain.Manifest

  @callback load_plugins(path :: String.t()) :: [Manifest.t()]
end
