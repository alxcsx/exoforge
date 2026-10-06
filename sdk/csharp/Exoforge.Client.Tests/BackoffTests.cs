using System;
using Exoforge.Client;
using Xunit;

namespace Exoforge.Client.Tests;

/// <summary>
/// The reconnect delay schedule. Unity-free, so it is tested here rather than in play mode — the
/// doubling and the cap are the only part of reconnecting with branches.
/// </summary>
public class BackoffTests
{
    [Fact]
    public void Doubles_from_the_base()
    {
        Assert.Equal(TimeSpan.FromSeconds(1), ExoBackoff.Delay(0, 1, 30));
        Assert.Equal(TimeSpan.FromSeconds(2), ExoBackoff.Delay(1, 1, 30));
        Assert.Equal(TimeSpan.FromSeconds(4), ExoBackoff.Delay(2, 1, 30));
        Assert.Equal(TimeSpan.FromSeconds(8), ExoBackoff.Delay(3, 1, 30));
    }

    [Fact]
    public void Never_exceeds_the_ceiling()
    {
        Assert.Equal(TimeSpan.FromSeconds(30), ExoBackoff.Delay(5, 1, 30));
        Assert.Equal(TimeSpan.FromSeconds(30), ExoBackoff.Delay(100, 1, 30));

        // A large attempt would overflow Math.Pow to infinity; the result must still be the cap.
        Assert.Equal(TimeSpan.FromSeconds(30), ExoBackoff.Delay(int.MaxValue, 1, 30));
    }

    [Fact]
    public void Tolerates_nonsense_input()
    {
        Assert.Equal(TimeSpan.FromSeconds(1), ExoBackoff.Delay(-5, 1, 30));

        // A ceiling below the base would otherwise make every delay the ceiling.
        Assert.Equal(TimeSpan.FromSeconds(5), ExoBackoff.Delay(0, 5, 1));

        // A non-positive base falls back to one second rather than producing a zero delay, which
        // would turn a retry loop into a spin.
        Assert.Equal(TimeSpan.FromSeconds(1), ExoBackoff.Delay(0, 0, 30));
        Assert.Equal(TimeSpan.FromSeconds(1), ExoBackoff.Delay(0, -3, 30));
    }
}
