defmodule Exoforge.Contracts.ExtensionRunner do
  @moduledoc """
  Extension Runners are responsible for starting and managing the lifecycle of extensions.
  """
  alias Exoforge.Domain.Manifest

  @callback load(manifest :: %Manifest{}) :: :ok | {:error, term()}
end
