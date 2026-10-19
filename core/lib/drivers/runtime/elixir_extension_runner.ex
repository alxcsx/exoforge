defmodule Exoforge.Drivers.Runtime.ElixirExtensionRunner do
  @moduledoc """
  Standardized alias for Exoforge.Drivers.Runtime.ElixirPluginRunner.
  """
  @behaviour Exoforge.Contracts.ExtensionRunner

  defdelegate load(manifest), to: Exoforge.Drivers.Runtime.ElixirPluginRunner
  defdelegate start_link(args), to: Exoforge.Drivers.Runtime.ElixirPluginRunner
end
