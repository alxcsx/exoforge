using System;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Client.Tests;

public class ProtocolAndDispatcherTests
{
    [Fact]
    public void CanSerializeActionRequest()
    {
        var request = new ExoActionRequest
        {
            Id = "req_1",
            Service = "combat",
            Action = "attack",
            Payload = new { attacker_id = 1, target_id = 2, damage = 25 }
        };

        string json = JsonSerializer.Serialize(request);

        Assert.Contains("\"type\":\"action\"", json);
        Assert.Contains("\"id\":\"req_1\"", json);
        Assert.Contains("\"service\":\"combat\"", json);
        Assert.Contains("\"action\":\"attack\"", json);
        Assert.Contains("\"damage\":25", json);
    }

    [Fact]
    public void CanDeserializeActionResult()
    {
        string json = "{\"type\":\"action_result\",\"id\":\"req_1\",\"status\":\"ok\",\"data\":42}";
        var result = JsonSerializer.Deserialize<ExoActionResult>(json);

        Assert.NotNull(result);
        Assert.Equal("action_result", result.Type);
        Assert.Equal("req_1", result.Id);
        Assert.Equal("ok", result.Status);
        Assert.True(result.IsSuccess);
        Assert.Equal(42, result.Data.GetInt32());
    }

    [Fact]
    public void CanDeserializeEventFrame()
    {
        string json = "{\"type\":\"event\",\"event\":\"player_damaged\",\"topic\":\"combat:events\",\"payload\":{\"target_id\":2,\"damage\":25}}";
        var frame = JsonSerializer.Deserialize<ExoEventFrame>(json);

        Assert.NotNull(frame);
        Assert.Equal("event", frame.Type);
        Assert.Equal("player_damaged", frame.Event);
        Assert.Equal("combat:events", frame.Topic);

        var payload = frame.DeserializePayload<DamageEventPayload>();
        Assert.NotNull(payload);
        Assert.Equal(2, payload.target_id);
        Assert.Equal(25, payload.damage);
    }

    [Fact]
    public void DispatcherQueuesAndExecutesOnCallingThread()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        int counter = 0;

        // Post from multiple background threads
        Parallel.For(0, 10, _ =>
        {
            dispatcher.Post(() => Interlocked.Increment(ref counter));
        });

        // Before update: queue is not empty, counter has not been updated
        Assert.Equal(10, dispatcher.PendingCount);
        Assert.Equal(0, counter);

        // Update drains all items
        dispatcher.Update();

        Assert.Equal(0, dispatcher.PendingCount);
        Assert.Equal(10, counter);
    }

    private class DamageEventPayload
    {
        public int target_id { get; set; }
        public int damage { get; set; }
    }
}
