using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;

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
    bool DbPut(string table, string key, string valueJson);
    bool DbDelete(string table, string key);
    string? GetState(string key);
    bool SetState(string key, string valueJson);
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
    private static readonly Dictionary<long, string> PendingHostCalls = new();
    private static Stream? _stdout;
    private static long _nextHostCallId;

    /// <summary>Runs <typeparamref name="T"/> until stdin closes.</summary>
    /// <remarks>
    /// The <see cref="DynamicallyAccessedMembersAttribute"/> keeps the plugin's action methods
    /// (and their parameter names) alive through NativeAOT trimming — they are only reached by
    /// reflection.
    /// </remarks>
    public static void Run<[DynamicallyAccessedMembers(
        DynamicallyAccessedMemberTypes.PublicMethods |
        DynamicallyAccessedMemberTypes.NonPublicMethods |
        DynamicallyAccessedMemberTypes.PublicParameterlessConstructor)] T>()
        where T : class, new() => RunInstance(new T());

    /// <summary>Runs a plugin instance until stdin closes.</summary>
    public static int RunInstance(object instance)
    {
        _stdout = Console.OpenStandardOutput();
        HostBridge.UseTransport(new NativeTransport());

        var pluginType = instance.GetType();
        var actions = BuildActionTable(pluginType);

        using var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);

        while (reader.ReadLine() is { } line)
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                Dispatch(line, instance, actions);
            }
        }

        return 0;
    }

    private static Dictionary<string, (MethodInfo Method, ParameterInfo[] Params)> BuildActionTable(Type pluginType)
    {
        var table = new Dictionary<string, (MethodInfo, ParameterInfo[])>(StringComparer.OrdinalIgnoreCase);

        foreach (var method in pluginType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance))
        {
            var attr = method.GetCustomAttribute<ExoActionAttribute>();

            if (attr != null)
            {
                table[attr.Name] = (method, method.GetParameters());
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
            object? result = entry.Method.Invoke(instance, args);

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

        return DefaultOf(target);
    }

    private static object? DefaultOf(Type type) => type.IsValueType ? Activator.CreateInstance(type) : null;

    /// <summary>Serializes a plugin return value without reflection-based JSON (NativeAOT-safe).</summary>
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
        _ => JsonEncode(value.ToString() ?? "")
    };

    private static string JsonEncode(string value)
    {
        var sb = new StringBuilder(value.Length + 2);
        sb.Append('"');

        foreach (char c in value)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                    else sb.Append(c);
                    break;
            }
        }

        sb.Append('"');
        return sb.ToString();
    }

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

                if (root.TryGetProperty("type", out var typeProp) &&
                    typeProp.GetString() == "host_call_result" &&
                    root.TryGetProperty("id", out var idProp) &&
                    idProp.GetInt64() == id)
                {
                    return root.TryGetProperty("result", out var resultProp) ? resultProp.GetRawText() : null;
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

        public bool DbPut(string table, string key, string valueJson) =>
            HostCall("db_put", $"{{\"table\":{JsonEncode(table)},\"key\":{JsonEncode(key)},\"value\":{valueJson}}}") != "false";

        public bool DbDelete(string table, string key) =>
            HostCall("db_delete", $"{{\"table\":{JsonEncode(table)},\"key\":{JsonEncode(key)}}}") != "false";

        public string? GetState(string key) => HostCall("get_state", $"{{\"key\":{JsonEncode(key)}}}");

        public bool SetState(string key, string valueJson) =>
            HostCall("set_state", $"{{\"key\":{JsonEncode(key)},\"value\":{valueJson}}}") != "false";

        public long ClockNow()
        {
            string? raw = HostCall("clock_now", "{}");
            return long.TryParse(raw, out var value) ? value : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }
    }
}
