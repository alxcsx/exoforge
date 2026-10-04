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
            Service = "sample_wasm",
            Action = "increment",
            Payload = new { counter_id = 1, amount = 25 }
        };

        string json = JsonSerializer.Serialize(request);

        Assert.Contains("\"type\":\"action\"", json);
        Assert.Contains("\"id\":\"req_1\"", json);
        Assert.Contains("\"service\":\"sample_wasm\"", json);
        Assert.Contains("\"action\":\"increment\"", json);
        Assert.Contains("\"amount\":25", json);
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
        string json = "{\"type\":\"event\",\"event\":\"value_changed\",\"topic\":\"sample:events\",\"payload\":{\"counter_id\":2,\"new_value\":25}}";
        var frame = JsonSerializer.Deserialize<ExoEventFrame>(json);

        Assert.NotNull(frame);
        Assert.Equal("event", frame.Type);
        Assert.Equal("value_changed", frame.Event);
        Assert.Equal("sample:events", frame.Topic);

        var payload = frame.DeserializePayload<CounterEventPayload>();
        Assert.NotNull(payload);
        Assert.Equal(2, payload.counter_id);
        Assert.Equal(25, payload.new_value);
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

    [Fact]
    public void CanAccessGeneratedServiceClientsFromExoClient()
    {
        var client = new ExoClient();
        Assert.NotNull(client.SampleWasm());
        Assert.NotNull(client.PlayerData());
        Assert.NotNull(client.Auth());
        Assert.NotNull(client.Http());
        Assert.NotNull(client.Ws());
        Assert.NotNull(client.Database());
        Assert.NotNull(client.PluginManager());

        // Same client yields same cached service instance
        Assert.Same(client.SampleWasm(), client.SampleWasm());
        Assert.Same(client.PlayerData(), client.PlayerData());
        Assert.Same(client.PluginManager(), client.PluginManager());
    }

    [Fact]
    public void CanDeserializeAuthResult()
    {
        string json = "{\"type\":\"auth_result\",\"status\":\"ok\",\"player_id\":\"p_123\",\"scopes\":[\"player\",\"admin\"]}";
        var result = JsonSerializer.Deserialize<ExoAuthResult>(json);

        Assert.NotNull(result);
        Assert.Equal("auth_result", result.Type);
        Assert.Equal("ok", result.Status);
        Assert.True(result.IsSuccess);
        Assert.Equal("p_123", result.PlayerId);
        Assert.Contains("player", result.Scopes!);
        Assert.Contains("admin", result.Scopes!);
    }

    [Fact]
    public void CanSerializeSubscriptionRequestWithWildcardTopic()
    {
        var req = new ExoSubscriptionRequest("subscribe", "*");
        string json = JsonSerializer.Serialize(req);
        Assert.Contains("\"type\":\"subscribe\"", json);
        Assert.Contains("\"topic\":\"*\"", json);
    }

    private class CounterEventPayload
    {
        public int counter_id { get; set; }
        public int new_value { get; set; }
    }
}
