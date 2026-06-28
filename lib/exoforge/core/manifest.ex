defmodule Exoforge.Core.Manifest do
  @moduledoc """
  Represents an ExoModule metadata
  """

  defstruct id: "",
            version: "",
            dependencies: %{},
            entry_point: "",
            static_dir: ""
end
