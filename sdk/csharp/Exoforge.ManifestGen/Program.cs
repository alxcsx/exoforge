using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.ManifestGen;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: Exoforge.ManifestGen <assembly-path> [output-manifest-path] [--type wasm|native]");
            return 1;
        }

        // Plugin runtime: `wasm` (reactor guest) or `native` (AOT process).
        string pluginType = "wasm";
        string? buildHash = null;
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--type")
            {
                pluginType = args[i + 1].ToLowerInvariant();
            }
            else if (args[i] == "--build")
            {
                buildHash = args[i + 1];
            }
        }

        string assemblyPath = Path.GetFullPath(args[0]);
        if (!File.Exists(assemblyPath))
        {
            Console.Error.WriteLine($"Error: Assembly not found at {assemblyPath}");
            return 1;
        }

        string assemblyDir = Path.GetDirectoryName(assemblyPath)!;
        string assemblyName = Path.GetFileNameWithoutExtension(assemblyPath);
        string outputPath = args.Length > 1 
            ? Path.GetFullPath(args[1]) 
            : Path.Combine(assemblyDir, "manifest.exs");

        var assembly = Assembly.LoadFrom(assemblyPath);
        var types = assembly.GetExportedTypes();

        string pluginId = assemblyName.ToLowerInvariant();
        string pluginVersion = "0.1.0";
        var provides = new List<string>();
        var dependencies = new HashSet<string>();
        var services = new List<ServiceMeta>();

        foreach (var type in types)
        {
            var serviceAttrs = type.GetCustomAttributes<ExoServiceAttribute>().ToList();
            if (serviceAttrs.Count == 0)
            {
                continue;
            }

            foreach (var sa in serviceAttrs)
            {
                if (!provides.Contains(sa.Name))
                {
                    provides.Add(sa.Name);
                }

                if (!string.IsNullOrEmpty(sa.Version))
                {
                    pluginVersion = sa.Version;
                }
            }

            string primaryService = serviceAttrs.FirstOrDefault()?.Name ?? pluginId;

            // Collect Actions
            var actions = new List<ActionMeta>();
            foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance))
            {
                var actionAttr = method.GetCustomAttribute<ExoActionAttribute>();
                if (actionAttr == null) continue;

                var parameters = method.GetParameters()
                    .Select(p => new ParamMeta(ToSnakeCase(p.Name ?? "arg"), MapTypeToElixir(p.ParameterType)))
                    .ToList();

                actions.Add(new ActionMeta(
                    ActionName(actionAttr, method),
                    ResolveActionMode(actionAttr.Mode, method.ReturnType),
                    actionAttr.Scope,
                    parameters,
                    MapTypeToElixir(method.ReturnType),
                    actionAttr.Transport.ToString().ToLowerInvariant()
                ));
            }

            // Collect Events
            var events = new List<EventMeta>();
            foreach (var evtAttr in type.GetCustomAttributes<ExoEventAttribute>())
            {
                events.Add(CreateEventMeta(evtAttr));
            }
            foreach (var method in type.GetMethods())
            {
                foreach (var evtAttr in method.GetCustomAttributes<ExoEventAttribute>())
                {
                    if (!events.Any(e => e.Name == evtAttr.Name))
                    {
                        events.Add(CreateEventMeta(evtAttr));
                    }
                }
            }

            // Collect Resources
            var resources = new List<ResourceMeta>();
            var actionNames = actions.Select(a => a.Name).ToArray();

            // 1. Explicitly referenced resources in ExoServiceAttribute
            foreach (var sa in serviceAttrs)
            {
                if (sa.Resources != null)
                {
                    foreach (var resType in sa.Resources)
                    {
                        resources.Add(ExtractResourceFromType(resType, null, actionNames));
                    }
                }
            }

            // 2. Resources declared on the service class via [ExoResource]
            foreach (var resAttr in type.GetCustomAttributes<ExoResourceAttribute>())
            {
                if (resAttr.ResourceType != null)
                {
                    resources.Add(ExtractResourceFromType(resAttr.ResourceType, resAttr.Name, actionNames));
                }
                else
                {
                    // Fallback: columns defined directly on the service class
                    var columns = new List<ColumnMeta>();
                    foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static))
                    {
                        var colAttr = prop.GetCustomAttribute<ExoColumnAttribute>();
                        if (colAttr != null)
                        {
                            columns.Add(new ColumnMeta(
                                !string.IsNullOrEmpty(colAttr.Name) ? colAttr.Name : ToSnakeCase(prop.Name),
                                !string.IsNullOrEmpty(colAttr.DataType) ? colAttr.DataType : MapTypeToElixir(prop.PropertyType),
                                colAttr.Label ?? ToTitleCase(!string.IsNullOrEmpty(colAttr.Name) ? colAttr.Name : prop.Name),
                                colAttr.Sortable,
                                colAttr.Filterable,
                                colAttr.Badge
                            ));
                        }
                    }

                    if (columns.Count > 0)
                    {
                        resources.Add(new ResourceMeta(
                            resAttr.Name ?? ToSnakeCase(type.Name),
                            resAttr.PrimaryKey ?? "id",
                            resAttr.DrawerTabs ?? new[] { "overview" },
                            actionNames,
                            columns
                        ));
                    }
                }
            }

            // 3. Standalone classes/records decorated with [ExoResource] in the assembly
            foreach (var candidateType in types)
            {
                if (candidateType == type) continue;
                var resAttr = candidateType.GetCustomAttribute<ExoResourceAttribute>();
                if (resAttr != null && !candidateType.GetCustomAttributes<ExoServiceAttribute>().Any())
                {
                    var resMeta = ExtractResourceFromType(candidateType, null, actionNames);
                    if (!resources.Any(r => r.Name == resMeta.Name))
                    {
                        resources.Add(resMeta);
                    }
                }
            }

            // Collect Injected Dependencies. Only an explicit service atom is a dependency;
            // unnamed [Inject] members are context capabilities (ILogger, IDatabase, ...).
            foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                var inject = prop.GetCustomAttribute<InjectAttribute>();
                if (inject?.ServiceName is { Length: > 0 } dep)
                {
                    dependencies.Add(dep);
                }
            }

            services.Add(new ServiceMeta(
                primaryService,
                actions,
                events,
                resources,
                serviceAttrs.FirstOrDefault()?.Category,
                serviceAttrs.FirstOrDefault()?.Title,
                serviceAttrs.FirstOrDefault()?.Icon,
                serviceAttrs.FirstOrDefault()?.System ?? false));
        }

        // SemVer build metadata: `1.0.0+<source fingerprint>` so a deploy is traceable to its sources.
        string version = string.IsNullOrEmpty(buildHash) ? pluginVersion : $"{pluginVersion}+{buildHash}";
        string entryPoint = pluginType == "native" ? pluginId : $"{pluginId}.wasm";
        string manifestContent = EmitElixirManifest(pluginId, version, pluginType, entryPoint, provides, dependencies.ToList(), services);

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        File.WriteAllText(outputPath, manifestContent, new UTF8Encoding(false));

        Console.WriteLine($"[Exoforge ManifestGen] Successfully generated {outputPath} from {Path.GetFileName(assemblyPath)}");
        return 0;
    }

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

        // Dependencies
        sb.Append("  dependencies: [");
        sb.Append(string.Join(", ", dependencies.Select(d => $":{d}")));
        sb.AppendLine("],");

        // Provides
        sb.Append("  provides: [");
        sb.Append(string.Join(", ", provides.Select(p => $":{p}")));
        sb.AppendLine("],");

        // Presentation metadata (category / system flag / dashboard view)
        var primaryServiceMeta = services.FirstOrDefault();
        if (!string.IsNullOrEmpty(primaryServiceMeta?.Category))
        {
            sb.AppendLine($"  category: \"{primaryServiceMeta!.Category}\",");
        }
        if (primaryServiceMeta?.System == true)
        {
            sb.AppendLine("  system: true,");
        }
        if (!string.IsNullOrEmpty(primaryServiceMeta?.Title))
        {
            sb.AppendLine($"  dashboard_view: %{{id: :{primaryServiceMeta!.Name}, title: \"{primaryServiceMeta!.Title}\", icon: \"{primaryServiceMeta!.Icon}\"}},");
        }

        // Services & Resources Metadata
        sb.AppendLine("  services: [");
        for (int i = 0; i < services.Count; i++)
        {
            var s = services[i];
            sb.AppendLine("    %{");
            sb.AppendLine($"      name: :{s.Name},");

            // Actions
            sb.AppendLine("      actions: [");
            foreach (var a in s.Actions)
            {
                var paramList = string.Join(", ", a.Params.Select(p => $"{p.Name}: :{p.Type}"));
                sb.AppendLine($"        %{{name: :{a.Name}, mode: :{a.Mode}, scope: :{a.Scope}, transport: :{a.Transport}, arity: {a.Params.Count}, params: [{paramList}], returns: :{a.Returns}}},");
            }
            sb.AppendLine("      ],");

            // Events
            sb.AppendLine("      events: [");
            foreach (var e in s.Events)
            {
                string topicPart = e.Topic != null ? $", topic: \"{e.Topic}\"" : "";
                string payloadPart = e.Payload != null && e.Payload.Count > 0
                    ? $", payload: [{string.Join(", ", e.Payload.Select(p => $"{p.Name}: :{p.Type}"))}]"
                    : "";
                sb.AppendLine($"        %{{name: :{e.Name}{topicPart}, scope: :{e.Scope}{payloadPart}}},");
            }
            sb.AppendLine("      ],");

            // Resources
            sb.AppendLine("      resources: [");
            foreach (var r in s.Resources)
            {
                string drawerPart = string.Join(", ", r.DrawerTabs.Select(d => $":{d}"));
                string actionsPart = string.Join(", ", r.Actions.Select(act => $":{act}"));
                sb.AppendLine("        %{");
                sb.AppendLine($"          name: :{r.Name},");
                sb.AppendLine($"          primary_key: :{r.PrimaryKey},");
                sb.AppendLine($"          drawer: [{drawerPart}],");
                sb.AppendLine($"          actions: [{actionsPart}],");
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

        // Entities Metadata (C# plugins declare no stateful entities)
        sb.AppendLine("  entities: []");
        sb.AppendLine("}");

        return sb.ToString();
    }

    private static ResourceMeta ExtractResourceFromType(Type resourceType, string? defaultName = null, string[]? serviceActions = null)
    {
        var resAttr = resourceType.GetCustomAttribute<ExoResourceAttribute>();
        string typeName = resourceType.Name;
        if (typeName.EndsWith("Resource", StringComparison.OrdinalIgnoreCase))
        {
            typeName = typeName[..^8];
        }

        string resName = !string.IsNullOrEmpty(resAttr?.Name)
            ? resAttr.Name
            : defaultName ?? ToSnakeCase(typeName);

        var columns = new List<ColumnMeta>();
        string? primaryKey = resAttr?.PrimaryKey;

        var props = resourceType.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
        foreach (var prop in props)
        {
            var colAttr = prop.GetCustomAttribute<ExoColumnAttribute>();
            var pkAttr = prop.GetCustomAttribute<PrimaryKeyAttribute>();
            bool isExplicitPk = pkAttr != null || prop.Name.Equals("Id", StringComparison.OrdinalIgnoreCase);

            if (colAttr != null || pkAttr != null || (resAttr != null && prop.CanRead && prop.GetMethod?.IsPublic == true))
            {
                string colName = !string.IsNullOrEmpty(colAttr?.Name) ? colAttr.Name : ToSnakeCase(prop.Name);
                string dataType = !string.IsNullOrEmpty(colAttr?.DataType) ? colAttr.DataType : MapTypeToElixir(prop.PropertyType);
                string label = !string.IsNullOrEmpty(colAttr?.Label) ? colAttr.Label : ToTitleCase(colName);
                bool sortable = colAttr?.Sortable ?? isExplicitPk;
                bool filterable = colAttr?.Filterable ?? false;
                bool badge = colAttr?.Badge ?? false;

                if (pkAttr != null && string.IsNullOrEmpty(primaryKey))
                {
                    primaryKey = colName;
                }

                columns.Add(new ColumnMeta(colName, dataType, label, sortable, filterable, badge));
            }
        }

        if (string.IsNullOrEmpty(primaryKey))
        {
            var candidatePk = columns.FirstOrDefault(c =>
                c.Name == "id" ||
                c.Name == $"{resName}_id" ||
                c.Name.EndsWith("_id")
            );
            primaryKey = candidatePk?.Name ?? (columns.Count > 0 ? columns[0].Name : "id");
        }

        var drawerTabs = resAttr?.DrawerTabs ?? new[] { "overview", "attributes" };
        return new ResourceMeta(resName, primaryKey, drawerTabs, serviceActions ?? Array.Empty<string>(), columns);
    }

    private static string MapTypeToElixir(Type t)
    {
        if (t == typeof(Task)) return "ok";
        if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(Task<>))
            return MapTypeToElixir(t.GetGenericArguments()[0]);

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

    private static string ToSnakeCase(string s) => ExoNaming.ToSnakeCase(s);

    /// <summary>Wire action name: an explicit name wins, otherwise the method name in snake_case.</summary>
    private static string ActionName(ExoActionAttribute attr, MethodInfo method) =>
        string.IsNullOrEmpty(attr.Name) ? ExoNaming.ToSnakeCase(method.Name) : attr.Name!;

    /// <summary>Resolves an <see cref="ActionMode.Auto"/> to sync/async from the return type.</summary>
    private static string ResolveActionMode(ActionMode mode, Type returnType) =>
        mode != ActionMode.Auto
            ? mode.ToString().ToLowerInvariant()
            : typeof(Task).IsAssignableFrom(returnType) ? "async" : "sync";

    private static EventMeta CreateEventMeta(ExoEventAttribute attr)
    {
        var payloadFields = new List<ParamMeta>();
        if (attr.PayloadType != null)
        {
            foreach (var prop in attr.PayloadType.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            {
                payloadFields.Add(new ParamMeta(ToSnakeCase(prop.Name), MapTypeToElixir(prop.PropertyType)));
            }
        }
        return new EventMeta(attr.Name, attr.Topic, attr.Scope, payloadFields);
    }

    private static string ToTitleCase(string s) =>
        string.Join(" ", s.Replace('_', ' ').Split(' ').Select(w =>
            w.Length > 0 ? char.ToUpperInvariant(w[0]) + w.Substring(1).ToLowerInvariant() : ""));

    private record ServiceMeta(
        string Name,
        List<ActionMeta> Actions,
        List<EventMeta> Events,
        List<ResourceMeta> Resources,
        string? Category = null,
        string? Title = null,
        string? Icon = null,
        bool System = false);
    private record ActionMeta(string Name, string Mode, string Scope, List<ParamMeta> Params, string Returns, string Transport = "auto");
    private record ParamMeta(string Name, string Type);
    private record EventMeta(string Name, string? Topic, string Scope, List<ParamMeta>? Payload = null);
    private record ResourceMeta(string Name, string PrimaryKey, string[] DrawerTabs, string[] Actions, List<ColumnMeta> Columns);
    private record ColumnMeta(string Name, string DataType, string Label, bool Sortable, bool Filterable, bool Badge);
}
