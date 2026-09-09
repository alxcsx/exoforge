defmodule Exoforge.Std.Database do
  use Exoforge.Plugin, provides: [:database, :lldb]

  # TODO: these should be required, currently it's just a warning.
  @impl true
  defaction execute(_operation) do
    %{rows: []}
  end

  @impl true
  defaction connection_config(_namespace) do
    %{
      url: "postgres://user:pass@localhost/db",
      pool_size: 10,
      driver: :postgres
    }
  end

  @impl true
  defaction health_check() do
    %{status: "ok"}
  end

  handle_event connection_lost(_payload) do
    # Handle the connection lost event here
    :ok
  end
end
