defmodule Exoforge.Contracts.PluginRunner do
  @moduledoc """
  Plugin Runners are responsible for starting and managing the lifecycle of plugins.
  """
  alias Exoforge.Domain.Manifest

  @callback load(manifest :: %Manifest{}) :: :ok | {:error, term()}
end
