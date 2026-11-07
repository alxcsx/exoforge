defmodule Exoforge.Std.Cron.Parser do
  @moduledoc """
  Lightweight standard 5-field cron expression evaluator.
  Supports wildcards (*), steps (*/N), ranges (A-B), discrete lists (A,B,C), and standard aliases.
  Evaluates in UTC against a given `DateTime`.
  """

  @aliases %{
    "@yearly" => "0 0 1 1 *",
    "@annually" => "0 0 1 1 *",
    "@monthly" => "0 0 1 * *",
    "@weekly" => "0 0 * * 0",
    "@daily" => "0 0 * * *",
    "@midnight" => "0 0 * * *",
    "@hourly" => "0 * * * *"
  }

  @doc """
  Returns true if the given cron expression matches the specified UTC DateTime.
  """
  @spec matches?(binary(), DateTime.t()) :: boolean()
  def matches?(expression, %DateTime{} = dt) when is_binary(expression) do
    expr = Map.get(@aliases, String.trim(expression), String.trim(expression))

    case String.split(expr, ~r/\s+/, trim: true) do
      [min_expr, hour_expr, dom_expr, mon_expr, dow_expr] ->
        field_matches?(min_expr, dt.minute, 0..59) and
          field_matches?(hour_expr, dt.hour, 0..23) and
          field_matches?(dom_expr, dt.day, 1..31) and
          field_matches?(mon_expr, dt.month, 1..12) and
          dow_matches?(dow_expr, dt)

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  defp dow_matches?(expr, %DateTime{} = dt) do
    # Calendar day of week: 1 (Monday) .. 7 (Sunday)
    # Cron standard dow: 0 (Sunday) .. 6 (Saturday) or 7 (Sunday)
    day_of_week = Date.day_of_week(DateTime.to_date(dt))
    cron_dow = if day_of_week == 7, do: 0, else: day_of_week

    field_matches?(expr, cron_dow, 0..7) or (cron_dow == 0 and field_matches?(expr, 7, 0..7))
  end

  defp field_matches?("*", _val, _range), do: true

  defp field_matches?("*/" <> step_str, val, range) do
    case Integer.parse(step_str) do
      {step, ""} when step > 0 ->
        min = range.first
        rem(val - min, step) == 0

      _ ->
        false
    end
  end

  defp field_matches?(expr, val, range) do
    parts = String.split(expr, ",", trim: true)

    Enum.any?(parts, fn part ->
      cond do
        String.contains?(part, "-") ->
          case String.split(part, "-", trim: true) do
            [from_str, to_str] ->
              with {from, ""} <- Integer.parse(from_str),
                   {to, ""} <- Integer.parse(to_str) do
                val in from..to and val in range
              else
                _ -> false
              end

            _ ->
              false
          end

        true ->
          case Integer.parse(part) do
            {target, ""} -> val == target and val in range
            _ -> false
          end
      end
    end)
  end
end
