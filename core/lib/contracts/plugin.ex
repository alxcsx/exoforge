defmodule Exoforge.Contracts.Plugin do
  alias Exoforge.Domain.Manifest
  @callback init(manifest :: %Manifest{}) :: :ok | {:error, any()}
end
