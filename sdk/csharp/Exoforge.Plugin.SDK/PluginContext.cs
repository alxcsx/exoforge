using System;
using System.Collections.Generic;
using System.Reflection;
using System.Text.Json;
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
    /// </summary>
    public static void Wire(object target, IPluginContext context)
    {
        if (target == null || context == null) return;

        var type = target.GetType();
        var props = type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);

        foreach (var prop in props)
        {
            var inject = prop.GetCustomAttribute<InjectAttribute>();
            if (inject == null || !prop.CanWrite) continue;

            if (prop.PropertyType == typeof(IDatabase))
            {
                prop.SetValue(target, context.Database);
            }
            else if (prop.PropertyType == typeof(IEventDispatcher))
            {
                prop.SetValue(target, context.Events);
            }
            else if (prop.PropertyType == typeof(IActionDispatcher))
            {
                prop.SetValue(target, context.Actions);
            }
            else if (prop.PropertyType == typeof(IEntityManager))
            {
                prop.SetValue(target, context.Entities);
            }
            else if (prop.PropertyType == typeof(ILogger))
            {
                prop.SetValue(target, context.Logger);
            }
            else if (prop.PropertyType == typeof(IPluginContext))
            {
                prop.SetValue(target, context);
            }
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

    public Task<Dictionary<string, object>?> GetAsync(string table, string key)
    {
        string? json = HostBridge.DbGet(table, key);
        if (string.IsNullOrEmpty(json))
        {
            return Task.FromResult<Dictionary<string, object>?>(null);
        }

        try
        {
            var result = JsonSerializer.Deserialize<Dictionary<string, object>>(json);
            return Task.FromResult<Dictionary<string, object>?>(result);
        }
        catch
        {
            return Task.FromResult<Dictionary<string, object>?>(null);
        }
    }

    public Task PutAsync(string table, string key, object value)
    {
        HostBridge.DbPut(table, key, value);
        return Task.CompletedTask;
    }

    public Task DeleteAsync(string table, string key)
    {
        HostBridge.DbDelete(table, key);
        return Task.CompletedTask;
    }

    public Task<List<Dictionary<string, object>>> ExecuteAsync(string operation, object[]? args = null)
    {
        string? json = HostBridge.DbExecute(operation, args);
        if (string.IsNullOrEmpty(json))
        {
            return Task.FromResult(new List<Dictionary<string, object>>());
        }

        try
        {
            var result = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(json);
            return Task.FromResult(result ?? new List<Dictionary<string, object>>());
        }
        catch
        {
            return Task.FromResult(new List<Dictionary<string, object>>());
        }
    }

    public Task<List<Dictionary<string, object>>> QueryAsync(string query, object[]? args = null)
    {
        return ExecuteAsync(query, args);
    }

    public async Task<Dictionary<string, object>?> QuerySingleAsync(string query, object[]? args = null)
    {
        var rows = await QueryAsync(query, args);
        return rows.Count > 0 ? rows[0] : null;
    }

    public async Task<object?> ExecuteScalarAsync(string query, object[]? args = null)
    {
        var row = await QuerySingleAsync(query, args);
        if (row != null && row.Count > 0)
        {
            using var enumerator = row.Values.GetEnumerator();
            if (enumerator.MoveNext())
            {
                return enumerator.Current;
            }
        }
        return null;
    }

    public async Task<TResult> TransactionAsync<TResult>(Func<IDatabase, Task<TResult>> action)
    {
        return await action(this);
    }
}

public class HostEventDispatcher : IEventDispatcher
{
    public Task EmitAsync(string eventName, object payload, string? topic = null)
    {
        HostBridge.EmitEvent(topic ?? "", eventName, payload);
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

