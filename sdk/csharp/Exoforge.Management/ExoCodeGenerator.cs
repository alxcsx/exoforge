using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
    public string Transport { get; set; } = "auto";
    public List<ParamModel> Params { get; set; } = new();
    public List<ParamModel> ReturnFields { get; set; } = new();
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
    public string? Doc { get; set; }
    public List<ParamModel> PayloadFields { get; set; } = new();
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

        // Actions
        if (svc.TryGetProperty("actions", out var actions) && actions.ValueKind == JsonValueKind.Array)
        {
            foreach (var act in actions.EnumerateArray())
            {
                var aModel = new ActionContractModel
                {
                    Name = act.TryGetProperty("name", out var an) ? an.GetString() ?? "" : "",
                    Doc = act.TryGetProperty("doc", out var ad) ? ad.GetString() : null,
                    Scope = act.TryGetProperty("scope", out var sc) ? sc.GetString() ?? "global" : "global",
                    Transport = act.TryGetProperty("transport", out var tr) ? tr.GetString() ?? "auto" : "auto"
                };

                // Parameters
                if (act.TryGetProperty("params", out var pArray))
                {
                    if (pArray.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var p in pArray.EnumerateArray())
                        {
                            if (p.ValueKind == JsonValueKind.Object)
                            {
                                aModel.Params.Add(new ParamModel
                                {
                                    Name = p.TryGetProperty("name", out var pn) ? pn.GetString() ?? "" : "",
                                    Type = p.TryGetProperty("type", out var pt) ? pt.GetString() ?? "term" : "term",
                                    Optional = p.TryGetProperty("optional", out var po) && po.GetBoolean()
                                });
                            }
                        }
                    }
                    else if (pArray.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var prop in pArray.EnumerateObject())
                        {
                            string pType = prop.Value.ValueKind == JsonValueKind.String ? prop.Value.GetString() ?? "term" : "term";
                            aModel.Params.Add(new ParamModel { Name = prop.Name, Type = pType });
                        }
                    }
                }

                // Return fields
                if (act.TryGetProperty("returns", out var retElem))
                {
                    if (retElem.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var prop in retElem.EnumerateObject())
                        {
                            string fType = prop.Value.ValueKind == JsonValueKind.String ? prop.Value.GetString() ?? "term" : "term";
                            aModel.ReturnFields.Add(new ParamModel { Name = prop.Name, Type = fType });
                        }
                    }
                    else if (retElem.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var r in retElem.EnumerateArray())
                        {
                            if (r.ValueKind == JsonValueKind.Object)
                            {
                                string rName = r.TryGetProperty("name", out var rn) ? rn.GetString() ?? "" : "";
                                string rType = r.TryGetProperty("type", out var rt) ? rt.GetString() ?? "term" : "term";
                                if (!string.IsNullOrEmpty(rName))
                                {
                                    aModel.ReturnFields.Add(new ParamModel { Name = rName, Type = rType });
                                }
                            }
                        }
                    }
                    else if (retElem.ValueKind == JsonValueKind.String)
                    {
                        aModel.ReturnType = retElem.GetString();
                    }
                }

                model.Actions.Add(aModel);
            }
        }

        // Events
        if (svc.TryGetProperty("events", out var events) && events.ValueKind == JsonValueKind.Array)
        {
            foreach (var evt in events.EnumerateArray())
            {
                var eModel = new EventContractModel
                {
                    Name = evt.TryGetProperty("name", out var en) ? en.GetString() ?? "" : "",
                    Topic = evt.TryGetProperty("topic", out var et) ? et.GetString() : null,
                    Doc = evt.TryGetProperty("doc", out var ed) ? ed.GetString() : null
                };

                if (evt.TryGetProperty("payload", out var payloadObj))
                {
                    if (payloadObj.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var p in payloadObj.EnumerateArray())
                        {
                            if (p.ValueKind == JsonValueKind.Object)
                            {
                                eModel.PayloadFields.Add(new ParamModel
                                {
                                    Name = p.TryGetProperty("name", out var pn) ? pn.GetString() ?? "" : "",
                                    Type = p.TryGetProperty("type", out var pt) ? pt.GetString() ?? "term" : "term"
                                });
                            }
                        }
                    }
                    else if (payloadObj.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var prop in payloadObj.EnumerateObject())
                        {
                            string pType = prop.Value.ValueKind == JsonValueKind.String ? prop.Value.GetString() ?? "term" : "term";
                            eModel.PayloadFields.Add(new ParamModel { Name = prop.Name, Type = pType });
                        }
                    }
                }

                model.Events.Add(eModel);
            }
        }

        // Resources
        if (svc.TryGetProperty("resources", out var resources) && resources.ValueKind == JsonValueKind.Array)
        {
            foreach (var res in resources.EnumerateArray())
            {
                var rModel = new ResourceContractModel
                {
                    Name = res.TryGetProperty("name", out var rn) ? rn.GetString() ?? "" : "",
                    PrimaryKey = res.TryGetProperty("primary_key", out var pk) ? pk.GetString() : null
                };

                if (res.TryGetProperty("columns", out var cols) && cols.ValueKind == JsonValueKind.Array)
                {
                    foreach (var col in cols.EnumerateArray())
                    {
                        rModel.Columns.Add(new ResourceColumnModel
                        {
                            Name = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "",
                            Type = col.TryGetProperty("type", out var ct) ? ct.GetString() ?? "string" : "string"
                        });
                    }
                }

                model.Resources.Add(rModel);
            }
        }

        return model;
    }

    /// <summary>
    /// Generates typed plugin service stubs from the contract export: request/response records plus a
    /// client per service that calls through <see cref="Exoforge.Plugin.SDK.IActionDispatcher"/>. The
    /// stubs depend only on the service contract, never on the plugin that implements it.
    /// </summary>
    public static string GeneratePluginStubs(string json, string targetNamespace = "Exoforge.Plugins.Generated")
    {
        using var doc = JsonDocument.Parse(json);
        return GeneratePluginStubs(ParseServices(doc.RootElement), targetNamespace);
    }

    public static void GeneratePluginStubsToFile(string json, string outputPath, string targetNamespace = "Exoforge.Plugins.Generated")
    {
        string code = GeneratePluginStubs(json, targetNamespace);
        string? dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        File.WriteAllText(outputPath, code);
    }

    public static string GeneratePluginStubs(IEnumerable<ServiceContractModel> services, string targetNamespace = "Exoforge.Plugins.Generated")
    {
        var serviceList = services.ToList();
        var sb = new StringBuilder();
        var serializable = new List<string>();

        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     Typed plugin service stubs generated from the cluster contract export.");
        sb.AppendLine("//     Do not edit. Regenerate with `exo plugin stubs <name>`.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine();
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("using System.Text.Json;");
        sb.AppendLine("using System.Text.Json.Serialization;");
        sb.AppendLine("using System.Threading.Tasks;");
        sb.AppendLine("using Exoforge.Plugin.SDK;");
        sb.AppendLine();
        sb.AppendLine($"namespace {targetNamespace}");
        sb.AppendLine("{");

        // Models
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);

            foreach (var res in svc.Resources)
            {
                string typeName = $"{svcPascal}{ResourceTypeName(res)}";
                serializable.Add(typeName);

                sb.AppendLine($"    /// <summary>{svc.Name}.{res.Name} resource.</summary>");
                sb.AppendLine($"    public class {typeName}");
                sb.AppendLine("    {");
                foreach (var col in res.Columns)
                {
                    sb.AppendLine($"        [JsonPropertyName(\"{col.Name}\")]");
                    sb.AppendLine($"        public {MapTypeToCSharp(col.Type)} {ToPascalCase(col.Name)} {{ get; set; }} = default!;");
                }
                sb.AppendLine("    }");
                sb.AppendLine();
            }

            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                string reqName = $"{svcPascal}{actPascal}Request";
                serializable.Add(reqName);

                sb.AppendLine($"    /// <summary>Request payload for {svc.Name}.{act.Name}.</summary>");
                sb.AppendLine($"    public class {reqName}");
                sb.AppendLine("    {");
                foreach (var p in act.Params)
                {
                    sb.AppendLine($"        [JsonPropertyName(\"{p.Name}\")]");
                    sb.AppendLine($"        public {MapTypeToCSharp(p.Type)} {ToPascalCase(p.Name)} {{ get; set; }} = default!;");
                }
                sb.AppendLine("    }");
                sb.AppendLine();

                if (act.ReturnFields.Count > 0)
                {
                    string respName = $"{svcPascal}{actPascal}Response";
                    serializable.Add(respName);

                    sb.AppendLine($"    /// <summary>Response payload for {svc.Name}.{act.Name}.</summary>");
                    sb.AppendLine($"    public class {respName}");
                    sb.AppendLine("    {");
                    foreach (var f in act.ReturnFields)
                    {
                        sb.AppendLine($"        [JsonPropertyName(\"{f.Name}\")]");
                        sb.AppendLine($"        public {MapReturnFieldType(svc, f)} {ToPascalCase(f.Name)} {{ get; set; }} = default!;");
                    }
                    sb.AppendLine("    }");
                    sb.AppendLine();
                }
            }

            foreach (var evt in svc.Events)
            {
                string evtName = $"{svcPascal}{ToPascalCase(evt.Name)}Event";
                serializable.Add(evtName);

                sb.AppendLine($"    /// <summary>Event payload for {evt.Name}.</summary>");
                sb.AppendLine($"    public class {evtName}");
                sb.AppendLine("    {");
                foreach (var f in evt.PayloadFields)
                {
                    sb.AppendLine($"        [JsonPropertyName(\"{f.Name}\")]");
                    sb.AppendLine($"        public {MapTypeToCSharp(f.Type)} {ToPascalCase(f.Name)} {{ get; set; }} = default!;");
                }
                sb.AppendLine("    }");
                sb.AppendLine();
            }
        }

        // Clients
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);

            sb.AppendLine($"    /// <summary>Typed client for the {svc.Name} service contract.</summary>");
            sb.AppendLine($"    public sealed class {svcPascal}ServiceClient");
            sb.AppendLine("    {");
            sb.AppendLine("        private readonly IActionDispatcher _dispatcher;");
            sb.AppendLine();
            sb.AppendLine($"        public {svcPascal}ServiceClient(IActionDispatcher dispatcher) => _dispatcher = dispatcher;");
            sb.AppendLine();

            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                string reqName = $"{svcPascal}{actPascal}Request";
                string respType = act.ReturnFields.Count > 0 ? $"{svcPascal}{actPascal}Response" : "JsonElement";
                string declaration = respType == "JsonElement" ? "JsonElement" : respType + "?";

                sb.AppendLine($"        /// <summary>{act.Doc ?? $"Calls {svc.Name}.{act.Name}."}</summary>");
                sb.AppendLine($"        public Task<{declaration}> {actPascal}Async({reqName} request)");
                sb.AppendLine($"            => _dispatcher.CallActionAsync<{respType}>(\"{svc.Name}\", \"{act.Name}\", request);");
                sb.AppendLine();

                if (act.Params.Count == 0)
                {
                    sb.AppendLine($"        /// <summary>{act.Doc ?? $"Calls {svc.Name}.{act.Name}."}</summary>");
                    sb.AppendLine($"        public Task<{declaration}> {actPascal}Async()");
                    sb.AppendLine($"            => {actPascal}Async(new {reqName}());");
                    sb.AppendLine();
                }
            }

            sb.AppendLine("    }");
            sb.AppendLine();
        }

        // Hub
        sb.AppendLine("    /// <summary>Typed access to every service contract over one IActionDispatcher.</summary>");
        sb.AppendLine("    public sealed class ExoforgePluginServices");
        sb.AppendLine("    {");
        sb.AppendLine("        private readonly IActionDispatcher _dispatcher;");
        sb.AppendLine();
        sb.AppendLine("        public ExoforgePluginServices(IActionDispatcher dispatcher) => _dispatcher = dispatcher;");
        sb.AppendLine();
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);
            string field = "_" + svc.Name.ToLowerInvariant().Replace("-", "_");
            sb.AppendLine($"        private {svcPascal}ServiceClient? {field};");
            sb.AppendLine($"        public {svcPascal}ServiceClient {svcPascal} => {field} ??= new {svcPascal}ServiceClient(_dispatcher);");
        }
        sb.AppendLine("    }");
        sb.AppendLine();

        // Context + self-registration
        if (serializable.Count > 0)
        {
            sb.AppendLine("    /// <summary>Source-generated JSON metadata for the contract stubs.</summary>");
            sb.AppendLine("    [JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]");
            foreach (var type in serializable.Distinct())
            {
                sb.AppendLine($"    [JsonSerializable(typeof({type}))]");
            }
            sb.AppendLine("    public partial class GeneratedServicesJsonContext : JsonSerializerContext");
            sb.AppendLine("    {");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    internal static class GeneratedServicesBootstrap");
            sb.AppendLine("    {");
            sb.AppendLine("        [System.Runtime.CompilerServices.ModuleInitializer]");
            sb.AppendLine("        internal static void Init() => PluginJson.AddContext(GeneratedServicesJsonContext.Default);");
            sb.AppendLine("    }");
        }

        sb.AppendLine("}");
        return sb.ToString();
    }

    private static string MapReturnFieldType(ServiceContractModel svc, ParamModel field)
    {
        string lower = field.Type.ToLowerInvariant();
        if (lower is "map" or "term" or "object")
        {
            var resource = svc.Resources.FirstOrDefault(r => MatchesFieldName(field.Name, r.Name));
            if (resource != null) return $"{ToPascalCase(svc.Name)}{ResourceTypeName(resource)}";
        }

        return MapTypeToCSharp(field.Type);
    }

    private static bool MatchesFieldName(string field, string resourceName) =>
        string.Equals(field, resourceName, StringComparison.OrdinalIgnoreCase) ||
        string.Equals(field, Singularize(resourceName), StringComparison.OrdinalIgnoreCase);

    private static string ResourceTypeName(ResourceContractModel resource) => ToPascalCase(Singularize(resource.Name));

    private static string Singularize(string name) =>
        name.EndsWith("s", StringComparison.Ordinal) &&
        !name.EndsWith("ss", StringComparison.Ordinal) &&
        !name.EndsWith("us", StringComparison.Ordinal)
            ? name.Substring(0, name.Length - 1)
            : name;

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
        sb.AppendLine("using System.Text.Json.Serialization;");
        sb.AppendLine("using System.Threading;");
        sb.AppendLine("using System.Threading.Tasks;");
        sb.AppendLine($"namespace {targetNamespace}");
        sb.AppendLine("{");

        // 1. Strongly-typed Models (Requests, Responses, Events)
        foreach (var svc in services)
        {
            string svcPascal = ToPascalCase(svc.Name);

            // Action Request & Response Models
            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);

                if (act.Params.Count > 0)
                {
                    sb.AppendLine($"/// <summary>Request payload for {svc.Name}.{act.Name} action.</summary>");
                    sb.AppendLine($"public class {svcPascal}{actPascal}Request");
                    sb.AppendLine("{");
                    foreach (var p in act.Params)
                    {
                        string propName = ToPascalCase(p.Name);
                        string csType = MapTypeToCSharp(p.Type);
                        sb.AppendLine($"    [JsonPropertyName(\"{p.Name}\")]");
                        sb.AppendLine($"    public {csType} {propName} {{ get; set; }} = default!;");
                    }
                    sb.AppendLine("}");
                    sb.AppendLine();
                }

                if (act.ReturnFields.Count > 0)
                {
                    sb.AppendLine($"/// <summary>Response model for {svc.Name}.{act.Name} action.</summary>");
                    sb.AppendLine($"public class {svcPascal}{actPascal}Response");
                    sb.AppendLine("{");
                    foreach (var r in act.ReturnFields)
                    {
                        string propName = ToPascalCase(r.Name);
                        string csType = MapTypeToCSharp(r.Type);
                        sb.AppendLine($"    [JsonPropertyName(\"{r.Name}\")]");
                        sb.AppendLine($"    public {csType} {propName} {{ get; set; }} = default!;");
                    }
                    sb.AppendLine("}");
                    sb.AppendLine();
                }
            }

            // Event Models
            foreach (var evt in svc.Events)
            {
                string evtPascal = ToPascalCase(evt.Name);
                sb.AppendLine($"/// <summary>Event payload for {evt.Topic ?? svc.Name} -> {evt.Name}.</summary>");
                sb.AppendLine($"public class {svcPascal}{evtPascal}Event");
                sb.AppendLine("{");
                if (evt.PayloadFields.Count > 0)
                {
                    foreach (var f in evt.PayloadFields)
                    {
                        string propName = ToPascalCase(f.Name);
                        string csType = MapTypeToCSharp(f.Type);
                        sb.AppendLine($"    [JsonPropertyName(\"{f.Name}\")]");
                        sb.AppendLine($"    public {csType} {propName} {{ get; set; }} = default!;");
                    }
                }
                else
                {
                    sb.AppendLine("    [JsonExtensionData]");
                    sb.AppendLine("    public Dictionary<string, JsonElement>? ExtraData { get; set; }");
                }
                sb.AppendLine("}");
                sb.AppendLine();
            }
        }

        // 2. Extensions on ExoClient
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

        // 3. Central Hub
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

        // 4. Service Clients
        foreach (var svc in services)
        {
            string svcPascal = ToPascalCase(svc.Name);
            sb.AppendLine($"/// <summary>Client interface for the {svc.Name} service.</summary>");
            sb.AppendLine($"public class {svcPascal}ServiceClient");
            sb.AppendLine("{");
            sb.AppendLine("    private readonly ExoClient _client;");
            sb.AppendLine();

            // Event delegates
            foreach (var evt in svc.Events)
            {
                string evtPascal = ToPascalCase(evt.Name);
                sb.AppendLine($"    /// <summary>Fired when server emits {evt.Name} event.</summary>");
                sb.AppendLine($"    public event Action<{svcPascal}{evtPascal}Event>? On{evtPascal};");
            }
            if (svc.Events.Count > 0) sb.AppendLine();

            sb.AppendLine($"    public {svcPascal}ServiceClient(ExoClient client)");
            sb.AppendLine("    {");
            sb.AppendLine("        _client = client ?? throw new ArgumentNullException(nameof(client));");

            if (svc.Events.Count > 0)
            {
                sb.AppendLine("        _client.OnAnyEvent += HandleIncomingEvent;");
            }

            sb.AppendLine("    }");
            sb.AppendLine();

            if (svc.Events.Count > 0)
            {
                sb.AppendLine("    private void HandleIncomingEvent(ExoEventFrame evt)");
                sb.AppendLine("    {");
                foreach (var evt in svc.Events)
                {
                    string evtPascal = ToPascalCase(evt.Name);
                    sb.AppendLine($"        if (evt.Event == \"{evt.Name}\" && On{evtPascal} != null)");
                    sb.AppendLine("        {");
                    sb.AppendLine($"            var parsed = evt.DeserializePayload<{svcPascal}{evtPascal}Event>();");
                    sb.AppendLine($"            if (parsed != null) On{evtPascal}.Invoke(parsed);");
                    sb.AppendLine("        }");
                }
                sb.AppendLine("    }");
                sb.AppendLine();

                string defaultTopic = svc.Events.FirstOrDefault(e => !string.IsNullOrEmpty(e.Topic))?.Topic ?? $"{svc.Name}:*";
                sb.AppendLine($"    /// <summary>Subscribes to all events for {svc.Name} on topic '{defaultTopic}'.</summary>");
                sb.AppendLine($"    public Task SubscribeAsync(string topic = \"{defaultTopic}\", CancellationToken cancellationToken = default) =>");
                sb.AppendLine("        _client.SubscribeAsync(topic, cancellationToken);");
                sb.AppendLine();
            }

            // Action Methods
            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                string transportPref = act.Transport.ToLowerInvariant() switch
                {
                    "http" => "ExoTransportPreference.Http",
                    "ws" or "websocket" => "ExoTransportPreference.WebSocket",
                    _ => "ExoTransportPreference.Auto"
                };

                bool hasParams = act.Params.Count > 0;
                bool hasReturnFields = act.ReturnFields.Count > 0;
                string returnType = hasReturnFields ? $"{svcPascal}{actPascal}Response" : "JsonElement";

                // Overload 1: Strongly-typed parameter arguments
                if (hasParams)
                {
                    var paramDefs = act.Params.Select(p =>
                    {
                        string csType = MapTypeToCSharp(p.Type);
                        string paramName = EscapeIdentifier(ToCamelCase(p.Name));
                        return $"{csType} {paramName}";
                    });
                    string paramSignature = string.Join(", ", paramDefs);

                    sb.AppendLine($"    /// <summary>{act.Doc ?? $"Executes {act.Name} action with typed arguments."}</summary>");
                    sb.AppendLine($"    public Task<{returnType}> {actPascal}Async({paramSignature}, CancellationToken cancellationToken = default)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        var req = new {svcPascal}{actPascal}Request");
                    sb.AppendLine("        {");
                    foreach (var p in act.Params)
                    {
                        string propName = ToPascalCase(p.Name);
                        string paramName = EscapeIdentifier(ToCamelCase(p.Name));
                        sb.AppendLine($"            {propName} = {paramName},");
                    }
                    sb.AppendLine("        };");
                    sb.AppendLine($"        return {actPascal}Async(req, cancellationToken);");
                    sb.AppendLine("    }");
                    sb.AppendLine();

                    // Overload 2: Strongly-typed Request DTO
                    sb.AppendLine($"    /// <summary>{act.Doc ?? $"Executes {act.Name} action with a typed request DTO."}</summary>");
                    sb.AppendLine($"    public Task<{returnType}> {actPascal}Async({svcPascal}{actPascal}Request request, CancellationToken cancellationToken = default)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        return _client.SendActionAsync<{returnType}>(\"{svc.Name}\", \"{act.Name}\", request, {transportPref}, cancellationToken: cancellationToken);");
                    sb.AppendLine("    }");
                    sb.AppendLine();
                }

                if (!hasParams)
                {
                    sb.AppendLine($"    /// <summary>{act.Doc ?? $"Executes {act.Name} action."}</summary>");
                    sb.AppendLine($"    public Task<JsonElement> {actPascal}Async(CancellationToken cancellationToken = default)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        return _client.SendActionAsync<JsonElement>(\"{svc.Name}\", \"{act.Name}\", null, {transportPref}, cancellationToken: cancellationToken);");
                    sb.AppendLine("    }");
                    sb.AppendLine();
                }

                // Overload 3: Untyped object payload (always available for fallback)
                sb.AppendLine($"    /// <summary>{act.Doc ?? $"Executes {act.Name} action."}</summary>");
                sb.AppendLine($"    public Task<JsonElement> {actPascal}Async(object? payload = null, CancellationToken cancellationToken = default)");
                sb.AppendLine("    {");
                sb.AppendLine($"        return _client.SendActionAsync<JsonElement>(\"{svc.Name}\", \"{act.Name}\", payload, {transportPref}, cancellationToken: cancellationToken);");
                sb.AppendLine("    }");
                sb.AppendLine();
            }

            sb.AppendLine("}");
            sb.AppendLine();
        }

        sb.AppendLine("}");

        return sb.ToString();
    }

    private static string MapTypeToCSharp(string type)
    {
        string lower = type.ToLowerInvariant().Trim();
        return lower switch
        {
            "string" or "binary" or "text" => "string",
            "integer" or "int" => "long",
            "int32" => "int",
            "int64" => "long",
            "float" or "double" or "number" => "double",
            "boolean" or "bool" => "bool",
            "map" or "object" or "term" => "JsonElement",
            "list_string" or "[:string]" => "List<string>",
            "list_int" or "[:integer]" => "List<long>",
            "list_map" or "[:map]" => "List<JsonElement>",
            _ => "JsonElement"
        };
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

    private static string ToCamelCase(string text)
    {
        string pascal = ToPascalCase(text);
        if (string.IsNullOrEmpty(pascal)) return pascal;
        return char.ToLowerInvariant(pascal[0]) + pascal.Substring(1);
    }

    private static string EscapeIdentifier(string name)
    {
        return CsharpKeywords.Contains(name) ? $"@{name}" : name;
    }
}
