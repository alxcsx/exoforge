using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Exoforge.Client;

/// <summary>
/// High-level client for Exoforge game backend platform.
/// Handles connection, action requests, topic subscriptions, and real-time event streaming.
/// Dispatches callbacks safely on Unity main thread or SynchronizationContext.
/// </summary>
public class ExoClient : IDisposable
{
    private readonly ExoTransport _transport;
    private readonly ExoDispatcher _dispatcher;
    private readonly ConcurrentDictionary<string, TaskCompletionSource<ExoActionResult>> _pendingActions = new();
    private readonly ConcurrentDictionary<string, List<Action<ExoEventFrame>>> _eventHandlers = new();
    private long _requestIdCounter;

    public bool IsConnected => _transport.IsConnected;
    public ExoDispatcher Dispatcher => _dispatcher;

    public event Action? OnConnected;
    public event Action<Exception?>? OnDisconnected;

    public ExoClient(ExoDispatcher? dispatcher = null)
    {
        _dispatcher = dispatcher ?? new ExoDispatcher();
        _transport = new ExoTransport();

        _transport.OnConnected += HandleConnected;
        _transport.OnDisconnected += HandleDisconnected;
        _transport.OnMessageReceived += HandleMessageReceived;
    }

    public Task ConnectAsync(Uri uri, CancellationToken cancellationToken = default)
    {
        return _transport.ConnectAsync(uri, cancellationToken);
    }

    public Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        return _transport.DisconnectAsync(cancellationToken);
    }

    /// <summary>
    /// Sends an action request to the Exoforge Kernel and awaits the typed response.
    /// </summary>
    public async Task<TResult> SendActionAsync<TResult>(
        string service,
        string action,
        object? payload = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
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

        TimeSpan effectiveTimeout = timeout ?? TimeSpan.FromSeconds(5);
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

        if (typeof(TResult) == typeof(JsonElement))
        {
            return (TResult)(object)result.Data;
        }

        if (typeof(TResult) == typeof(int) && result.Data.ValueKind == JsonValueKind.Number)
        {
            return (TResult)(object)result.Data.GetInt32();
        }

        if (typeof(TResult) == typeof(long) && result.Data.ValueKind == JsonValueKind.Number)
        {
            return (TResult)(object)result.Data.GetInt64();
        }

        if (typeof(TResult) == typeof(double) && result.Data.ValueKind == JsonValueKind.Number)
        {
            return (TResult)(object)result.Data.GetDouble();
        }

        if (typeof(TResult) == typeof(string) && result.Data.ValueKind == JsonValueKind.String)
        {
            return (TResult)(object)result.Data.GetString()!;
        }

        return JsonSerializer.Deserialize<TResult>(result.Data.GetRawText())!;
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
    }

    private void HandleConnected()
    {
        _dispatcher.Post(() => OnConnected?.Invoke());
    }

    private void HandleDisconnected(Exception? ex)
    {
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
