using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;

namespace Exoforge.Management;

public class ServiceContractModel
{
    public string Name { get; set; } = string.Empty;
    public string? Doc { get; set; }
    public List<ActionContractModel> Actions { get; set; } = new();
    public List<EventContractModel> Events { get; set; } = new();
    public List<ResourceContractModel> Resources { get; set; } = new();
}

public class ActionContractModel
{
    public string Name { get; set; } = string.Empty;
    public string? Doc { get; set; }
    public string Scope { get; set; } = "global";
    public List<ParamModel> Params { get; set; } = new();
    public string? ReturnType { get; set; }
}

public class ParamModel
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = "term";
    public bool Optional { get; set; }
}

public class EventContractModel
{
    public string Name { get; set; } = string.Empty;
    public string? Topic { get; set; }
}

public class ResourceContractModel
{
    public string Name { get; set; } = string.Empty;
    public string? PrimaryKey { get; set; }
    public List<ResourceColumnModel> Columns { get; set; } = new();
}

public class ResourceColumnModel
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = "string";
}

public static class ExoCodeGenerator
{
    private static readonly HashSet<string> CsharpKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char",
        "checked", "class", "const", "continue", "decimal", "default", "delegate", "do",
        "double", "else", "enum", "event", "explicit", "extern", "false", "finally",
        "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "int",
        "interface", "internal", "is", "lock", "long", "namespace", "new", "null",
        "object", "operator", "out", "override", "params", "private", "protected",
        "public", "readonly", "record", "ref", "return", "sbyte", "sealed", "short",
        "sizeof", "stackalloc", "static", "string", "struct", "switch", "this",
        "throw", "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe",
        "ushort", "using", "virtual", "void", "volatile", "while"
    };

    public static string GenerateFromExportJson(string json, string targetNamespace = "Exoforge.Client")
    {
        using var doc = JsonDocument.Parse(json);
        var services = ParseServices(doc.RootElement);
        return Generate(services, targetNamespace);
    }

    public static void GenerateToFile(string json, string outputPath, string targetNamespace = "Exoforge.Client")
    {
        string code = GenerateFromExportJson(json, targetNamespace);
        string? dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }
        File.WriteAllText(outputPath, code);
    }

    private static List<ServiceContractModel> ParseServices(JsonElement root)
    {
        var result = new Dictionary<string, ServiceContractModel>(StringComparer.OrdinalIgnoreCase);

        JsonElement pluginsElement = root;
        if (root.TryGetProperty("export", out var exportProp))
        {
            pluginsElement = exportProp;
        }

        if (pluginsElement.TryGetProperty("plugins", out var pluginsArray) && pluginsArray.ValueKind == JsonValueKind.Array)
        {
            foreach (var plugin in pluginsArray.EnumerateArray())
            {
                if (plugin.TryGetProperty("services", out var servicesArray) && servicesArray.ValueKind == JsonValueKind.Array)
                {
                    foreach (var svc in servicesArray.EnumerateArray())
                    {
                        var model = ParseServiceElement(svc);
                        if (!string.IsNullOrEmpty(model.Name))
                        {
                            result[model.Name] = model;
                        }
                    }
                }

                // If services is empty but provides is present, create basic service entry
                if (plugin.TryGetProperty("provides", out var providesArray) && providesArray.ValueKind == JsonValueKind.Array)
                {
                    foreach (var p in providesArray.EnumerateArray())
                    {
                        string sName = p.GetString() ?? "";
                        if (!string.IsNullOrEmpty(sName) && !result.ContainsKey(sName))
                        {
                            result[sName] = new ServiceContractModel { Name = sName };
                        }
                    }
                }
            }
        }

        return new List<ServiceContractModel>(result.Values);
    }

    private static ServiceContractModel ParseServiceElement(JsonElement svc)
    {
        var model = new ServiceContractModel
        {
            Name = svc.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "",
            Doc = svc.TryGetProperty("doc", out var d) ? d.GetString() : null
        };

        if (svc.TryGetProperty("actions", out var actions) && actions.ValueKind == JsonValueKind.Array)
        {
            foreach (var act in actions.EnumerateArray())
            {
                var aModel = new ActionContractModel
                {
                    Name = act.TryGetProperty("name", out var an) ? an.GetString() ?? "" : "",
                    Doc = act.TryGetProperty("doc", out var ad) ? ad.GetString() : null,
                    Scope = act.TryGetProperty("scope", out var sc) ? sc.GetString() ?? "global" : "global"
                };

                if (act.TryGetProperty("params", out var pArray) && pArray.ValueKind == JsonValueKind.Array)
                {
                    foreach (var p in pArray.EnumerateArray())
                    {
                        aModel.Params.Add(new ParamModel
                        {
                            Name = p.TryGetProperty("name", out var pn) ? pn.GetString() ?? "" : "",
                            Type = p.TryGetProperty("type", out var pt) ? pt.GetString() ?? "term" : "term",
                            Optional = p.TryGetProperty("optional", out var po) && po.GetBoolean()
                        });
                    }
                }

                model.Actions.Add(aModel);
            }
        }

        return model;
    }

    public static string Generate(IEnumerable<ServiceContractModel> services, string targetNamespace = "Exoforge.Client")
    {
        var sb = new StringBuilder();

        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     This code was generated by Exoforge C# Management Engine.");
        sb.AppendLine("//     Do not modify this file directly. Changes will be overwritten.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine();
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("using System;");
        sb.AppendLine("using System.Collections.Generic;");
        sb.AppendLine("using System.Runtime.CompilerServices;");
        sb.AppendLine("using System.Text.Json;");
        sb.AppendLine("using System.Threading;");
        sb.AppendLine("using System.Threading.Tasks;");
        sb.AppendLine();
        sb.AppendLine($"namespace {targetNamespace};");
        sb.AppendLine();

        // 1. Extensions
        sb.AppendLine("/// <summary>");
        sb.AppendLine("/// Extension methods providing strongly-typed access to Exoforge services from ExoClient.");
        sb.AppendLine("/// </summary>");
        sb.AppendLine("public static class ExoClientGeneratedExtensions");
        sb.AppendLine("{");
        sb.AppendLine("    private static readonly ConditionalWeakTable<ExoClient, ExoforgeServicesHub> _hubs = new();");
        sb.AppendLine();
        sb.AppendLine("    public static ExoforgeServicesHub Services(this ExoClient client) =>");
        sb.AppendLine("        _hubs.GetValue(client, c => new ExoforgeServicesHub(c));");
        sb.AppendLine();

        foreach (var svc in services)
        {
            string pascalName = ToPascalCase(svc.Name);
            sb.AppendLine($"    /// <summary>Access the {pascalName} service contract.</summary>");
            sb.AppendLine($"    public static {pascalName}ServiceClient {pascalName}(this ExoClient client) =>");
            sb.AppendLine($"        client.Services().{pascalName};");
            sb.AppendLine();
        }
        sb.AppendLine("}");
        sb.AppendLine();

        // 2. Hub
        sb.AppendLine("/// <summary>");
        sb.AppendLine("/// Central hub managing service client instances per ExoClient.");
        sb.AppendLine("/// </summary>");
        sb.AppendLine("public class ExoforgeServicesHub");
        sb.AppendLine("{");
        sb.AppendLine("    private readonly ExoClient _client;");
        sb.AppendLine();
        sb.AppendLine("    public ExoforgeServicesHub(ExoClient client)");
        sb.AppendLine("    {");
        sb.AppendLine("        _client = client ?? throw new ArgumentNullException(nameof(client));");
        sb.AppendLine("    }");
        sb.AppendLine();

        foreach (var svc in services)
        {
            string pascalName = ToPascalCase(svc.Name);
            string fieldName = $"_{svc.Name.ToLowerInvariant().Replace("-", "_")}";
            sb.AppendLine($"    private {pascalName}ServiceClient? {fieldName};");
            sb.AppendLine($"    public {pascalName}ServiceClient {pascalName} => {fieldName} ??= new {pascalName}ServiceClient(_client);");
            sb.AppendLine();
        }
        sb.AppendLine("}");
        sb.AppendLine();

        // 3. Service Clients
        foreach (var svc in services)
        {
            string pascalName = ToPascalCase(svc.Name);
            sb.AppendLine($"/// <summary>Client interface for the {svc.Name} service.</summary>");
            sb.AppendLine($"public class {pascalName}ServiceClient");
            sb.AppendLine("{");
            sb.AppendLine("    private readonly ExoClient _client;");
            sb.AppendLine();
            sb.AppendLine($"    public {pascalName}ServiceClient(ExoClient client)");
            sb.AppendLine("    {");
            sb.AppendLine("        _client = client ?? throw new ArgumentNullException(nameof(client));");
            sb.AppendLine("    }");
            sb.AppendLine();

            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                sb.AppendLine($"    /// <summary>{act.Doc ?? $"Executes {act.Name} action."}</summary>");
                sb.AppendLine($"    public Task<JsonElement> {actPascal}Async(object? payload = null, CancellationToken cancellationToken = default)");
                sb.AppendLine("    {");
                sb.AppendLine($"        return _client.SendActionAsync<JsonElement>(\"{svc.Name}\", \"{act.Name}\", payload, cancellationToken: cancellationToken);");
                sb.AppendLine("    }");
                sb.AppendLine();
            }

            sb.AppendLine("}");
            sb.AppendLine();
        }

        return sb.ToString();
    }

    private static string ToPascalCase(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        string[] parts = text.Split(new[] { '_', '-' }, StringSplitOptions.RemoveEmptyEntries);
        for (int i = 0; i < parts.Length; i++)
        {
            if (parts[i].Length > 0)
            {
                parts[i] = char.ToUpperInvariant(parts[i][0]) + parts[i].Substring(1);
            }
        }
        return string.Join("", parts);
    }
}
