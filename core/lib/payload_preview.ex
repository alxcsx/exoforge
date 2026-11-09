defmodule Exoforge.PayloadPreview do
  @moduledoc """
  A bounded, credential-masked preview of an action payload or result.

  Both the action trace and the error groups show what was sent and what came back, and neither
  may keep the payload itself: previews are capped in size and depth, and fields whose names look
  like credentials are replaced. Nothing here is ever written to disk.
  """

  @preview_bytes 512
  @preview_items 20
  @mask "•••"
  @sensitive ~w(password password_hash token secret authorization api_key)

  def preview(value), do: preview(value, 0)

  defp preview(_value, depth) when depth > 3, do: "…"

  defp preview(value, _depth) when is_binary(value) do
    if byte_size(value) > @preview_bytes do
      binary_part(value, 0, @preview_bytes) <> "… (#{byte_size(value)} bytes)"
    else
      value
    end
  end

  defp preview(%{__struct__: _} = value, depth), do: value |> Map.from_struct() |> preview(depth)

  defp preview(value, depth) when is_map(value) do
    value
    |> Enum.take(@preview_items)
    |> Map.new(fn {k, v} ->
      if sensitive?(k), do: {k, @mask}, else: {k, preview(v, depth + 1)}
    end)
  end

  defp preview(value, depth) when is_list(value) do
    Enum.map(Enum.take(value, @preview_items), &preview(&1, depth + 1))
  end

  defp preview(value, _depth) when is_tuple(value), do: value |> inspect() |> truncate()

  defp preview(value, _depth) when is_atom(value) or is_number(value) or is_nil(value), do: value

  defp preview(value, _depth), do: value |> inspect() |> truncate()

  defp truncate(string) do
    if byte_size(string) > @preview_bytes, do: binary_part(string, 0, @preview_bytes) <> "…", else: string
  end

  defp sensitive?(key) do
    down = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive, &String.contains?(down, &1))
  end
end
