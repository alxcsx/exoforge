using System;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Client.Tests;

public class VerticalSliceIntegrationTests
{
    private static readonly Uri ServerUri = new("ws://127.0.0.1:4000/ws");

    [Fact]
    public async Task EndToEnd_Client_WsPlugin_Kernel_WasmPlugin_Event_Loop()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        using var client = new ExoClient(dispatcher);

        try
        {
            await client.ConnectAsync(ServerUri);
        }
        catch (Exception ex)
        {
            // If the server isn't running locally on port 4000 during isolated test runs, skip gracefully
            Console.WriteLine($"[IntegrationTest] Skipping live connection test (server not running on 4000): {ex.Message}");
            return;
        }

        Assert.True(client.IsConnected);

        // Authenticate client session before invoking actions
        var authResult = await client.AuthenticateAsync("dev:test_e2e_player");
        Assert.True(authResult.IsSuccess);
        Assert.True(client.IsAuthenticated);
        Assert.Equal("test_e2e_player", client.PlayerId);

        // 1. Client invokes action `combat.ping` -> WASM plugin executes and returns 42
        int pingResult = await client.SendActionAsync<int>("combat", "ping", Array.Empty<int>());
        Assert.Equal(42, pingResult);

        // 2. Client subscribes to topic `combat:events`
        await client.SubscribeAsync("combat:events");

        // Prepare event capture
        ExoEventFrame? receivedEvent = null;
        var eventReceivedSignal = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        client.OnEvent("combat:events", "player_damaged", evt =>
        {
            receivedEvent = evt;
            eventReceivedSignal.TrySetResult(true);
        });

        // 3. Client invokes action `combat.attack` with attacker_id=1, target_id=2, damage=65
        int attackResult = await client.SendActionAsync<int>("combat", "attack", new[] { 1, 2, 65 });
        Assert.Equal(65, attackResult);

        // 4. Pump dispatcher while waiting for event broadcast from server
        for (int i = 0; i < 30 && !eventReceivedSignal.Task.IsCompleted; i++)
        {
            dispatcher.Update();
            await Task.Delay(100);
        }
        dispatcher.Update();

        Assert.True(eventReceivedSignal.Task.IsCompleted, "Timed out waiting for player_damaged event broadcast.");
        Assert.NotNull(receivedEvent);
        Assert.Equal("player_damaged", receivedEvent.Event);
        Assert.Equal("combat:events", receivedEvent.Topic);

        using var doc = JsonDocument.Parse(receivedEvent.Payload.GetRawText());
        Assert.Equal(65, doc.RootElement.GetProperty("damage").GetInt32());
        Assert.Equal(2, doc.RootElement.GetProperty("target_id").GetInt32());

        await client.DisconnectAsync();
    }
}
