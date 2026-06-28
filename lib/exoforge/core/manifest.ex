defmodule Exoforge.Core.Manifest do
  @moduledoc """
  Represents a module metadata
  """

  defstruct id: "",
            version: "",
            dependencies: %{},
            entry_point: "",
            static_dir: ""
end
