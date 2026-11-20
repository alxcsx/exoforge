using System;
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
    string? CallerPlayerId { get; }
    IReadOnlyList<string> CallerScopes { get; }
    /// <summary>The game version the calling client reported at sign-in; null for a call that carries none.</summary>
    string? CallerGameVersion { get; }
}

/// <summary>
/// Write-only batch recorder for <see cref="IDatabase.Transaction"/>.
/// The callback only records write operations (<see cref="Execute"/>, <see cref="Put{T}"/>,
/// <see cref="Delete"/>); no reads (<c>Get</c>, <c>All</c>, <c>Query</c>) are available inside
/// a transaction callback because recorded operations are sent to the host after the callback
/// returns and executed atomically in a single <c>db_batch</c> transaction round trip.
/// </summary>
public interface ITransaction
{
    /// <summary>Records a write (or overwrite) of a record.</summary>
    void Put<T>(string table, string key, T value);

    /// <summary>Records the removal of a record.</summary>
    void Delete(string table, string key);

    /// <summary>Records a SQL write statement (INSERT/UPDATE/DELETE) with positional <c>$1, $2, ...</c> arguments.</summary>
    void Execute(string sql, params object?[] args);
}

/// <summary>
/// The plugin's isolated data store: a typed record key/value surface plus a typed SQL runner.
/// Values are plain records; JSON never appears in plugin code. These members are the synchronous
/// surface; <see cref="HostBridge"/> carries the async twins, which keep a thread free while the
/// host answers.
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

    /// <summary>
    /// Records write operations (<c>Execute</c>, <c>ExecuteSql</c>, <c>Put</c>, <c>Delete</c>) via
    /// <paramref name="tx"/> and executes them atomically in a single <c>db_batch</c> round trip.
    /// The callback only records operations; reads are not permitted inside it.
    /// </summary>
    void Transaction(Action<ITransaction> tx)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        var recorder = new BatchTransactionRecorder();
        tx(recorder);
        ExecuteBatch(recorder.Operations);
    }

    /// <summary>
    /// Executes an ordered sequence of write operations atomically in a single <c>db_batch</c> round trip.
    /// </summary>
    void ExecuteBatch(IEnumerable<DbBatchOperation> operations)
    {
        if (operations == null) throw new ArgumentNullException(nameof(operations));
        foreach (var op in operations)
        {
            if (op == null) throw new ArgumentException("Batch operations cannot contain null elements.", nameof(operations));
            switch (op.Action)
            {
                case "put":
                    Put<object?>(op.Table ?? "", op.Key ?? "", op.Value);
                    break;
                case "delete":
                    Delete(op.Table ?? "", op.Key ?? "");
                    break;
                case "execute":
                    Execute(op.Sql ?? "", op.Args ?? Array.Empty<object?>());
                    break;
                default:
                    throw new InvalidOperationException($"Unsupported batch operation '{op.Action}'.");
            }
        }
    }
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
    /// Calls another service's action and returns its result synchronously. It waits on the same
    /// multiplexed connection the async call uses; prefer <see cref="CallActionAsync{TResponse}"/>
    /// where the caller can await.
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
