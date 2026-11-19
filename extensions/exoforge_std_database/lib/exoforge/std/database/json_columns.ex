defmodule Exoforge.Std.Database.JsonColumns do
  @moduledoc """
  Maps and lists in a declared resource's `:map`, `:list` and `:term` columns.

  Those columns are text (`resource_store` creates them that way on every adapter), so a list handed
  to a driver is a type error - "expected a binary, got []". The key-value path encodes them to JSON
  on `put` and decodes them on `get`/`all`, so a C# `List<string>` round-trips whatever the adapter.
  Tables that are not declared resources are untouched.
  """

  @json_types ["map", "list", "term"]

  def encode(%{action: :put, table: table, data: data} = command) when is_map(data) do
    case json_columns(table) do
      [] -> command
      columns -> %{command | data: Map.new(data, fn {k, v} -> {k, encode_value(to_string(k) in columns, v)} end)}
    end
  end

  def encode(command), do: command

  def decode(%{action: action, table: table}, {:ok, %{rows: rows} = result}) when action in [:get, :all] do
    case json_columns(table) do
      [] -> {:ok, result}
      columns -> {:ok, %{result | rows: Enum.map(rows, &decode_row(&1, columns))}}
    end
  end

  def decode(_command, result), do: result

  defp encode_value(true, value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp encode_value(_json?, value), do: value

  defp decode_row(row, columns) when is_map(row) do
    Enum.reduce(columns, row, fn column, acc ->
      case acc do
        %{^column => text} when is_binary(text) -> Map.put(acc, column, decode_text(text))
        _ -> acc
      end
    end)
  end

  defp decode_row(row, _columns), do: row

  # A text column that is not JSON (a row written before the column was typed) stays as it is.
  defp decode_text(text) do
    case Jason.decode(text) do
      {:ok, value} when is_map(value) or is_list(value) -> value
      _ -> text
    end
  end

  defp json_type?(type), do: type in @json_types or String.starts_with?(type, "[")

  defp json_columns(table) do
    case Exoforge.ExtensionRegistry.fetch_resource(to_string(table)) do
      {:ok, %{resource: res}} ->
        for column <- res[:columns] || res["columns"] || [],
            json_type?(to_string(column[:type] || column["type"])),
            do: to_string(column[:name] || column["name"])

      _ ->
        []
    end
  rescue
    _ -> []
  end
end
