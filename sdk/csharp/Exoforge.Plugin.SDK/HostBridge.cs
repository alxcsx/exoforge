using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Low-level bridge between a plugin and its host: routes capability calls through the transport
/// <see cref="PluginHost"/> installs.
/// </summary>
public static class HostBridge
{
    // When set, host calls go through the process transport. PluginHost.Run<T>() installs one for native plugins.
    private static IPluginTransport? _transport;

    /// <summary>Routes host calls through a process transport (native plugins). Pass <c>null</c> to reset.</summary>
    public static void UseTransport(IPluginTransport? transport)
    {
        _transport = transport;
        // A new transport is a new host session: what the last host declared does not carry over.
        _hostProtocol = 0;
        _hostCapabilities = null;
        Handshaken = false;
    }

    // -- protocol handshake --

    /// <summary>The frames this SDK can receive; declared to the host in the hello reply.</summary>
    public static readonly IReadOnlyList<string> PluginCapabilities =
        new[] { "action", "event", "host_call_result", "lifecycle" };

    private static int _hostProtocol;
    private static IReadOnlyList<string>? _hostCapabilities;

    /// <summary>True once the host's hello has been read.</summary>
    public static bool Handshaken { get; private set; }

    /// <summary>The host's protocol version, once handshaken; 0 before that.</summary>
    public static int HostProtocol => _hostProtocol;

    internal static void NoteHandshake(int protocol, IReadOnlyList<string> capabilities)
    {
        _hostProtocol = protocol;
        _hostCapabilities = capabilities;
        Handshaken = true;
    }

    /// <summary>
    /// Whether the host declared it can receive a frame. Before a handshake this is permissive: a
    /// host that does not negotiate is assumed to be one that predates capabilities and handles
    /// everything this protocol version has.
    /// </summary>
    public static bool HostSupports(string capability) =>
        _hostCapabilities == null || _hostCapabilities.Contains(capability);

    /// <summary>
    /// Serializes a host-call payload without reflection where possible. A <c>string</c> is treated
    /// as already-encoded JSON; everything else goes through <see cref="PluginJson"/>, which prefers
    /// a registered source-generated context and falls back to reflection.
    /// </summary>
    private static string ToJson(object? payload) => payload switch
    {
        null => "null",
        string s => s,
        System.Text.Json.Nodes.JsonNode node => node.ToJsonString(),
        JsonElement element => element.GetRawText(),
        _ => PluginJson.Serialize(payload)
    };

    /// <summary>
    /// Returns the current BEAM cluster time in milliseconds.
    /// </summary>
    public static long ClockNow()
    {
        return _transport != null ? _transport.ClockNow() : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    }

    /// <summary>
    /// Broadcasts an event to the Exoforge Kernel EventDispatcher via host transport.
    /// </summary>
    public static bool EmitEvent(string topic, string eventName, object payload)
    {
        return _transport?.EmitEvent(topic ?? "", eventName ?? "", ToJson(payload)) ?? false;
    }

    /// <summary>
    /// Calls another service's action through the Exoforge ActionDispatcher. Returns whether the
    /// call was made; a failed call throws instead of looking like a success.
    /// </summary>
    public static bool CallAction(string service, string action, object payload)
    {
        string? raw = _transport?.CallAction(service ?? "", action ?? "", ToJson(payload));
        if (raw == null) return false;

        ThrowIfActionError(raw, service ?? "", action ?? "");
        return true;
    }

    /// <summary>
    /// Calls another service's action and returns the raw JSON response, or <c>null</c> when the
    /// call could not be made.
    /// </summary>
    public static string? CallActionRaw(string service, string action, object payload)
    {
        return _transport?.CallAction(service ?? "", action ?? "", ToJson(payload));
    }

    /// <summary>
    /// Calls another service's action and deserializes the JSON response. A failed call throws
    /// <see cref="ExoActionException"/> carrying the code the callee threw, so a caller branches on
    /// the failure instead of treating a default value as an answer.
    /// </summary>
    public static TResponse? CallAction<TResponse>(string service, string action, object payload)
    {
        string? raw = CallActionRaw(service, action, payload);
        if (raw == null) return default;
        ThrowIfActionError(raw, service ?? "", action ?? "");

        if (typeof(TResponse) == typeof(string)) return (TResponse)(object)raw;
        if (typeof(TResponse) == typeof(JsonElement)) return (TResponse)(object)JsonDocument.Parse(raw).RootElement.Clone();

        return PluginJson.Deserialize<TResponse>(raw);
    }

    /// <summary>
    /// Turns an error reply into an exception: the callee's <c>{code, message}</c> becomes an
    /// <see cref="ExoActionException"/> with that code. A host that predates structured errors sends
    /// a bare string, which is the code.
    /// </summary>
    private static void ThrowIfActionError(string raw, string service, string action)
    {
        JsonElement error;
        string? code;

        try
        {
            using var doc = JsonDocument.Parse(raw);
            if (doc.RootElement.ValueKind != JsonValueKind.Object ||
                !doc.RootElement.TryGetProperty("error", out error))
            {
                return;
            }

            if (error.ValueKind == JsonValueKind.Object)
            {
                string structuredCode =
                    error.TryGetProperty("code", out var codeProp) && codeProp.ValueKind == JsonValueKind.String
                        ? codeProp.GetString() ?? "action_failed"
                        : "action_failed";

                string message =
                    error.TryGetProperty("message", out var messageProp) && messageProp.ValueKind == JsonValueKind.String
                        ? messageProp.GetString() ?? ""
                        : "";

                throw new ExoActionException(structuredCode, message);
            }

            if (error.ValueKind != JsonValueKind.String) return;

            code = error.GetString();
        }
        catch (JsonException)
        {
            return;
        }

        string failureCode = string.IsNullOrEmpty(code) ? "action_failed" : code;

        // Keep the actionable wording for the two failures a caller can fix in its own project.
        if (failureCode == "service_not_found")
        {
            throw new ExoActionException(
                failureCode,
                $"Service '{service}' (called via '{service}.{action}') was not found on the server. " +
                $"Ensure the extension providing '{service}' is deployed and running.");
        }

        if (failureCode == "service_not_declared")
        {
            throw new ExoActionException(
                failureCode,
                $"Service '{service}' is not declared in this extension's dependencies. " +
                $"Add '{service}' to your extension dependencies and regenerate stubs.");
        }

        throw new ExoActionException(failureCode, $"Call to '{service}.{action}' failed: {failureCode}");
    }

    /// <summary>
    /// Emits a structured log message to the kernel logger.
    /// Level: 0=Debug, 1=Info, 2=Warning, 3=Error.
    /// </summary>
    public static void Log(int level, string message)
    {
        _transport?.Log(level, message ?? "");
    }

    public static void LogInfo(string message) => Log(1, message);
    public static void LogWarning(string message) => Log(2, message);
    public static void LogError(string message) => Log(3, message);

    /// <summary>
    /// Reads a record from the plugin's isolated multi-tenant database.
    /// </summary>
    public static string? DbGet(string table, string key)
    {
        return _transport?.DbGet(table ?? "", key ?? "");
    }

    /// <summary>
    /// Puts a record into the plugin's isolated multi-tenant database.
    /// </summary>
    public static bool DbPut(string table, string key, object value)
    {
        return _transport?.DbPut(table ?? "", key ?? "", ToJson(value)) ?? false;
    }

    /// <summary>
    /// Reads every record in a table from the plugin's isolated multi-tenant database,
    /// as a JSON array.
    /// </summary>
    public static string? DbAll(string table) => _transport?.DbAll(table ?? "");

    /// <summary>
    /// Deletes a record from the plugin's isolated multi-tenant database.
    /// </summary>
    public static bool DbDelete(string table, string key)
    {
        return _transport?.DbDelete(table ?? "", key ?? "") ?? false;
    }
}
