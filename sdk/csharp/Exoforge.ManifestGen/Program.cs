using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using Exoforge.Plugin.SDK;

namespace Exoforge.ManifestGen;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: Exoforge.ManifestGen <assembly-path> [output-manifest-path]");
            return 1;
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
            if (serviceAttrs.Count == 0 && !typeof(IExoforgePlugin).IsAssignableFrom(type))
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
                    actionAttr.Name,
                    actionAttr.Mode.ToString().ToLowerInvariant(),
                    actionAttr.Scope,
                    parameters,
                    MapTypeToElixir(method.ReturnType)
                ));
            }

            // Collect Events
            var events = new List<EventMeta>();
            foreach (var evtAttr in type.GetCustomAttributes<ExoEventAttribute>())
            {
                events.Add(new EventMeta(evtAttr.Name, evtAttr.Topic, evtAttr.Scope));
            }
            foreach (var method in type.GetMethods())
            {
                foreach (var evtAttr in method.GetCustomAttributes<ExoEventAttribute>())
                {
                    if (!events.Any(e => e.Name == evtAttr.Name))
                    {
                        events.Add(new EventMeta(evtAttr.Name, evtAttr.Topic, evtAttr.Scope));
                    }
                }
            }

            // Collect Resources
            var resources = new List<ResourceMeta>();
            foreach (var resAttr in type.GetCustomAttributes<ExoResourceAttribute>())
            {
                var columns = new List<ColumnMeta>();
                foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static))
                {
                    var colAttr = prop.GetCustomAttribute<ExoColumnAttribute>();
                    if (colAttr != null)
                    {
                        columns.Add(new ColumnMeta(
                            colAttr.Name,
                            colAttr.DataType,
                            colAttr.Label ?? ToTitleCase(colAttr.Name),
                            colAttr.Sortable,
                            colAttr.Filterable,
                            colAttr.Badge
                        ));
                    }
                }

                resources.Add(new ResourceMeta(
                    resAttr.Name,
                    resAttr.PrimaryKey,
                    resAttr.DrawerTabs ?? new[] { "overview" },
                    actions.Select(a => a.Name).ToArray(),
                    columns
                ));
            }

            // Collect Injected Dependencies
            foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                var inject = prop.GetCustomAttribute<InjectAttribute>();
                if (inject != null)
                {
                    string dep = inject.ServiceName ?? prop.PropertyType.Name.TrimStart('I').ToLowerInvariant();
                    dependencies.Add(dep);
                }
            }

            services.Add(new ServiceMeta(primaryService, actions, events, resources));
        }

        string entryPoint = $"{pluginId}.wasm";
        string manifestContent = EmitElixirManifest(pluginId, pluginVersion, entryPoint, provides, dependencies.ToList(), services);

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        File.WriteAllText(outputPath, manifestContent, new UTF8Encoding(false));

        Console.WriteLine($"[Exoforge ManifestGen] Successfully generated {outputPath} from {Path.GetFileName(assemblyPath)}");
        return 0;
    }

    private static string EmitElixirManifest(
        string id,
        string version,
        string entryPoint,
        List<string> provides,
        List<string> dependencies,
        List<ServiceMeta> services)
    {
        var sb = new StringBuilder();
        sb.AppendLine("%{");
        sb.AppendLine($"  id: :{id},");
        sb.AppendLine($"  name: \"{id}\",");
        sb.AppendLine("  type: :wasm,");
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
                sb.AppendLine($"        %{{name: :{a.Name}, mode: :{a.Mode}, scope: :{a.Scope}, arity: {a.Params.Count}, params: [{paramList}], returns: :{a.Returns}}},");
            }
            sb.AppendLine("      ],");

            // Events
            sb.AppendLine("      events: [");
            foreach (var e in s.Events)
            {
                string topicPart = e.Topic != null ? $", topic: \"{e.Topic}\"" : "";
                sb.AppendLine($"        %{{name: :{e.Name}{topicPart}, scope: :{e.Scope}}},");
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
        sb.AppendLine("  ]");
        sb.AppendLine("}");

        return sb.ToString();
    }

    private static string MapTypeToElixir(Type t)
    {
        if (t == typeof(void)) return "ok";
        if (t == typeof(int) || t == typeof(long) || t == typeof(short) || t == typeof(byte)) return "integer";
        if (t == typeof(string)) return "string";
        if (t == typeof(bool)) return "boolean";
        if (t == typeof(float) || t == typeof(double) || t == typeof(decimal)) return "float";
        if (t == typeof(byte[])) return "binary";
        return "map";
    }

    private static string ToSnakeCase(string s)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            if (char.IsUpper(s[i]) && i > 0)
            {
                sb.Append('_');
            }
            sb.Append(char.ToLowerInvariant(s[i]));
        }
        return sb.ToString();
    }

    private static string ToTitleCase(string s) =>
        string.Join(" ", s.Replace('_', ' ').Split(' ').Select(w =>
            w.Length > 0 ? char.ToUpperInvariant(w[0]) + w.Substring(1).ToLowerInvariant() : ""));

    private record ServiceMeta(string Name, List<ActionMeta> Actions, List<EventMeta> Events, List<ResourceMeta> Resources);
    private record ActionMeta(string Name, string Mode, string Scope, List<ParamMeta> Params, string Returns);
    private record ParamMeta(string Name, string Type);
    private record EventMeta(string Name, string? Topic, string Scope);
    private record ResourceMeta(string Name, string PrimaryKey, string[] DrawerTabs, string[] Actions, List<ColumnMeta> Columns);
    private record ColumnMeta(string Name, string DataType, string Label, bool Sortable, bool Filterable, bool Badge);
}
