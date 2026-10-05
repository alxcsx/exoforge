using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Host transport used by a plugin when it runs as a native process instead of a WASM guest.
/// </summary>
public interface IPluginTransport
{
    bool EmitEvent(string topic, string evt, string payloadJson);
    string? CallAction(string service, string action, string payloadJson);
    void Log(int level, string message);
    string? DbGet(string table, string key);
    string? DbAll(string table);
    bool DbPut(string table, string key, string valueJson);
    bool DbDelete(string table, string key);
    long ClockNow();
}

/// <summary>
/// Runs a C# plugin as a native host process.
///
/// Wire it up from the plugin's entry point:
/// <code>public static void Main() =&gt; PluginHost.Run&lt;SnakeServerPlugin&gt;();</code>
///
/// The host spawns the binary and speaks newline-delimited JSON over stdin/stdout:
/// <code>
/// host  -> plugin   {"type":"action","id":1,"action":"move","payload":{"x":1}}
/// plugin -> host    {"type":"action_result","id":1,"status":"ok","data":1}
/// plugin -> host    {"type":"host_call","id":7,"op":"emit_event","args":{...}}
/// host  -> plugin   {"type":"host_call_result","id":7,"result":true}
/// </code>
/// Host calls are synchronous: the plugin writes a request and reads the matching reply.
/// </summary>
public static class PluginHost
{
    private static readonly object WriteLock = new();
    private static Stream? _stdout;
    private static long _nextHostCallId;
    private static object? _instance;
    private static MethodInfo? _eventHandler;

    /// <summary>Runs <typeparamref name="T"/> until stdin closes.</summary>
    /// <remarks>
    /// The <see cref="DynamicallyAccessedMembersAttribute"/> keeps the plugin's action methods
    /// (and their parameter names) alive through NativeAOT trimming — they are only reached by
    /// reflection.
    /// </remarks>
    public static void Run<[DynamicallyAccessedMembers(
        DynamicallyAccessedMemberTypes.PublicMethods |
        DynamicallyAccessedMemberTypes.NonPublicMethods |
        DynamicallyAccessedMemberTypes.PublicProperties |
        DynamicallyAccessedMemberTypes.NonPublicProperties |
        DynamicallyAccessedMemberTypes.PublicParameterlessConstructor)] T>()
        where T : class, new() => RunInstance(new T());

    /// <summary>
    /// Runs <typeparamref name="T"/> with a source-generated <see cref="JsonSerializerContext"/>.
    /// This is the NativeAOT-safe overload: reflection-based JSON is disabled in AOT, so typed
    /// action arguments, results, event payloads and stored records need a context.
    /// </summary>
    public static void Run<[DynamicallyAccessedMembers(
        DynamicallyAccessedMemberTypes.PublicMethods |
        DynamicallyAccessedMemberTypes.NonPublicMethods |
        DynamicallyAccessedMemberTypes.PublicProperties |
        DynamicallyAccessedMemberTypes.NonPublicProperties |
        DynamicallyAccessedMemberTypes.PublicParameterlessConstructor)] T, TContext>()
        where T : class, new()
        where TContext : JsonSerializerContext, new()
    {
        // Add (not replace): generated contract stubs may have already registered their own context.
        PluginJson.AddContext(new TContext());
        RunInstance(new T());
    }

    /// <summary>Runs a plugin instance until stdin closes.</summary>
    public static int RunInstance(object instance)
    {
        _stdout = Console.OpenStandardOutput();
        HostBridge.UseTransport(new NativeTransport());

        _instance = instance;
        var pluginType = instance.GetType();

        // Wire [Inject] dependencies (including static properties on plain plugin classes).
        HostPluginContext.Wire(instance, new HostPluginContext(ResolvePluginId(pluginType)));

        var actions = BuildActionTable(pluginType);
        _eventHandler = FindEventHandler(pluginType);

        using var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);

        while (reader.ReadLine() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (IsEventFrame(line))
            {
                DispatchEvent(line);
            }
            else
            {
                Dispatch(line, instance, actions);
            }
        }

        return 0;
    }

    /// <summary>
    /// Resolves the plugin's inbound event handler: <c>OnEvent(string, TPayload)</c> for any
    /// payload type, or <c>OnEvent(string)</c>. Optional — plugins that ignore events need not
    /// define it.
    /// </summary>
    private static MethodInfo? FindEventHandler(Type pluginType)
    {
        const BindingFlags flags =
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;

        foreach (var method in pluginType.GetMethods(flags))
        {
            if (method.Name != "OnEvent") continue;

            var parameters = method.GetParameters();
            if (parameters.Length == 1 && parameters[0].ParameterType == typeof(string)) return method;
            if (parameters.Length == 2 && parameters[0].ParameterType == typeof(string)) return method;
        }

        return null;
    }

    private static string ResolvePluginId(Type pluginType)
    {
        // ManifestGen derives the manifest id from the assembly name; the host keys the plugin's
        // isolated database (KV and SQL) by that id, so use the same source.
        return pluginType.Assembly.GetName().Name?.ToLowerInvariant() ?? pluginType.Name.ToLowerInvariant();
    }

    private static bool IsEventFrame(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            return doc.RootElement.TryGetProperty("type", out var type) && type.GetString() == "event";
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>Dispatches an inbound host event to the plugin's <c>OnEvent</c> handler.</summary>
    private static void DispatchEvent(string line)
    {
        if (_eventHandler == null)
        {
            return;
        }

        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;

            string name = root.TryGetProperty("event", out var eventProp) ? eventProp.GetString() ?? "" : "";
            JsonElement payload = root.TryGetProperty("payload", out var payloadProp) ? payloadProp : default;

            var parameters = _eventHandler.GetParameters();
            object?[] args;

            if (parameters.Length == 2)
            {
                var payloadType = parameters[1].ParameterType;
                object? value = payloadType == typeof(JsonElement)
                    ? payload.Clone()
                    : payload.ValueKind == JsonValueKind.Undefined
                        ? null
                        : PluginJson.Deserialize(payload.GetRawText(), payloadType);

                args = new object?[] { name, value };
            }
            else
            {
                args = new object?[] { name };
            }

            _eventHandler.Invoke(_instance, args);
        }
        catch (Exception ex)
        {
            Write($"{{\"type\":\"host_log\",\"level\":3,\"message\":{JsonEncode((ex as TargetInvocationException)?.InnerException?.Message ?? ex.Message)}}}");
        }
    }

    private static Dictionary<string, (MethodInfo Method, ParameterInfo[] Params)> BuildActionTable(Type pluginType)
    {
        var table = new Dictionary<string, (MethodInfo, ParameterInfo[])>(StringComparer.OrdinalIgnoreCase);

        foreach (var method in pluginType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance))
        {
            var attr = method.GetCustomAttribute<ExoActionAttribute>();

            if (attr != null)
            {
                string name = string.IsNullOrEmpty(attr.Name) ? ExoNaming.ToSnakeCase(method.Name) : attr.Name!;
                table[name] = (method, method.GetParameters());
            }
        }

        return table;
    }

    private static void Dispatch(string line, object? instance, Dictionary<string, (MethodInfo Method, ParameterInfo[] Params)> actions)
    {
        long id = 0;
        string action = "";

        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;

            id = root.TryGetProperty("id", out var idProp) ? idProp.GetInt64() : 0;
            action = root.TryGetProperty("action", out var actionProp) ? actionProp.GetString() ?? "" : "";

            if (!actions.TryGetValue(action, out var entry))
            {
                Write($"{{\"type\":\"action_result\",\"id\":{id},\"status\":\"error\",\"error\":\"unknown_action\"}}");
                return;
            }

            var payload = root.TryGetProperty("payload", out var payloadProp) ? payloadProp : default;
            object?[] args = BindArguments(entry.Params, payload);
            object? result = AwaitResult(entry.Method.Invoke(instance, args));

            Write($"{{\"type\":\"action_result\",\"id\":{id},\"status\":\"ok\",\"data\":{ToJson(result)}}}");
        }
        catch (Exception ex)
        {
            string message = JsonEncode((ex as TargetInvocationException)?.InnerException?.Message ?? ex.Message);
            Write($"{{\"type\":\"action_result\",\"id\":{id},\"status\":\"error\",\"error\":{message}}}");
        }
    }

    private static object?[] BindArguments(ParameterInfo[] parameters, JsonElement payload)
    {
        var args = new object?[parameters.Length];

        for (int i = 0; i < parameters.Length; i++)
        {
            var parameter = parameters[i];

            if (payload.ValueKind == JsonValueKind.Object &&
                TryGetArgument(payload, parameter.Name ?? "", out var value))
            {
                args[i] = ConvertElement(value, parameter.ParameterType);
            }
            else
            {
                args[i] = parameter.HasDefaultValue ? parameter.DefaultValue : DefaultOf(parameter.ParameterType);
            }
        }

        return args;
    }

    /// <summary>
    /// Matches a payload key to a parameter name, ignoring case and underscores
    /// (so JSON <c>snake_length</c> binds to the C# <c>snakeLength</c> parameter).
    /// </summary>
    private static bool TryGetArgument(JsonElement payload, string name, out JsonElement value)
    {
        string normalized = NormalizeName(name);

        foreach (var property in payload.EnumerateObject())
        {
            if (NormalizeName(property.Name) == normalized)
            {
                value = property.Value;
                return true;
            }
        }

        value = default;
        return false;
    }

    private static string NormalizeName(string name) => name.Replace("_", "").ToLowerInvariant();

    private static object? ConvertElement(JsonElement element, Type target)
    {
        if (target == typeof(int)) return element.GetInt32();
        if (target == typeof(long)) return element.GetInt64();
        if (target == typeof(double)) return element.GetDouble();
        if (target == typeof(float)) return (float)element.GetDouble();
        if (target == typeof(bool)) return element.GetBoolean();
        if (target == typeof(string)) return element.GetString();
        if (target == typeof(JsonElement)) return element.Clone();

        // Records / command objects: let the SDK's JSON layer do the conversion so plugin
        // code never sees raw JSON.
        if (element.ValueKind == JsonValueKind.Object || element.ValueKind == JsonValueKind.Array)
        {
            return PluginJson.Deserialize(element.GetRawText(), target);
        }

        return DefaultOf(target);
    }

    private static object? DefaultOf(Type type) => type.IsValueType ? Activator.CreateInstance(type) : null;

    /// <summary>
    /// Unwraps a <see cref="Task"/> returned by an async action. The native transport is synchronous,
    /// so the task is awaited to completion on the dispatch thread.
    /// </summary>
    private static object? AwaitResult(object? result)
    {
        if (result is not Task task)
        {
            return result;
        }

        task.GetAwaiter().GetResult();

        Type taskType = task.GetType();
        if (!taskType.IsGenericType)
        {
            return null;
        }

        // GenericTaskType roots Task<T>.Result for the trimmer (see below).
        _ = GenericTaskType;

#pragma warning disable IL2075 // Task<> metadata is rooted via GenericTaskType
        return taskType.GetProperty("Result")?.GetValue(task);
#pragma warning restore IL2075
    }

    /// <summary>
    /// Roots <c>Task&lt;T&gt;.Result</c> for reflection; NativeAOT trims the metadata otherwise and
    /// async action results would silently come back as <c>null</c>.
    /// </summary>
    [DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicProperties)]
    private static readonly Type GenericTaskType = typeof(Task<>);

    /// <summary>Serializes a plugin return value, routing collections and records through <see cref="PluginJson"/>.</summary>
    private static string ToJson(object? value) => value switch
    {
        null => "null",
        int i => i.ToString(),
        long l => l.ToString(),
        short s => s.ToString(),
        byte b => b.ToString(),
        bool bo => bo ? "true" : "false",
        double d => d.ToString(System.Globalization.CultureInfo.InvariantCulture),
        float f => f.ToString(System.Globalization.CultureInfo.InvariantCulture),
        string str => JsonEncode(str),
        JsonElement el => el.GetRawText(),
        System.Text.Json.Nodes.JsonNode node => node.ToJsonString(),
        _ => PluginJson.Serialize(value)
    };

    private static string JsonEncode(string value) => PluginJson.EncodeString(value);

    private static void Write(string json)
    {
        lock (WriteLock)
        {
            if (_stdout == null) return;

            byte[] bytes = Encoding.UTF8.GetBytes(json + "\n");
            _stdout.Write(bytes, 0, bytes.Length);
            _stdout.Flush();
        }
    }

    /// <summary>Issues a synchronous host call and returns the raw result JSON.</summary>
    private static string? HostCall(string op, string argsJson)
    {
        long id = ++_nextHostCallId;
        Write($"{{\"type\":\"host_call\",\"id\":{id},\"op\":{JsonEncode(op)},\"args\":{argsJson}}}");

        using var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);

        while (reader.ReadLine() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;

            try
            {
                using var doc = JsonDocument.Parse(line);
                var root = doc.RootElement;

                // Events may arrive while an action is blocked on a host call; handle them here
                // too so they are not dropped.
                if (root.TryGetProperty("type", out var frameType) && frameType.GetString() == "event")
                {
                    DispatchEvent(line);
                    continue;
                }

                if (root.TryGetProperty("type", out var typeProp) &&
                    typeProp.GetString() == "host_call_result" &&
                    root.TryGetProperty("id", out var idProp) &&
                    idProp.GetInt64() == id)
                {
                    if (!root.TryGetProperty("result", out var resultProp) || resultProp.ValueKind == JsonValueKind.Null)
                    {
                        return null;
                    }

                    return resultProp.GetRawText();
                }
            }
            catch (JsonException)
            {
                // ignore malformed lines
            }
        }

        return null;
    }

    private sealed class NativeTransport : IPluginTransport
    {
        public bool EmitEvent(string topic, string evt, string payloadJson) =>
            HostCall("emit_event", $"{{\"topic\":{JsonEncode(topic)},\"event\":{JsonEncode(evt)},\"payload\":{payloadJson}}}") != "false";

        public string? CallAction(string service, string action, string payloadJson) =>
            HostCall("call_action", $"{{\"service\":{JsonEncode(service)},\"action\":{JsonEncode(action)},\"payload\":{payloadJson}}}");

        public void Log(int level, string message) =>
            HostCall("log", $"{{\"level\":{level},\"message\":{JsonEncode(message)}}}");

        public string? DbGet(string table, string key) =>
            HostCall("db_get", $"{{\"table\":{JsonEncode(table)},\"key\":{JsonEncode(key)}}}");

        public string? DbAll(string table) =>
            HostCall("db_all", $"{{\"table\":{JsonEncode(table)}}}");

        public bool DbPut(string table, string key, string valueJson) =>
            HostCall("db_put", $"{{\"table\":{JsonEncode(table)},\"key\":{JsonEncode(key)},\"value\":{valueJson}}}") != "false";

        public bool DbDelete(string table, string key) =>
            HostCall("db_delete", $"{{\"table\":{JsonEncode(table)},\"key\":{JsonEncode(key)}}}") != "false";

        public long ClockNow()
        {
            string? raw = HostCall("clock_now", "{}");
            return long.TryParse(raw, out var value) ? value : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }
    }
}
