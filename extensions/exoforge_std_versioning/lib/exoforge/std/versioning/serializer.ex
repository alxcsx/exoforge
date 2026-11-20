defmodule Exoforge.Std.Versioning.Serializer do
  @moduledoc """
  Runs status changes one at a time. A change reads every row and writes what moved, so two at once
  (two promotions, a promotion and a registration) could each decide from the same stale list.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Runs `fun` in the serializer and returns its result."
  def run(fun), do: GenServer.call(__MODULE__, {:run, fun}, :infinity)

  @impl true
  def init(_), do: {:ok, nil}

  @impl true
  def handle_call({:run, fun}, _from, state), do: {:reply, fun.(), state}
end
