defmodule Exoforge.Domain.Manifest do
  @moduledoc """
  Represents an Plugin metadata
  """

  @enforce_keys [:id, :name, :version, :entry_point]

  defstruct id: "",
            name: "",
            version: nil,
            type: :elixir,
            context: :global,
            # automatically set by the loader.
            physical_path: "",
            entry_point: nil,
            dependencies: [],
            provides: [],
            assets_path: "assets"
end
