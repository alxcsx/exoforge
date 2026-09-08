defmodule Exoforge.PluginSupervisor do
  use DynamicSupervisor

  def start_link(_opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_plugin(plugin_child_spec) do
    DynamicSupervisor.start_child(__MODULE__, plugin_child_spec)
  end
end
