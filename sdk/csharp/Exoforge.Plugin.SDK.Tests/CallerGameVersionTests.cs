using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class CallerGameVersionTests
{
    [Fact]
    public void The_game_version_comes_with_the_caller_and_does_not_outlive_the_call()
    {
        var context = new HostPluginContext("versioned");

        context.UpdateCaller("player-1", new[] { "player" }, "1.4.0");
        Assert.Equal("1.4.0", context.CallerGameVersion);
        Assert.Equal("player-1", context.CallerPlayerId);

        // The next call carries none: nothing of the last caller's version may linger.
        context.UpdateCaller(null, null);
        Assert.Null(context.CallerGameVersion);
    }
}
