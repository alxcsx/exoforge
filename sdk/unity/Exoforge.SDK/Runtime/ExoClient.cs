using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Exoforge.Client;

/// <summary>
/// Preferred transport mechanism for dispatching an Exoforge action.
/// </summary>
public enum ExoTransportPreference
{
    /// <summary>Uses WebSocket if connected; otherwise falls back to HTTP REST if HttpBaseUri is available.</summary>
    Auto,
    /// <summary>Forces dispatching via the persistent WebSocket session.</summary>
    WebSocket,
    /// <summary>Forces dispatching via HTTP REST (POST /api/{service}/{action}).</summary>
    Http
}

/// <summary>
/// High-level client for Exoforge game backend platform.
/// Handles connection, action requests, topic subscriptions, and real-time event streaming.
/// Dispatches callbacks safely on Unity main thread or SynchronizationContext.
/// </summary>
public class ExoClient : IDisposable
{
    private static readonly JsonSerializerOptions DefaultJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly ExoTransport _transport;
    private readonly ExoDispatcher _dispatcher;
    private readonly HttpClient _httpClient;
    private readonly ConcurrentDictionary<string, TaskCompletionSource<ExoActionResult>> _pendingActions = new();
    private readonly ConcurrentDictionary<string, List<Action<ExoEventFrame>>> _eventHandlers = new();
    private long _requestIdCounter;
    private TaskCompletionSource<ExoAuthResult>? _pendingAuth;
    private bool _isAuthenticated;
    private readonly List<string> _scopes = new();

    public bool IsConnected => _transport.IsConnected;
    public bool IsAuthenticated => _isAuthenticated;
    public string? PlayerId { get; private set; }
    public IReadOnlyList<string> Scopes => _scopes.AsReadOnly();
    public ExoDispatcher Dispatcher => _dispatcher;
    public Uri? HttpBaseUri { get; set; }
    /// <summary>The token last used to authenticate. Set by <see cref="AuthenticateAsync"/>.</summary>
    public string? AuthToken { get; private set; }
    public HttpClient HttpClient => _httpClient;

    /// <summary>
    /// Default per-call timeout. Overridable on any individual call.
    ///
    /// Was three separate magic numbers (5s, 5s, 10s) with no way to raise them, so a cold first
    /// call failed with a bare TimeoutException and nothing to point at.
    /// </summary>
    public static TimeSpan DefaultTimeout { get; set; } = TimeSpan.FromSeconds(10);

    public event Action? OnConnected;
    public event Action<Exception?>? OnDisconnected;
    public event Action<ExoEventFrame>? OnAnyEvent;

    public ExoClient(ExoDispatcher? dispatcher = null, Uri? httpBaseUri = null, HttpClient? httpClient = null)
    {
        _dispatcher = dispatcher ?? new ExoDispatcher();
        _transport = new ExoTransport();
        _httpClient = httpClient ?? new HttpClient();
        HttpBaseUri = httpBaseUri;

        _transport.OnConnected += HandleConnected;
        _transport.OnDisconnected += HandleDisconnected;
        _transport.OnMessageReceived += HandleMessageReceived;
    }

    public Task ConnectAsync(Uri uri, CancellationToken cancellationToken = default)
    {
        if (uri == null) throw new ArgumentNullException(nameof(uri));

        // The HTTP base is configuration, not arithmetic. It used to be derived as
        // `uri.Port == 4000 ? 4001 : uri.Port`, which is wrong for any non-default gateway and failed
        // silently — a bad Uri left HttpBaseUri null, so HTTP transport was quietly unavailable
        // rather than reporting anything. Callers set it from the workspace config.
        return _transport.ConnectAsync(uri, cancellationToken);
    }

    public Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        return _transport.DisconnectAsync(cancellationToken);
    }

    /// <summary>
    /// Authenticates the client session with a token frame.
    /// </summary>
    public async Task<ExoAuthResult> AuthenticateAsync(
        string token,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        AuthToken = token;
        var request = new ExoAuthRequest(token);
        var tcs = new TaskCompletionSource<ExoAuthResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pendingAuth = tcs;

        string json = JsonSerializer.Serialize(request);
        await _transport.SendAsync(json, cancellationToken).ConfigureAwait(false);

        TimeSpan effectiveTimeout = timeout ?? DefaultTimeout;
        using var timeoutCts = new CancellationTokenSource(effectiveTimeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);

        linkedCts.Token.Register(() =>
        {
            if (_pendingAuth == tcs)
            {
                if (timeoutCts.IsCancellationRequested)
                {
                    tcs.TrySetException(new TimeoutException($"Authentication timed out after {effectiveTimeout.TotalSeconds}s."));
                }
                else
                {
                    tcs.TrySetCanceled(cancellationToken);
                }
            }
        });

        return await tcs.Task.ConfigureAwait(false);
    }

    /// <summary>
    /// Sends an action request to the Exoforge Kernel using automatic transport selection.
    /// </summary>
    public Task<TResult> SendActionAsync<TResult>(
        string service,
        string action,
        object? payload = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        return SendActionAsync<TResult>(service, action, payload, ExoTransportPreference.Auto, timeout, cancellationToken);
    }

    /// <summary>
    /// Sends an action request to the Exoforge Kernel with explicit transport preference.
    /// </summary>
    public async Task<TResult> SendActionAsync<TResult>(
        string service,
        string action,
        object? payload,
        ExoTransportPreference transportPreference,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        bool useHttp = transportPreference == ExoTransportPreference.Http ||
                       (transportPreference == ExoTransportPreference.Auto && !IsConnected && HttpBaseUri != null);

        if (useHttp)
        {
            return await SendActionHttpAsync<TResult>(service, action, payload, timeout, cancellationToken).ConfigureAwait(false);
        }

        string reqId = $"req_{Interlocked.Increment(ref _requestIdCounter)}";

        var request = new ExoActionRequest
        {
            Id = reqId,
            Service = service,
            Action = action,
            Payload = payload
        };

        var tcs = new TaskCompletionSource<ExoActionResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pendingActions[reqId] = tcs;

        string json = JsonSerializer.Serialize(request);
        await _transport.SendAsync(json, cancellationToken).ConfigureAwait(false);

        TimeSpan effectiveTimeout = timeout ?? DefaultTimeout;
        using var timeoutCts = new CancellationTokenSource(effectiveTimeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);

        linkedCts.Token.Register(() =>
        {
            if (_pendingActions.TryRemove(reqId, out var removedTcs))
            {
                if (timeoutCts.IsCancellationRequested)
                {
                    removedTcs.TrySetException(new TimeoutException($"Action '{service}.{action}' timed out after {effectiveTimeout.TotalSeconds}s."));
                }
                else
                {
                    removedTcs.TrySetCanceled(cancellationToken);
                }
            }
        });

        ExoActionResult result = await tcs.Task.ConfigureAwait(false);

        if (!result.IsSuccess)
        {
            string errCode = result.Error?.Code ?? "unknown_error";
            string errMsg = result.Error?.Message ?? "Action failed on server";
            throw new ExoActionException(errCode, errMsg);
        }

        return DeserializeResult<TResult>(result.Data);
    }

    private async Task<TResult> SendActionHttpAsync<TResult>(
        string service,
        string action,
        object? payload,
        TimeSpan? timeout,
        CancellationToken cancellationToken)
    {
        if (HttpBaseUri == null)
        {
            throw new InvalidOperationException("HttpBaseUri is not set on ExoClient. Configure HttpBaseUri or connect via WebSocket first.");
        }

        var endpoint = new Uri(HttpBaseUri, $"/api/{service}/{action}");
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);

        if (!string.IsNullOrEmpty(AuthToken))
        {
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", AuthToken);
        }

        string jsonPayload = payload != null ? JsonSerializer.Serialize(payload) : "{}";
        request.Content = new StringContent(jsonPayload, System.Text.Encoding.UTF8, "application/json");

        TimeSpan effectiveTimeout = timeout ?? DefaultTimeout;
        using var timeoutCts = new CancellationTokenSource(effectiveTimeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, linkedCts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested)
        {
            throw new TimeoutException($"HTTP Action '{service}.{action}' timed out after {effectiveTimeout.TotalSeconds}s.");
        }

        string responseContent = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
        using var doc = JsonDocument.Parse(responseContent);
        var root = doc.RootElement;

        string status = root.TryGetProperty("status", out var sProp) ? sProp.GetString() ?? "" : "";
        if (status != "ok" && !response.IsSuccessStatusCode)
        {
            string errCode = "http_error";
            string errMsg = $"HTTP {(int)response.StatusCode}";
            if (root.TryGetProperty("error", out var errProp))
            {
                if (errProp.ValueKind == JsonValueKind.String)
                {
                    errMsg = errProp.GetString() ?? errMsg;
                }
                else if (errProp.ValueKind == JsonValueKind.Object)
                {
                    if (errProp.TryGetProperty("code", out var cProp)) errCode = cProp.GetString() ?? errCode;
                    if (errProp.TryGetProperty("message", out var mProp)) errMsg = mProp.GetString() ?? errMsg;
                }
            }
            throw new ExoActionException(errCode, errMsg);
        }

        JsonElement dataElement = root.TryGetProperty("data", out var dProp) ? dProp.Clone() : root.Clone();
        return DeserializeResult<TResult>(dataElement);
    }

    private static TResult DeserializeResult<TResult>(JsonElement data)
    {
        if (typeof(TResult) == typeof(JsonElement))
        {
            return (TResult)(object)data;
        }

        if (typeof(TResult) == typeof(int) && data.ValueKind == JsonValueKind.Number)
        {
            return (TResult)(object)data.GetInt32();
        }

        if (typeof(TResult) == typeof(long) && data.ValueKind == JsonValueKind.Number)
        {
            return (TResult)(object)data.GetInt64();
        }

        if (typeof(TResult) == typeof(double) && data.ValueKind == JsonValueKind.Number)
        {
            return (TResult)(object)data.GetDouble();
        }

        if (typeof(TResult) == typeof(string) && data.ValueKind == JsonValueKind.String)
        {
            return (TResult)(object)data.GetString()!;
        }

        if (typeof(TResult) == typeof(bool) && (data.ValueKind == JsonValueKind.True || data.ValueKind == JsonValueKind.False))
        {
            return (TResult)(object)data.GetBoolean();
        }

        return JsonSerializer.Deserialize<TResult>(data.GetRawText(), DefaultJsonOptions)!;
    }

    /// <summary>
    /// Subscribes to an event topic.
    /// </summary>
    public async Task SubscribeAsync(string topic, CancellationToken cancellationToken = default)
    {
        var request = new ExoSubscriptionRequest("subscribe", topic);
        string json = JsonSerializer.Serialize(request);
        await _transport.SendAsync(json, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Unsubscribes from an event topic.
    /// </summary>
    public async Task UnsubscribeAsync(string topic, CancellationToken cancellationToken = default)
    {
        var request = new ExoSubscriptionRequest("unsubscribe", topic);
        string json = JsonSerializer.Serialize(request);
        await _transport.SendAsync(json, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Registers a handler for a broadcast event by event name.
    /// Callbacks are dispatched safely on the main thread via ExoDispatcher.
    /// </summary>
    public void OnEvent(string eventName, Action<ExoEventFrame> handler)
    {
        string key = eventName.ToLowerInvariant();
        _eventHandlers.AddOrUpdate(
            key,
            _ => new List<Action<ExoEventFrame>> { handler },
            (_, list) =>
            {
                lock (list)
                {
                    list.Add(handler);
                }
                return list;
            });
    }

    /// <summary>
    /// Registers a handler for a broadcast event scoped to a specific topic.
    /// </summary>
    public void OnEvent(string topic, string eventName, Action<ExoEventFrame> handler)
    {
        string key = $"{topic}:{eventName}".ToLowerInvariant();
        _eventHandlers.AddOrUpdate(
            key,
            _ => new List<Action<ExoEventFrame>> { handler },
            (_, list) =>
            {
                lock (list)
                {
                    list.Add(handler);
                }
                return list;
            });
    }

    private void HandleMessageReceived(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("type", out var typeProp))
            {
                return;
            }

            string type = typeProp.GetString() ?? "";

            switch (type)
            {
                case "auth_result":
                    HandleAuthResult(json);
                    break;

                case "action_result":
                    HandleActionResult(json);
                    break;

                case "event":
                    HandleEventBroadcast(json);
                    break;

                case "pong":
                    break;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[ExoClient] Failed to parse message: {ex.Message}");
        }
    }

    private void HandleAuthResult(string json)
    {
        var result = JsonSerializer.Deserialize<ExoAuthResult>(json);
        if (result != null)
        {
            if (result.IsSuccess)
            {
                _isAuthenticated = true;
                PlayerId = result.PlayerId;
                _scopes.Clear();
                if (result.Scopes != null)
                {
                    _scopes.AddRange(result.Scopes);
                }
                _pendingAuth?.TrySetResult(result);
            }
            else
            {
                string errMsg = result.Error?.ToString() ?? "Authentication failed";
                _pendingAuth?.TrySetException(new ExoActionException("auth_failed", errMsg));
            }
        }
    }

    private void HandleActionResult(string json)
    {
        var result = JsonSerializer.Deserialize<ExoActionResult>(json);
        if (result != null && !string.IsNullOrEmpty(result.Id))
        {
            if (_pendingActions.TryRemove(result.Id, out var tcs))
            {
                tcs.TrySetResult(result);
            }
        }
    }

    private void HandleEventBroadcast(string json)
    {
        var evt = JsonSerializer.Deserialize<ExoEventFrame>(json);
        if (evt == null)
        {
            return;
        }

        string eventKey = evt.Event.ToLowerInvariant();
        string topicKey = $"{evt.Topic}:{evt.Event}".ToLowerInvariant();

        void NotifyHandlers(string key)
        {
            if (_eventHandlers.TryGetValue(key, out var list))
            {
                List<Action<ExoEventFrame>> handlersSnapshot;
                lock (list)
                {
                    handlersSnapshot = new List<Action<ExoEventFrame>>(list);
                }

                foreach (var handler in handlersSnapshot)
                {
                    _dispatcher.Post(() => handler(evt));
                }
            }
        }

        NotifyHandlers(eventKey);
        NotifyHandlers(topicKey);
        _dispatcher.Post(() => OnAnyEvent?.Invoke(evt));
    }

    private void HandleConnected()
    {
        _dispatcher.Post(() => OnConnected?.Invoke());
    }

    private void HandleDisconnected(Exception? ex)
    {
        _isAuthenticated = false;
        PlayerId = null;
        _scopes.Clear();
        _pendingAuth?.TrySetException(ex ?? new InvalidOperationException("Disconnected from server."));
        _pendingAuth = null;

        // Cancel all pending actions
        foreach (var kvp in _pendingActions)
        {
            if (_pendingActions.TryRemove(kvp.Key, out var tcs))
            {
                tcs.TrySetException(ex ?? new InvalidOperationException("Disconnected from server."));
            }
        }

        _dispatcher.Post(() => OnDisconnected?.Invoke(ex));
    }

    public void Dispose()
    {
        _transport.Dispose();
    }
}

public class ExoActionException : Exception
{
    public string Code { get; }

    public ExoActionException(string code, string message) : base($"[{code}] {message}")
    {
        Code = code;
    }
}
