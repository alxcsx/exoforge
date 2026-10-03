defmodule Exoforge.TimeWindowTest do
  use ExUnit.Case, async: true
  alias Exoforge.TimeWindow

  setup do
    {:ok, start_dt, _} = DateTime.from_iso8601("2026-10-01T12:00:00Z")
    {:ok, end_dt, _} = DateTime.from_iso8601("2026-10-05T12:00:00Z")

    window =
      TimeWindow.new!(%{
        id: "double_xp_october",
        title: "Double XP Weekend",
        start_at: start_dt,
        end_at: end_dt,
        metadata: %{multiplier: 2.0}
      })

    %{window: window, start_dt: start_dt, end_dt: end_dt}
  end

  test "correctly evaluates status: upcoming, active, expired", %{window: window} do
    {:ok, before_dt, _} = DateTime.from_iso8601("2026-09-30T10:00:00Z")
    {:ok, during_dt, _} = DateTime.from_iso8601("2026-10-02T12:00:00Z")
    {:ok, after_dt, _} = DateTime.from_iso8601("2026-10-06T10:00:00Z")

    assert TimeWindow.status(window, before_dt) == :upcoming
    refute TimeWindow.active?(window, before_dt)

    assert TimeWindow.status(window, during_dt) == :active
    assert TimeWindow.active?(window, during_dt)

    assert TimeWindow.status(window, after_dt) == :expired
    refute TimeWindow.active?(window, after_dt)
  end

  test "calculates remaining_seconds and countdown formatting", %{window: window} do
    # 24 hours before end (during event)
    {:ok, during_dt, _} = DateTime.from_iso8601("2026-10-04T12:00:00Z")
    rem_secs = TimeWindow.remaining_seconds(window, during_dt)
    assert rem_secs == 86_400
    assert TimeWindow.format_countdown(rem_secs) == "1d 0h"

    # Progress halfway
    assert_in_delta TimeWindow.progress(window, during_dt), 0.75, 0.01

    # Formatting small durations
    assert TimeWindow.format_countdown(3665) == "1h 1m"
    assert TimeWindow.format_countdown(90) == "1m 30s"
    assert TimeWindow.format_countdown(45) == "45s"
    assert TimeWindow.format_countdown(0) == "0s"
  end

  test "serializes to map with all computed fields", %{window: window} do
    {:ok, during_dt, _} = DateTime.from_iso8601("2026-10-03T12:00:00Z")
    map = TimeWindow.to_map(window, during_dt)

    assert map.id == "double_xp_october"
    assert map.title == "Double XP Weekend"
    assert map.is_active == true
    assert map.status == :active
    assert map.metadata.multiplier == 2.0
    assert map.progress > 0.0
    assert is_binary(map.countdown_text)
  end

  test "evaluates daily recurrent window" do
    {:ok, start_dt, _} = DateTime.from_iso8601("2026-10-01T14:00:00Z") # 14:00
    {:ok, end_dt, _} = DateTime.from_iso8601("2026-10-01T18:00:00Z")   # 18:00

    daily =
      TimeWindow.new!(%{
        id: "daily_happy_hour",
        start_at: start_dt,
        end_at: end_dt,
        recurrence: :daily
      })

    # Oct 3 at 15:30 -> Active
    {:ok, active_dt, _} = DateTime.from_iso8601("2026-10-03T15:30:00Z")
    assert TimeWindow.active?(daily, active_dt)

    # Oct 3 at 19:00 -> Upcoming (for next day)
    {:ok, inactive_dt, _} = DateTime.from_iso8601("2026-10-03T19:00:00Z")
    refute TimeWindow.active?(daily, inactive_dt)
  end

  test "rejects invalid dates" do
    assert {:error, :start_after_end} =
             TimeWindow.new(%{
               start_at: "2026-10-05T00:00:00Z",
               end_at: "2026-10-01T00:00:00Z"
             })

    assert {:error, {:invalid_iso8601, _}} =
             TimeWindow.new(%{
               start_at: "not-a-date",
               end_at: "2026-10-01T00:00:00Z"
             })
  end
end
