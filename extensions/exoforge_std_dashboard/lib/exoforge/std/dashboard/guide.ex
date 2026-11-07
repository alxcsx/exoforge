defmodule Exoforge.Std.Dashboard.Guide do
  @moduledoc """
  Backward-compatible delegate for the Developer Guide.
  The Developer Guide and live dynamic API reference are implemented in the decoupled
  `exoforge_std_docs` extension (`Exoforge.Std.Docs.View`).
  """

  def view(assigns) do
    apply(Exoforge.Std.Docs.View, :view, [assigns])
  end
end
