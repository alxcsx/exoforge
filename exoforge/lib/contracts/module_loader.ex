defmodule Exoforge.Contracts.ModuleLoader do
  alias Exoforge.Domain.Manifest

  @callback load_modules(path :: String.t()) :: [Manifest.t()]
end
