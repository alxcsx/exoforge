defmodule Exoforge.VersionStamp do
  @moduledoc "Encodes extension versions for row and schema stamps."

  def encode(version) when is_binary(version) do
    # "1.4.0-beta.1" and "1.4.0+build5" are the 1.4.0 release for ordering purposes (the SDK does the same).
    [release | _] = String.split(version, ["-", "+"], parts: 2)

    case String.split(release, ".") do
      [major, minor, patch] ->
        with {major, ""} <- Integer.parse(major),
             {minor, ""} <- Integer.parse(minor),
             {patch, ""} <- Integer.parse(patch),
             true <- major >= 0 and minor in 0..999 and patch in 0..999 do
          major * 1_000_000 + minor * 1_000 + patch
        else
          _ -> 0
        end

      _ -> 0
    end
  end

  def encode(%Version{} = version), do: encode(to_string(version))
  def encode(_), do: 0

  @doc "The version a stamp stands for: `2001000` is `\"2.1.0\"`. A stamp of 0 has no version."
  def decode(stamp) when is_integer(stamp) and stamp > 0 do
    "#{div(stamp, 1_000_000)}.#{stamp |> div(1_000) |> rem(1_000)}.#{rem(stamp, 1_000)}"
  end

  def decode(_), do: nil
end
