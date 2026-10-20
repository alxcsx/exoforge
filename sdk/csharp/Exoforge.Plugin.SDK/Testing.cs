using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// In-memory implementation of <see cref="IDatabase"/> for unit testing C# plugins and extensions
/// without requiring a running BEAM host or database process.
/// </summary>
public class InMemoryDatabase : IDatabase
{
    private readonly ConcurrentDictionary<(string Table, string Key), object> _store = new();

    /// <summary>Raw stored entries for test assertions.</summary>
    public IReadOnlyDictionary<(string Table, string Key), object> Entries => _store;

    public T? Get<T>(string table, string key)
    {
        if (_store.TryGetValue((table.ToLowerInvariant(), key), out var val))
        {
            if (val is T typed) return typed;
            string json = val is string s ? s : PluginJson.Serialize(val);
            return PluginJson.Deserialize<T>(json);
        }

        return default;
    }

    public IReadOnlyList<T> All<T>(string table)
    {
        string tbl = table.ToLowerInvariant();
        var list = new List<T>();

        foreach (var entry in _store)
        {
            if (string.IsNullOrEmpty(tbl) || string.Equals(entry.Key.Table, tbl, StringComparison.OrdinalIgnoreCase))
            {
                if (entry.Value is T typed)
                {
                    list.Add(typed);
                }
                else
                {
                    string json = entry.Value is string s ? s : PluginJson.Serialize(entry.Value);
                    var item = PluginJson.Deserialize<T>(json);
                    if (item != null) list.Add(item);
                }
            }
        }

        return list;
    }

    public void Put<T>(string table, string key, T value)
    {
        if (value == null)
        {
            Delete(table, key);
        }
        else
        {
            _store[(table.ToLowerInvariant(), key)] = value;
        }
    }

    public void Delete(string table, string key)
    {
        _store.TryRemove((table.ToLowerInvariant(), key), out _);
    }

    public IReadOnlyList<T> Query<T>(string sql, params object?[] args) => All<T>("");

    public T? QuerySingle<T>(string sql, params object?[] args) => All<T>("").FirstOrDefault();

    public int Execute(string sql, params object?[] args) => 0;

    public int Count(string table)
    {
        string tbl = table.ToLowerInvariant();
        return _store.Keys.Count(k => string.IsNullOrEmpty(tbl) || string.Equals(k.Table, tbl, StringComparison.OrdinalIgnoreCase));
    }

    public void Clear() => _store.Clear();
}

/// <summary>
/// In-memory implementation of <see cref="IEventDispatcher"/> that captures emitted events for assertions.
/// </summary>
public class InMemoryEventDispatcher : IEventDispatcher
{
    private readonly List<(string EventName, object Payload, string? Topic)> _events = new();

    /// <summary>All events emitted through this dispatcher in chronological order.</summary>
    public IReadOnlyList<(string EventName, object Payload, string? Topic)> EmittedEvents
    {
        get
        {
            lock (_events) return _events.ToArray();
        }
    }

    public Task EmitAsync<T>(string eventName, T payload, string? topic = null)
    {
        lock (_events)
        {
            _events.Add((eventName, payload!, topic));
        }

        return Task.CompletedTask;
    }

    public bool HasEmitted(string eventName, string? topic = null)
    {
        lock (_events)
        {
            return _events.Any(e =>
                string.Equals(e.EventName, eventName, StringComparison.OrdinalIgnoreCase) &&
                (topic == null || string.Equals(e.Topic, topic, StringComparison.OrdinalIgnoreCase)));
        }
    }

    public TPayload? GetPayload<TPayload>(string eventName)
    {
        lock (_events)
        {
            var match = _events.LastOrDefault(e => string.Equals(e.EventName, eventName, StringComparison.OrdinalIgnoreCase));
            if (match.Payload is TPayload typed) return typed;
            if (match.Payload == null) return default;

            string json = match.Payload is string s ? s : PluginJson.Serialize(match.Payload);
            return PluginJson.Deserialize<TPayload>(json);
        }
    }

    public void Clear()
    {
        lock (_events) _events.Clear();
    }
}

/// <summary>
/// In-memory implementation of <see cref="ILogger"/> that captures logs for assertions.
/// </summary>
public class InMemoryLogger : ILogger
{
    private readonly List<(int Level, string Message)> _logs = new();

    public IReadOnlyList<(int Level, string Message)> Logs
    {
        get
        {
            lock (_logs) return _logs.ToArray();
        }
    }

    public void Log(int level, string message)
    {
        lock (_logs) _logs.Add((level, message ?? ""));
    }

    public void Debug(string message) => Log(0, message);
    public void Info(string message) => Log(1, message);
    public void Warning(string message) => Log(2, message);
    public void Error(string message) => Log(3, message);

    public bool HasLogged(string messageSubstring, int? level = null)
    {
        lock (_logs)
        {
            return _logs.Any(l =>
                (level == null || l.Level == level.Value) &&
                l.Message.IndexOf(messageSubstring, StringComparison.OrdinalIgnoreCase) >= 0);
        }
    }

    public void Clear()
    {
        lock (_logs) _logs.Clear();
    }
}

/// <summary>
/// In-memory implementation of <see cref="IActionDispatcher"/> allowing mocking of external services.
/// </summary>
public class InMemoryActionDispatcher : IActionDispatcher
{
    private readonly Dictionary<(string Service, string Action), Func<object?, object?>> _handlers = new();
    private readonly List<(string Service, string Action, object? Payload)> _calls = new();

    public IReadOnlyList<(string Service, string Action, object? Payload)> Calls
    {
        get
        {
            lock (_calls) return _calls.ToArray();
        }
    }

    public void Register(string service, string action, Func<object?, object?> handler)
    {
        lock (_handlers)
        {
            _handlers[(service.ToLowerInvariant(), action.ToLowerInvariant())] = handler;
        }
    }

    public void Register<TPayload, TResponse>(string service, string action, Func<TPayload, TResponse> handler)
    {
        Register(service, action, payload =>
        {
            if (payload is TPayload typed) return handler(typed);
            string json = payload is string s ? s : PluginJson.Serialize(payload);
            var deserialized = PluginJson.Deserialize<TPayload>(json);
            return handler(deserialized!);
        });
    }

    public TResponse? CallAction<TResponse>(string service, string action, object payload)
    {
        lock (_calls)
        {
            _calls.Add((service, action, payload));
        }

        Func<object?, object?>? handler = null;
        lock (_handlers)
        {
            _handlers.TryGetValue((service.ToLowerInvariant(), action.ToLowerInvariant()), out handler);
        }

        if (handler != null)
        {
            object? result = handler(payload);
            if (result is TResponse typed) return typed;
            if (result == null) return default;

            string json = result is string s ? s : PluginJson.Serialize(result);
            return PluginJson.Deserialize<TResponse>(json);
        }

        return default;
    }

    public Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload)
    {
        return Task.FromResult(CallAction<TResponse>(service, action, payload));
    }

    public void Clear()
    {
        lock (_calls) _calls.Clear();
        lock (_handlers) _handlers.Clear();
    }
}

/// <summary>
/// Unit testing harness for Exoforge C# plugins and extensions.
/// Automatically configures <see cref="PluginHost.CurrentContext"/> and ambient <c>Exo</c> services
/// with in-memory test doubles on instantiation, and restores previous context on disposal.
/// </summary>
public sealed class ExoTestContext : IPluginContext, IDisposable
{
    public string PluginId { get; set; }
    public InMemoryDatabase Database { get; } = new();
    public InMemoryEventDispatcher Events { get; } = new();
    public InMemoryLogger Logger { get; } = new();
    public InMemoryActionDispatcher Actions { get; } = new();

    IDatabase IPluginContext.Database => Database;
    IEventDispatcher IPluginContext.Events => Events;
    IActionDispatcher IPluginContext.Actions => Actions;
    ILogger IPluginContext.Logger => Logger;

    public string? CallerPlayerId { get; set; }
    public IReadOnlyList<string> CallerScopes { get; set; } = Array.Empty<string>();

    private readonly IPluginContext? _previousContext;

    public ExoTestContext(string pluginId = "test_plugin")
    {
        PluginId = pluginId;
        _previousContext = PluginHost.CurrentContext;
        PluginHost.CurrentContext = this;
    }

    /// <summary>
    /// Creates an instance of <typeparamref name="T"/> and wires its context capabilities.
    /// </summary>
    public T Create<T>() where T : class, new()
    {
        var instance = new T();
        Wire(instance);
        return instance;
    }

    /// <summary>
    /// Injects database, logger, events, and action dispatcher into target's properties.
    /// </summary>
    public void Wire(object target)
    {
        HostPluginContext.Wire(target, this);
    }

    public void Dispose()
    {
        PluginHost.CurrentContext = _previousContext!;
    }
}

/// <summary>
/// Static helper for starting an in-memory testing session.
/// </summary>
public static class ExoTestHost
{
    /// <summary>
    /// Starts an isolated in-memory test context for unit testing plugins.
    /// Use inside a <c>using</c> block to automatically restore ambient state when the test finishes.
    /// </summary>
    public static ExoTestContext Start(string pluginId = "test_plugin") => new(pluginId);
}
