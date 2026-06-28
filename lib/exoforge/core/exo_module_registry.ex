defmodule Exoforge.Core.ExoModuleRegistry do
  use GenServer
  alias Exoforge.Core.Manifest
  # -- Client API
  def start_link(_opt) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def register(%Manifest{} = manifest) do
    GenServer.call(__MODULE__, {:register, manifest})
  end

  # -- Server Callbacks
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
