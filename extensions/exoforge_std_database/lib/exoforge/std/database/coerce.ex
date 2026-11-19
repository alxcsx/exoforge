defmodule Exoforge.Std.Database.Coerce do
  @moduledoc """
  Turns the JSON-ish values a caller sends into the terms a column of a given logical type accepts.

  The types are the engine-neutral ones `lldb.introspect` reports (`int32`, `decimal`, `bool`,
  `timestamp`, `json`, ...), so this knows nothing about any engine's catalog. A value that cannot be
  coerced is `{:error, {:invalid_value, column, type}}`.
  """

  @doc "Coerces `{column, value}` pairs against `types` (`column => %{type:, tz:}`), stopping at the first failure."
  def pairs(pairs, types) do
    Enum.reduce_while(pairs, {:ok, []}, fn {col, val}, {:ok, acc} ->
      case value(col, Map.get(types, col), val) do
        {:ok, coerced} -> {:cont, {:ok, [{col, coerced} | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  def value(_col, _column, nil), do: {:ok, nil}

  def value(col, %{type: type}, val) when type in ["int16", "int32", "int64"] do
    cond do
      is_integer(val) ->
        {:ok, val}

      is_float(val) and trunc(val) == val ->
        {:ok, trunc(val)}

      is_binary(val) ->
        case Integer.parse(String.trim(val)) do
          {n, ""} -> {:ok, n}
          _ -> {:error, {:invalid_value, col, type}}
        end

      true ->
        {:error, {:invalid_value, col, type}}
    end
  end

  def value(col, %{type: type}, val) when type in ["decimal", "float32", "float64"] do
    cond do
      is_number(val) ->
        {:ok, val}

      is_binary(val) ->
        case Float.parse(String.trim(val)) do
          {n, ""} -> {:ok, n}
          _ -> {:error, {:invalid_value, col, type}}
        end

      true ->
        {:error, {:invalid_value, col, type}}
    end
  end

  def value(col, %{type: "bool"}, val) do
    cond do
      is_boolean(val) ->
        {:ok, val}

      val in [1, "1", "true", "t", "TRUE", "True"] ->
        {:ok, true}

      val in [0, "0", "false", "f", "FALSE", "False"] ->
        {:ok, false}

      is_binary(val) ->
        case String.downcase(String.trim(val)) do
          s when s in ["true", "t", "1"] -> {:ok, true}
          s when s in ["false", "f", "0"] -> {:ok, false}
          _ -> {:error, {:invalid_value, col, "bool"}}
        end

      true ->
        {:error, {:invalid_value, col, "bool"}}
    end
  end

  # A timestamp without a time zone.
  def value(col, %{type: "timestamp", tz: false}, val) do
    case val do
      %NaiveDateTime{} ->
        {:ok, val}

      %DateTime{} ->
        {:ok, DateTime.to_naive(val)}

      s when is_binary(s) ->
        case NaiveDateTime.from_iso8601(s) do
          {:ok, ndt} ->
            {:ok, ndt}

          {:error, _} ->
            case DateTime.from_iso8601(s) do
              {:ok, dt, _} -> {:ok, DateTime.to_naive(dt)}
              {:error, _} -> {:error, {:invalid_value, col, "timestamp"}}
            end
        end

      _ ->
        {:error, {:invalid_value, col, "timestamp"}}
    end
  end

  # A timestamp with a time zone.
  def value(col, %{type: "timestamp"}, val) do
    case val do
      %DateTime{} ->
        {:ok, val}

      %NaiveDateTime{} ->
        {:ok, DateTime.from_naive!(val, "Etc/UTC")}

      s when is_binary(s) ->
        case DateTime.from_iso8601(s) do
          {:ok, dt, _} ->
            {:ok, dt}

          {:error, _} ->
            case NaiveDateTime.from_iso8601(s) do
              {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
              {:error, _} -> {:error, {:invalid_value, col, "timestamp"}}
            end
        end

      _ ->
        {:error, {:invalid_value, col, "timestamp"}}
    end
  end

  def value(col, %{type: "json"}, val) do
    cond do
      is_binary(val) -> {:ok, val}
      is_map(val) or is_list(val) -> {:ok, Jason.encode!(val)}
      true -> {:error, {:invalid_value, col, "json"}}
    end
  end

  def value(_col, _column, val), do: {:ok, val}

  @doc "A row read from a typed table, in the shapes JSON carries: ISO-8601 timestamps and plain numbers."
  def row(row) when is_map(row), do: Map.new(row, fn {col, val} -> {col, out(val)} end)

  defp out(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp out(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp out(%Decimal{} = dec), do: Decimal.to_float(dec)
  defp out(val), do: val
end
