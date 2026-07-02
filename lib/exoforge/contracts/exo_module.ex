defmodule Exoforge.Contracts.ExoModule do
  alias Exoforge.Core.Manifest
  @callback init(manifest :: Manifest) :: {:ok, [map()] | {:error, any()}}
end
