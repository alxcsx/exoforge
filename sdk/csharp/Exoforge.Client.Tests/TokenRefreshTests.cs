using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Client.Tests;

/// <summary>
/// The client's half of short-lived access tokens: a call that comes back `token_expired` renews
/// the pair through <see cref="ExoClient.RefreshTokensAsync"/> and is made once more.
/// </summary>
public class TokenRefreshTests
{
    [Fact]
    public async Task A_token_expired_result_refreshes_the_tokens_and_retries_once()
    {
        var handler = new ScriptedAuthHandler();
        using var client = NewClient(handler, "exo_ses_stale");

        int refreshes = 0;
        client.RefreshTokensAsync = _ =>
        {
            refreshes++;
            client.UseToken("exo_ses_fresh");
            return Task.CompletedTask;
        };

        JsonElement result = await client.SendActionAsync<JsonElement>("demo", "ping", new { value = 1 });

        Assert.True(result.GetProperty("pong").GetBoolean());
        Assert.Equal(1, refreshes);
        Assert.Equal(2, handler.Count("demo.ping"));
        Assert.Equal("exo_ses_fresh", handler.LastAuthorization("demo.ping"));
    }

    [Fact]
    public async Task Concurrent_expiries_share_one_refresh_because_rotation_is_single_use()
    {
        var handler = new ScriptedAuthHandler();
        using var client = NewClient(handler, "exo_ses_stale");

        int refreshes = 0;
        client.RefreshTokensAsync = async _ =>
        {
            Interlocked.Increment(ref refreshes);
            // The real one rotates a token, so a second refresh with the same input would revoke
            // the session's whole family.
            await Task.Delay(100);
            client.UseToken("exo_ses_fresh");
        };

        await Task.WhenAll(
            client.SendActionAsync<JsonElement>("demo", "ping", new { value = 1 }),
            client.SendActionAsync<JsonElement>("demo", "ping", new { value = 2 }));

        Assert.Equal(1, refreshes);
    }

    [Fact]
    public async Task Refreshing_is_not_itself_retried_by_a_refresh()
    {
        var handler = new ScriptedAuthHandler { AlwaysExpired = true };
        using var client = NewClient(handler, "exo_ses_stale");

        int refreshes = 0;
        client.RefreshTokensAsync = _ =>
        {
            refreshes++;
            return Task.CompletedTask;
        };

        var failure = await Assert.ThrowsAsync<ExoActionException>(
            () => client.SendActionAsync<JsonElement>("auth", "refresh", new { token = "exo_ref_stale" }));

        Assert.Equal("token_expired", failure.Code);
        Assert.Equal(0, refreshes);
    }

    private static ExoClient NewClient(HttpMessageHandler handler, string token)
    {
        var client = new ExoClient(httpClient: new HttpClient(handler), httpBaseUri: new Uri("http://cluster.test/"));
        client.DefaultTransportPreference = ExoTransportPreference.Http;
        client.UseToken(token);
        return client;
    }

    private sealed class ScriptedAuthHandler : HttpMessageHandler
    {
        private readonly List<(string Action, string Authorization)> _calls = new();
        private readonly object _lock = new();

        public bool AlwaysExpired { get; init; }

        public int Count(string action)
        {
            lock (_lock) return _calls.FindAll(c => c.Action == action).Count;
        }

        public string LastAuthorization(string action)
        {
            lock (_lock) return _calls.FindAll(c => c.Action == action)[^1].Authorization;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            string path = request.RequestUri!.AbsolutePath;
            string action = path.Trim('/').Replace("api/", "").Replace('/', '.');

            string? authorization = request.Headers.Authorization?.Parameter;
            lock (_lock) _calls.Add((action, authorization ?? ""));

            if (action == "auth.refresh")
            {
                return Task.FromResult(Json(AlwaysExpired ? 401 : 200, AlwaysExpired
                    ? "{\"status\":\"error\",\"error\":{\"code\":\"token_expired\",\"message\":\"expired\"}}"
                    : "{\"status\":\"ok\",\"data\":{\"token\":\"exo_ses_fresh\",\"refresh_token\":\"exo_ref_new\"}}"));
            }

            if (authorization == "exo_ses_stale")
            {
                return Task.FromResult(Json(401,
                    "{\"status\":\"error\",\"error\":{\"code\":\"token_expired\",\"message\":\"The access token has expired.\"}}"));
            }

            return Task.FromResult(Json(200, "{\"status\":\"ok\",\"data\":{\"pong\":true}}"));
        }

        private static HttpResponseMessage Json(int status, string body) =>
            new((HttpStatusCode)status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json")
            };
    }
}
