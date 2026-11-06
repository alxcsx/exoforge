defmodule Exoforge.Contracts.Extension do
  @moduledoc """
  Behaviour for Exoforge extensions.
  """
  alias Exoforge.Domain.Manifest
  @callback init(manifest :: %Manifest{}) :: :ok | {:error, any()}
end
