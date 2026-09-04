defmodule Exoforge.Std.Database do
  use Exoforge.Plugin, provides: [:database, :lldb]

  defaction execute(operation, arguments) do
    %{rows: []}
  end
end
