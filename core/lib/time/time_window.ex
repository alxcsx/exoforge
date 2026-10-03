defmodule Exoforge.TimeWindow do
  @moduledoc """
  Core time and scheduling primitive for liveops events, seasonal schedules,
  maintenance windows, and timed game mechanics.

  Provides standardized time-window evaluation, recurrence calculation (daily, weekly),
  countdown calculation, and JSON serialization for studio dashboards and client SDKs.
  """

  @enforce_keys [:start_at, :end_at]
  defstruct [
    :id,
    :title,
    :start_at,
    :end_at,
    recurrence: :none,
    timezone: "Etc/UTC",
    metadata: %{}
  ]

  @type recurrence :: :none | :daily | :weekly | :monthly
  @type t :: %__MODULE__{
          id: String.t() | atom() | nil,
          title: String.t() | nil,
          start_at: DateTime.t(),
          end_at: DateTime.t(),
          recurrence: recurrence(),
          timezone: String.t(),
          metadata: map()
        }

  @doc """
  Creates a new `TimeWindow` from a keyword list or map.
  Accepts `DateTime` structs or ISO8601 string timestamps.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, start_dt} <- parse_datetime(Map.get(attrs, :start_at) || Map.get(attrs, "start_at")),
         {:ok, end_dt} <- parse_datetime(Map.get(attrs, :end_at) || Map.get(attrs, "end_at")),
         :ok <- validate_chronology(start_dt, end_dt) do
      recurrence = parse_recurrence(Map.get(attrs, :recurrence) || Map.get(attrs, "recurrence", :none))
      id = Map.get(attrs, :id) || Map.get(attrs, "id")
      title = Map.get(attrs, :title) || Map.get(attrs, "title")
      timezone = Map.get(attrs, :timezone) || Map.get(attrs, "timezone", "Etc/UTC")
      metadata = Map.get(attrs, :metadata) || Map.get(attrs, "metadata", %{})

      {:ok,
       %__MODULE__{
         id: id,
         title: title,
         start_at: start_dt,
         end_at: end_dt,
         recurrence: recurrence,
         timezone: timezone,
         metadata: metadata
       }}
    end
  end

  @doc """
  Bang variant of `new/1`. Raises on validation error.
  """
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, window} -> window
      {:error, reason} -> raise ArgumentError, "Invalid TimeWindow: #{inspect(reason)}"
    end
  end

  @doc """
  Evaluates if the window is currently active at given `now` (defaults to `DateTime.utc_now()`).
  Takes recurrence into account.
  """
  @spec active?(t(), DateTime.t()) :: boolean()
  def active?(window, now \\ DateTime.utc_now())

  def active?(%__MODULE__{recurrence: :none} = w, now) do
    DateTime.compare(now, w.start_at) in [:gt, :eq] and DateTime.compare(now, w.end_at) == :lt
  end

  def active?(%__MODULE__{recurrence: :daily} = w, now) do
    if DateTime.compare(now, w.start_at) == :lt do
      false
    else
      start_tod = Time.to_seconds_after_midnight(DateTime.to_time(w.start_at)) |> elem(0)
      end_tod = Time.to_seconds_after_midnight(DateTime.to_time(w.end_at)) |> elem(0)
      now_tod = Time.to_seconds_after_midnight(DateTime.to_time(now)) |> elem(0)

      if end_tod >= start_tod do
        now_tod >= start_tod and now_tod < end_tod
      else
        # Overnight window (e.g. 22:00 -> 04:00)
        now_tod >= start_tod or now_tod < end_tod
      end
    end
  end

  def active?(%__MODULE__{recurrence: :weekly} = w, now) do
    if DateTime.compare(now, w.start_at) == :lt do
      false
    else
      start_day = Date.day_of_week(DateTime.to_date(w.start_at))
      end_day = Date.day_of_week(DateTime.to_date(w.end_at))
      now_day = Date.day_of_week(DateTime.to_date(now))

      start_tod = Time.to_seconds_after_midnight(DateTime.to_time(w.start_at)) |> elem(0)
      end_tod = Time.to_seconds_after_midnight(DateTime.to_time(w.end_at)) |> elem(0)
      now_tod = Time.to_seconds_after_midnight(DateTime.to_time(now)) |> elem(0)

      if start_day == end_day do
        now_day == start_day and now_tod >= start_tod and now_tod < end_tod
      else
        # Multi-day span within week
        cond do
          now_day > start_day and now_day < end_day -> true
          now_day == start_day -> now_tod >= start_tod
          now_day == end_day -> now_tod < end_tod
          true -> false
        end
      end
    end
  end

  def active?(%__MODULE__{} = w, now), do: active?(%{w | recurrence: :none}, now)

  @doc """
  Determines status: `:active`, `:upcoming`, or `:expired`.
  """
  @spec status(t(), DateTime.t()) :: :active | :upcoming | :expired
  def status(%__MODULE__{} = w, now \\ DateTime.utc_now()) do
    cond do
      active?(w, now) ->
        :active

      w.recurrence == :none and DateTime.compare(now, w.end_at) in [:gt, :eq] ->
        :expired

      DateTime.compare(now, w.start_at) == :lt ->
        :upcoming

      w.recurrence in [:daily, :weekly] ->
        :upcoming

      true ->
        :expired
    end
  end

  @doc """
  Calculates remaining seconds:
  - If `:active`: seconds until current window ends.
  - If `:upcoming`: seconds until next window starts.
  - If `:expired`: 0.
  """
  @spec remaining_seconds(t(), DateTime.t()) :: non_neg_integer()
  def remaining_seconds(%__MODULE__{} = w, now \\ DateTime.utc_now()) do
    case status(w, now) do
      :active ->
        if w.recurrence == :none do
          max(0, DateTime.diff(w.end_at, now, :second))
        else
          # Recurrent: calculate seconds until today's end_tod
          end_tod = Time.to_seconds_after_midnight(DateTime.to_time(w.end_at)) |> elem(0)
          now_tod = Time.to_seconds_after_midnight(DateTime.to_time(now)) |> elem(0)

          if end_tod >= now_tod do
            end_tod - now_tod
          else
            86_400 - now_tod + end_tod
          end
        end

      :upcoming ->
        if DateTime.compare(now, w.start_at) == :lt do
          max(0, DateTime.diff(w.start_at, now, :second))
        else
          # Next occurrence for recurrent
          start_tod = Time.to_seconds_after_midnight(DateTime.to_time(w.start_at)) |> elem(0)
          now_tod = Time.to_seconds_after_midnight(DateTime.to_time(now)) |> elem(0)

          if start_tod >= now_tod do
            start_tod - now_tod
          else
            86_400 - now_tod + start_tod
          end
        end

      :expired ->
        0
    end
  end

  @doc """
  Calculates progress of an active window as a float between 0.0 and 1.0.
  Returns 0.0 if upcoming, 1.0 if expired.
  """
  @spec progress(t(), DateTime.t()) :: float()
  def progress(%__MODULE__{} = w, now \\ DateTime.utc_now()) do
    case status(w, now) do
      :upcoming ->
        0.0

      :expired ->
        1.0

      :active ->
        total = DateTime.diff(w.end_at, w.start_at, :second)

        if total <= 0 do
          1.0
        else
          remaining = remaining_seconds(w, now)
          elapsed = max(0, total - remaining)
          Float.round(elapsed / total, 4) |> min(1.0) |> max(0.0)
        end
    end
  end

  @doc """
  Formats remaining seconds into a concise, readable duration string (e.g., "3d 4h", "2h 15m", "45s").
  """
  @spec format_countdown(non_neg_integer()) :: String.t()
  def format_countdown(0), do: "0s"

  def format_countdown(seconds) when is_integer(seconds) and seconds > 0 do
    days = div(seconds, 86_400)
    rem_day = rem(seconds, 86_400)
    hours = div(rem_day, 3600)
    rem_hour = rem(rem_day, 3600)
    minutes = div(rem_hour, 60)
    secs = rem(rem_hour, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  @doc """
  Converts a `TimeWindow` to a plain JSON-serializable map.
  """
  @spec to_map(t(), DateTime.t()) :: map()
  def to_map(%__MODULE__{} = w, now \\ DateTime.utc_now()) do
    current_status = status(w, now)
    rem_secs = remaining_seconds(w, now)

    %{
      id: w.id,
      title: w.title,
      start_at: DateTime.to_iso8601(w.start_at),
      end_at: DateTime.to_iso8601(w.end_at),
      recurrence: w.recurrence,
      timezone: w.timezone,
      status: current_status,
      is_active: current_status == :active,
      remaining_seconds: rem_secs,
      countdown_text: format_countdown(rem_secs),
      progress: progress(w, now),
      metadata: w.metadata
    }
  end

  ## Private Helpers

  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}

  defp parse_datetime(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, {:invalid_iso8601, binary}}
    end
  end

  defp parse_datetime(nil), do: {:error, :missing_datetime}
  defp parse_datetime(val), do: {:error, {:unsupported_datetime_format, val}}

  defp validate_chronology(start_dt, end_dt) do
    if DateTime.compare(start_dt, end_dt) in [:lt, :eq] do
      :ok
    else
      {:error, :start_after_end}
    end
  end

  defp parse_recurrence(r) when r in [:none, :daily, :weekly, :monthly], do: r
  defp parse_recurrence("none"), do: :none
  defp parse_recurrence("daily"), do: :daily
  defp parse_recurrence("weekly"), do: :weekly
  defp parse_recurrence("monthly"), do: :monthly
  defp parse_recurrence(_), do: :none
end
