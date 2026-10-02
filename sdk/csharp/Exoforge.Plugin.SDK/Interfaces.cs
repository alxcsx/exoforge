using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Lifecycle interface for Exoforge plugins.
/// </summary>
public interface IExoforgePlugin
{
    string Id { get; }
    string Version { get; }
    Task OnInitAsync(IPluginContext context);
    Task OnShutdownAsync();
}

/// <summary>
/// Ambient execution context provided to an active plugin.
/// </summary>
public interface IPluginContext
{
    string PluginId { get; }
    IDatabase Database { get; }
    IEventDispatcher Events { get; }
    IActionDispatcher Actions { get; }
    IEntityManager Entities { get; }
    ILogger Logger { get; }
}

/// <summary>
/// Stateful entity actor invocation interface.
/// </summary>
public interface IEntityManager
{
    Task<TResponse?> CallAsync<TResponse>(string plugin, string type, string id, object message);
    Task CastAsync(string plugin, string type, string id, object message);
    Task StopAsync(string plugin, string type, string id);
}

/// <summary>
/// Isolated multi-tenant database abstraction for plugins.
/// </summary>
public interface IDatabase
{
    Task<List<Dictionary<string, object>>> ExecuteAsync(string operation, object[]? args = null);
    Task<Dictionary<string, object>?> GetAsync(string table, string key);
    Task PutAsync(string table, string key, object value);
    Task DeleteAsync(string table, string key);
    Task<List<Dictionary<string, object>>> QueryAsync(string query, object[]? args = null);
    Task<Dictionary<string, object>?> QuerySingleAsync(string query, object[]? args = null);
    Task<object?> ExecuteScalarAsync(string query, object[]? args = null);
    Task<TResult> TransactionAsync<TResult>(Func<IDatabase, Task<TResult>> action);
}

/// <summary>
/// Event broadcasting interface for emitting BEAM cluster events.
/// </summary>
public interface IEventDispatcher
{
    Task EmitAsync(string eventName, object payload, string? topic = null);
}

/// <summary>
/// Inter-plugin action invocation interface.
/// </summary>
public interface IActionDispatcher
{
    Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload);
}

/// <summary>
/// Structured logging interface routed to kernel logger.
/// </summary>
public interface ILogger
{
    void Debug(string message);
    void Info(string message);
    void Warning(string message);
    void Error(string message);
}
