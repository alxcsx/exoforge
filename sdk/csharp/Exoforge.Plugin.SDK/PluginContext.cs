using System.Linq;
using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Default implementation of IPluginContext wiring injected dependencies and host capabilities.
/// </summary>
public class HostPluginContext : IPluginContext
{
    private static readonly Lazy<HostPluginContext> _defaultInstance = new(() => new HostPluginContext("plugin"));
    public static HostPluginContext Default => _defaultInstance.Value;

    public string PluginId { get; }
    public IDatabase Database { get; }
    public IEventDispatcher Events { get; }
    public IActionDispatcher Actions { get; }
    public ILogger Logger { get; }
    public string? CallerPlayerId { get; private set; }
    public IReadOnlyList<string> CallerScopes { get; private set; } = Array.Empty<string>();
    public string? CallerGameVersion { get; private set; }

    public HostPluginContext(string pluginId)
    {
        PluginId = pluginId;
        Database = new HostDatabase(pluginId);
        Events = new HostEventDispatcher();
        Actions = new HostActionDispatcher();
        Logger = new HostLogger();
    }

    public void UpdateCaller(string? playerId, IReadOnlyList<string>? scopes, string? gameVersion = null)
    {
        CallerPlayerId = playerId;
        CallerScopes = scopes ?? Array.Empty<string>();
        CallerGameVersion = gameVersion;
    }

    /// <summary>
    /// Configures the ambient <c>Exo</c> context and injects capabilities into matching properties on <paramref name="target"/>.
    /// </summary>
    public static void Wire(object target, IPluginContext context)
    {
        if (context != null) PluginHost.CurrentContext = context;
        if (target == null || context == null) return;

        const BindingFlags flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
        foreach (var prop in target.GetType().GetProperties(flags))
        {
            if (!prop.CanWrite) continue;
            if (prop.PropertyType == typeof(IDatabase)) prop.SetValue(target, context.Database);
            else if (prop.PropertyType == typeof(ILogger)) prop.SetValue(target, context.Logger);
            else if (prop.PropertyType == typeof(IEventDispatcher)) prop.SetValue(target, context.Events);
            else if (prop.PropertyType == typeof(IActionDispatcher)) prop.SetValue(target, context.Actions);
            else if (prop.PropertyType == typeof(IPluginContext)) prop.SetValue(target, context);
        }
    }
}

public class HostDatabase : IDatabase
{
    public string PluginId { get; }

    public HostDatabase(string pluginId)
    {
        PluginId = pluginId;
    }

    private static void CheckDbError(string table, string? json) =>
        ExoDatabaseException.ThrowIfError(table, json);

    public T? Get<T>(string table, string key)
    {
        if (ForkedTable<T>(table)) return GetForked<T>(table, key);

        string? json = HostBridge.DbGet(table, key);
        CheckDbError(table, json);
        if (string.IsNullOrEmpty(json)) return default;

        using var doc = JsonDocument.Parse(json);
        return ReadRow<T>(table, key, doc.RootElement) is { } row ? row : default;
    }

    /// <summary>
    /// A stored row as <typeparamref name="T"/>. A row written under an older extension version is brought up to
    /// date first and written back (guarded by its old stamp, so a lost race changes nothing here).
    /// </summary>
    private T? ReadRow<T>(string table, string? key, JsonElement row)
    {
        var info = RowMigrations.InfoFor(typeof(T));
        if (!info.Active || info.Fork || RowMigrations.Suppressed) return PluginJson.DeserializeDatabaseRow<T>(row.GetRawText());

        if (RowMigrations.StampOf(row) is long stamp)
        {
            // A row a breaking change has already reshaped cannot be read by a client built before it.
            if (ExoDispatch.CallerLockedVersion() is long locked && RowMigrations.FloorOf(typeof(T), stamp) > locked)
            {
                throw new ExoActionException("client_outdated", "This data was written by a newer version of the game; update the game to continue.");
            }

            // A client built before the newest step must not see a half-migrated row, nor trigger the write-back.
            bool callerBehind = ExoDispatch.CallerLockedVersion() is long behind && behind < RowMigrations.TargetOf(typeof(T));

            if (!callerBehind && RowMigrations.PendingFrom<T>(row) is long pending)
            {
                T upgraded = RowMigrations.Upgrade<T>(row, pending);
                if (info.Mode == RowMigrationMode.WriteBack)
                {
                    HostBridge.DbPut(table, key ?? EntityMetadata<T>.GetKey(upgraded), RowMigrations.WithGuard(upgraded!, pending));
                }

                return upgraded;
            }
        }

        return PluginJson.DeserializeDatabaseRow<T>(row.GetRawText());
    }

    // ---- forked resources: one table per generation ----

    private static bool ForkedTable<T>(string table) =>
        RowMigrations.InfoFor(typeof(T)).Fork && table == EntityMetadata<T>.TableName;

    internal static string GenerationTable(string table, long generation) =>
        generation == 0 ? table : table + "_g" + generation.ToString(System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>The caller's generation first, then each older one down to the original table.</summary>
    private static IEnumerable<long> GenerationsFor<T>()
    {
        long own = ExoDispatch.CallerGeneration(typeof(T));
        yield return own;
        foreach (long generation in System.Linq.Enumerable.Reverse(RowMigrations.Generations(typeof(T))))
        {
            if (generation < own) yield return generation;
        }

        if (own != 0) yield return 0;
    }

    private string? TryGet(string table, string key)
    {
        try
        {
            string? json = HostBridge.DbGet(table, key);
            ExoDatabaseException.ThrowIfError(table, json);
            return json;
        }
        catch (ExoDatabaseException)
        {
            // An older generation's table may not exist on this instance: nothing is stored there.
            return null;
        }
    }

    private T? GetForked<T>(string table, string key)
    {
        long own = ExoDispatch.CallerGeneration(typeof(T));
        foreach (long generation in GenerationsFor<T>())
        {
            string? json = TryGet(GenerationTable(table, generation), key);
            if (string.IsNullOrEmpty(json)) continue;

            using var doc = JsonDocument.Parse(json);
            return generation == own
                ? PluginJson.DeserializeDatabaseRow<T>(doc.RootElement.GetRawText())
                : RowMigrations.Upgrade<T>(doc.RootElement, generation, own);
        }

        return default;
    }

    /// <summary>
    /// Writes the rows only an older generation has into the caller's generation (each brought forward through the
    /// breaking migrations), so the new generation starts as a copy. Returns how many were copied.
    /// </summary>
    internal int DuplicateGeneration<T>()
    {
        string table = EntityMetadata<T>.TableName;
        long own = ExoDispatch.CallerGeneration(typeof(T));
        var ownKeys = new HashSet<string>(ReadGeneration<T>(table, own).Select(e => EntityMetadata<T>.GetKey(e)));

        int copied = 0;
        foreach (long generation in GenerationsFor<T>().Where(g => g != own))
        {
            foreach (var row in ReadGeneration<T>(table, generation, own))
            {
                if (!ownKeys.Add(EntityMetadata<T>.GetKey(row))) continue;
                Put(table, EntityMetadata<T>.GetKey(row), row);
                copied++;
            }
        }

        return copied;
    }

    /// <summary>
    /// For rows both the caller's generation and an older one have, copies the named properties (the columns the
    /// generations share) from the older row into the caller's. Returns how many rows changed.
    /// </summary>
    internal int SyncGeneration<T>(params string[] properties)
    {
        string table = EntityMetadata<T>.TableName;
        long own = ExoDispatch.CallerGeneration(typeof(T));
        var mine = ReadGeneration<T>(table, own).ToDictionary(e => EntityMetadata<T>.GetKey(e));
        var wanted = new HashSet<string>(properties, StringComparer.OrdinalIgnoreCase);

        int changed = 0;
        foreach (long generation in GenerationsFor<T>().Where(g => g < own))
        {
            foreach (var older in ReadGeneration<T>(table, generation, own))
            {
                string key = EntityMetadata<T>.GetKey(older);
                if (!mine.TryGetValue(key, out var current)) continue;

                var target = System.Text.Json.Nodes.JsonNode.Parse(PluginJson.Serialize(current))!.AsObject();
                var source = System.Text.Json.Nodes.JsonNode.Parse(PluginJson.Serialize(older))!.AsObject();
                foreach (var pair in source.ToList())
                {
                    if (wanted.Contains(pair.Key)) target[pair.Key] = pair.Value?.DeepClone();
                }

                var updated = PluginJson.DeserializeDatabaseRow<T>(target.ToJsonString());
                if (updated is null) continue;
                Put(table, key, updated);
                mine[key] = updated;
                changed++;
            }
        }

        return changed;
    }

    // One generation's rows; those of an older one are brought forward to <paramref name="upTo"/> (the caller's own).
    private List<T> ReadGeneration<T>(string table, long generation, long upTo = 0)
    {
        var rows = new List<T>();
        string? json;
        try
        {
            json = HostBridge.DbAll(GenerationTable(table, generation));
            ExoDatabaseException.ThrowIfError(table, json);
        }
        catch (ExoDatabaseException)
        {
            return rows;
        }

        if (string.IsNullOrEmpty(json)) return rows;
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Array) return rows;

        foreach (var row in doc.RootElement.EnumerateArray())
        {
            T? value = generation == upTo || upTo == 0
                ? PluginJson.DeserializeDatabaseRow<T>(row.GetRawText())
                : RowMigrations.Upgrade<T>(row, generation, upTo);
            if (value is not null) rows.Add(value);
        }

        return rows;
    }

    private IReadOnlyList<T> AllForked<T>(string table)
    {
        long own = ExoDispatch.CallerGeneration(typeof(T));
        var seen = new HashSet<string>();
        var rows = new List<T>();

        foreach (long generation in GenerationsFor<T>())
        {
            string? json;
            try
            {
                json = HostBridge.DbAll(GenerationTable(table, generation));
                ExoDatabaseException.ThrowIfError(table, json);
            }
            catch (ExoDatabaseException)
            {
                continue;
            }

            if (string.IsNullOrEmpty(json)) continue;
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) continue;

            foreach (var row in doc.RootElement.EnumerateArray())
            {
                T? value = generation == own
                    ? PluginJson.DeserializeDatabaseRow<T>(row.GetRawText())
                    : RowMigrations.Upgrade<T>(row, generation, own);
                if (value is not null && seen.Add(EntityMetadata<T>.GetKey(value))) rows.Add(value);
            }
        }

        return rows;
    }

    /// <summary>
    /// The sweeper's unit of work: migrates up to <paramref name="limit"/> rows of <typeparamref name="T"/> that
    /// are still stamped below its newest row migration, so rows of players who never come back catch up too.
    /// Returns how many it touched; 0 means the table is current.
    /// </summary>
    internal int MigrateBatch<T>(int limit)
    {
        string table = EntityMetadata<T>.TableName;
        var rows = RunSql($"SELECT * FROM \"{table}\" WHERE _v < $1 ORDER BY _v LIMIT $2",
            new object?[] { RowMigrations.TargetOf(typeof(T)), limit }, out _);
        if (rows is null) return 0;

        int migrated = 0;
        foreach (var row in rows.Value.EnumerateArray())
        {
            if (RowMigrations.PendingFrom<T>(row) is null) continue;
            ReadRow<T>(table, null, row);
            migrated++;
        }

        return migrated;
    }

    /// <summary>One throttled pass over every migrated record type; stops at <paramref name="limit"/> rows.</summary>
    internal int MigrateBatch(int limit)
    {
        int done = 0;
        foreach (var type in RowMigrations.MigratedTypes())
        {
            var method = System.Linq.Enumerable.First(typeof(HostDatabase).GetMethods(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic),
                m => m.Name == nameof(MigrateBatch) && m.IsGenericMethodDefinition)
                .MakeGenericMethod(type);
            done += (int)method.Invoke(this, new object[] { limit - done })!;
            if (done >= limit) break;
        }

        return done;
    }

    public IReadOnlyList<T> All<T>(string table)
    {
        if (ForkedTable<T>(table)) return AllForked<T>(table);

        string? json = HostBridge.DbAll(table);
        CheckDbError(table, json);
        if (string.IsNullOrEmpty(json)) return Array.Empty<T>();

        var rows = new List<T>();

        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var row in doc.RootElement.EnumerateArray())
            {
                if (ReadRow<T>(table, null, row) is { } value)
                {
                    rows.Add(value);
                }
            }
        }

        return rows;
    }

    public void Put<T>(string table, string key, T value)
    {
        if (ForkedTable<T>(table)) table = GenerationTable(table, ExoDispatch.CallerGeneration(typeof(T)));
        bool ok = HostBridge.DbPut(table, key, PluginJson.Serialize(value));
        if (!ok)
        {
            throw new ExoDatabaseException(table, "Database put operation failed");
        }
    }

    public void Delete(string table, string key)
    {
        bool ok = HostBridge.DbDelete(table, key);
        if (!ok)
        {
            throw new ExoDatabaseException(table, "Database delete operation failed");
        }
    }

    public IReadOnlyList<T> Query<T>(string sql, params object?[] args)
    {
        var rows = RunSql(sql, args, out _);
        if (rows is null) return Array.Empty<T>();

        var list = new List<T>();
        bool migrates = RowMigrations.InfoFor(typeof(T)) is { Active: true, Fork: false };
        foreach (var row in rows.Value.EnumerateArray())
        {
            // A typed resource read through SQL is brought forward like one read by key (a projection has no _v and is left).
            T? value = migrates
                ? ReadRow<T>(EntityMetadata<T>.TableName, null, row)
                : PluginJson.DeserializeDatabaseRow(row.GetRawText(), typeof(T)) is T plain ? plain : default;
            if (value is not null) list.Add(value);
        }

        return list;
    }

    public T? QuerySingle<T>(string sql, params object?[] args)
    {
        var rows = Query<T>(sql, args);
        return rows.Count > 0 ? rows[0] : default;
    }

    public int Execute(string sql, params object?[] args)
    {
        RunSql(sql, args, out int affected);
        return affected;
    }

    public void Transaction(Action<ITransaction> tx)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        var recorder = new BatchTransactionRecorder();
        tx(recorder);
        ExecuteBatch(recorder.Operations);
    }

    public void ExecuteBatch(IEnumerable<DbBatchOperation> operations)
    {
        if (operations == null) throw new ArgumentNullException(nameof(operations));

        var array = new JsonArray();
        foreach (var op in operations)
        {
            if (op == null) throw new ArgumentException("Batch operations cannot contain null elements.", nameof(operations));

            switch (op.Action)
            {
                case "execute":
                    array.Add(new JsonObject
                    {
                        ["action"] = "execute",
                        ["sql"] = op.Sql ?? "",
                        ["args"] = JsonNode.Parse(PluginJson.Serialize(op.Args ?? Array.Empty<object?>()))
                    });
                    break;

                case "put":
                    array.Add(new JsonObject
                    {
                        ["action"] = "put",
                        ["table"] = op.Table ?? "",
                        ["key"] = op.Key ?? "",
                        ["value"] = JsonNode.Parse(op.ValueJson ?? PluginJson.Serialize(op.Value))
                    });
                    break;

                case "delete":
                    array.Add(new JsonObject
                    {
                        ["action"] = "delete",
                        ["table"] = op.Table ?? "",
                        ["key"] = op.Key ?? ""
                    });
                    break;

                default:
                    throw new InvalidOperationException($"Unsupported batch operation '{op.Action}'.");
            }
        }

        if (array.Count == 0) return;

        bool ok = HostBridge.DbBatch(array);
        if (!ok)
        {
            throw new ExoDatabaseException("batch", "Database batch operation failed");
        }
    }

    /// <summary>Runs SQL through the <c>:database</c> service and returns its rows array.</summary>
    private JsonElement? RunSql(string sql, object?[] args, out int affected)
    {
        affected = 0;

        var payload = new JsonObject
        {
            ["plugin"] = PluginId,
            ["query"] = sql,
            ["args"] = JsonNode.Parse(PluginJson.Serialize(args ?? Array.Empty<object?>()))
        };

        string? raw = HostBridge.CallActionRaw("database", "execute", payload);
        if (raw is null)
        {
            throw new InvalidOperationException("SQL call failed: the :database service is unavailable.");
        }

        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement;

        if (root.ValueKind == JsonValueKind.Object)
        {
            if (root.TryGetProperty("error", out var error))
            {
                throw new InvalidOperationException($"SQL failed: {error}");
            }

            if (root.TryGetProperty("num_rows", out var num) && num.ValueKind == JsonValueKind.Number)
            {
                affected = num.GetInt32();
            }

            return root.TryGetProperty("rows", out var rows) && rows.ValueKind == JsonValueKind.Array
                ? rows.Clone()
                : null;
        }

        return root.ValueKind == JsonValueKind.Array ? root.Clone() : null;
    }
}

public class HostEventDispatcher : IEventDispatcher
{
    public Task EmitAsync<T>(string eventName, T payload, string? topic = null) =>
        HostBridge.EmitEventAsync(topic ?? "", eventName, payload!);
}

public class HostActionDispatcher : IActionDispatcher
{
    public Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload) =>
        HostBridge.CallActionAsync<TResponse>(service, action, payload);

    public TResponse? CallAction<TResponse>(string service, string action, object payload)
    {
        return HostBridge.CallAction<TResponse>(service, action, payload);
    }
}

public class HostLogger : ILogger
{
    public void Debug(string message) => HostBridge.Log(0, message);
    public void Info(string message) => HostBridge.LogInfo(message);
    public void Warning(string message) => HostBridge.LogWarning(message);
    public void Error(string message) => HostBridge.LogError(message);
}

