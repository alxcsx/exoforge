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
    private static readonly JsonSerializerOptions ReflectionOptions = BuildReflectionOptions();

    /// <summary>
    /// Options for the reflection fallback, which is the path with no source-generated context.
    /// </summary>
    /// <remarks>
    /// It needs the runtime <see cref="JsonStringEnumConverter"/>, and that converter cannot be
    /// statically analyzed - it is the only one that works without a type in hand, since the generic
    /// form needs the enum. So this path cannot be AOT-safe, and it does not need to be: it runs only
    /// when no context is registered, and in a NativeAOT build reflection serialization is disabled
    /// outright, so the code is unreachable there. Suppressed here rather than by a blanket NoWarn so
    /// the reason travels with it.
    /// </remarks>
    [UnconditionalSuppressMessage("AOT", "IL3050", Justification = "Reflection-only path; unreachable under NativeAOT, where reflection serialization is disabled.")]
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
            throw new InvalidOperationException(AotHint(value.GetType()), ex);
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
            throw new InvalidOperationException(AotHint(type), ex);
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

    internal static string AotHint(Type type)
    {
        // An anonymous object is the trap this message exists for. It serializes fine in a test run,
        // where reflection is available, and fails in the published plugin - so the author sees green
        // tests and a broken build. And the usual advice is impossible to follow: a compiler-generated
        // type cannot be named in source, so "[JsonSerializable(typeof(...))]" is not missing, it is
        // unwritable. A closure's display class is the same shape of problem.
        //
        // The obvious way out was tried, and it does not hold. Walking the object into a JsonObject
        // works - JsonObject and JsonValue are known to STJ without a context entry - and in a flat
        // object it works in a published AOT plugin. It is not reliable: the trimmer removes property
        // metadata nothing references, and a type with no name cannot be rooted, so the walk finds
        // some properties and not others. An action returning `new { value = 7, nested = new { deep =
        // true } }` came back as {"value":7,"nested":{}} - the outer object intact, the inner one
        // empty. A wrong answer on the wire is worse than the loud failure this hint replaces, and no
        // guard can detect it, since a partly trimmed type is indistinguishable from a small one. So
        // there is deliberately no such fallback: declare the type, and its name makes it rootable.
        //
        // Nor can the switches be turned back on, which is worth knowing before trying. Publishing with
        // JsonSerializerIsReflectionEnabledByDefault=true and IlcTrimMetadata=false - reflection on,
        // metadata kept, 2.8MB of binary becoming 7.2MB - gets further and still fails: it reaches the
        // anonymous type, then cannot build a converter for it, because NativeAOT compiles generic
        // instantiations statically and the one STJ needs here was never in the program. IL2CPP gets
        // away with the same trick for two reasons that AOT does not share: it strips nothing by
        // default, and it shares generic code across reference-type instantiations. Unity developers
        // meet the IL2CPP half of this too - link.xml, [Preserve], AOTGenericReferences, and code that
        // works in the Editor and breaks in the build. It is not a configuration mistake in either.
        //
        // What it costs to have reflection back, measured rather than guessed. Disk is cheap and RAM
        // is not, so the number that matters is the marginal one, and a single process does not show
        // it: Pss divides shared pages among their sharers, so per-process cost falls as plugins are
        // added. Eight of each, spawned directly and left idle:
        //
        //                                    N=1        N=8 total    marginal per plugin
        //   NativeAOT                        3.2MB Pss    10MB        ~1MB      (2.8MB on disk)
        //   framework-dependent             12.5MB Pss    57MB        ~6.4MB    (144KB on disk)
        //
        // So dropping AOT buys 20x less disk and costs 6x more RAM per plugin. Disk is an image layer
        // in a container and effectively free; RAM is what runs out. AOT's per-process Pss falls as
        // plugins are added, because they share the binary's code pages - which is also why a shared
        // in-process host is a weaker RAM argument than it looks: eight AOT plugins cost less in total
        // than one framework-dependent host process, before any plugin's own working set.
        //
        // None of this is an argument about code. It is the whole reason the workarounds above exist:
        // the deployment mode is the cause, and changing it deletes them rather than fixing them. It
        // just costs more RAM than it saves, which is the wrong trade when RAM is the scarce thing.
        if (type.IsDefined(typeof(System.Runtime.CompilerServices.CompilerGeneratedAttribute), false) &&
            type.Name.StartsWith("<", StringComparison.Ordinal))
        {
            return $"Could not serialize '{type.Name}': it is a compiler-generated type, so it cannot be " +
                   "named in source and there is no way to register it. An anonymous object works in a " +
                   "test run, where reflection is available, and fails here in the published plugin. " +
                   "Declare a record instead - `public record MyResult(int Value);` - and return " +
                   "`new MyResult(7)`. Its name is what the manifest, the generated client and the " +
                   "dashboard describe, and it is what makes the type rootable. Converting the object " +
                   "to a JsonObject is not a way around this: the trimmer removes the property " +
                   "metadata the conversion needs, and it drops fields rather than failing.";
        }

        return $"Could not (de)serialize '{type}'. On NativeAOT, register the type on a source-generated " +
               "JsonSerializerContext and start the plugin with PluginHost.Run<TPlugin, TJsonContext>(), " +
               "adding [JsonSerializable(typeof(" + type.Name + "))].";
    }
}
