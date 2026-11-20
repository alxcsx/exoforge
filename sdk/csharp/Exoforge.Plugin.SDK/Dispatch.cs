using System;
using System.Text.Json;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Compile-time action and event dispatch for a plugin.
///
/// The <c>Exoforge.Plugin.Generator</c> source generator emits an implementation from the plugin's
/// own <c>[ExoAction]</c> methods, so the host never reflects over them: the table is generated at
/// compile time and kept alive by the call site that uses it.
/// </summary>
public interface IExoforgeDispatch
{
    /// <summary>Invokes the named action. Returns false when the plugin declares no such action.</summary>
    bool TryInvoke(object instance, string action, JsonElement payload, out object? result);

    /// <summary>Hands an inbound event to the plugin's handler. Returns false when it has none.</summary>
    bool TryHandleEvent(object instance, string name, JsonElement payload);

    /// <summary>Runs the optional [ExoSeed] hook. Returns false when the plugin declares no seed method.</summary>
    bool TryRunSeed(object instance, out object? result)
    {
        result = null;
        return false;
    }
}

/// <summary>
/// Argument binding shared by generated dispatch code, so a generated table stays a table and does
/// not carry a copy of the SDK's JSON handling.
/// </summary>
public static class ExoDispatch
{
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, (long? Locked, long At)> LockCache = new();
    private const long LockCacheMillis = 30_000;

    /// <summary>
    /// True when the caller is served by an action revision that starts at <paramref name="from"/> (an encoded
    /// extension version): its game version locks this extension at or above it. A caller with no game version,
    /// an extension the game version does not lock, or an unreachable versioning service gets the newest revision.
    /// </summary>
    public static bool CallerAtLeast(long from)
    {
        var context = PluginHost.CurrentContext;
        string? gameVersion = context.CallerGameVersion;
        if (string.IsNullOrEmpty(gameVersion) || context is not HostPluginContext host) return true;

        return LockedVersion(host.PluginId, gameVersion!) is not long locked || locked >= from;
    }

    private static long? LockedVersion(string pluginId, string gameVersion)
    {
        long now = System.Diagnostics.Stopwatch.GetTimestamp() / (System.Diagnostics.Stopwatch.Frequency / 1000);
        string key = pluginId + "|" + gameVersion;
        if (LockCache.TryGetValue(key, out var hit) && now - hit.At < LockCacheMillis) return hit.Locked;

        long? locked = null;
        try
        {
            string? raw = HostBridge.CallActionRaw("versioning", "resolve", new System.Text.Json.Nodes.JsonObject { ["version"] = gameVersion });
            if (raw is not null)
            {
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.TryGetProperty("locks", out var locks) && locks.ValueKind == JsonValueKind.Object &&
                    locks.TryGetProperty(pluginId, out var lockElement) && lockElement.ValueKind == JsonValueKind.String)
                {
                    locked = ExoVersion.Encode(lockElement.GetString());
                }
            }
        }
        catch (Exception)
        {
            // An unreachable versioning service must not break the action: serve the newest revision.
        }

        LockCache[key] = (locked, now);
        return locked;
    }

    /// <summary>Forgets resolved locks (tests).</summary>
    internal static void ResetLockCache() => LockCache.Clear();

    /// <summary>
    /// Reads a payload argument by name, ignoring case and underscores so JSON <c>snake_length</c>
    /// binds to the C# <c>snakeLength</c> parameter. Missing, null or unreadable values fall back.
    /// </summary>
    public static T Get<T>(JsonElement payload, string name, T fallback)
    {
        if (payload.ValueKind != JsonValueKind.Object) return fallback;

        // A webhook handler receives the whole frame: the router sends body, headers, method and
        // query as top-level keys, and [ExoWebhook] allows no other parameter shape.
        if (typeof(T) == typeof(WebhookPayload)) return (T)(object)Convert<WebhookPayload>(payload);

        if (!TryFind(payload, name, out var value))
        {
            if ((name == "payload" || name == "request") && typeof(T) == typeof(JsonElement))
            {
                return (T)(object)payload.Clone();
            }
            return fallback;
        }
        if (value.ValueKind == JsonValueKind.Null || value.ValueKind == JsonValueKind.Undefined) return fallback;

        return Convert<T>(value);
    }

    /// <summary>Converts a JSON element to <typeparamref name="T"/>, routing records through the SDK's JSON layer.</summary>
    public static T Convert<T>(JsonElement element)
    {
        Type target = typeof(T);
        Type underlying = Nullable.GetUnderlyingType(target) ?? target;

        if (underlying == typeof(int)) return (T)(object)element.GetInt32();
        if (underlying == typeof(long)) return (T)(object)element.GetInt64();
        if (underlying == typeof(double)) return (T)(object)element.GetDouble();
        if (underlying == typeof(float)) return (T)(object)(float)element.GetDouble();
        if (underlying == typeof(bool)) return (T)(object)element.GetBoolean();
        if (target == typeof(string)) return (T)(object)(element.GetString() ?? "");
        if (target == typeof(JsonElement)) return (T)(object)element.Clone();

        if (element.ValueKind == JsonValueKind.Object || element.ValueKind == JsonValueKind.Array)
        {
            return (T)PluginJson.Deserialize(element.GetRawText(), target)!;
        }

        return default!;
    }

    private static bool TryFind(JsonElement payload, string name, out JsonElement value)
    {
        string normalized = Normalize(name);

        foreach (var property in payload.EnumerateObject())
        {
            if (Normalize(property.Name) == normalized)
            {
                value = property.Value;
                return true;
            }
        }

        value = default;
        return false;
    }

    private static string Normalize(string name) => name.Replace("_", "").ToLowerInvariant();
}
