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
}

/// <summary>
/// Argument binding shared by generated dispatch code, so a generated table stays a table and does
/// not carry a copy of the SDK's JSON handling.
/// </summary>
public static class ExoDispatch
{
    /// <summary>
    /// Reads a payload argument by name, ignoring case and underscores so JSON <c>snake_length</c>
    /// binds to the C# <c>snakeLength</c> parameter. Missing, null or unreadable values fall back.
    /// </summary>
    public static T Get<T>(JsonElement payload, string name, T fallback)
    {
        if (payload.ValueKind != JsonValueKind.Object) return fallback;
        if (!TryFind(payload, name, out var value)) return fallback;
        if (value.ValueKind == JsonValueKind.Null || value.ValueKind == JsonValueKind.Undefined) return fallback;

        return Convert<T>(value);
    }

    /// <summary>Converts a JSON element to <typeparamref name="T"/>, routing records through the SDK's JSON layer.</summary>
    public static T Convert<T>(JsonElement element)
    {
        Type target = typeof(T);

        if (target == typeof(int)) return (T)(object)element.GetInt32();
        if (target == typeof(long)) return (T)(object)element.GetInt64();
        if (target == typeof(double)) return (T)(object)element.GetDouble();
        if (target == typeof(float)) return (T)(object)(float)element.GetDouble();
        if (target == typeof(bool)) return (T)(object)element.GetBoolean();
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
