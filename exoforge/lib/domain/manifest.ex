defmodule Exoforge.Domain.Manifest do
  @moduledoc """
  Represents an ExoModule metadata
  """

  defstruct id: "",
            name: "",
            version: "",
            type: "elixir",
            physical_path: "",
            dependencies: %{},
            entry_point: ""

  @typedoc "The parsed representation of a plugin's manifest.toml"
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          type: String.t(),
          physical_path: String.t(),
          dependencies: map(),
          entry_point: module() | nil
        }
end
