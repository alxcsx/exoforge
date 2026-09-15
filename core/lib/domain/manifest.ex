defmodule Exoforge.Domain.Manifest do
  @moduledoc """
  Represents an Plugin metadata
  """

  @enforce_keys [:id, :name, :version, :entry_point]

  defstruct [
    :id,
    :name,
    :version,
    :entry_point,
    type: :elixir,
    context: :global,
    # automatically set by the loader.
    physical_path: "",
    dependencies: [],
    provides: [],
    assets_path: "assets"
  ]
end
