using System.Collections.Generic;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Ambient execution context provided to an active plugin.
/// </summary>
public interface IPluginContext
{
    string PluginId { get; }
    IDatabase Database { get; }
    IEventDispatcher Events { get; }
    IActionDispatcher Actions { get; }
    ILogger Logger { get; }
}

/// <summary>
/// The plugin's isolated data store: a typed record key/value surface plus a typed SQL runner.
/// Values are plain records; JSON never appears in plugin code. The native host transport is
/// synchronous, so this API is too.
/// </summary>
public interface IDatabase
{
    /// <summary>Reads a record, or <c>null</c> when the key is absent.</summary>
    T? Get<T>(string table, string key);

    /// <summary>Reads every record in a table.</summary>
    IReadOnlyList<T> All<T>(string table);

    /// <summary>Writes (or overwrites) a record.</summary>
    void Put<T>(string table, string key, T value);

    /// <summary>Removes a record.</summary>
    void Delete(string table, string key);

    /// <summary>
    /// Runs a query and maps each row to <typeparamref name="T"/> (column names bind to record
    /// members, snake_case). Use <c>$1, $2, ...</c> placeholders for the arguments.
    /// </summary>
    IReadOnlyList<T> Query<T>(string sql, params object?[] args);

    /// <summary>Runs a query and maps the first row to <typeparamref name="T"/>, or <c>default</c>.</summary>
    T? QuerySingle<T>(string sql, params object?[] args);

    /// <summary>Runs a statement (INSERT/UPDATE/DELETE) and returns the affected row count.</summary>
    int Execute(string sql, params object?[] args);
}

/// <summary>
/// Event broadcasting interface for emitting BEAM cluster events.
/// </summary>
public interface IEventDispatcher
{
    Task EmitAsync<T>(string eventName, T payload, string? topic = null);
}

/// <summary>
/// Inter-plugin action invocation interface.
/// </summary>
public interface IActionDispatcher
{
    Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload);

    /// <summary>
    /// Calls another service's action and returns its result synchronously. The native host
    /// transport is synchronous, so plugin actions (which are sync) can use this directly.
    /// </summary>
    TResponse? CallAction<TResponse>(string service, string action, object payload);
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
