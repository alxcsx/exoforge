defmodule Exoforge.Contracts.ModuleLoader do
  alias Exoforge.Domain.Manifest

  @callback load_modules() :: [Manifest.t()]
end
