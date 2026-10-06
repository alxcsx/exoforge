using System.IO;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("frame_loop", Version = "1.0.0")]
public class FrameLoopPlugin
{
    public int Dispatched { get; private set; }

    public string? HostResult { get; private set; }

    [ExoAction("count", Mode = ActionMode.Sync)]
    public int Count()
    {
        Dispatched++;
        return Dispatched;
    }

    [ExoAction("with_host_call", Mode = ActionMode.Sync)]
    public string WithHostCall()
    {
        Dispatched++;
        HostResult = HostBridge.DbGet("t", "k");
        return HostResult ?? "null";
    }
}

/// <summary>
/// The frame loop reads stdin through one reader for the whole process.
///
/// It used to open a second one per host call. Two readers over one stdin each buffer ahead, so a
/// host call could not see a reply the loop had already buffered, and everything the host call's
/// reader buffered past its own line was discarded when it was disposed — the next action frame.
/// </summary>
public class FrameLoopTests
{
    [Fact]
    public void A_host_call_sees_its_reply_and_the_next_frame_still_runs()
    {
        var plugin = new FrameLoopPlugin();

        // Back to back, the way they arrive when the host writes more than one frame in one go.
        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"with_host_call\",\"payload\":{}}",
            "{\"type\":\"host_call_result\",\"id\":1,\"result\":{\"v\":1}}",
            "{\"type\":\"action\",\"id\":2,\"action\":\"count\",\"payload\":{}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input);

        Assert.Equal("{\"v\":1}", plugin.HostResult);
        Assert.Equal(2, plugin.Dispatched);
    }
}
