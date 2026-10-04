using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// JSON plumbing for typed plugin payloads (action arguments/results, event payloads,
/// stored records). Plugin code should never touch <see cref="JsonElement"/> or raw JSON:
/// use records and let this class convert.
///
/// On NativeAOT, reflection-based JSON is disabled by the runtime. Declare a source-generated
/// context and register it with <see cref="PluginHost.Run{TPlugin, TJsonContext}"/>:
/// <code>
/// [JsonSerializable(typeof(SnakeScoreRecord))]
/// internal partial class PluginJsonContext : JsonSerializerContext { }
///
/// public static void Main() => PluginHost.Run&lt;MyPlugin, PluginJsonContext&gt;();
/// </code>
/// Values are written with snake_case names to match the host wire format. Outside AOT
/// (unit tests, WASM contract stubs) a reflection fallback keeps things working without a context.
/// </summary>
public static class PluginJson
{
    private static readonly JsonSerializerOptions ReflectionOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    private static JsonSerializerOptions? _options;
    private static readonly List<JsonSerializerContext> Contexts = new();

    /// <summary>Registers the source-generated context(s) used for typed (de)serialization. Replaces any previous registration.</summary>
    public static void UseContext(JsonSerializerContext? context)
    {
        Contexts.Clear();
        if (context != null) Contexts.Add(context);
        RebuildOptions();
    }

    /// <summary>
    /// Adds another source-generated context. Generated contract stubs register their own context via
    /// a module initializer, so the plugin's context and the generated one coexist.
    /// </summary>
    public static void AddContext(JsonSerializerContext context)
    {
        if (context == null || Contexts.Contains(context)) return;

        Contexts.Add(context);
        RebuildOptions();
    }

    private static void RebuildOptions()
    {
        if (Contexts.Count == 0)
        {
            _options = null;
            return;
        }

        IJsonTypeInfoResolver resolver = Contexts.Count == 1
            ? Contexts[0]
            : JsonTypeInfoResolver.Combine(Contexts.ToArray());

        _options = new JsonSerializerOptions
        {
            TypeInfoResolver = resolver,
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
    }

    /// <summary>Serializes a value to JSON, mapping lists and arrays to JSON arrays.</summary>
    public static string Serialize(object? value)
    {
        if (value is null) return "null";

        // Scalars are common as SQL arguments; serialize them without needing a context entry.
        if (value is string s) return EncodeString(s);
        if (value is bool b) return b ? "true" : "false";
        if (value is int i) return i.ToString(CultureInfo.InvariantCulture);
        if (value is long l) return l.ToString(CultureInfo.InvariantCulture);
        if (value is short sh) return sh.ToString(CultureInfo.InvariantCulture);
        if (value is byte by) return by.ToString(CultureInfo.InvariantCulture);
        if (value is double d) return d.ToString("R", CultureInfo.InvariantCulture);
        if (value is float f) return f.ToString("R", CultureInfo.InvariantCulture);
        if (value is decimal m) return m.ToString(CultureInfo.InvariantCulture);
        if (value is DateTime dt) return EncodeString(dt.ToString("O", CultureInfo.InvariantCulture));
        if (value is DateTimeOffset dto) return EncodeString(dto.ToString("O", CultureInfo.InvariantCulture));
        if (value is Guid guid) return EncodeString(guid.ToString("D"));

        // Collections are serialized element-wise so only the element type needs a context entry.
        if (value is IList list)
        {
            var sb = new StringBuilder("[");
            for (int index = 0; index < list.Count; index++)
            {
                if (index > 0) sb.Append(',');
                sb.Append(Serialize(list[index]));
            }
            return sb.Append(']').ToString();
        }

        if (TryGetTypeInfo(value.GetType(), out var info))
        {
            return JsonSerializer.Serialize(value, info);
        }

#pragma warning disable IL2026, IL3050 // reflection path is a dev/test convenience, never the AOT path
        try
        {
            return JsonSerializer.Serialize(value, value.GetType(), ReflectionOptions);
        }
        catch (InvalidOperationException ex)
        {
            throw new InvalidOperationException(AotHint(value.GetType()), ex);
        }
#pragma warning restore IL2026, IL3050
    }

    /// <summary>Deserializes JSON into <paramref name="type"/>.</summary>
    public static object? Deserialize(string json, Type type)
    {
        if (TryGetTypeInfo(type, out var info))
        {
            return JsonSerializer.Deserialize(json, info);
        }

#pragma warning disable IL2026, IL3050 // reflection path is a dev/test convenience, never the AOT path
        try
        {
            return JsonSerializer.Deserialize(json, type, ReflectionOptions);
        }
        catch (InvalidOperationException ex)
        {
            throw new InvalidOperationException(AotHint(type), ex);
        }
#pragma warning restore IL2026, IL3050
    }

    /// <summary>Deserializes JSON into <typeparamref name="T"/>.</summary>
    public static T? Deserialize<T>(string json) => (T?)Deserialize(json, typeof(T));

    /// <summary>JSON-encodes a string, including the surrounding quotes.</summary>
    internal static string EncodeString(string value)
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

    private static bool TryGetTypeInfo(Type type, out JsonTypeInfo info)
    {
        if (_options is not null)
        {
            try
            {
                info = _options.GetTypeInfo(type);
                return true;
            }
            catch (Exception ex) when (ex is InvalidOperationException or NotSupportedException)
            {
                // Not registered on the context — fall through to reflection.
            }
        }

        info = null!;
        return false;
    }

    private static string AotHint(Type type) =>
        $"Could not (de)serialize '{type}'. On NativeAOT, register the type on a source-generated " +
        "JsonSerializerContext and start the plugin with PluginHost.Run<TPlugin, TJsonContext>(), " +
        "adding [JsonSerializable(typeof(" + type.Name + "))].";
}
