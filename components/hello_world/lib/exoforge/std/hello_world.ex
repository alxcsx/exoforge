defmodule Exoforge.Std.HelloWorld do
  @behaviour Exoforge.Contracts.ExoModule

  @impl true
  def init(_m) do
  end

  def hello do
    :world
  end
end
