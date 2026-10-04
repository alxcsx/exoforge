using System;
using System.Collections.Generic;
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
    public IEntityManager Entities { get; }
    public ILogger Logger { get; }

    public HostPluginContext(string pluginId)
    {
        PluginId = pluginId;
        Database = new HostDatabase(pluginId);
        Events = new HostEventDispatcher();
        Actions = new HostActionDispatcher();
        Entities = new HostEntityManager();
        Logger = new HostLogger();
    }

    /// <summary>
    /// Inspects plugin object properties and injects services decorated with [Inject].
    /// Handles both instance and static members, so plain (non-<see cref="PluginBehaviour"/>) plugins
    /// used with <see cref="PluginHost"/> get their dependencies too.
    /// </summary>
    public static void Wire(object target, IPluginContext context)
    {
        if (target == null || context == null) return;

        var type = target.GetType();
        var props = type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);

        foreach (var prop in props)
        {
            var inject = prop.GetCustomAttribute<InjectAttribute>();
            if (inject == null || !prop.CanWrite) continue;

            object? value =
                prop.PropertyType == typeof(IDatabase) ? context.Database :
                prop.PropertyType == typeof(IEventDispatcher) ? context.Events :
                prop.PropertyType == typeof(IActionDispatcher) ? context.Actions :
                prop.PropertyType == typeof(IEntityManager) ? context.Entities :
                prop.PropertyType == typeof(ILogger) ? context.Logger :
                prop.PropertyType == typeof(IPluginContext) ? context :
                null;

            // Generated service clients are registered by their module initializer; inject them too,
            // so plugin code only ever deals with services.
            if (value == null)
            {
                PluginServiceRegistry.TryCreate(prop.PropertyType, context.Actions, out value);
            }

            if (value == null) continue;

            if (prop.GetMethod?.IsStatic == true) prop.SetValue(null, value);
            else prop.SetValue(target, value);
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

    public T? Get<T>(string table, string key)
    {
        string? json = HostBridge.DbGet(table, key);
        return string.IsNullOrEmpty(json) ? default : PluginJson.Deserialize<T>(json);
    }

    public IReadOnlyList<T> All<T>(string table)
    {
        string? json = HostBridge.DbAll(table);
        if (string.IsNullOrEmpty(json)) return Array.Empty<T>();

        var rows = new List<T>();

        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var row in doc.RootElement.EnumerateArray())
            {
                if (PluginJson.Deserialize(row.GetRawText(), typeof(T)) is T value)
                {
                    rows.Add(value);
                }
            }
        }

        return rows;
    }

    public void Put<T>(string table, string key, T value)
    {
        HostBridge.DbPut(table, key, PluginJson.Serialize(value));
    }

    public void Delete(string table, string key)
    {
        HostBridge.DbDelete(table, key);
    }

    public IReadOnlyList<T> Query<T>(string sql, params object?[] args)
    {
        var rows = RunSql(sql, args, out _);
        if (rows is null) return Array.Empty<T>();

        var list = new List<T>();
        foreach (var row in rows.Value.EnumerateArray())
        {
            if (PluginJson.Deserialize(row.GetRawText(), typeof(T)) is T value)
            {
                list.Add(value);
            }
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
    public Task EmitAsync<T>(string eventName, T payload, string? topic = null)
    {
        HostBridge.EmitEvent(topic ?? "", eventName, payload!);
        return Task.CompletedTask;
    }
}

public class HostActionDispatcher : IActionDispatcher
{
    public Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload)
    {
        var response = HostBridge.CallAction<TResponse>(service, action, payload);
        return Task.FromResult(response);
    }

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

public class HostEntityManager : IEntityManager
{
    public Task<TResponse?> CallAsync<TResponse>(string plugin, string type, string id, object message)
    {
        var response = HostBridge.CallAction<TResponse>($"{plugin}:{type}:{id}", "call", message);
        return Task.FromResult(response);
    }

    public Task CastAsync(string plugin, string type, string id, object message)
    {
        HostBridge.CallAction($"{plugin}:{type}:{id}", "cast", message);
        return Task.CompletedTask;
    }

    public Task StopAsync(string plugin, string type, string id)
    {
        HostBridge.CallAction($"{plugin}:{type}:{id}", "stop", new { });
        return Task.CompletedTask;
    }
}

