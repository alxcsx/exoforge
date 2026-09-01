defmodule Exoforge.Std.Database do
  use Exoforge.Module

  @impl true
  def start(_type, _args) do
    # Start the database module
    IO.puts("Starting Database Module...")
    {:ok, self()}
  end

  @impl true
  def stop(_state) do
    # Stop the database module
    IO.puts("Stopping Database Module...")
    :ok
  end
end
