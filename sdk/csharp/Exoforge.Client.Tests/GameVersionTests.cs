using System;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Client.Tests;

/// <summary>
/// The client tells the server which game version it is, and shows an update screen when the server
/// will not serve it any more.
/// </summary>
public class GameVersionTests
{
    [Fact]
    public void The_sign_in_frame_carries_the_game_version_only_when_there_is_one()
    {
        string with = JsonSerializer.Serialize(new ExoAuthRequest("tok") { GameVersion = "1.4.0" });
        string without = JsonSerializer.Serialize(new ExoAuthRequest("tok"));

        Assert.Equal("1.4.0", JsonDocument.Parse(with).RootElement.GetProperty("game_version").GetString());
        // Nothing new on the wire for a client that has no version: old servers see the frame they always saw.
        Assert.False(JsonDocument.Parse(without).RootElement.TryGetProperty("game_version", out _));
    }

    [Fact]
    public async Task Every_http_call_carries_the_game_version_header()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, "{\"status\":\"ok\",\"data\":{\"pong\":true}}");
        using var client = NewClient(handler);
        client.GameVersion = "1.4.0";

        await client.SendActionAsync<JsonElement>("demo", "ping", new { });

        Assert.Equal("1.4.0", handler.GameVersionHeader);
    }

    [Fact]
    public async Task No_game_version_means_no_header()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, "{\"status\":\"ok\",\"data\":{}}");
        using var client = NewClient(handler);

        await client.SendActionAsync<JsonElement>("demo", "ping", new { });

        Assert.Null(handler.GameVersionHeader);
    }

    [Fact]
    public async Task A_426_raises_upgrade_required_and_the_event()
    {
        var handler = new RecordingHandler(
            (HttpStatusCode)426,
            "{\"status\":\"error\",\"error\":{\"code\":\"upgrade_required\",\"message\":\"This version is no longer supported\"}}");
        using var client = NewClient(handler);
        client.GameVersion = "0.9.0";
        int raised = 0;
        client.OnUpgradeRequired += () => raised++;

        var ex = await Assert.ThrowsAsync<ExoUpgradeRequiredException>(() => client.SendActionAsync<JsonElement>("demo", "ping", new { }));

        Assert.Equal("upgrade_required", ex.Code);
        Assert.Equal(1, raised);
        // It is still an action exception, so existing catch blocks keep working.
        Assert.IsAssignableFrom<ExoActionException>(ex);
    }

    private static ExoClient NewClient(HttpMessageHandler handler)
    {
        var client = new ExoClient(httpClient: new HttpClient(handler), httpBaseUri: new Uri("http://cluster.test/"));
        client.DefaultTransportPreference = ExoTransportPreference.Http;
        client.UseToken("exo_ses_x");
        return client;
    }

    private sealed class RecordingHandler(HttpStatusCode status, string body) : HttpMessageHandler
    {
        public string? GameVersionHeader { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            GameVersionHeader = request.Headers.TryGetValues("x-exoforge-game-version", out var values) ? string.Join(",", values) : null;
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") });
        }
    }
}
