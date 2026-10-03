defmodule Exoforge.Std.Dashboard.ScheduleComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import Exoforge.Std.Dashboard.Components

  test "renders schedule_timeline with active and upcoming events" do
    events = [
      %{
        id: "double_xp",
        title: "Double XP Weekend",
        status: :active,
        countdown_text: "1d 4h",
        progress: 0.6,
        recurrence: :weekly,
        start_at: "2026-10-01T12:00:00Z",
        end_at: "2026-10-05T12:00:00Z",
        metadata: %{"multiplier" => 2.0}
      },
      %{
        id: "boss_raid",
        title: "World Boss Raid",
        status: :upcoming,
        countdown_text: "3d 12h",
        progress: 0.0,
        recurrence: :none,
        start_at: "2026-10-10T20:00:00Z",
        end_at: "2026-10-10T22:00:00Z",
        metadata: %{"level" => 50}
      }
    ]

    html = render_component(&schedule_timeline/1, events: events, title: "Custom LiveOps Events")

    assert html =~ "Custom LiveOps Events"
    assert html =~ "2 Scheduled"
    assert html =~ "Double XP Weekend"
    assert html =~ "ACTIVE NOW"
    assert html =~ "1d 4h"
    assert html =~ "60%"
    assert html =~ "multiplier"
    assert html =~ "World Boss Raid"
    assert html =~ "UPCOMING"
  end

  test "renders schedule_timeline empty state" do
    html = render_component(&schedule_timeline/1, events: [], empty_message: "No live events active.")
    assert html =~ "No live events active."
    assert html =~ "0 Scheduled"
  end

  test "renders calendar_view with day markers" do
    events = [
      %{
        id: "daily_gift",
        title: "Daily Login Reward",
        status: :active,
        start_at: "2026-10-03T00:00:00Z"
      }
    ]

    html = render_component(&calendar_view/1, events: events, title: "Seasonal Schedule")

    assert html =~ "Seasonal Schedule"
    assert html =~ "Mon"
    assert html =~ "Sun"
    assert html =~ "Today"
    assert html =~ "Daily Login Reward"
  end
end
