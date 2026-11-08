defmodule Exoforge.ExtensionSupervisor do
  @moduledoc """
  Dynamic supervisor for supervised extension processes.
  """
  use DynamicSupervisor

  def start_link(_opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 100, max_seconds: 5)
  end
end
