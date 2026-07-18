defmodule Exoforge.Domain.Manifest do
  @moduledoc """
  Represents an ExoModule metadata
  """

  @enforce_keys [:id, :name, :version, :type, :entry_point]

  defstruct id: "",
              name: "",
              version: nil,
              type: :elixir,
              physical_path: "", # automatically set by the loader.
              entry_point: nil

  @typedoc "The parsed representation of a plugin's manifest.exs"
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: Version.t(),
          type: :elixir | :wasm | atom(),
          physical_path: String.t(),
          entry_point: module() | String.t()
        }
  end
