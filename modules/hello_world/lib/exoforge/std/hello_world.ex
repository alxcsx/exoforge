defmodule Exoforge.Std.HelloWorld do
  @behaviour Exoforge.Contracts.ExoModule

  @impl true
  def init(_m) do
    {:ok, []}
  end

  def hello do
    :world
  end
end
