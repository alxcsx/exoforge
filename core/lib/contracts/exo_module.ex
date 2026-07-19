defmodule Exoforge.Contracts.ExoModule do
  alias Exoforge.Domain.Manifest
  @callback init(manifest :: Manifest.t()) :: {:ok, [map()] | {:error, any()}}
end
