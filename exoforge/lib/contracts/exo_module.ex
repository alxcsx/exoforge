defmodule Exoforge.Contracts.ExoModule do
  alias Exoforge.Domain.Manifest
  @callback init(manifest :: Manifest) :: {:ok, [map()] | {:error, any()}}
end
