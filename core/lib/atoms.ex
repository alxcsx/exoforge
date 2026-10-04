defmodule Exoforge.Atoms do
  @moduledoc """
  Safe atom conversion for values that may originate from manifests, URLs, or sockets.

  Never creates atoms — returns an existing atom, or the caller's fallback. Use this instead
  of `String.to_atom/1` anywhere the input is not already known to be a bounded set.
  """

  @doc """
  Returns the existing atom for `value`, or `fallback` (default `nil`) when it does not exist.

      iex> Exoforge.Atoms.existing(:player)
      :player
      iex> Exoforge.Atoms.existing("player")
      :player
      iex> Exoforge.Atoms.existing("nope_not_an_atom", "nope_not_an_atom")
      "nope_not_an_atom"
  """
  def existing(value, fallback \\ nil)

  def existing(value, _fallback) when is_atom(value), do: value

  def existing(value, fallback) do
    String.to_existing_atom(to_string(value))
  rescue
    ArgumentError -> fallback
  end
end
