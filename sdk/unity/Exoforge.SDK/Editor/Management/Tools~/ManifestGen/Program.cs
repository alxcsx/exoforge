using System.Collections.ObjectModel;
using System.Reflection;
using System.Text;

namespace Exoforge.ManifestGen;

/// <summary>
/// Generates <c>manifest.exs</c> from a compiled plugin assembly.
///
/// The attributes are read as <see cref="CustomAttributeData"/> and matched by type name rather
/// than by referencing <c>Exoforge.Plugin.SDK</c>. That is what lets this tool ship inside the SDK
/// package with no project or package references: it can be run from anywhere, with nothing to
/// restore, and it works for a plugin cross-built for any RID.
/// </summary>
public static class Program
{
    private const string SdkPrefix = "Exoforge.Plugin.SDK.";

    public static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: Exoforge.ManifestGen <assembly-path> [output-manifest-path] [--type wasm|native] [--build <stamp>]");
            return 1;
        }

        string pluginType = "wasm";
        string? buildHash = null;

        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--type") pluginType = args[i + 1].ToLowerInvariant();
            else if (args[i] == "--build") buildHash = args[i + 1];
        }

        string assemblyPath = Path.GetFullPath(args[0]);

        if (!File.Exists(assemblyPath))
        {
            Console.Error.WriteLine($"Error: Assembly not found at {assemblyPath}");
            return 1;
        }

        string assemblyDir = Path.GetDirectoryName(assemblyPath)!;
        string assemblyName = Path.GetFileNameWithoutExtension(assemblyPath);
        string outputPath = args.Length > 1 ? Path.GetFullPath(args[1]) : Path.Combine(assemblyDir, "manifest.exs");

        Type[] types;
        try
        {
            types = Assembly.LoadFrom(assemblyPath).GetExportedTypes();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: could not read {assemblyPath}: {ex.Message}");
            return 1;
        }

        string pluginId = assemblyName.ToLowerInvariant();
        string pluginVersion = "0.1.0";
        var provides = new List<string>();
        var dependencies = new HashSet<string>();
        var services = new List<ServiceMeta>();

        foreach (var type in types)
        {
            var serviceAttrs = Attrs(type, "ExoServiceAttribute").ToList();
            if (serviceAttrs.Count == 0) continue;

            foreach (var sa in serviceAttrs)
            {
                string name = Positional(sa, 0) as string ?? "";
                if (name.Length > 0 && !provides.Contains(name)) provides.Add(name);

                string? declared = Named<string>(sa, "Version");
                if (!string.IsNullOrEmpty(declared)) pluginVersion = declared;
            }

            string primaryService = Positional(serviceAttrs[0], 0) as string ?? pluginId;

            // Actions
            var actions = new List<ActionMeta>();

            foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance))
            {
                var actionAttr = Attrs(method, "ExoActionAttribute").FirstOrDefault();
                if (actionAttr == null) continue;

                var parameters = method.GetParameters()
                    .Select(p => new ParamMeta(ToSnakeCase(p.Name ?? "arg"), MapTypeToElixir(p.ParameterType)))
                    .ToList();

                string? explicitName = Positional(actionAttr, 0) as string;

                actions.Add(new ActionMeta(
                    string.IsNullOrEmpty(explicitName) ? ToSnakeCase(method.Name) : explicitName!,
                    ResolveActionMode(actionAttr, method.ReturnType),
                    Named<string>(actionAttr, "Scope") ?? "global",
                    parameters,
                    MapTypeToElixir(method.ReturnType),
                    (NamedEnum(actionAttr, "Transport") ?? "auto").ToLowerInvariant()));
            }

            var actionNames = actions.Select(a => a.Name).ToArray();

            // Events
            var events = new List<EventMeta>();

            foreach (var evtAttr in Attrs(type, "ExoEventAttribute"))
            {
                events.Add(CreateEventMeta(evtAttr));
            }

            foreach (var method in type.GetMethods())
            {
                foreach (var evtAttr in Attrs(method, "ExoEventAttribute"))
                {
                    var meta = CreateEventMeta(evtAttr);
                    if (!events.Any(e => e.Name == meta.Name)) events.Add(meta);
                }
            }

            // Resources
            var resources = new List<ResourceMeta>();

            foreach (var sa in serviceAttrs)
            {
                foreach (var resType in TypeArray(sa, "Resources"))
                {
                    resources.Add(ExtractResourceFromType(resType, null, actionNames));
                }
            }

            foreach (var resAttr in Attrs(type, "ExoResourceAttribute"))
            {
                var resourceType = Named<Type>(resAttr, "ResourceType");

                if (resourceType != null)
                {
                    resources.Add(ExtractResourceFromType(resourceType, null, actionNames));
                    continue;
                }

                // Fallback: columns declared directly on the service class.
                var columns = ColumnsFor(type, null, out _);

                if (columns.Count > 0)
                {
                    string resName = Named<string>(resAttr, "Name") ?? Positional(resAttr, 0) as string ?? ToSnakeCase(type.Name);

                    resources.Add(new ResourceMeta(
                        resName,
                        Named<string>(resAttr, "PrimaryKey") ?? "id",
                        StringArray(resAttr, "DrawerTabs") ?? new[] { "overview" },
                        actionNames,
                        columns));
                }
            }

            // Standalone records decorated with [ExoResource] elsewhere in the assembly.
            foreach (var candidate in types)
            {
                if (candidate == type) continue;
                if (Attrs(candidate, "ExoServiceAttribute").Any()) continue;
                if (!Attrs(candidate, "ExoResourceAttribute").Any()) continue;

                var meta = ExtractResourceFromType(candidate, null, actionNames);
                if (!resources.Any(r => r.Name == meta.Name)) resources.Add(meta);
            }

            // Injected dependencies: only an explicit service atom counts. An unnamed [Inject] is a
            // context capability (ILogger, IDatabase, ...), not a plugin dependency.
            foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                var inject = Attrs(prop, "InjectAttribute").FirstOrDefault();
                if (inject == null) continue;

                string? dep = Positional(inject, 0) as string ?? Named<string>(inject, "ServiceName");
                if (!string.IsNullOrEmpty(dep)) dependencies.Add(dep!);
            }

            var first = serviceAttrs[0];

            services.Add(new ServiceMeta(
                primaryService,
                actions,
                events,
                resources,
                Named<string>(first, "Category"),
                Named<string>(first, "Title"),
                Named<string>(first, "Icon"),
                Named<bool>(first, "System")));
        }

        // SemVer build metadata: `1.0.0+<build>.<fingerprint>` so a deploy is traceable to its sources.
        string version = string.IsNullOrEmpty(buildHash) ? pluginVersion : $"{pluginVersion}+{buildHash}";
        string entryPoint = pluginType == "native" ? pluginId : $"{pluginId}.wasm";

        string manifest = EmitElixirManifest(pluginId, version, pluginType, entryPoint, provides, dependencies.ToList(), services);

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        File.WriteAllText(outputPath, manifest, new UTF8Encoding(false));

        Console.WriteLine($"[Exoforge ManifestGen] Successfully generated {outputPath} from {Path.GetFileName(assemblyPath)}");
        return 0;
    }

    // ---- attribute reading -------------------------------------------------------------

    private static IEnumerable<CustomAttributeData> Attrs(MemberInfo member, string attributeName)
    {
        string full = SdkPrefix + attributeName;

        foreach (var data in member.GetCustomAttributesData())
        {
            if (data.AttributeType.FullName == full) yield return data;
        }
    }

    private static object? Positional(CustomAttributeData? attribute, int index) =>
        attribute != null && attribute.ConstructorArguments.Count > index ? attribute.ConstructorArguments[index].Value : null;

    private static T? Named<T>(CustomAttributeData? attribute, string member)
    {
        if (attribute == null) return default;

        foreach (var arg in attribute.NamedArguments)
        {
            if (arg.MemberName == member && arg.TypedValue.Value is T typed) return typed;
        }

        return default;
    }

    /// <summary>
    /// Enum arguments arrive as their underlying value. Resolving the name from the argument's own
    /// type keeps this correct if the enum is ever reordered.
    /// </summary>
    private static string? NamedEnum(CustomAttributeData? attribute, string member)
    {
        if (attribute == null) return null;

        foreach (var arg in attribute.NamedArguments)
        {
            if (arg.MemberName != member) continue;
            return Enum.GetName(arg.TypedValue.ArgumentType, arg.TypedValue.Value!);
        }

        return null;
    }

    private static Type[] TypeArray(CustomAttributeData? attribute, string member)
    {
        if (attribute == null) return Array.Empty<Type>();

        foreach (var arg in attribute.NamedArguments)
        {
            if (arg.MemberName != member) continue;

            if (arg.TypedValue.Value is ReadOnlyCollection<CustomAttributeTypedArgument> items)
            {
                return items.Select(i => i.Value as Type).Where(t => t != null).ToArray()!;
            }
        }

        return Array.Empty<Type>();
    }

    private static string[]? StringArray(CustomAttributeData? attribute, string member)
    {
        if (attribute == null) return null;

        foreach (var arg in attribute.NamedArguments)
        {
            if (arg.MemberName != member) continue;

            if (arg.TypedValue.Value is ReadOnlyCollection<CustomAttributeTypedArgument> items)
            {
                return items.Select(i => i.Value as string ?? "").ToArray();
            }
        }

        return null;
    }

    // ---- metadata ----------------------------------------------------------------------

    private static ResourceMeta ExtractResourceFromType(Type resourceType, string? defaultName, string[]? serviceActions)
    {
        var resAttr = Attrs(resourceType, "ExoResourceAttribute").FirstOrDefault();

        string typeName = resourceType.Name;
        if (typeName.EndsWith("Resource", StringComparison.OrdinalIgnoreCase)) typeName = typeName[..^8];

        string resName = Named<string>(resAttr, "Name")
            ?? (resAttr != null ? Positional(resAttr, 0) as string : null)
            ?? defaultName
            ?? ToSnakeCase(typeName);

        string? primaryKey = Named<string>(resAttr, "PrimaryKey");
        var columns = ColumnsFor(resourceType, resAttr, out primaryKey);

        if (string.IsNullOrEmpty(primaryKey))
        {
            var candidate = columns.FirstOrDefault(c =>
                c.Name == "id" || c.Name == $"{resName}_id" || c.Name.EndsWith("_id"));

            primaryKey = candidate?.Name ?? (columns.Count > 0 ? columns[0].Name : "id");
        }

        return new ResourceMeta(
            resName,
            primaryKey,
            StringArray(resAttr, "DrawerTabs") ?? new[] { "overview", "attributes" },
            serviceActions ?? Array.Empty<string>(),
            columns);
    }

    private static List<ColumnMeta> ColumnsFor(Type type, CustomAttributeData? resourceAttr, out string? primaryKey)
    {
        var columns = new List<ColumnMeta>();
        primaryKey = Named<string>(resourceAttr, "PrimaryKey");

        foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static))
        {
            var colAttr = Attrs(prop, "ExoColumnAttribute").FirstOrDefault();
            var pkAttr = Attrs(prop, "PrimaryKeyAttribute").FirstOrDefault();

            bool isExplicitPk = pkAttr != null || prop.Name.Equals("Id", StringComparison.OrdinalIgnoreCase);

            // Without a [ExoColumn] the property still counts when the record carries [ExoResource].
            if (colAttr == null && pkAttr == null && (resourceAttr == null || !prop.CanRead || prop.GetMethod?.IsPublic != true))
            {
                continue;
            }

            string colName = Named<string>(colAttr, "Name") ?? Positional(colAttr, 0) as string ?? ToSnakeCase(prop.Name);

            columns.Add(new ColumnMeta(
                colName,
                Named<string>(colAttr, "DataType") ?? MapTypeToElixir(prop.PropertyType),
                Named<string>(colAttr, "Label") ?? ToTitleCase(colName),
                Named<bool>(colAttr, "Sortable") || isExplicitPk,
                Named<bool>(colAttr, "Filterable"),
                Named<bool>(colAttr, "Badge")));

            if (pkAttr != null && string.IsNullOrEmpty(primaryKey)) primaryKey = colName;
        }

        return columns;
    }

    private static EventMeta CreateEventMeta(CustomAttributeData attr)
    {
        var payload = new List<ParamMeta>();
        var payloadType = Named<Type>(attr, "PayloadType") ?? Positional(attr, 1) as Type;

        if (payloadType != null)
        {
            foreach (var prop in payloadType.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            {
                payload.Add(new ParamMeta(ToSnakeCase(prop.Name), MapTypeToElixir(prop.PropertyType)));
            }
        }

        return new EventMeta(
            Positional(attr, 0) as string ?? "",
            Named<string>(attr, "Topic"),
            Named<string>(attr, "Scope") ?? "global",
            payload);
    }

    private static string MapTypeToElixir(Type t)
    {
        if (t == typeof(Task)) return "ok";
        if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(Task<>)) return MapTypeToElixir(t.GetGenericArguments()[0]);

        var underlying = Nullable.GetUnderlyingType(t);
        if (underlying != null) t = underlying;

        if (t == typeof(void)) return "ok";
        if (t == typeof(int) || t == typeof(long) || t == typeof(short) || t == typeof(byte) || t == typeof(uint) || t == typeof(ulong)) return "integer";
        if (t == typeof(string) || t == typeof(char)) return "string";
        if (t == typeof(bool)) return "boolean";
        if (t == typeof(float) || t == typeof(double) || t == typeof(decimal)) return "float";
        if (t == typeof(DateTime) || t == typeof(DateTimeOffset)) return "datetime";
        if (t == typeof(Guid)) return "uuid";
        if (t == typeof(byte[])) return "binary";
        return "map";
    }

    /// <summary>ActionMode.Auto resolves from the return type: a Task means async, anything else sync.</summary>
    private static string ResolveActionMode(CustomAttributeData attr, Type returnType)
    {
        string? mode = NamedEnum(attr, "Mode");

        if (mode == null || mode == "Auto")
        {
            return typeof(Task).IsAssignableFrom(returnType) ? "async" : "sync";
        }

        return mode.ToLowerInvariant();
    }

    private static string ToSnakeCase(string name)
    {
        var sb = new StringBuilder(name.Length + 4);

        for (int i = 0; i < name.Length; i++)
        {
            if (char.IsUpper(name[i]) && i > 0) sb.Append('_');
            sb.Append(char.ToLowerInvariant(name[i]));
        }

        return sb.ToString();
    }

    private static string ToTitleCase(string s) =>
        string.Join(" ", s.Replace('_', ' ').Split(' ')
            .Select(w => w.Length > 0 ? char.ToUpperInvariant(w[0]) + w.Substring(1).ToLowerInvariant() : ""));

    // ---- elixir emission ---------------------------------------------------------------

    private static string EmitElixirManifest(
        string id,
        string version,
        string pluginType,
        string entryPoint,
        List<string> provides,
        List<string> dependencies,
        List<ServiceMeta> services)
    {
        var sb = new StringBuilder();
        sb.AppendLine("%{");
        sb.AppendLine($"  id: :{id},");
        sb.AppendLine($"  name: \"{id}\",");
        sb.AppendLine($"  type: :{pluginType},");
        sb.AppendLine($"  version: \"{version}\",");
        sb.AppendLine("  context: :global,");
        sb.AppendLine($"  entry_point: \"{entryPoint}\",");
        sb.Append("  dependencies: [");
        sb.Append(string.Join(", ", dependencies.Select(d => $":{d}")));
        sb.AppendLine("],");
        sb.Append("  provides: [");
        sb.Append(string.Join(", ", provides.Select(p => $":{p}")));
        sb.AppendLine("],");

        var primary = services.FirstOrDefault();

        if (!string.IsNullOrEmpty(primary?.Category)) sb.AppendLine($"  category: \"{primary!.Category}\",");
        if (primary?.System == true) sb.AppendLine("  system: true,");
        if (!string.IsNullOrEmpty(primary?.Title))
        {
            sb.AppendLine($"  dashboard_view: %{{id: :{primary!.Name}, title: \"{primary!.Title}\", icon: \"{primary!.Icon}\"}},");
        }

        sb.AppendLine("  services: [");

        for (int i = 0; i < services.Count; i++)
        {
            var s = services[i];
            sb.AppendLine("    %{");
            sb.AppendLine($"      name: :{s.Name},");

            sb.AppendLine("      actions: [");
            foreach (var a in s.Actions)
            {
                string paramList = string.Join(", ", a.Params.Select(p => $"{p.Name}: :{p.Type}"));
                sb.AppendLine($"        %{{name: :{a.Name}, mode: :{a.Mode}, scope: :{a.Scope}, transport: :{a.Transport}, arity: {a.Params.Count}, params: [{paramList}], returns: :{a.Returns}}},");
            }
            sb.AppendLine("      ],");

            sb.AppendLine("      events: [");
            foreach (var e in s.Events)
            {
                string topicPart = e.Topic != null ? $", topic: \"{e.Topic}\"" : "";
                string payloadPart = e.Payload is { Count: > 0 }
                    ? $", payload: [{string.Join(", ", e.Payload.Select(p => $"{p.Name}: :{p.Type}"))}]"
                    : "";
                sb.AppendLine($"        %{{name: :{e.Name}{topicPart}, scope: :{e.Scope}{payloadPart}}},");
            }
            sb.AppendLine("      ],");

            sb.AppendLine("      resources: [");
            foreach (var r in s.Resources)
            {
                sb.AppendLine("        %{");
                sb.AppendLine($"          name: :{r.Name},");
                sb.AppendLine($"          primary_key: :{r.PrimaryKey},");
                sb.AppendLine($"          drawer: [{string.Join(", ", r.DrawerTabs.Select(d => $":{d}"))}],");
                sb.AppendLine($"          actions: [{string.Join(", ", r.Actions.Select(a => $":{a}"))}],");
                sb.AppendLine("          columns: [");
                foreach (var c in r.Columns)
                {
                    sb.AppendLine($"            %{{name: :{c.Name}, type: :{c.DataType}, label: \"{c.Label}\", sortable: {c.Sortable.ToString().ToLowerInvariant()}, filterable: {c.Filterable.ToString().ToLowerInvariant()}, badge: {c.Badge.ToString().ToLowerInvariant()}}},");
                }
                sb.AppendLine("          ]");
                sb.AppendLine("        },");
            }
            sb.AppendLine("      ]");
            sb.AppendLine(i < services.Count - 1 ? "    }," : "    }");
        }

        sb.AppendLine("  ],");
        sb.AppendLine("  entities: []");
        sb.AppendLine("}");

        return sb.ToString();
    }

    // ---- models ------------------------------------------------------------------------

    private sealed record ServiceMeta(
        string Name,
        List<ActionMeta> Actions,
        List<EventMeta> Events,
        List<ResourceMeta> Resources,
        string? Category = null,
        string? Title = null,
        string? Icon = null,
        bool System = false);

    private sealed record ActionMeta(string Name, string Mode, string Scope, List<ParamMeta> Params, string Returns, string Transport = "auto");
    private sealed record ParamMeta(string Name, string Type);
    private sealed record EventMeta(string Name, string? Topic, string Scope, List<ParamMeta> Payload);
    private sealed record ResourceMeta(string Name, string PrimaryKey, string[] DrawerTabs, string[] Actions, List<ColumnMeta> Columns);
    private sealed record ColumnMeta(string Name, string DataType, string Label, bool Sortable, bool Filterable, bool Badge);
}
