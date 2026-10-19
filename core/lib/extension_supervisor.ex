defmodule Exoforge.ExtensionSupervisor do
  @moduledoc """
  Extension supervisor delegating to PluginSupervisor.
  """

  defdelegate start_link(init_arg \\ []), to: Exoforge.PluginSupervisor
end
