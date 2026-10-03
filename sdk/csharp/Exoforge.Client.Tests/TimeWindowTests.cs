using System;
using Exoforge.Client.Time;
using Xunit;

namespace Exoforge.Client.Tests;

public class TimeWindowTests
{
    [Fact]
    public void TimeWindow_Active_Evaluation_Works_Correctly()
    {
        var window = new ExoTimeWindow
        {
            Id = "xp_boost",
            Title = "Weekend Boost",
            StartAtUtc = new DateTime(2026, 10, 1, 12, 0, 0, DateTimeKind.Utc),
            EndAtUtc = new DateTime(2026, 10, 5, 12, 0, 0, DateTimeKind.Utc),
            Recurrence = "none"
        };

        var before = new DateTime(2026, 9, 30, 12, 0, 0, DateTimeKind.Utc);
        var during = new DateTime(2026, 10, 3, 12, 0, 0, DateTimeKind.Utc);
        var after = new DateTime(2026, 10, 6, 12, 0, 0, DateTimeKind.Utc);

        Assert.False(window.EvaluateIsActive(before));
        Assert.True(window.EvaluateIsActive(during));
        Assert.False(window.EvaluateIsActive(after));
    }

    [Fact]
    public void TimeWindow_Countdown_Formatting_Produces_Human_Durations()
    {
        Assert.Equal("1d 4h", ExoTimeWindow.FormatCountdown(100800)); // 28 hours
        Assert.Equal("2h 15m", ExoTimeWindow.FormatCountdown(8100));
        Assert.Equal("30s", ExoTimeWindow.FormatCountdown(30));
        Assert.Equal("0s", ExoTimeWindow.FormatCountdown(0));
        Assert.Equal("0s", ExoTimeWindow.FormatCountdown(-10));
    }

    [Fact]
    public void TimeWindow_Daily_Recurrence_Evaluates_TimeOfDay()
    {
        var daily = new ExoTimeWindow
        {
            Id = "daily_raid",
            StartAtUtc = new DateTime(2026, 10, 1, 14, 0, 0, DateTimeKind.Utc),
            EndAtUtc = new DateTime(2026, 10, 1, 18, 0, 0, DateTimeKind.Utc),
            Recurrence = "daily"
        };

        var inside = new DateTime(2026, 10, 5, 15, 30, 0, DateTimeKind.Utc);
        var outside = new DateTime(2026, 10, 5, 19, 0, 0, DateTimeKind.Utc);

        Assert.True(daily.EvaluateIsActive(inside));
        Assert.False(daily.EvaluateIsActive(outside));
    }
}
