using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Brings a stored row up to the current shape when it is read (see <see cref="ExoRowMigrationAttribute"/>).
/// A row carries <c>_v</c>, the encoded extension version it was written under; the migrations of its type with
/// a higher <c>To</c> run in order, and the result is written back with <c>_if_v</c> set to the old stamp, so
/// two callers migrating the same row cannot both win. A row without <c>_v</c> comes from a server that does
/// not stamp rows and is left as it is.
/// </summary>
internal static class RowMigrations
{
    internal const string StampKey = "_v";
    internal const string GuardKey = "_if_v";

    internal sealed class Step
    {
        public Step(long to, MethodInfo method)
        {
            To = to;
            Method = method;
        }

        public long To { get; }
        public MethodInfo Method { get; }
    }

    /// <summary>What reads need to know about a record type, found once.</summary>
    internal sealed class Info
    {
        public Info(Step[] steps, RowMigrationMode mode, bool fork)
        {
            Steps = steps;
            Mode = mode;
            Fork = fork;
        }

        public Step[] Steps { get; }
        public RowMigrationMode Mode { get; }
        public bool Fork { get; }

        /// <summary>True when reads have anything to do for this type.</summary>
        public bool Active => Steps.Length > 0 && Mode != RowMigrationMode.Off;
    }

    private static readonly ConcurrentDictionary<Type, Info> Cache = new();

    private static readonly System.Threading.AsyncLocal<bool> SuppressedScope = new();

    /// <summary>True inside <see cref="Suppress"/>: reads return rows as stored (the QueryRaw escape hatch).</summary>
    internal static bool Suppressed => SuppressedScope.Value;

    internal static IDisposable Suppress()
    {
        SuppressedScope.Value = true;
        return new Scope();
    }

    private sealed class Scope : IDisposable
    {
        public void Dispose() => SuppressedScope.Value = false;
    }

    /// <summary>Methods registered by hand (tests, or an assembly the scan does not see).</summary>
    private static readonly ConcurrentDictionary<Type, List<Step>> Registered = new();

    internal static void Register(Type resource, string to, MethodInfo method)
    {
        Registered.GetOrAdd(resource, _ => new List<Step>()).Add(new Step(ExoVersion.Encode(to), method));
        Cache.Clear();
    }

    internal static void Reset()
    {
        Registered.Clear();
        Cache.Clear();
    }

    internal static Info InfoFor(Type resource) =>
        Cache.GetOrAdd(resource, type =>
        {
            var steps = new List<Step>();
            if (Registered.TryGetValue(type, out var registered)) steps.AddRange(registered);

            // The record's own assembly first, then the extension's entry assembly when that is a different one.
            var assemblies = new[] { type.Assembly, Assembly.GetEntryAssembly() }.Where(a => a is not null).Distinct();
            foreach (var candidate in assemblies.SelectMany(a => SafeTypes(a!)))
            {
                foreach (var method in candidate.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
                {
                    var attr = method.GetCustomAttribute<ExoRowMigrationAttribute>();
                    if (attr is not null && attr.Resource == type) steps.Add(new Step(ExoVersion.Encode(attr.To), method));
                }
            }

            var resourceAttr = type.GetCustomAttribute<ExoResourceAttribute>();
            return new Info(
                steps.OrderBy(s => s.To).ToArray(),
                resourceAttr?.RowMigration ?? RowMigrationMode.WriteBack,
                resourceAttr?.BreakingChanges == BreakingChangeMode.Fork);
        });

    private static Step[] StepsFor(Type resource) => InfoFor(resource).Steps;

    private static IEnumerable<Type> SafeTypes(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes();
        }
        catch (ReflectionTypeLoadException ex)
        {
            return ex.Types.Where(t => t is not null)!;
        }
    }

    /// <summary>
    /// The row's stored stamp when a migration of <typeparamref name="T"/> is pending for it, else null.
    /// </summary>
    internal static long? PendingFrom<T>(JsonElement row)
    {
        var info = InfoFor(typeof(T));
        if (!info.Active || Suppressed) return null;
        if (StampOf(row) is not long stamp) return null;

        return info.Steps.Any(s => s.To > stamp) ? stamp : null;
    }

    /// <summary>The stored <c>_v</c> of a row, or null when it has none.</summary>
    internal static long? StampOf(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Object || !row.TryGetProperty(StampKey, out var stampElement)) return null;
        return stampElement.ValueKind == JsonValueKind.Number && stampElement.TryGetInt64(out long stamp) ? stamp : null;
    }

    /// <summary>
    /// The oldest extension version that can read a row stamped <paramref name="stamp"/>: the newest row migration
    /// it has been through. Declarative migrations are safe changes older clients tolerate, so they never count.
    /// </summary>
    internal static long FloorOf(Type resource, long stamp)
    {
        long floor = 0;
        foreach (var step in StepsFor(resource))
        {
            if (step.To <= stamp) floor = step.To;
        }

        return floor;
    }

    /// <summary>Runs the pending migrations in order. Each sees the row as the one before left it.</summary>
    internal static T Upgrade<T>(JsonElement row, long stamp, long upTo = long.MaxValue)
    {
        var working = JsonNode.Parse(row.GetRawText())!.AsObject();
        object? current = null;

        foreach (var step in StepsFor(typeof(T)).Where(s => s.To > stamp && s.To <= upTo))
        {
            using var doc = JsonDocument.Parse(working.ToJsonString());
            current = step.Method.Invoke(null, new object[] { doc.RootElement.Clone() })
                      ?? throw new InvalidOperationException($"Row migration {step.Method.DeclaringType?.Name}.{step.Method.Name} returned null.");

            // What the step produced replaces the columns it knows; old columns it does not know stay for the next step.
            if (JsonNode.Parse(PluginJson.Serialize(current)) is JsonObject produced)
            {
                foreach (var pair in produced.ToList())
                {
                    working[pair.Key] = pair.Value?.DeepClone();
                }
            }
        }

        return (T)current!;
    }

    /// <summary>The record types that have a row migration, in the record's assembly or the entry assembly.</summary>
    internal static Type[] MigratedTypes() =>
        MigratedTypesAll().Where(t => InfoFor(t) is { Fork: false, Mode: RowMigrationMode.WriteBack }).ToArray();

    private static Type[] MigratedTypesAll()
    {
        var types = new HashSet<Type>(Registered.Keys);
        var entry = Assembly.GetEntryAssembly();
        if (entry is not null)
        {
            foreach (var candidate in SafeTypes(entry))
            {
                foreach (var method in candidate.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
                {
                    if (method.GetCustomAttribute<ExoRowMigrationAttribute>() is { } attr) types.Add(attr.Resource);
                }
            }
        }

        return types.ToArray();
    }

    /// <summary>The newest stamp any row migration of the type leads to.</summary>
    internal static long TargetOf(Type resource) => StepsFor(resource).Max(s => s.To);

    /// <summary>The generation numbers (the row migrations' <c>To</c>) a forking type has, ascending; generation 0 is the original table.</summary>
    internal static long[] Generations(Type resource) => StepsFor(resource).Select(s => s.To).Distinct().ToArray();

    /// <summary>The record as JSON with the guard set, for the write-back.</summary>
    internal static string WithGuard(object upgraded, long stamp)
    {
        var node = JsonNode.Parse(PluginJson.Serialize(upgraded))!.AsObject();
        node[GuardKey] = stamp;
        return node.ToJsonString();
    }
}
