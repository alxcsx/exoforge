using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// JSON plumbing for typed plugin payloads (action arguments/results, event payloads,
/// stored records). Plugin code should never touch <see cref="JsonElement"/> or raw JSON:
/// use records and let this class convert.
///
/// A plugin may declare a source-generated context and register it with
/// <see cref="PluginHost.Run{TPlugin, TJsonContext}"/>, which serialises without reflection:
/// <code>
/// [JsonSerializable(typeof(SnakeScoreRecord))]
/// internal partial class PluginJsonContext : JsonSerializerContext { }
///
/// public static void Main() => PluginHost.Run&lt;MyPlugin, PluginJsonContext&gt;();
/// </code>
/// Values are written with snake_case names to match the host wire format. A context is optional:
/// without one, reflection serialises the value, because a plugin is framework-dependent.
/// </summary>
public static class PluginJson
{
    private static readonly JsonSerializerOptions ReflectionOptions = BuildReflectionOptions();

    /// <summary>
    /// Options for the reflection fallback, which is the path with no source-generated context.
    /// </summary>
    /// <remarks>
    /// It needs the runtime <see cref="JsonStringEnumConverter"/>, and that converter cannot be
    /// statically analyzed - it is the only one that works without a type in hand, since the generic
    /// form needs the enum. So this path cannot satisfy the trimmer on its own. The suppression keeps
    /// SDK code from warning in a consumer that trims directly; the plugin build refuses trimming
    /// anyway. Suppressed here rather than by a blanket NoWarn so the reason travels with it.
    /// </remarks>
    [UnconditionalSuppressMessage("AOT", "IL3050", Justification = "Reflection-only path used when no JSON context is registered; the plugin build refuses trimming.")]
    private static JsonSerializerOptions BuildReflectionOptions() => new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        // An enum is written as its name, snake_cased - the same spelling a schema's `choices` uses and
        // the same one an Elixir contract writes. Without this it serialises as its number, which is
        // not what a `text` column holds and not what the choices say.
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
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

        // No enum converter here, deliberately. The generator writes one per enum the plugin
        // declares and registers it on the context, which is AOT-safe; the runtime
        // JsonStringEnumConverter is not, and adding it here as well was both redundant and one of
        // the warnings that reached every plugin author's build log.
        _options = new JsonSerializerOptions
        {
            TypeInfoResolver = resolver,
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true,
        };
    }

    /// <summary>Serializes a value to JSON, mapping lists and arrays to JSON arrays.</summary>
    [UnconditionalSuppressMessage("Trimming", "IL2026", Justification = "Reflection JSON is the non-AOT fallback; a source-generated context is used when present, and the catch turns a failure into an actionable message.")]
    [UnconditionalSuppressMessage("AOT", "IL3050", Justification = "Reflection JSON is the non-AOT fallback; a source-generated context is used when present, and the catch turns a failure into an actionable message.")]
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
        if (value is double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new InvalidOperationException(NonFiniteHint("double", d));
            return d.ToString("R", CultureInfo.InvariantCulture);
        }

        if (value is float f)
        {
            if (float.IsNaN(f) || float.IsInfinity(f)) throw new InvalidOperationException(NonFiniteHint("float", f));
            return f.ToString("R", CultureInfo.InvariantCulture);
        }
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

        try
        {
            return JsonSerializer.Serialize(value, value.GetType(), ReflectionOptions);
        }
        catch (InvalidOperationException ex)
        {
            throw new InvalidOperationException(SerializationHint(value.GetType()), ex);
        }
    }

    /// <summary>Deserializes JSON into <paramref name="type"/>.</summary>
    [UnconditionalSuppressMessage("Trimming", "IL2026", Justification = "Reflection JSON is the non-AOT fallback; a source-generated context is used when present, and the catch turns a failure into an actionable message.")]
    [UnconditionalSuppressMessage("AOT", "IL3050", Justification = "Reflection JSON is the non-AOT fallback; a source-generated context is used when present, and the catch turns a failure into an actionable message.")]
    public static object? Deserialize(string json, Type type)
    {
        if (TryGetTypeInfo(type, out var info))
        {
            return JsonSerializer.Deserialize(json, info);
        }

        try
        {
            return JsonSerializer.Deserialize(json, type, ReflectionOptions);
        }
        catch (InvalidOperationException ex)
        {
            throw new InvalidOperationException(SerializationHint(type), ex);
        }
    }

    /// <summary>Deserializes JSON into <typeparamref name="T"/>.</summary>
    public static T? Deserialize<T>(string json) => (T?)Deserialize(json, typeof(T));

    /// <summary>
    /// Why a non-finite number cannot be sent, and what to do instead.
    /// </summary>
    /// <remarks>
    /// JSON has no NaN or infinity. Written raw - which is what this used to do - they make the whole
    /// frame unparseable, so the host sees a decode error rather than a value, and nothing says which
    /// field was at fault. Refusing is louder and points at the number.
    /// </remarks>
    private static string NonFiniteHint(string kind, object value) =>
        $"Cannot send the {kind} '{value}': JSON has no representation for NaN or infinity, and writing " +
        "it raw makes the whole frame unreadable to the host. Send null, or a sentinel of your own, if " +
        "a non-finite value is meaningful here - which in position and physics code it often is.";

    /// <summary>JSON-encodes a string, including the surrounding quotes.</summary>
    internal static string EncodeString(string value)
    {
        var sb = new StringBuilder(value.Length + 2);
        sb.Append('"');

        for (int index = 0; index < value.Length; index++)
        {
            char c = value[index];

            // A matched pair is one character and goes through as it is.
            if (char.IsHighSurrogate(c) && index + 1 < value.Length && char.IsLowSurrogate(value[index + 1]))
            {
                sb.Append(c).Append(value[++index]);
                continue;
            }

            // An unpaired one cannot be escaped into validity - \uD800 on its own is still not valid
            // JSON - so it has to be replaced. Truncating a string mid-character is how this happens.
            if (char.IsSurrogate(c))
            {
                sb.Append("\ufffd");
                continue;
            }

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

    /// <summary>
    /// Why a value could not be serialised, in terms the author can act on.
    /// </summary>
    /// <remarks>
    /// This used to explain a deployment problem: under NativeAOT the trimmer removed the property
    /// metadata reflection needed, and a compiler-generated type could not be rooted by name, so the
    /// only answer was to declare a record. Plugins are framework-dependent now, so reflection works
    /// and this fires for a genuinely unserialisable value instead - a cycle, a property that throws,
    /// a type with nothing readable on it.
    /// </remarks>
    internal static string SerializationHint(Type type) =>
        $"Could not serialize '{type.FullName}'. Reflection is available, so the value is the problem " +
        "rather than the deployment: look for a reference cycle, a property whose getter throws, or a " +
        "type with no readable properties.";
}
