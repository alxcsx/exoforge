defmodule Exoforge.Domain.Manifest do
  @moduledoc """
  Represents an Plugin metadata
  """

  @enforce_keys [:id, :name, :version, :type, :entry_point, :dependencies, :provides]

  defstruct id: "",
            name: "",
            version: nil,
            type: :elixir,
            context: :global,
            # automatically set by the loader.
            physical_path: "",
            entry_point: nil,
            dependencies: [],
            provides: []
end
