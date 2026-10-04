using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Low-level WASM P/Invoke host bridge and native runtime interface.
/// Interacts directly with Exoforge WasmPluginRunner imports.
/// </summary>
public static class HostBridge
{
    private const int BufferSize = 65536;

    // When set, host calls go through a process transport instead of the WASM `env` imports.
    // PluginHost.Run<T>() installs one for native plugins.
    private static IPluginTransport? _transport;

    /// <summary>Routes host calls through a process transport (native plugins).</summary>
    public static void UseTransport(IPluginTransport transport) => _transport = transport;

    /// <summary>
    /// Serializes a host-call payload without reflection where possible, so it stays NativeAOT-safe.
    /// Prefer <see cref="System.Text.Json.Nodes.JsonObject"/>, <c>JsonElement</c>, or a raw JSON string.
    /// </summary>
    private static string ToJson(object? payload) => payload switch
    {
        null => "null",
        string s => s,
        System.Text.Json.Nodes.JsonNode node => node.ToJsonString(),
        JsonElement element => element.GetRawText(),
        _ => JsonSerializer.Serialize(payload)
    };

    [DllImport("env", EntryPoint = "host_clock_now")]
    private static extern long NativeHostClockNow();

    [DllImport("env", EntryPoint = "host_emit_event")]
    private static extern int NativeHostEmitEvent(
        byte[] topic, int topicLen,
        byte[] evt, int evtLen,
        byte[] payload, int payloadLen);

    [DllImport("env", EntryPoint = "host_call_action")]
    private static extern int NativeHostCallAction(
        byte[] service, int serviceLen,
        byte[] action, int actionLen,
        byte[] payload, int payloadLen);

    [DllImport("env", EntryPoint = "host_call_action_json")]
    private static extern int NativeHostCallActionJson(
        byte[] service, int serviceLen,
        byte[] action, int actionLen,
        byte[] payload, int payloadLen,
        byte[] outBuf, int outMaxLen);

    [DllImport("env", EntryPoint = "host_log")]
    private static extern int NativeHostLog(int level, byte[] msg, int msgLen);

    [DllImport("env", EntryPoint = "host_db_get")]
    private static extern int NativeHostDbGet(
        byte[] table, int tableLen,
        byte[] key, int keyLen,
        byte[] outBuf, int outMaxLen);

    [DllImport("env", EntryPoint = "host_db_put")]
    private static extern int NativeHostDbPut(
        byte[] table, int tableLen,
        byte[] key, int keyLen,
        byte[] val, int valLen);

    [DllImport("env", EntryPoint = "host_db_delete")]
    private static extern int NativeHostDbDelete(
        byte[] table, int tableLen,
        byte[] key, int keyLen);

    [DllImport("env", EntryPoint = "host_get_state")]
    private static extern int NativeHostGetState(
        byte[] key, int keyLen,
        byte[] outBuf, int outMaxLen);

    [DllImport("env", EntryPoint = "host_set_state")]
    private static extern int NativeHostSetState(
        byte[] key, int keyLen,
        byte[] val, int valLen);

    /// <summary>
    /// Returns the current BEAM cluster time in milliseconds.
    /// </summary>
    public static long ClockNow()
    {
        if (_transport != null) return _transport.ClockNow();

        try
        {
            return NativeHostClockNow();
        }
        catch
        {
            return DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }
    }

    /// <summary>
    /// Broadcasts an event to the Exoforge Kernel EventDispatcher via host import.
    /// </summary>
    public static bool EmitEvent(string topic, string eventName, object payload)
    {
        string json = ToJson(payload);

        if (_transport != null) return _transport.EmitEvent(topic ?? "", eventName ?? "", json);

        try
        {
            byte[] topicBytes = Encoding.UTF8.GetBytes(topic ?? "");
            byte[] evtBytes = Encoding.UTF8.GetBytes(eventName ?? "");
            byte[] payloadBytes = Encoding.UTF8.GetBytes(json);

            return NativeHostEmitEvent(
                topicBytes, topicBytes.Length,
                evtBytes, evtBytes.Length,
                payloadBytes, payloadBytes.Length) == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Calls another service's action through the Exoforge ActionDispatcher host import.
    /// </summary>
    public static bool CallAction(string service, string action, object payload)
    {
        if (_transport != null) return _transport.CallAction(service ?? "", action ?? "", ToJson(payload)) != null;

        try
        {
            byte[] svcBytes = Encoding.UTF8.GetBytes(service ?? "");
            byte[] actBytes = Encoding.UTF8.GetBytes(action ?? "");
            string json = payload is string str ? str : JsonSerializer.Serialize(payload);
            byte[] payloadBytes = Encoding.UTF8.GetBytes(json);

            return NativeHostCallAction(
                svcBytes, svcBytes.Length,
                actBytes, actBytes.Length,
                payloadBytes, payloadBytes.Length) == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Calls another service's action and deserializes the JSON response.
    /// </summary>
    public static TResponse? CallAction<TResponse>(string service, string action, object payload)
    {
        if (_transport != null)
        {
            // Native transport returns raw JSON; reflection-free conversion only.
            string? raw = _transport.CallAction(service ?? "", action ?? "", ToJson(payload));

            if (raw == null) return default;
            if (typeof(TResponse) == typeof(string)) return (TResponse)(object)raw;
            if (typeof(TResponse) == typeof(JsonElement)) return (TResponse)(object)JsonDocument.Parse(raw).RootElement.Clone();

            return default;
        }

        try
        {
            byte[] svcBytes = Encoding.UTF8.GetBytes(service ?? "");
            byte[] actBytes = Encoding.UTF8.GetBytes(action ?? "");
            string json = payload is string str ? str : JsonSerializer.Serialize(payload);
            byte[] payloadBytes = Encoding.UTF8.GetBytes(json);
            byte[] outBuf = new byte[BufferSize];

            int bytesRead = NativeHostCallActionJson(
                svcBytes, svcBytes.Length,
                actBytes, actBytes.Length,
                payloadBytes, payloadBytes.Length,
                outBuf, outBuf.Length);

            if (bytesRead <= 0) return default;

            string resJson = Encoding.UTF8.GetString(outBuf, 0, bytesRead);
            return JsonSerializer.Deserialize<TResponse>(resJson);
        }
        catch
        {
            return default;
        }
    }

    /// <summary>
    /// Emits a structured log message to the kernel logger.
    /// Level: 0=Debug, 1=Info, 2=Warning, 3=Error.
    /// </summary>
    public static void Log(int level, string message)
    {
        if (_transport != null)
        {
            _transport.Log(level, message ?? "");
            return;
        }

        try
        {
            byte[] msgBytes = Encoding.UTF8.GetBytes(message ?? "");
            NativeHostLog(level, msgBytes, msgBytes.Length);
        }
        catch
        {
            // Silently ignore if running outside WASI host
        }
    }

    public static void LogInfo(string message) => Log(1, message);
    public static void LogWarning(string message) => Log(2, message);
    public static void LogError(string message) => Log(3, message);

    /// <summary>
    /// Reads a record from the plugin's isolated multi-tenant database.
    /// </summary>
    public static string? DbGet(string table, string key)
    {
        if (_transport != null) return _transport.DbGet(table ?? "", key ?? "");

        try
        {
            byte[] tblBytes = Encoding.UTF8.GetBytes(table ?? "");
            byte[] keyBytes = Encoding.UTF8.GetBytes(key ?? "");
            byte[] outBuf = new byte[BufferSize];

            int bytesRead = NativeHostDbGet(tblBytes, tblBytes.Length, keyBytes, keyBytes.Length, outBuf, outBuf.Length);
            if (bytesRead <= 0) return null;

            return Encoding.UTF8.GetString(outBuf, 0, bytesRead);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Puts a record into the plugin's isolated multi-tenant database.
    /// </summary>
    public static bool DbPut(string table, string key, object value)
    {
        if (_transport != null)
        {
            return _transport.DbPut(table ?? "", key ?? "", ToJson(value));
        }

        try
        {
            byte[] tblBytes = Encoding.UTF8.GetBytes(table ?? "");
            byte[] keyBytes = Encoding.UTF8.GetBytes(key ?? "");
            string json = value is string str ? str : JsonSerializer.Serialize(value);
            byte[] valBytes = Encoding.UTF8.GetBytes(json);

            return NativeHostDbPut(tblBytes, tblBytes.Length, keyBytes, keyBytes.Length, valBytes, valBytes.Length) == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Deletes a record from the plugin's isolated multi-tenant database.
    /// </summary>
    public static bool DbDelete(string table, string key)
    {
        if (_transport != null) return _transport.DbDelete(table ?? "", key ?? "");

        try
        {
            byte[] tblBytes = Encoding.UTF8.GetBytes(table ?? "");
            byte[] keyBytes = Encoding.UTF8.GetBytes(key ?? "");

            return NativeHostDbDelete(tblBytes, tblBytes.Length, keyBytes, keyBytes.Length) == 0;
        }
        catch
        {
            return false;
        }
    }

    public static string? DbExecute(string operation, object[]? args = null)
    {
        return DbGet("default", operation);
    }

    /// <summary>
    /// Reads host-authoritative actor state for this plugin.
    /// </summary>
    public static string? GetState(string key)
    {
        if (_transport != null) return _transport.GetState(key ?? "");

        try
        {
            byte[] keyBytes = Encoding.UTF8.GetBytes(key ?? "");
            byte[] outBuf = new byte[BufferSize];

            int bytesRead = NativeHostGetState(keyBytes, keyBytes.Length, outBuf, outBuf.Length);
            if (bytesRead <= 0) return null;

            return Encoding.UTF8.GetString(outBuf, 0, bytesRead);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Writes host-authoritative actor state for this plugin.
    /// </summary>
    public static bool SetState(string key, object value)
    {
        if (_transport != null)
        {
            return _transport.SetState(key ?? "", value is string str0 ? str0 : ToJson(value));
        }

        try
        {
            byte[] keyBytes = Encoding.UTF8.GetBytes(key ?? "");
            string json = value is string str ? str : JsonSerializer.Serialize(value);
            byte[] valBytes = Encoding.UTF8.GetBytes(json);

            return NativeHostSetState(keyBytes, keyBytes.Length, valBytes, valBytes.Length) == 0;
        }
        catch
        {
            return false;
        }
    }
}
