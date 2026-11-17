using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Exoforge.Management.Tests;

/// <summary>
/// A cluster with just enough of the auth contract to exercise a saved CLI session: <c>auth.login</c>
/// opens a device session (replacing whatever that device held), <c>auth.refresh</c> rotates the pair
/// once, and the socket handshake refuses an access token that has expired. Tokens are minted the way
/// the real extension mints them - <c>exo_ses_…</c> and <c>exo_ref_…</c> - so a test can tell a login
/// pair from a service credential.
///
/// Deliberately not a general server: everything else answers <c>service_not_found</c>.
/// </summary>
internal sealed class StubCluster : IAsyncDisposable
{
    public const string Password = "pw";

    private sealed class Session
    {
        public string Access = "";
        public string Refresh = "";
        public string DeviceId = "";
        public bool AccessExpired;
        public bool RefreshSpent;
    }

    private readonly HttpListener _listener = new();
    private readonly CancellationTokenSource _cts = new();
    private readonly object _lock = new();
    private readonly List<Session> _sessions = new();
    private readonly List<JsonElement> _loginPayloads = new();
    private readonly Task _acceptLoop;

    private WebSocket? _socket;
    private int _counter;
    private int _loginCalls;
    private int _refreshCalls;
    private int _issueTokenCalls;
    private int _replayedRefreshTokens;

    private StubCluster(int port)
    {
        WsUri = new Uri($"ws://127.0.0.1:{port}/ws");
        HttpUri = new Uri($"http://127.0.0.1:{port}/");
        _listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        _listener.Start();
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token));
    }

    public Uri WsUri { get; }

    public Uri HttpUri { get; }

    public static StubCluster Start() => new(FreePort());

    public int LoginCalls { get { lock (_lock) return _loginCalls; } }

    public int RefreshCalls { get { lock (_lock) return _refreshCalls; } }

    public int IssueTokenCalls { get { lock (_lock) return _issueTokenCalls; } }

    public int ReplayedRefreshTokens { get { lock (_lock) return _replayedRefreshTokens; } }

    public JsonElement[] LoginPayloads
    {
        get { lock (_lock) return _loginPayloads.ToArray(); }
    }

    /// <summary>The one pair a working session should leave behind.</summary>
    public (string Access, string Refresh) LiveSession
    {
        get
        {
            lock (_lock)
            {
                Session live = _sessions.Last(s => !s.RefreshSpent);
                return (live.Access, live.Refresh);
            }
        }
    }

    public int LiveSessionCount
    {
        get { lock (_lock) return _sessions.Count(s => !s.RefreshSpent); }
    }

    /// <summary>How many token rows exist, spent or not - a second connect must not add any.</summary>
    public int TokenRowCount
    {
        get { lock (_lock) return _sessions.Count; }
    }

    /// <summary>What the real server does when the hour is up: the access token stops working, the refresh token still does.</summary>
    public void ExpireAccessTokens()
    {
        lock (_lock)
        {
            foreach (var session in _sessions)
            {
                session.AccessExpired = true;
            }
        }
    }

    private bool AccessTokenIsLive(string token)
    {
        lock (_lock)
        {
            return _sessions.Any(s => s.Access == token && !s.AccessExpired);
        }
    }

    private (string PlayerId, string Access, string Refresh)? Rotate(string refreshToken)
    {
        lock (_lock)
        {
            Session? row = _sessions.FirstOrDefault(s => s.Refresh == refreshToken);

            if (row == null || row.RefreshSpent)
            {
                _replayedRefreshTokens++;
                return null;
            }

            row.RefreshSpent = true;

            var next = new Session
            {
                DeviceId = row.DeviceId,
                Access = $"exo_ses_{Interlocked.Increment(ref _counter)}.secret",
                Refresh = $"exo_ref_{Interlocked.Increment(ref _counter)}.secret"
            };

            _sessions.Add(next);
            return ("admin", next.Access, next.Refresh);
        }
    }

    private (string PlayerId, string Access, string Refresh) StartSession(string deviceId)
    {
        lock (_lock)
        {
            // The server's device-replace rule: one login per device, older rows revoked.
            foreach (var old in _sessions.Where(s => s.DeviceId == deviceId))
            {
                old.RefreshSpent = true;
                old.AccessExpired = true;
            }

            var session = new Session
            {
                DeviceId = deviceId,
                Access = $"exo_ses_{Interlocked.Increment(ref _counter)}.secret",
                Refresh = $"exo_ref_{Interlocked.Increment(ref _counter)}.secret"
            };

            _sessions.Add(session);
            return ("admin", session.Access, session.Refresh);
        }
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            HttpListenerContext context;

            try
            {
                context = await _listener.GetContextAsync();
            }
            catch (Exception)
            {
                return;
            }

            _ = Task.Run(() => HandleContextAsync(context, cancellationToken), CancellationToken.None);
        }
    }

    private async Task HandleContextAsync(HttpListenerContext context, CancellationToken cancellationToken)
    {
        try
        {
            if (context.Request.IsWebSocketRequest)
            {
                var wsContext = await context.AcceptWebSocketAsync(subProtocol: null);
                _socket = wsContext.WebSocket;
                await ReceiveLoopAsync(wsContext.WebSocket, cancellationToken);
                return;
            }

            string path = context.Request.Url!.AbsolutePath.Trim('/');
            string body = "";

            if (context.Request.HasEntityBody)
            {
                using var reader = new System.IO.StreamReader(context.Request.InputStream, Encoding.UTF8);
                body = await reader.ReadToEndAsync();
            }

            var payload = string.IsNullOrEmpty(body)
                ? new JsonObject()
                : JsonNode.Parse(body) as JsonObject ?? new JsonObject();

            (int status, string json) = Route(path, payload, context.Request.Headers["Authorization"]);

            byte[] bytes = Encoding.UTF8.GetBytes(json);
            context.Response.StatusCode = status;
            context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes, 0, bytes.Length);
            context.Response.Close();
        }
        catch (Exception)
        {
            try { context.Response.Abort(); } catch { /* client gone */ }
        }
    }

    private (int Status, string Json) Route(string path, JsonObject payload, string? authorization)
    {
        switch (path)
        {
            case "api/auth/login":
            {
                string device = payload["device_id"]?.GetValue<string>() ?? "";
                var started = StartSession(device);

                lock (_lock)
                {
                    _loginCalls++;
                    _loginPayloads.Add(JsonSerializer.SerializeToElement(payload));
                }

                return (200, Ok(new JsonObject
                {
                    ["player_id"] = started.PlayerId,
                    ["token"] = started.Access,
                    ["refresh_token"] = started.Refresh,
                    ["scopes"] = new JsonArray("admin"),
                    ["role"] = "admin"
                }));
            }

            case "api/auth/refresh":
            {
                string token = payload["token"]?.GetValue<string>() ?? "";
                var rotated = Rotate(token);

                lock (_lock) _refreshCalls++;

                if (rotated == null)
                {
                    return (401, Error("invalid_token", "refresh token already used"));
                }

                return (200, Ok(new JsonObject
                {
                    ["player_id"] = rotated.Value.PlayerId,
                    ["token"] = rotated.Value.Access,
                    ["refresh_token"] = rotated.Value.Refresh
                }));
            }

            case "api/auth/issue_token":
                lock (_lock) _issueTokenCalls++;
                return (200, Ok(new JsonObject { ["token"] = "exo_svc_unexpected.secret" }));

            case "api/extension_manager/get_system_info":
            {
                string bearer = authorization?.StartsWith("Bearer ", StringComparison.Ordinal) == true
                    ? authorization["Bearer ".Length..]
                    : "";

                if (!AccessTokenIsLive(bearer))
                {
                    return (401, Error("token_expired", "expired"));
                }

                return (200, Ok(new JsonObject { ["cluster"] = "stub" }));
            }

            default:
                return (404, Error("service_not_found", path));
        }
    }

    private static string Ok(JsonObject data) =>
        new JsonObject { ["status"] = "ok", ["data"] = data }.ToJsonString();

    private static string Error(string code, string message) =>
        new JsonObject
        {
            ["status"] = "error",
            ["error"] = new JsonObject { ["code"] = code, ["message"] = message }
        }.ToJsonString();

    private async Task ReceiveLoopAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];

        try
        {
            while (!cancellationToken.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                var message = new MemoryStream();
                WebSocketReceiveResult result;

                do
                {
                    result = await socket.ReceiveAsync(buffer, cancellationToken);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        try { await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None); } catch { }
                        return;
                    }

                    message.Write(buffer, 0, result.Count);
                }
                while (!result.EndOfMessage);

                using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(message.ToArray()));
                var root = doc.RootElement;
                string type = root.TryGetProperty("type", out var typeProp) ? typeProp.GetString() ?? "" : "";

                switch (type)
                {
                    case "auth":
                    {
                        string token = root.TryGetProperty("token", out var tokenProp) ? tokenProp.GetString() ?? "" : "";

                        string reply = AccessTokenIsLive(token)
                            ? new JsonObject
                            {
                                ["type"] = "auth_result",
                                ["status"] = "ok",
                                ["player_id"] = "admin",
                                ["scopes"] = new JsonArray("admin")
                            }.ToJsonString()
                            : new JsonObject
                            {
                                ["type"] = "auth_result",
                                ["status"] = "error",
                                ["error"] = new JsonObject { ["code"] = "token_expired", ["message"] = "expired" }
                            }.ToJsonString();

                        await SendAsync(socket, reply);
                        break;
                    }

                    case "action":
                    {
                        string id = root.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
                        string service = root.TryGetProperty("service", out var sProp) ? sProp.GetString() ?? "" : "";
                        string action = root.TryGetProperty("action", out var aProp) ? aProp.GetString() ?? "" : "";

                        await SendAsync(socket, new JsonObject
                        {
                            ["type"] = "action_result",
                            ["id"] = id,
                            ["status"] = "error",
                            ["error"] = new JsonObject
                            {
                                ["code"] = "service_not_found",
                                ["message"] = $"{service}.{action} is not part of the stub"
                            }
                        }.ToJsonString());
                        break;
                    }

                    case "ping":
                        await SendAsync(socket, "{\"type\":\"pong\"}");
                        break;
                }
            }
        }
        catch (Exception)
        {
            // A closed connection ends the loop; the test asserts on what was recorded.
        }
    }

    private static Task SendAsync(WebSocket socket, string json) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, endOfMessage: true, CancellationToken.None);

    private static int FreePort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        int port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    public ValueTask DisposeAsync()
    {
        _cts.Cancel();
        try { _socket?.Abort(); } catch { }
        try { _socket?.Dispose(); } catch { }
        try { _listener.Stop(); } catch { }
        _cts.Dispose();
        return ValueTask.CompletedTask;
    }
}
