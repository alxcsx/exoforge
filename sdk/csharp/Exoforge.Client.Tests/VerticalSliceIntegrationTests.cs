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

        // 1. Client invokes action `sample_wasm.ping` -> WASM plugin executes and returns 42
        int pingResult = await client.SendActionAsync<int>("sample_wasm", "ping", Array.Empty<int>());
        Assert.Equal(42, pingResult);

        // 2. Client subscribes to topic `sample:events`
        await client.SubscribeAsync("sample:events");

        // Prepare event capture
        ExoEventFrame? receivedEvent = null;
        var eventReceivedSignal = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        client.OnEvent("sample:events", "value_changed", evt =>
        {
            receivedEvent = evt;
            eventReceivedSignal.TrySetResult(true);
        });

        // 3. Client invokes action `sample_wasm.increment` with counter_id=7, amount=65
        int incrementResult = await client.SendActionAsync<int>("sample_wasm", "increment", new[] { 7, 65 });
        Assert.Equal(65, incrementResult);

        // 4. Pump dispatcher while waiting for event broadcast from server
        for (int i = 0; i < 30 && !eventReceivedSignal.Task.IsCompleted; i++)
        {
            dispatcher.Update();
            await Task.Delay(100);
        }
        dispatcher.Update();

        Assert.True(eventReceivedSignal.Task.IsCompleted, "Timed out waiting for value_changed event broadcast.");
        Assert.NotNull(receivedEvent);
        Assert.Equal("value_changed", receivedEvent.Event);
        Assert.Equal("sample:events", receivedEvent.Topic);

        using var doc = JsonDocument.Parse(receivedEvent.Payload.GetRawText());
        Assert.Equal(65, doc.RootElement.GetProperty("new_value").GetInt32());
        Assert.Equal(7, doc.RootElement.GetProperty("counter_id").GetInt32());

        await client.DisconnectAsync();
    }

    [Fact]
    public async Task EndToEnd_Client_Wildcard_Subscription_Receives_Events()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        using var client = new ExoClient(dispatcher);

        try
        {
            await client.ConnectAsync(ServerUri);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[IntegrationTest] Skipping live connection test: {ex.Message}");
            return;
        }

        await client.AuthenticateAsync("dev:wildcard_tester");

        // Subscribe to wildcard
        await client.SubscribeAsync("*");

        ExoEventFrame? receivedWildcardEvent = null;
        var signal = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        client.OnAnyEvent += evt =>
        {
            receivedWildcardEvent = evt;
            signal.TrySetResult(true);
        };

        // Trigger action that emits value_changed
        await client.SendActionAsync<int>("sample_wasm", "increment", new[] { 10, 80 });

        for (int i = 0; i < 30 && !signal.Task.IsCompleted; i++)
        {
            dispatcher.Update();
            await Task.Delay(100);
        }
        dispatcher.Update();

        Assert.True(signal.Task.IsCompleted, "Timed out waiting for wildcard event broadcast.");
        Assert.NotNull(receivedWildcardEvent);
        Assert.Equal("value_changed", receivedWildcardEvent.Event);

        await client.DisconnectAsync();
    }

    [Fact]
    public async Task Guest_Can_Login_And_Reauthenticate_With_Issued_Token()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        using var client = new ExoClient(dispatcher);

        try
        {
            await client.ConnectAsync(ServerUri);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[IntegrationTest] Skipping live login test (server not running on 4000): {ex.Message}");
            return;
        }

        // Bootstrap as guest: `auth.login` requires an authenticated socket.
        var guest = await client.AuthenticateAsync("guest");
        Assert.True(guest.IsSuccess);

        string email = Environment.GetEnvironmentVariable("EXOFORGE_ADMIN_EMAIL") ?? "admin@exoforge.local";
        string password = Environment.GetEnvironmentVariable("EXOFORGE_ADMIN_PASSWORD") ?? "exoforge";

        var login = await client.Auth().LoginAsync(email, password);
        Assert.False(string.IsNullOrEmpty(login.Token), "login response has no token");
        string token = login.Token;

        // The issued token must authenticate on its own.
        var reauth = await client.AuthenticateAsync(token);
        Assert.True(reauth.IsSuccess);

        await client.DisconnectAsync();
    }

    [Fact]
    public async Task PluginManager_ListPlugins_And_SystemInfo()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        using var client = new ExoClient(dispatcher);

        try
        {
            await client.ConnectAsync(ServerUri);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[IntegrationTest] Skipping live plugin-manager test (server not running on 4000): {ex.Message}");
            return;
        }

        var auth = await client.AuthenticateAsync("dev:developer");
        Assert.True(auth.IsSuccess);

        int ping = await client.SendActionAsync<int>("sample_wasm", "ping", Array.Empty<int>());
        Assert.Equal(42, ping);

        var plugins = await client.SendActionAsync<JsonElement>("plugin_manager", "list_plugins", null);
        Assert.Equal(JsonValueKind.Object, plugins.ValueKind);
        Assert.True(plugins.TryGetProperty("plugins", out var arr));
        Assert.Equal(JsonValueKind.Array, arr.ValueKind);

        var sysInfo = await client.SendActionAsync<JsonElement>("plugin_manager", "get_system_info", null);
        Assert.Equal(JsonValueKind.Object, sysInfo.ValueKind);
        Assert.True(sysInfo.TryGetProperty("system", out var sys));

        await client.DisconnectAsync();
    }

    [Fact]
    public async Task Two_Stage_Sign_In_Names_A_Fresh_Account()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        using var client = new ExoClient(dispatcher);

        try
        {
            await client.ConnectAsync(ServerUri);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[IntegrationTest] Skipping live two-stage test (server not running): {ex.Message}");
            return;
        }

        string device = "dev_two_stage_" + Guid.NewGuid().ToString("N")[..8];

        // Stage 1 - enter or register the account, no name.
        var anonymous = await client.SendActionAsync<JsonElement>("auth", "anonymous", new { player_id = device });
        Assert.Equal(device, anonymous.GetProperty("player_id").GetString());
        Assert.Equal("", anonymous.GetProperty("name").GetString());

        string token = anonymous.GetProperty("token").GetString()!;
        var auth = await client.AuthenticateAsync(token);
        Assert.True(auth.IsSuccess, $"the issued token did not authenticate: {auth.Error}");
        Assert.Equal(device, auth.PlayerId);

        // Stage 2 - name the signed-in player. The server takes the player from the caller.
        var named = await client.SendActionAsync<JsonElement>("auth", "set_display_name", new { name = "TwoStage" });
        Assert.Equal("TwoStage", named.GetProperty("name").GetString());

        // Re-entering the device now returns the name.
        var again = await client.SendActionAsync<JsonElement>("auth", "anonymous", new { player_id = device });
        Assert.Equal("TwoStage", again.GetProperty("name").GetString());

        await client.DisconnectAsync();
    }

    [Fact]
    public async Task Anonymous_Auth_Creates_Player_Before_Any_Session()
    {
        var dispatcher = new ExoDispatcher(useSynchronizationContext: false);
        using var client = new ExoClient(dispatcher);

        try
        {
            await client.ConnectAsync(ServerUri);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[IntegrationTest] Skipping live anonymous test (server not running): {ex.Message}");
            return;
        }

        // No prior auth: `auth.anonymous` must be reachable on an unauthenticated socket.
        var result = await client.SendActionAsync<JsonElement>(
            "auth", "anonymous", new { name = "AnonTester" });

        Assert.True(result.TryGetProperty("token", out var tokenProp), "anonymous returned no token");
        string token = tokenProp.GetString() ?? "";
        Assert.False(string.IsNullOrEmpty(token));

        // The issued token authenticates on its own.
        var reauth = await client.AuthenticateAsync(token);
        Assert.True(reauth.IsSuccess);
        Assert.False(string.IsNullOrEmpty(reauth.PlayerId));

        await client.DisconnectAsync();
    }
}
