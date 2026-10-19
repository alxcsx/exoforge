defmodule Exoforge.Extension do
  @moduledoc """
  Public DSL for creating Exoforge extensions.
  Standardized primary interface for extensions across Exoforge.
  """

  defmacro __using__(opts) do
    quote location: :keep do
      use Exoforge.Plugin, unquote(opts)
    end
  end
end
