using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Client.Tests;

/// <summary>
/// Transport behaviour, driven against <see cref="StubWebSocketServer"/>.
///
/// These live here rather than in <see cref="VerticalSliceIntegrationTests"/> because that suite
/// needs a live cluster and skips when one is not running — which means it never runs in CI. The
/// transport is Unity-free, so everything about connecting, timing out and failing belongs here.
/// </summary>
public class TransportTests
{
    [Fact]
    public async Task Connects_sends_an_action_and_reads_the_result()
    {
        await using var server = StubWebSocketServer.Start();
        using var client = NewClient();

        await client.ConnectAsync(server.Uri);
        Assert.True(client.IsConnected);

        var call = client.SendActionAsync<JsonElement>("demo", "ping", new { value = 1 });

        string frame = await server.NextReceivedAsync(TimeSpan.FromSeconds(5));
        Assert.Contains("\"type\":\"action\"", frame);
        Assert.Contains("\"service\":\"demo\"", frame);
        Assert.Contains("\"action\":\"ping\"", frame);

        await server.SendActionResultAsync(RequestId(frame), "{\"pong\":true}");

        JsonElement result = await PumpAsync(call, client, TimeSpan.FromSeconds(5));
        Assert.True(result.GetProperty("pong").GetBoolean());
    }

    [Fact]
    public async Task Surfaces_a_server_error_as_an_exception()
    {
        await using var server = StubWebSocketServer.Start();
        using var client = NewClient();

        await client.ConnectAsync(server.Uri);

        var call = client.SendActionAsync<JsonElement>("demo", "explode", new { });
        string frame = await server.NextReceivedAsync(TimeSpan.FromSeconds(5));

        await server.SendAsync(
            "{\"type\":\"action_result\",\"id\":\"" + RequestId(frame) +
            "\",\"status\":\"error\",\"error\":{\"code\":\"boom\",\"message\":\"it broke\"}}");

        var failure = await Assert.ThrowsAsync<ExoActionException>(
            () => PumpAsync(call, client, TimeSpan.FromSeconds(5)));

        Assert.Equal("boom", failure.Code);
        Assert.Equal("[boom] it broke", failure.Message);
    }

    [Fact]
    public async Task Drops_the_connection_when_the_server_aborts_it()
    {
        await using var server = StubWebSocketServer.Start();
        using var client = NewClient();

        bool disconnected = false;
        client.OnDisconnected += _ => disconnected = true;

        await client.ConnectAsync(server.Uri);
        Assert.True(client.IsConnected);

        server.DropConnection();

        // OnDisconnected is posted through the dispatcher, so it needs the same pump as a result.
        await PumpUntil(() => disconnected, client, TimeSpan.FromSeconds(5));

        Assert.True(disconnected,
            $"the client never noticed the drop: IsConnected={client.IsConnected}, " +
            $"pendingCallbacks={client.Dispatcher.PendingCount}, serverConnections={server.ConnectionCount}");
    }

    [Fact]
    public async Task Reconnecting_leaves_exactly_one_receive_loop()
    {
        await using var server = StubWebSocketServer.Start();
        using var client = NewClient();

        int disconnects = 0;
        client.OnDisconnected += _ => Interlocked.Increment(ref disconnects);

        await client.ConnectAsync(server.Uri);
        server.DropConnection();
        await PumpUntil(() => !client.IsConnected, client, TimeSpan.FromSeconds(5));

        await client.ConnectAsync(server.Uri);
        Assert.Equal(2, server.ConnectionCount);

        var seen = new List<string>();
        client.OnEvent("ping", frame => seen.Add(frame.Event));

        // Every frame must arrive, exactly once. A leftover receive loop reading the same socket
        // would split them between two readers, so some would never surface.
        for (int i = 0; i < 5; i++)
        {
            await server.SendAsync("{\"type\":\"event\",\"event\":\"ping\",\"topic\":\"t\",\"payload\":{}}");
        }

        await PumpUntil(() => seen.Count == 5, client, TimeSpan.FromSeconds(5));
        Assert.Equal(5, seen.Count);

        // One drop, one notification. A duplicate is indistinguishable from the new connection
        // failing, which is what a reconnect handler must not be told.
        Assert.Equal(1, disconnects);
    }

    [Fact]
    public async Task A_clean_disconnect_notifies_exactly_once()
    {
        await using var server = StubWebSocketServer.Start();
        using var client = NewClient();

        int disconnects = 0;
        client.OnDisconnected += _ => Interlocked.Increment(ref disconnects);

        await client.ConnectAsync(server.Uri);
        await client.DisconnectAsync();

        await PumpUntil(() => disconnects > 0, client, TimeSpan.FromSeconds(5));
        await Task.Delay(100); // give a second notification time to arrive

        // Both the receive loop and the teardown path can reach the notification. A duplicate is
        // indistinguishable from the next connection failing, which a reconnect handler must not see.
        Assert.Equal(1, disconnects);
        Assert.False(client.IsConnected);
    }

    // ---- helpers -----------------------------------------------------------------------

    private static ExoClient NewClient() => new(new ExoDispatcher(useSynchronizationContext: false));

    private static string RequestId(string frame)
    {
        using var doc = JsonDocument.Parse(frame);
        return doc.RootElement.GetProperty("id").GetString()!;
    }

    /// <summary>
    /// Drives the dispatcher until <paramref name="task"/> finishes, the way
    /// <c>ExoforgeBehaviour.Update()</c> does in Unity. Without a pump the callbacks never run.
    /// </summary>
    private static async Task<T> PumpAsync<T>(Task<T> task, ExoClient client, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;

        while (!task.IsCompleted && DateTime.UtcNow < deadline)
        {
            client.Dispatcher.Update();
            await Task.Delay(5);
        }

        client.Dispatcher.Update();
        return await task;
    }

    /// <summary>Drives the dispatcher until <paramref name="condition"/> holds or time runs out.</summary>
    private static async Task PumpUntil(Func<bool> condition, ExoClient client, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;

        while (!condition() && DateTime.UtcNow < deadline)
        {
            client.Dispatcher.Update();
            await Task.Delay(5);
        }

        client.Dispatcher.Update();
    }
}
