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
    public List<(string PascalName, string Id)> CustomInputs { get; set; } = new();
}

public class ActionContractModel
{
    public string Name { get; set; } = string.Empty;
    public string? Doc { get; set; }
    public string Scope { get; set; } = "player";
    public string Transport { get; set; } = "auto";
    public List<ParamModel> Params { get; set; } = new();
    public List<ParamModel> ReturnFields { get; set; } = new();
    public string? ReturnType { get; set; }

    /// <summary>True when the action returns a list of <see cref="ReturnType"/> or of the response model.</summary>
    public bool ReturnsList { get; set; }

    /// <summary>
    /// The contract's own name for the returned record, when it has one. The generated response model
    /// takes that name, so the client mirrors the plugin's types instead of inventing `…Response`.
    /// </summary>
    public string? ReturnTypeName { get; set; }
}

public class ParamModel
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = "term";
    public bool Optional { get; set; }
    public bool Nullable { get; set; }

    /// <summary>The server-side default as JSON text (a valid C# literal for a number, bool or string).</summary>
    public string? Default { get; set; }
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
    public bool Nullable { get; set; }
}

public static class ExoCodeGenerator
{
    /// <summary>
    /// Makes a contract doc string safe to drop inside a C# XML doc comment.
    ///
    /// Contract docs are free-form (they can be multi-line `@doc` heredocs and contain quotes and
    /// apostrophes). Emitted raw, a newline ends the comment and the rest of the doc becomes
    /// invalid C# — which is exactly how a multi-line action doc broke every generated client.
    /// </summary>
    private static string XmlDoc(string? text, string fallback)
    {
        if (string.IsNullOrWhiteSpace(text)) return fallback;

        string collapsed = string.Join(" ", text
            .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Trim())
            .Where(line => line.Length > 0));

        return collapsed
            .Replace("&", "&amp;")
            .Replace("<", "&lt;")
            .Replace(">", "&gt;");
    }

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

    public static string GenerateFromExportJson(
        string json,
        string targetNamespace = "Exoforge.Client",
        bool includeStudio = false)
    {
        using var doc = JsonDocument.Parse(json);
        var services = ParseServices(doc.RootElement);
        return Generate(services, targetNamespace, includeStudio);
    }

    public const string ContractMetadataPrefix = "// @exoforge-contract: ";

    public static List<ServiceContractModel> ReadEmbeddedContracts(string existingFilePath)
    {
        var list = new List<ServiceContractModel>();
        if (!File.Exists(existingFilePath)) return list;

        foreach (string line in File.ReadLines(existingFilePath))
        {
            if (line.StartsWith(ContractMetadataPrefix, StringComparison.Ordinal))
            {
                string json = line.Substring(ContractMetadataPrefix.Length).Trim();
                try
                {
                    var model = JsonSerializer.Deserialize<ServiceContractModel>(json);
                    if (model != null && !string.IsNullOrEmpty(model.Name))
                        list.Add(model);
                }
                catch
                {
                    // Ignore malformed metadata lines
                }
            }
        }
        return list;
    }

    public static bool IsServiceReferencedInCode(ServiceContractModel svc, string searchRoot, string generatedFilePath)
    {
        if (string.IsNullOrEmpty(searchRoot) || !Directory.Exists(searchRoot)) return false;

        string svcPascal = ToPascalCase(svc.Name);
        string fullGenerated = Path.GetFullPath(generatedFilePath);

        var tokens = new List<string>
        {
            $"{svcPascal}ServiceClient",
            $"I{svcPascal}Service",
            $".{svcPascal}(",
            $".{svcPascal};",
            $".{svcPascal}.",
            $"Exo.{svcPascal}",
            $"ExoServices.{svcPascal}",
            $"ExoStudioServices.{svcPascal}",
            $"Exoforge.{svcPascal}"
        };

        foreach (var act in svc.Actions)
        {
            string actPascal = ToPascalCase(act.Name);
            tokens.Add($"{svcPascal}{actPascal}Request");
            tokens.Add(ResponseModelName(svcPascal, act));
        }

        foreach (var evt in svc.Events)
        {
            tokens.Add($"{svcPascal}{ToPascalCase(evt.Name)}Event");
        }

        try
        {
            foreach (string file in Directory.EnumerateFiles(searchRoot, "*.cs", SearchOption.AllDirectories))
            {
                if (string.Equals(Path.GetFullPath(file), fullGenerated, StringComparison.OrdinalIgnoreCase))
                    continue;

                string norm = file.Replace('\\', '/');
                if (norm.Contains("/obj/") || norm.Contains("/bin/") || norm.Contains("/Library/") || norm.Contains("/Temp/"))
                    continue;

                string content;
                try { content = File.ReadAllText(file); }
                catch { continue; }

                foreach (string token in tokens)
                {
                    if (content.IndexOf(token, StringComparison.Ordinal) >= 0)
                        return true;
                }
            }
        }
        catch
        {
            // Ignore scan errors
        }

        return false;
    }

    private static string? InferSearchRoot(string outputPath)
    {
        try
        {
            string full = Path.GetFullPath(outputPath);
            string? dir = Path.GetDirectoryName(full);
            while (dir != null)
            {
                if (string.Equals(Path.GetFileName(dir), "Assets", StringComparison.OrdinalIgnoreCase))
                {
                    return dir;
                }
                if (File.Exists(Path.Combine(dir, "exoforge.json")))
                {
                    return dir;
                }
                dir = Path.GetDirectoryName(dir);
            }
            return Path.GetDirectoryName(full);
        }
        catch
        {
            return null;
        }
    }

    private static void EnsureGeneratedAsmdef(string outputFilePath, string targetNamespace)
    {
        string? dir = Path.GetDirectoryName(Path.GetFullPath(outputFilePath));
        if (string.IsNullOrEmpty(dir)) return;

        string normalized = dir.Replace('\\', '/');
        string asmdefPath = Path.Combine(dir, "Exoforge.Generated.asmdef");
        if (!normalized.Contains("/Assets/") && !File.Exists(asmdefPath)) return;

        string asmdefJson =
            "{\n" +
            "    \"name\": \"Exoforge.Generated\",\n" +
            $"    \"rootNamespace\": \"{targetNamespace}\",\n" +
            "    \"references\": [],\n" +
            "    \"includePlatforms\": [],\n" +
            "    \"excludePlatforms\": [],\n" +
            "    \"allowUnsafeCode\": false,\n" +
            "    \"overrideReferences\": false,\n" +
            "    \"precompiledReferences\": [],\n" +
            "    \"autoReferenced\": true,\n" +
            "    \"defineConstraints\": [],\n" +
            "    \"versionDefines\": [],\n" +
            "    \"noEngineReferences\": true\n" +
            "}\n";

        if (!File.Exists(asmdefPath) || File.ReadAllText(asmdefPath) != asmdefJson)
        {
            File.WriteAllText(asmdefPath, asmdefJson, new UTF8Encoding(false));
        }
    }

    public static bool GenerateToFile(
        string json,
        string outputPath,
        string targetNamespace = "Exoforge.Client",
        string? codeSearchRoot = null,
        Action<string>? log = null,
        bool includeStudio = false)
    {
        using var doc = JsonDocument.Parse(json);
        var services = ParseServices(doc.RootElement);

        var previous = ReadEmbeddedContracts(outputPath);
        if (previous.Count > 0)
        {
            string searchRoot = codeSearchRoot ?? InferSearchRoot(outputPath) ?? "";
            var currentNames = new HashSet<string>(services.Select(s => s.Name), StringComparer.OrdinalIgnoreCase);

            foreach (var prevSvc in previous)
            {
                if (!currentNames.Contains(prevSvc.Name))
                {
                    // A preserved stub follows the same client/staff split as a fresh one. Otherwise
                    // a studio-only service that game code once referenced would keep reappearing
                    // after the generator stopped emitting it.
                    bool mayPreserve = includeStudio || IsClientVisibleService(prevSvc);

                    if (mayPreserve && (services.Count == 0 || IsServiceReferencedInCode(prevSvc, searchRoot, outputPath)))
                    {
                        services.Add(prevSvc);
                        currentNames.Add(prevSvc.Name);
                        log?.Invoke($"[codegen] Preserved stub for '{prevSvc.Name}' (referenced in code, not present on remote).");
                    }
                }
            }
            services = services.OrderBy(s => s.Name, StringComparer.Ordinal).ToList();
        }

        string code = Generate(services, targetNamespace, includeStudio);
        string? dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        EnsureGeneratedAsmdef(outputPath, targetNamespace);

        if (File.Exists(outputPath))
        {
            string existing = File.ReadAllText(outputPath);
            if (string.Equals(existing, code, StringComparison.Ordinal))
            {
                return false;
            }
        }

        File.WriteAllText(outputPath, code);
        return true;
    }

    private static List<ServiceContractModel> ParseServices(JsonElement root)
    {
        var result = new Dictionary<string, ServiceContractModel>(StringComparer.OrdinalIgnoreCase);

        JsonElement pluginsElement = root;
        if (root.TryGetProperty("export", out var exportProp))
        {
            pluginsElement = exportProp;
        }

        bool hasExtensions = pluginsElement.TryGetProperty("extensions", out var extensionsArray) && extensionsArray.ValueKind == JsonValueKind.Array;
        bool hasPlugins = pluginsElement.TryGetProperty("plugins", out var pluginsArray) && pluginsArray.ValueKind == JsonValueKind.Array;
        var arrayToEnumerate = hasExtensions ? extensionsArray : (hasPlugins ? pluginsArray : default);

        if (arrayToEnumerate.ValueKind == JsonValueKind.Array)
        {
            foreach (var plugin in arrayToEnumerate.EnumerateArray())
            {
                var inputs = new List<(string PascalName, string Id)>();
                if (plugin.TryGetProperty("input_types", out var inputTypes) && inputTypes.ValueKind == JsonValueKind.Object)
                {
                    foreach (var prop in inputTypes.EnumerateObject())
                    {
                        inputs.Add((ToPascalCase(prop.Name), prop.Name));
                    }
                }

                if (plugin.TryGetProperty("services", out var servicesArray) && servicesArray.ValueKind == JsonValueKind.Array)
                {
                    foreach (var svc in servicesArray.EnumerateArray())
                    {
                        var model = ParseServiceElement(svc);
                        if (!string.IsNullOrEmpty(model.Name))
                        {
                            model.CustomInputs.AddRange(inputs);
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
                            result[sName] = new ServiceContractModel { Name = sName, CustomInputs = new(inputs) };
                        }
                    }
                }
            }
        }

        // Sorted, not insertion-ordered. The output is committed, so its order has to be a property of
        // the contracts rather than of the order they arrived in.
        return result.Values.OrderBy(s => s.Name, StringComparer.Ordinal).ToList();
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
                    Scope = act.TryGetProperty("scope", out var sc) ? sc.GetString() ?? "player" : "player",
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

                MarkNullable(aModel.Params, act, "params_nullable");
                MarkParamDefaults(aModel.Params, act);

                if (act.TryGetProperty("returns_list", out var listElem) && listElem.ValueKind == JsonValueKind.True)
                {
                    aModel.ReturnsList = true;
                }

                if (act.TryGetProperty("returns_type", out var typeElem) && typeElem.ValueKind == JsonValueKind.String)
                {
                    aModel.ReturnTypeName = typeElem.GetString();
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

                MarkNullable(aModel.ReturnFields, act, "returns_nullable");

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

                MarkNullable(eModel.PayloadFields, evt, "payload_nullable");
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
                            Type = col.TryGetProperty("type", out var ct) ? ct.GetString() ?? "string" : "string",
                            Nullable = col.TryGetProperty("nullable", out var cnull) && cnull.ValueKind == JsonValueKind.True
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
    /// client per service that calls through the plugin SDK's IActionDispatcher. The
    /// stubs depend only on the service contract, never on the plugin that implements it.
    /// </summary>
    /// <summary>
    /// Generates typed plugin service stubs. Pass <paramref name="services"/> to include only the
    /// contracts the plugin depends on; this keeps the generated file small.
    /// </summary>
    public static string GeneratePluginStubs(
        string json,
        string targetNamespace = "Exoforge.Plugins.Generated",
        IEnumerable<string>? services = null,
        string? pluginId = null)
    {
        using var doc = JsonDocument.Parse(json);
        var parsed = ParseServices(doc.RootElement);

        if (services != null)
        {
            var wanted = new HashSet<string>(
                services.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()),
                StringComparer.OrdinalIgnoreCase);

            parsed = parsed.Where(s => wanted.Contains(s.Name)).ToList();
        }

        var customInputs = ExtractCustomInputTypes(doc.RootElement, services);

        return GeneratePluginStubs(
            parsed,
            targetNamespace,
            pluginId is null ? null : OwnJsonTypes(doc.RootElement, pluginId),
            customInputs);
    }

    public static List<(string PascalName, string Id)> ExtractCustomInputTypes(
        JsonElement root,
        IEnumerable<string>? services)
    {
        var result = new List<(string PascalName, string Id)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        JsonElement pluginsElem;
        if (root.TryGetProperty("export", out var export) &&
            ((export.TryGetProperty("extensions", out var p1) && p1.ValueKind == JsonValueKind.Array) ||
             (export.TryGetProperty("plugins", out p1) && p1.ValueKind == JsonValueKind.Array)))
        {
            pluginsElem = p1;
        }
        else if ((root.TryGetProperty("extensions", out var p2) && p2.ValueKind == JsonValueKind.Array) ||
                 (root.TryGetProperty("plugins", out p2) && p2.ValueKind == JsonValueKind.Array))
        {
            pluginsElem = p2;
        }
        else
        {
            return result;
        }

        var wanted = services != null
            ? new HashSet<string>(services.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()), StringComparer.OrdinalIgnoreCase)
            : null;

        foreach (var plugin in pluginsElem.EnumerateArray())
        {
            if (wanted != null)
            {
                bool matches = false;
                if (plugin.TryGetProperty("id", out var idProp) && wanted.Contains(idProp.GetString() ?? "")) matches = true;
                if (!matches && plugin.TryGetProperty("name", out var nameProp) && wanted.Contains(nameProp.GetString() ?? "")) matches = true;
                if (!matches && plugin.TryGetProperty("provides", out var provProp) && provProp.ValueKind == JsonValueKind.Array)
                {
                    foreach (var p in provProp.EnumerateArray())
                    {
                        if (wanted.Contains(p.GetString() ?? "")) { matches = true; break; }
                    }
                }
                if (!matches && plugin.TryGetProperty("services", out var svcsProp) && svcsProp.ValueKind == JsonValueKind.Array)
                {
                    foreach (var s in svcsProp.EnumerateArray())
                    {
                        if (s.TryGetProperty("name", out var sn) && wanted.Contains(sn.GetString() ?? "")) { matches = true; break; }
                    }
                }

                if (!matches) continue;
            }

            if (plugin.TryGetProperty("input_types", out var inputTypes) && inputTypes.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in inputTypes.EnumerateObject())
                {
                    string id = prop.Name;
                    string pascal = ToPascalCase(id);
                    if (seen.Add(pascal))
                    {
                        result.Add((pascal, id));
                    }
                }
            }
        }

        return result;
    }

    public static bool GeneratePluginStubsToFile(
        string json,
        string outputPath,
        string targetNamespace = "Exoforge.Plugins.Generated",
        IEnumerable<string>? services = null,
        string? pluginId = null,
        string? codeSearchRoot = null,
        Action<string>? log = null)
    {
        using var doc = JsonDocument.Parse(json);
        var parsed = ParseServices(doc.RootElement);

        if (services != null)
        {
            var wanted = new HashSet<string>(
                services.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()),
                StringComparer.OrdinalIgnoreCase);

            parsed = parsed.Where(s => wanted.Contains(s.Name)).ToList();
        }

        var previous = ReadEmbeddedContracts(outputPath);
        if (previous.Count > 0)
        {
            string searchRoot = codeSearchRoot ?? Path.GetDirectoryName(Path.GetDirectoryName(outputPath)) ?? "";
            var currentNames = new HashSet<string>(parsed.Select(s => s.Name), StringComparer.OrdinalIgnoreCase);
            var wanted = services != null
                ? new HashSet<string>(services.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()), StringComparer.OrdinalIgnoreCase)
                : null;

            foreach (var prevSvc in previous)
            {
                if (!currentNames.Contains(prevSvc.Name))
                {
                    bool isWanted = wanted != null && wanted.Contains(prevSvc.Name);
                    if (parsed.Count == 0 || isWanted || IsServiceReferencedInCode(prevSvc, searchRoot, outputPath))
                    {
                        parsed.Add(prevSvc);
                        currentNames.Add(prevSvc.Name);
                        log?.Invoke($"[codegen] Preserved stub for '{prevSvc.Name}' in plugin stubs.");
                    }
                }
            }
            parsed = parsed.OrderBy(s => s.Name, StringComparer.Ordinal).ToList();
        }

        var customInputs = ExtractCustomInputTypes(doc.RootElement, services);
        string code = GeneratePluginStubs(
            parsed,
            targetNamespace,
            pluginId is null ? null : OwnJsonTypes(doc.RootElement, pluginId),
            customInputs);

        string? dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        if (File.Exists(outputPath))
        {
            string existing = File.ReadAllText(outputPath);
            if (string.Equals(existing, code, StringComparison.Ordinal))
            {
                return false;
            }
        }

        File.WriteAllText(outputPath, code);
        return true;
    }

    public static string GeneratePluginStubs(
        IEnumerable<ServiceContractModel> services,
        string targetNamespace = "Exoforge.Plugins.Generated",
        IEnumerable<string>? ownJsonTypes = null,
        IReadOnlyList<(string PascalName, string Id)>? customInputs = null)
    {
        var serviceList = services.ToList();
        var sb = new StringBuilder();
        var serializable = new List<string>();
        var emittedModels = new HashSet<string>(StringComparer.Ordinal);

        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     Typed plugin service stubs generated from the cluster contract export.");
        sb.AppendLine("//     Do not edit. Regenerate with `exo plugin stubs <name>`.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine();
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("using System;");
        sb.AppendLine("using System.Collections.Generic;");
        sb.AppendLine("using System.Text.Json;");
        sb.AppendLine("using System.Text.Json.Serialization;");
        sb.AppendLine("using System.Threading.Tasks;");
        sb.AppendLine("using Exoforge.Plugin.SDK;");
        sb.AppendLine();
        sb.AppendLine($"namespace {targetNamespace}");
        sb.AppendLine("{");

        // Names the table a stub record stands for, so `[ExoColumn(ReferencesType = typeof(...))]` on a
        // stub resolves the foreign key from the contract. The extension's own generator reads it.
        sb.AppendLine("    [AttributeUsage(AttributeTargets.Class)]");
        sb.AppendLine("    internal sealed class ExoContractResourceAttribute : Attribute");
        sb.AppendLine("    {");
        sb.AppendLine("        public ExoContractResourceAttribute(string name) => Name = name;");
        sb.AppendLine("        public string Name { get; }");
        sb.AppendLine("        public string? PrimaryKey { get; set; }");
        sb.AppendLine("    }");
        sb.AppendLine();

        var actionRespNames = new Dictionary<ActionContractModel, string>();
        var emittedModelSignatures = new Dictionary<string, string>(StringComparer.Ordinal);

        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);
            foreach (var act in svc.Actions)
            {
                if (act.ReturnFields.Count > 0 || !string.IsNullOrEmpty(act.ReturnTypeName))
                {
                    string respName = ResolveResponseModelName(svcPascal, act, emittedModelSignatures);
                    actionRespNames[act] = respName;
                    if (act.ReturnFields.Count > 0)
                    {
                        string sig = string.Join("|", act.ReturnFields.Select(f => $"{f.Name}:{f.Type}"));
                        emittedModelSignatures[respName] = sig;
                    }
                }
            }
        }

        // Models
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);

            foreach (var res in svc.Resources)
            {
                string typeName = $"{svcPascal}{ResourceTypeName(res)}";
                emittedModels.Add(typeName);
                serializable.Add(typeName);

                string primaryKey = string.IsNullOrEmpty(res.PrimaryKey) ? "" : $", PrimaryKey = \"{res.PrimaryKey}\"";
                sb.AppendLine($"    [ExoContractResource(\"{res.Name}\"{primaryKey})]");
                sb.AppendLine($"    public class {typeName}");
                sb.AppendLine("    {");
                var usedProps = new HashSet<string>(StringComparer.Ordinal);
                foreach (var col in res.Columns)
                {
                    string propName = SafePropertyName(col.Name, typeName, usedProps);
                    sb.AppendLine($"        [JsonPropertyName(\"{col.Name}\")]");
                    sb.AppendLine($"        public {WithNullable(MapTypeToCSharp(col.Type), col.Nullable)} {propName} {{ get; set; }} = default!;");
                }
                sb.AppendLine("    }");
                sb.AppendLine();
            }

            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                string reqName = $"{svcPascal}{actPascal}Request";
                serializable.Add(reqName);

                sb.AppendLine($"    public class {reqName}");
                sb.AppendLine("    {");
                var usedReqProps = new HashSet<string>(StringComparer.Ordinal);
                foreach (var p in act.Params)
                {
                    string propType = WithNullable(MapTypeToCSharp(p.Type), p.Nullable);
                    string propName = SafePropertyName(p.Name, reqName, usedReqProps);
                    sb.AppendLine($"        [JsonPropertyName(\"{p.Name}\")]");
                    if (p.Optional || propType == "JsonElement")
                    {
                        sb.AppendLine("        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]");
                    }
                    sb.AppendLine($"        public {propType} {propName} {{ get; set; }} = {ParamInitializer(p, propType)};");
                }
                sb.AppendLine("    }");
                sb.AppendLine();

                if (act.ReturnFields.Count > 0)
                {
                    string respName = actionRespNames[act];

                    if (!emittedModels.Add(respName))
                    {
                        continue;
                    }

                    serializable.Add(respName);

                    sb.AppendLine($"    public class {respName}");
                    sb.AppendLine("    {");
                    var usedRespProps = new HashSet<string>(StringComparer.Ordinal);
                    foreach (var f in act.ReturnFields)
                    {
                        string propName = SafePropertyName(f.Name, respName, usedRespProps);
                        sb.AppendLine($"        [JsonPropertyName(\"{f.Name}\")]");
                        sb.AppendLine($"        public {WithNullable(MapReturnFieldType(svc, f), f.Nullable)} {propName} {{ get; set; }} = default!;");
                    }
                    sb.AppendLine("    }");
                    sb.AppendLine();
                }
            }

            foreach (var evt in svc.Events)
            {
                string evtName = $"{svcPascal}{ToPascalCase(evt.Name)}Event";
                serializable.Add(evtName);

                sb.AppendLine($"    public class {evtName}");
                sb.AppendLine("    {");
                var usedProps = new HashSet<string>(StringComparer.Ordinal);
                foreach (var f in evt.PayloadFields)
                {
                    string propName = SafePropertyName(f.Name, evtName, usedProps);
                    sb.AppendLine($"        [JsonPropertyName(\"{f.Name}\")]");
                    sb.AppendLine($"        public {WithNullable(MapTypeToCSharp(f.Type), f.Nullable)} {propName} {{ get; set; }} = default!;");
                }
                sb.AppendLine("    }");
                sb.AppendLine();
            }
        }

        // Clients
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);

            // `Service` suffix on purpose: a service named `database` would otherwise emit `IDatabase`
            // and collide with the SDK's own capability interface.
            string iface = $"I{svcPascal}Service";

            // The contract for a service that lives on the server - a C# plugin or an Elixir one -
            // and therefore is not reachable from this project. Plugin code injects and fakes the
            // interface; the generated client is one implementation of it.
            sb.AppendLine($"    /// <summary>Contract of the '{svc.Name}' service, as the plugin providing it declares it.</summary>");
            sb.AppendLine($"    public interface {iface}");
            sb.AppendLine("    {");

            if (svc.CustomInputs.Count > 0)
            {
                sb.AppendLine("        // Custom dashboard input types provided by this service:");
                foreach (var (pascal, id) in svc.CustomInputs)
                {
                    sb.AppendLine($"        public const string {pascal} = \"{id}\";");
                }
                sb.AppendLine();
            }

            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                string reqName = $"{svcPascal}{actPascal}Request";
                string? respName = actionRespNames.TryGetValue(act, out var arName) ? arName : null;
                string respType = ReturnTypeName(svcPascal, act, respName);
                string declaration = respType == "JsonElement" ? "JsonElement" : respType + "?";
                string scope = string.IsNullOrEmpty(act.Scope) ? "" : $", Scope = \"{act.Scope}\"";

                sb.AppendLine($"        [ExoAction(\"{act.Name}\"{scope})]");
                sb.AppendLine($"        Task<{declaration}> {actPascal}Async({reqName} request);");

                if (act.Params.Count == 0)
                {
                    sb.AppendLine($"        Task<{declaration}> {actPascal}Async();");
                }

                sb.AppendLine();
            }

            sb.AppendLine("    }");
            sb.AppendLine();

            sb.AppendLine($"    public sealed class {svcPascal}ServiceClient : {iface}");
            sb.AppendLine("    {");
            sb.AppendLine("        private readonly IActionDispatcher _dispatcher;");
            sb.AppendLine();
            sb.AppendLine($"        public {svcPascal}ServiceClient(IActionDispatcher dispatcher) => _dispatcher = dispatcher;");
            sb.AppendLine();

            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);
                string reqName = $"{svcPascal}{actPascal}Request";
                string? respName = actionRespNames.TryGetValue(act, out var arName) ? arName : null;
                string respType = ReturnTypeName(svcPascal, act, respName);
                string declaration = respType == "JsonElement" ? "JsonElement" : respType + "?";
                bool isValueType = respType is "int" or "long" or "bool" or "float" or "double" or "byte" or "short" or "uint" or "ulong" or "sbyte" or "ushort" or "decimal";
                string callType = isValueType ? respType + "?" : respType;

                sb.AppendLine($"        public Task<{declaration}> {actPascal}Async({reqName} request)");
                sb.AppendLine($"            => _dispatcher.CallActionAsync<{callType}>(\"{svc.Name}\", \"{act.Name}\", request);");
                sb.AppendLine();

                if (act.Params.Count == 0)
                {
                    sb.AppendLine($"        public Task<{declaration}> {actPascal}Async()");
                    sb.AppendLine($"            => {actPascal}Async(new {reqName}());");
                    sb.AppendLine();
                }
            }

            sb.AppendLine("    }");
            sb.AppendLine();

            if (svc.CustomInputs.Count > 0)
            {
                sb.AppendLine($"    /// <summary>Custom dashboard input types provided by '{svc.Name}'.</summary>");
                sb.AppendLine($"    public static class {svcPascal}Inputs");
                sb.AppendLine("    {");
                foreach (var (pascal, id) in svc.CustomInputs)
                {
                    sb.AppendLine($"        public const string {pascal} = \"{id}\";");
                }
                sb.AppendLine("    }");
                sb.AppendLine();
            }
        }

        // Hub
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
        sb.AppendLine("}");
        sb.AppendLine();

        sb.AppendLine("namespace Exoforge.Plugin.SDK");
        sb.AppendLine("{");
        sb.AppendLine("    public static class ExoServices");
        sb.AppendLine("    {");
        sb.AppendLine("        // AsyncLocal so parallel test hosts own their own stubs; a plugin process has one flow.");
        sb.AppendLine("        private static readonly global::System.Threading.AsyncLocal<IDatabase?> _databaseOverride = new();");
        sb.AppendLine("        private static readonly global::System.Threading.AsyncLocal<ILogger?> _loggerOverride = new();");
        sb.AppendLine("        private static readonly global::System.Threading.AsyncLocal<IEventDispatcher?> _eventsOverride = new();");
        sb.AppendLine("        private static readonly global::System.Threading.AsyncLocal<IActionDispatcher?> _actionsOverride = new();");
        sb.AppendLine("        private static readonly global::System.Threading.AsyncLocal<IPluginContext?> _contextOverride = new();");
        sb.AppendLine();
        sb.AppendLine("        public static IDatabase Database");
        sb.AppendLine("        {");
        sb.AppendLine("            get => _databaseOverride.Value ?? Context.Database;");
        sb.AppendLine("            set => _databaseOverride.Value = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static ILogger Logger");
        sb.AppendLine("        {");
        sb.AppendLine("            get => _loggerOverride.Value ?? Context.Logger;");
        sb.AppendLine("            set => _loggerOverride.Value = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IEventDispatcher Events");
        sb.AppendLine("        {");
        sb.AppendLine("            get => _eventsOverride.Value ?? Context.Events;");
        sb.AppendLine("            set => _eventsOverride.Value = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IActionDispatcher Actions");
        sb.AppendLine("        {");
        sb.AppendLine("            get => _actionsOverride.Value ?? Context.Actions;");
        sb.AppendLine("            set => _actionsOverride.Value = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IPluginContext Context");
        sb.AppendLine("        {");
        sb.AppendLine("            get => _contextOverride.Value ?? PluginHost.CurrentContext;");
        sb.AppendLine("            set => _contextOverride.Value = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine($"        private static readonly global::System.Threading.AsyncLocal<global::{targetNamespace}.ExoforgePluginServices?> _services = new();");
        sb.AppendLine($"        public static global::{targetNamespace}.ExoforgePluginServices Services");
        sb.AppendLine("        {");
        sb.AppendLine($"            get => _services.Value ?? (_services.Value = new global::{targetNamespace}.ExoforgePluginServices(Actions));");
        sb.AppendLine("            set => _services.Value = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        foreach (var svc in serviceList)
        {
            if (svc.Name.Equals("database", StringComparison.OrdinalIgnoreCase)) continue;
            string svcPascal = ToPascalCase(svc.Name);
            string fieldName = "_" + svc.Name.ToLowerInvariant().Replace("-", "_") + "Override";
            sb.AppendLine($"        private static readonly global::System.Threading.AsyncLocal<global::{targetNamespace}.I{svcPascal}Service?> {fieldName} = new();");
            sb.AppendLine($"        public static global::{targetNamespace}.I{svcPascal}Service {svcPascal}");
            sb.AppendLine("        {");
            sb.AppendLine($"            get => {fieldName}.Value ?? Services.{svcPascal};");
            sb.AppendLine($"            set => {fieldName}.Value = value;");
            sb.AppendLine("        }");
            sb.AppendLine($"        public static global::{targetNamespace}.I{svcPascal}Service {svcPascal}Service");
            sb.AppendLine("        {");
            sb.AppendLine($"            get => {svcPascal};");
            sb.AppendLine($"            set => {svcPascal} = value;");
            sb.AppendLine("        }");
            sb.AppendLine();
        }
        sb.AppendLine("        public static void Reset()");
        sb.AppendLine("        {");
        sb.AppendLine("            _databaseOverride.Value = null;");
        sb.AppendLine("            _loggerOverride.Value = null;");
        sb.AppendLine("            _eventsOverride.Value = null;");
        sb.AppendLine("            _actionsOverride.Value = null;");
        sb.AppendLine("            _contextOverride.Value = null;");
        sb.AppendLine("            _services.Value = null;");
        foreach (var svc in serviceList)
        {
            if (svc.Name.Equals("database", StringComparison.OrdinalIgnoreCase)) continue;
            string fieldName = "_" + svc.Name.ToLowerInvariant().Replace("-", "_") + "Override";
            sb.AppendLine($"            {fieldName}.Value = null;");
        }
        sb.AppendLine("        }");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    public static class Exo");
        sb.AppendLine("    {");
        sb.AppendLine("        public static IDatabase Database");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Database;");
        sb.AppendLine("            set => ExoServices.Database = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static ILogger Logger");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Logger;");
        sb.AppendLine("            set => ExoServices.Logger = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IEventDispatcher Events");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Events;");
        sb.AppendLine("            set => ExoServices.Events = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IActionDispatcher Actions");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Actions;");
        sb.AppendLine("            set => ExoServices.Actions = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IPluginContext Context");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Context;");
        sb.AppendLine("            set => ExoServices.Context = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine($"        public static global::{targetNamespace}.ExoforgePluginServices Services");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Services;");
        sb.AppendLine("            set => ExoServices.Services = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        foreach (var svc in serviceList)
        {
            if (svc.Name.Equals("database", StringComparison.OrdinalIgnoreCase)) continue;
            string svcPascal = ToPascalCase(svc.Name);
            sb.AppendLine($"        public static global::{targetNamespace}.I{svcPascal}Service {svcPascal}");
            sb.AppendLine("        {");
            sb.AppendLine($"            get => ExoServices.{svcPascal};");
            sb.AppendLine($"            set => ExoServices.{svcPascal} = value;");
            sb.AppendLine("        }");
            sb.AppendLine($"        public static global::{targetNamespace}.I{svcPascal}Service {svcPascal}Service");
            sb.AppendLine("        {");
            sb.AppendLine($"            get => ExoServices.{svcPascal};");
            sb.AppendLine($"            set => ExoServices.{svcPascal} = value;");
            sb.AppendLine("        }");
            sb.AppendLine();
        }
        sb.AppendLine("        public static void Reset() => ExoServices.Reset();");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    public static class Exoforge");
        sb.AppendLine("    {");
        sb.AppendLine("        public static IDatabase Database");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Database;");
        sb.AppendLine("            set => ExoServices.Database = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static ILogger Logger");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Logger;");
        sb.AppendLine("            set => ExoServices.Logger = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IEventDispatcher Events");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Events;");
        sb.AppendLine("            set => ExoServices.Events = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IActionDispatcher Actions");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Actions;");
        sb.AppendLine("            set => ExoServices.Actions = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public static IPluginContext Context");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Context;");
        sb.AppendLine("            set => ExoServices.Context = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine($"        public static global::{targetNamespace}.ExoforgePluginServices Services");
        sb.AppendLine("        {");
        sb.AppendLine("            get => ExoServices.Services;");
        sb.AppendLine("            set => ExoServices.Services = value;");
        sb.AppendLine("        }");
        sb.AppendLine();
        foreach (var svc in serviceList)
        {
            if (svc.Name.Equals("database", StringComparison.OrdinalIgnoreCase)) continue;
            string svcPascal = ToPascalCase(svc.Name);
            sb.AppendLine($"        public static global::{targetNamespace}.I{svcPascal}Service {svcPascal}");
            sb.AppendLine("        {");
            sb.AppendLine($"            get => ExoServices.{svcPascal};");
            sb.AppendLine($"            set => ExoServices.{svcPascal} = value;");
            sb.AppendLine("        }");
            sb.AppendLine($"        public static global::{targetNamespace}.I{svcPascal}Service {svcPascal}Service");
            sb.AppendLine("        {");
            sb.AppendLine($"            get => ExoServices.{svcPascal};");
            sb.AppendLine($"            set => ExoServices.{svcPascal} = value;");
            sb.AppendLine("        }");
            sb.AppendLine();
        }
        sb.AppendLine("        public static void Reset() => ExoServices.Reset();");
        sb.AppendLine("    }");
        sb.AppendLine("}");
        sb.AppendLine();
        sb.AppendLine($"namespace {targetNamespace}");
        sb.AppendLine("{");

        // The plugin's own records need metadata too. Its compile cannot supply it - a source
        // generator's output is invisible to the System.Text.Json generator - so the stubs, which are
        // a real file, do.
        foreach (var type in ownJsonTypes ?? Enumerable.Empty<string>())
        {
            if (!serializable.Contains(type)) serializable.Add(type);
        }

        // Context + self-registration
        if (serializable.Count > 0)
        {
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
            sb.AppendLine("        internal static void Init()");
            sb.AppendLine("        {");
            sb.AppendLine("            PluginJson.AddContext(GeneratedServicesJsonContext.Default);");
            sb.AppendLine("            PluginServiceRegistry.Register(d => new ExoforgePluginServices(d));");
            foreach (var svc in serviceList)
            {
                sb.AppendLine($"            PluginServiceRegistry.Register<I{ToPascalCase(svc.Name)}Service>(d => new {ToPascalCase(svc.Name)}ServiceClient(d));");
                sb.AppendLine($"            PluginServiceRegistry.Register(d => new {ToPascalCase(svc.Name)}ServiceClient(d));");
            }
            sb.AppendLine("        }");
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

    public static string Generate(
        IEnumerable<ServiceContractModel> services,
        string targetNamespace = "Exoforge.Client",
        bool includeStudio = false)
    {
        // The Unity client facade is the game's surface: player/global actions only, plus any
        // service that still has at least one of them. Studio/admin actions and system-only
        // services are reachable through the raw client or includeStudio, not through ExoServices.
        var serviceList = includeStudio
            ? services.ToList()
            : services.Select(ClientVisibleService).Where(s => s != null).Select(s => s!).ToList();
        var sb = new StringBuilder();
        var emittedModels = new HashSet<string>(StringComparer.Ordinal);
        var actionRespNames = new Dictionary<ActionContractModel, string>();
        var emittedModelSignatures = new Dictionary<string, string>(StringComparer.Ordinal);

        var clientModelNames = new HashSet<string>(StringComparer.Ordinal);
        foreach (var svc in serviceList.Where(IsClientVisibleService))
        {
            string svcPascal = ToPascalCase(svc.Name);
            foreach (var act in svc.Actions.Where(IsClientAction))
            {
                if (act.Params.Count > 0)
                {
                    clientModelNames.Add($"{svcPascal}{ToPascalCase(act.Name)}Request");
                }
                if (act.ReturnFields.Count > 0 || !string.IsNullOrEmpty(act.ReturnTypeName))
                {
                    string respName = ResolveResponseModelName(svcPascal, act, emittedModelSignatures);
                    actionRespNames[act] = respName;
                    clientModelNames.Add(respName);
                    if (act.ReturnFields.Count > 0)
                    {
                        string sig = string.Join("|", act.ReturnFields.Select(f => $"{f.Name}:{f.Type}"));
                        emittedModelSignatures[respName] = sig;
                    }
                }
            }
        }

        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);
            foreach (var act in svc.Actions)
            {
                if ((act.ReturnFields.Count > 0 || !string.IsNullOrEmpty(act.ReturnTypeName)) && !actionRespNames.ContainsKey(act))
                {
                    string respName = ResolveResponseModelName(svcPascal, act, emittedModelSignatures);
                    actionRespNames[act] = respName;
                    if (act.ReturnFields.Count > 0)
                    {
                        string sig = string.Join("|", act.ReturnFields.Select(f => $"{f.Name}:{f.Type}"));
                        emittedModelSignatures[respName] = sig;
                    }
                }
            }
        }

        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     This code was generated by Exoforge C# Management Engine.");
        sb.AppendLine("//     Do not modify this file directly. Changes will be overwritten.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine();
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("using System;");
        sb.AppendLine("using System.Collections.Generic;");
        sb.AppendLine("using System.Reflection;");
        sb.AppendLine("using System.Runtime.CompilerServices;");
        sb.AppendLine("using System.Text.Json;");
        sb.AppendLine("using System.Text.Json.Serialization;");
        sb.AppendLine("using System.Threading;");
        sb.AppendLine("using System.Threading.Tasks;");
        sb.AppendLine($"namespace {targetNamespace}");
        sb.AppendLine("{");

        // 1. Strongly-typed Models (Requests, Responses, Events)
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);

            // Action Request & Response Models
            foreach (var act in svc.Actions)
            {
                string actPascal = ToPascalCase(act.Name);

                if (act.Params.Count > 0)
                {
                    string reqName = $"{svcPascal}{actPascal}Request";
                    bool isStudioReq = !clientModelNames.Contains(reqName);
                    if (isStudioReq) sb.AppendLine("#if UNITY_EDITOR");
                    sb.AppendLine($"/// <summary>Request payload for {svc.Name}.{act.Name} action.</summary>");
                    sb.AppendLine($"public class {reqName}");
                    sb.AppendLine("{");
                    var usedProps = new HashSet<string>(StringComparer.Ordinal);
                    foreach (var p in act.Params)
                    {
                        string propName = SafePropertyName(p.Name, reqName, usedProps);
                        string csType = WithNullable(MapTypeToCSharp(p.Type), p.Nullable);
                        sb.AppendLine($"    [JsonPropertyName(\"{p.Name}\")]");
                        if (p.Optional || csType == "JsonElement")
                        {
                            sb.AppendLine("    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]");
                        }
                        sb.AppendLine($"    public {csType} {propName} {{ get; set; }} = {ParamInitializer(p, csType)};");
                    }
                    sb.AppendLine("}");
                    if (isStudioReq) sb.AppendLine("#endif");
                    sb.AppendLine();
                }

                if (act.ReturnFields.Count > 0)
                {
                    string respName = actionRespNames[act];

                    if (emittedModels.Add(respName))
                    {
                        bool isStudioResp = !clientModelNames.Contains(respName);
                        if (isStudioResp) sb.AppendLine("#if UNITY_EDITOR");
                        sb.AppendLine($"/// <summary>Response model for {svc.Name}.{act.Name} action.</summary>");
                        sb.AppendLine($"public class {respName}");
                        sb.AppendLine("{");
                        var usedProps = new HashSet<string>(StringComparer.Ordinal);
                        foreach (var r in act.ReturnFields)
                        {
                            string propName = SafePropertyName(r.Name, respName, usedProps);
                            string csType = WithNullable(MapTypeToCSharp(r.Type), r.Nullable);
                            sb.AppendLine($"    [JsonPropertyName(\"{r.Name}\")]");
                            sb.AppendLine($"    public {csType} {propName} {{ get; set; }} = default!;");
                        }
                        sb.AppendLine("}");
                        if (isStudioResp) sb.AppendLine("#endif");
                        sb.AppendLine();
                    }
                }
            }

            // Event Models
            foreach (var evt in svc.Events)
            {
                bool isStudioSvc = !IsClientVisibleService(svc);
                if (isStudioSvc) sb.AppendLine("#if UNITY_EDITOR");
                string evtPascal = ToPascalCase(evt.Name);
                string evtName = $"{svcPascal}{evtPascal}Event";
                sb.AppendLine($"/// <summary>Event payload for {evt.Topic ?? svc.Name} -> {evt.Name}.</summary>");
                sb.AppendLine($"public class {evtName}");
                sb.AppendLine("{");
                if (evt.PayloadFields.Count > 0)
                {
                    var usedProps = new HashSet<string>(StringComparer.Ordinal);
                    foreach (var f in evt.PayloadFields)
                    {
                        string propName = SafePropertyName(f.Name, evtName, usedProps);
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
                if (isStudioSvc) sb.AppendLine("#endif");
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

        foreach (var svc in serviceList)
        {
            string pascalName = ToPascalCase(svc.Name);
            bool isStudioOnly = !IsClientVisibleService(svc);
            if (isStudioOnly) sb.AppendLine("#if UNITY_EDITOR");
            sb.AppendLine($"    /// <summary>Access the {pascalName} service contract.</summary>");
            sb.AppendLine($"    public static {pascalName}ServiceClient {pascalName}(this ExoClient client) =>");
            sb.AppendLine($"        client.Services().{pascalName};");
            if (isStudioOnly) sb.AppendLine("#endif");
            sb.AppendLine();
        }
        sb.AppendLine("}");
        sb.AppendLine();

        // 2b. Static ExoServices facade matching the extension runtime syntax
        sb.AppendLine("/// <summary>");
        sb.AppendLine("/// Static access to Exoforge services matching the extension runtime syntax.");
        sb.AppendLine("/// In Unity, uses the ambient ExoforgeSDK.Client; in standalone applications, assign ExoServices.Client.");
        sb.AppendLine("/// </summary>");
        sb.AppendLine("public static class ExoServices");
        sb.AppendLine("{");
        sb.AppendLine("    private static Func<ExoClient>? _clientLocator;");
        sb.AppendLine("    private static ExoClient? _fallbackClient;");
        sb.AppendLine();
        sb.AppendLine("    /// <summary>The active ExoClient used by static service calls.</summary>");
        sb.AppendLine("    public static ExoClient Client");
        sb.AppendLine("    {");
        sb.AppendLine("        get");
        sb.AppendLine("        {");
        sb.AppendLine("            if (_clientLocator != null) return _clientLocator();");
        sb.AppendLine("            if (_fallbackClient != null) return _fallbackClient;");
        sb.AppendLine();
        sb.AppendLine("            var unitySdkType = Type.GetType(\"Exoforge.Client.Unity.ExoforgeSDK, Exoforge.SDK\")");
        sb.AppendLine("                ?? Type.GetType(\"Exoforge.Client.Unity.ExoforgeSDK, Exoforge.SDK.Runtime\")");
        sb.AppendLine("                ?? Type.GetType(\"Exoforge.Client.Unity.ExoforgeSDK\");");
        sb.AppendLine();
        sb.AppendLine("            if (unitySdkType == null)");
        sb.AppendLine("            {");
        sb.AppendLine("                try");
        sb.AppendLine("                {");
        sb.AppendLine("                    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())");
        sb.AppendLine("                    {");
        sb.AppendLine("                        unitySdkType = asm.GetType(\"Exoforge.Client.Unity.ExoforgeSDK\");");
        sb.AppendLine("                        if (unitySdkType != null) break;");
        sb.AppendLine("                    }");
        sb.AppendLine("                }");
        sb.AppendLine("                catch { }");
        sb.AppendLine("            }");
        sb.AppendLine();
        sb.AppendLine("            if (unitySdkType != null)");
        sb.AppendLine("            {");
        sb.AppendLine("                var prop = unitySdkType.GetProperty(\"Client\", BindingFlags.Public | BindingFlags.Static);");
        sb.AppendLine("                if (prop?.GetValue(null) is ExoClient unityClient)");
        sb.AppendLine("                {");
        sb.AppendLine("                    return unityClient;");
        sb.AppendLine("                }");
        sb.AppendLine("            }");
        sb.AppendLine();
        sb.AppendLine("            throw new InvalidOperationException(\"No active ExoClient configured. Call ExoforgeSDK.Auth.LoginAnonymously(), ExoforgeSDK.ConnectAsync() or assign ExoServices.Client.\");");
        sb.AppendLine("        }");
        sb.AppendLine("        set => _fallbackClient = value;");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    /// <summary>Configures a custom resolver for the active ExoClient.</summary>");
        sb.AppendLine("    public static void SetClientLocator(Func<ExoClient> locator) => _clientLocator = locator;");
        sb.AppendLine();
        foreach (var svc in serviceList.Where(IsClientVisibleService))
        {
            string pascalName = ToPascalCase(svc.Name);
            sb.AppendLine($"    /// <summary>Access the {pascalName} service contract.</summary>");
            sb.AppendLine($"    public static {pascalName}ServiceClient {pascalName} =>");
            sb.AppendLine($"        Client.{pascalName}();");
            sb.AppendLine();
        }
        sb.AppendLine("}");
        sb.AppendLine();
        sb.AppendLine("/// <summary>");
        sb.AppendLine("/// Backwards-compatibility alias forwarding to <see cref=\"ExoServices\"/>.");
        sb.AppendLine("/// </summary>");
        sb.AppendLine("public static class Exo");
        sb.AppendLine("{");
        sb.AppendLine("    /// <summary>The active ExoClient used by static service calls.</summary>");
        sb.AppendLine("    public static ExoClient Client");
        sb.AppendLine("    {");
        sb.AppendLine("        get => ExoServices.Client;");
        sb.AppendLine("        set => ExoServices.Client = value;");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    /// <summary>Configures a custom resolver for the active ExoClient.</summary>");
        sb.AppendLine("    public static void SetClientLocator(Func<ExoClient> locator) => ExoServices.SetClientLocator(locator);");
        sb.AppendLine();
        foreach (var svc in serviceList.Where(IsClientVisibleService))
        {
            string pascalName = ToPascalCase(svc.Name);
            sb.AppendLine($"    /// <summary>Access the {pascalName} service contract.</summary>");
            sb.AppendLine($"    public static {pascalName}ServiceClient {pascalName} =>");
            sb.AppendLine($"        ExoServices.{pascalName};");
            sb.AppendLine();
        }
        sb.AppendLine("}");
        sb.AppendLine();

        var studioServices = serviceList.Where(s => !IsClientVisibleService(s) || s.Actions.Any(a => !IsClientAction(a))).ToList();
        if (includeStudio && studioServices.Count > 0)
        {
            sb.AppendLine("#if UNITY_EDITOR");
            sb.AppendLine("/// <summary>");
            sb.AppendLine("/// Static access to Exoforge studio/admin services matching the extension runtime syntax.");
            sb.AppendLine("/// Reachable only from Unity Editor assemblies.");
            sb.AppendLine("/// </summary>");
            sb.AppendLine("public static class ExoStudioServices");
            sb.AppendLine("{");
            sb.AppendLine("    /// <summary>The active ExoClient used by static studio service calls.</summary>");
            sb.AppendLine("    public static ExoClient Client");
            sb.AppendLine("    {");
            sb.AppendLine("        get => ExoServices.Client;");
            sb.AppendLine("        set => ExoServices.Client = value;");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    /// <summary>Configures a custom resolver for the active ExoClient.</summary>");
            sb.AppendLine("    public static void SetClientLocator(Func<ExoClient> locator) => ExoServices.SetClientLocator(locator);");
            sb.AppendLine();
            foreach (var svc in studioServices)
            {
                string pascalName = ToPascalCase(svc.Name);
                sb.AppendLine($"    /// <summary>Access the {pascalName} studio service contract.</summary>");
                sb.AppendLine($"    public static {pascalName}ServiceClient {pascalName} =>");
                sb.AppendLine($"        Client.{pascalName}();");
                sb.AppendLine();
            }
            sb.AppendLine("}");
            sb.AppendLine("#endif");
            sb.AppendLine();
        }

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

        foreach (var svc in serviceList)
        {
            string pascalName = ToPascalCase(svc.Name);
            string fieldName = SanitizeFieldName(svc.Name);
            bool isStudioOnly = !IsClientVisibleService(svc);
            if (isStudioOnly) sb.AppendLine("#if UNITY_EDITOR");
            sb.AppendLine($"    private {pascalName}ServiceClient? {fieldName};");
            sb.AppendLine($"    public {pascalName}ServiceClient {pascalName} => {fieldName} ??= new {pascalName}ServiceClient(_client);");
            if (isStudioOnly) sb.AppendLine("#endif");
            sb.AppendLine();
        }
        sb.AppendLine("}");
        sb.AppendLine();

        // 4. Service Clients
        foreach (var svc in serviceList)
        {
            string svcPascal = ToPascalCase(svc.Name);
            bool isStudioOnly = !IsClientVisibleService(svc);
            if (isStudioOnly) sb.AppendLine("#if UNITY_EDITOR");
            sb.AppendLine($"/// <summary>Client interface for the {svc.Name} service.</summary>");
            if (svc.Name.Equals("auth", StringComparison.OrdinalIgnoreCase))
            {
                sb.AppendLine("/// <remarks>");
                sb.AppendLine("/// ⚠️ IMPORTANT: In Unity games, use <c>ExoforgeSDK.Auth.LoginAnonymously()</c> or <c>ExoforgeSDK.Auth.LoginWithEmail()</c>");
                sb.AppendLine("/// instead of calling raw RPCs on this client. <c>ExoforgeSDK.Auth</c> handles device ID caching, token persistence, and session lifecycle.");
                sb.AppendLine("/// </remarks>");
            }
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
                bool isStudioAction = !isStudioOnly && includeStudio && !IsClientAction(act);
                if (isStudioAction) sb.AppendLine("#if UNITY_EDITOR");

                string actPascal = ToPascalCase(act.Name);
                string transportPref = act.Transport.ToLowerInvariant() switch
                {
                    "http" => "ExoTransportPreference.Http",
                    "ws" or "websocket" => "ExoTransportPreference.WebSocket",
                    _ => "ExoTransportPreference.Auto"
                };

                bool hasParams = act.Params.Count > 0;
                string? respName = actionRespNames.TryGetValue(act, out var arName) ? arName : null;
                string returnType = ReturnTypeName(svcPascal, act, respName);

                bool isAuthAction = svc.Name.Equals("auth", StringComparison.OrdinalIgnoreCase) &&
                    (act.Name.Equals("anonymous", StringComparison.OrdinalIgnoreCase) ||
                     act.Name.Equals("login", StringComparison.OrdinalIgnoreCase) ||
                     act.Name.Equals("register", StringComparison.OrdinalIgnoreCase));
                string authDocNotice = isAuthAction
                    ? "\n    /// <remarks>⚠️ NOTE: In Unity game code, prefer ExoforgeSDK.Auth (e.g. ExoforgeSDK.Auth.LoginAnonymously()) instead.</remarks>"
                    : "";
                string authObsoleteAttr = isAuthAction
                    ? "    [Obsolete(\"In Unity game code, prefer using ExoforgeSDK.Auth (e.g. ExoforgeSDK.Auth.LoginAnonymously()) which automatically persists device IDs and manages session credentials.\", false)]\n"
                    : "";

                // Overload 1: Strongly-typed parameter arguments
                if (hasParams)
                {
                    var usedParams = new HashSet<string>(StringComparer.Ordinal);
                    var usedReqProps = new HashSet<string>(StringComparer.Ordinal);
                    var paramDefs = new List<string>();
                    var assignments = new List<(string Prop, string Param)>();

                    foreach (var p in act.Params)
                    {
                        string csType = MapTypeToCSharp(p.Type);
                        string propName = SafePropertyName(p.Name, $"{svcPascal}{actPascal}Request", usedReqProps);
                        string paramName = EscapeIdentifier(SafeParamName(p.Name, usedParams));
                        paramDefs.Add($"{csType} {paramName}");
                        assignments.Add((propName, paramName));
                    }
                    string paramSignature = string.Join(", ", paramDefs);

                    sb.AppendLine($"    /// <summary>{XmlDoc(act.Doc, $"Executes {act.Name} action with typed arguments.")}</summary>{authDocNotice}");
                    if (!string.IsNullOrEmpty(authObsoleteAttr)) sb.Append(authObsoleteAttr);
                    sb.AppendLine($"    public Task<{returnType}> {actPascal}Async({paramSignature}, CancellationToken cancellationToken = default)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        var req = new {svcPascal}{actPascal}Request");
                    sb.AppendLine("        {");
                    foreach (var (propName, paramName) in assignments)
                    {
                        sb.AppendLine($"            {propName} = {paramName},");
                    }
                    sb.AppendLine("        };");
                    sb.AppendLine($"        return {actPascal}Async(req, cancellationToken);");
                    sb.AppendLine("    }");
                    sb.AppendLine();

                    // Callback overload 1 (Unity-friendly)
                    string callbackParams = $"{paramSignature}, Action<{returnType}> onComplete, Action<ExoActionException>? onError = null";
                    string callArgs = string.Join(", ", assignments.Select(a => a.Item2));
                    sb.AppendLine($"    /// <summary>{XmlDoc(act.Doc, $"Executes {act.Name} action with callbacks on the Unity main thread.")}</summary>{authDocNotice}");
                    if (!string.IsNullOrEmpty(authObsoleteAttr)) sb.Append(authObsoleteAttr);
                    sb.AppendLine($"    public void {actPascal}({callbackParams})");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        _ = {actPascal}Async({callArgs}).ContinueWith(t =>");
                    sb.AppendLine("        {");
                    sb.AppendLine("            if (t.IsFaulted)");
                    sb.AppendLine("            {");
                    sb.AppendLine("                var ex = t.Exception?.InnerException as ExoActionException ?? new ExoActionException(\"action_failed\", t.Exception?.InnerException?.Message ?? \"Action failed\");");
                    sb.AppendLine($"                _client.Dispatcher.Post(() => {{ if (onError != null) onError(ex); else ExoClient.OnError?.Invoke($\"[{svc.Name}.{act.Name}] Action error: {{ex.Message}}\", ex); }});");
                    sb.AppendLine("            }");
                    sb.AppendLine("            else");
                    sb.AppendLine("            {");
                    sb.AppendLine("                var res = t.Result;");
                    sb.AppendLine("                _client.Dispatcher.Post(() => onComplete?.Invoke(res));");
                    sb.AppendLine("            }");
                    sb.AppendLine("        });");
                    sb.AppendLine("    }");
                    sb.AppendLine();

                    // Overload 2: Strongly-typed Request DTO
                    sb.AppendLine($"    /// <summary>{XmlDoc(act.Doc, $"Executes {act.Name} action with a typed request DTO.")}</summary>{authDocNotice}");
                    if (!string.IsNullOrEmpty(authObsoleteAttr)) sb.Append(authObsoleteAttr);
                    sb.AppendLine($"    public Task<{returnType}> {actPascal}Async({svcPascal}{actPascal}Request request, CancellationToken cancellationToken = default)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        return _client.SendActionAsync<{returnType}>(\"{svc.Name}\", \"{act.Name}\", request, {transportPref}, cancellationToken: cancellationToken);");
                    sb.AppendLine("    }");
                    sb.AppendLine();

                    // Callback overload 2: Strongly-typed Request DTO with callback
                    sb.AppendLine($"    /// <summary>{XmlDoc(act.Doc, $"Executes {act.Name} action with a typed request DTO and callbacks.")}</summary>{authDocNotice}");
                    if (!string.IsNullOrEmpty(authObsoleteAttr)) sb.Append(authObsoleteAttr);
                    sb.AppendLine($"    public void {actPascal}({svcPascal}{actPascal}Request request, Action<{returnType}> onComplete, Action<ExoActionException>? onError = null)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        _ = {actPascal}Async(request).ContinueWith(t =>");
                    sb.AppendLine("        {");
                    sb.AppendLine("            if (t.IsFaulted)");
                    sb.AppendLine("            {");
                    sb.AppendLine("                var ex = t.Exception?.InnerException as ExoActionException ?? new ExoActionException(\"action_failed\", t.Exception?.InnerException?.Message ?? \"Action failed\");");
                    sb.AppendLine($"                _client.Dispatcher.Post(() => {{ if (onError != null) onError(ex); else ExoClient.OnError?.Invoke($\"[{svc.Name}.{act.Name}] Action error: {{ex.Message}}\", ex); }});");
                    sb.AppendLine("            }");
                    sb.AppendLine("            else");
                    sb.AppendLine("            {");
                    sb.AppendLine("                var res = t.Result;");
                    sb.AppendLine("                _client.Dispatcher.Post(() => onComplete?.Invoke(res));");
                    sb.AppendLine("            }");
                    sb.AppendLine("        });");
                    sb.AppendLine("    }");
                    sb.AppendLine();
                }

                if (!hasParams)
                {
                    sb.AppendLine($"    /// <summary>{XmlDoc(act.Doc, $"Executes {act.Name} action.")}</summary>{authDocNotice}");
                    if (!string.IsNullOrEmpty(authObsoleteAttr)) sb.Append(authObsoleteAttr);
                    sb.AppendLine($"    public Task<{returnType}> {actPascal}Async(CancellationToken cancellationToken = default)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        return _client.SendActionAsync<{returnType}>(\"{svc.Name}\", \"{act.Name}\", null, {transportPref}, cancellationToken: cancellationToken);");
                    sb.AppendLine("    }");
                    sb.AppendLine();

                    sb.AppendLine($"    /// <summary>{XmlDoc(act.Doc, $"Executes {act.Name} action with callbacks on the Unity main thread.")}</summary>{authDocNotice}");
                    if (!string.IsNullOrEmpty(authObsoleteAttr)) sb.Append(authObsoleteAttr);
                    sb.AppendLine($"    public void {actPascal}(Action<{returnType}> onComplete, Action<ExoActionException>? onError = null)");
                    sb.AppendLine("    {");
                    sb.AppendLine($"        _ = {actPascal}Async().ContinueWith(t =>");
                    sb.AppendLine("        {");
                    sb.AppendLine("            if (t.IsFaulted)");
                    sb.AppendLine("            {");
                    sb.AppendLine("                var ex = t.Exception?.InnerException as ExoActionException ?? new ExoActionException(\"action_failed\", t.Exception?.InnerException?.Message ?? \"Action failed\");");
                    sb.AppendLine($"                _client.Dispatcher.Post(() => {{ if (onError != null) onError(ex); else ExoClient.OnError?.Invoke($\"[{svc.Name}.{act.Name}] Action error: {{ex.Message}}\", ex); }});");
                    sb.AppendLine("            }");
                    sb.AppendLine("            else");
                    sb.AppendLine("            {");
                    sb.AppendLine("                var res = t.Result;");
                    sb.AppendLine("                _client.Dispatcher.Post(() => onComplete?.Invoke(res));");
                    sb.AppendLine("            }");
                    sb.AppendLine("        });");
                    sb.AppendLine("    }");
                    sb.AppendLine();
                }

                if (isStudioAction) sb.AppendLine("#endif");
            }

            sb.AppendLine("}");
            if (isStudioOnly) sb.AppendLine("#endif");
            sb.AppendLine();
        }

        sb.AppendLine("}");
        sb.AppendLine();

        foreach (var svc in serviceList)
        {
            string serialized = JsonSerializer.Serialize(svc);
            sb.AppendLine($"{ContractMetadataPrefix}{serialized}");
        }

        return sb.ToString();
    }

    /// <summary>
    /// The C# records the plugin itself owns - its resources, event payloads and action returns -
    /// as fully-qualified names, taken from the plugin's own entry in the export.
    /// </summary>
    private static List<string> OwnJsonTypes(JsonElement root, string pluginId)
    {
        var types = new List<string>();
        JsonElement export = root.TryGetProperty("export", out var exportProp) ? exportProp : root;

        if ((!export.TryGetProperty("extensions", out var plugins) && !export.TryGetProperty("plugins", out plugins)) || plugins.ValueKind != JsonValueKind.Array)
        {
            return types;
        }

        foreach (var plugin in plugins.EnumerateArray())
        {
            string id = plugin.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
            if (!string.Equals(id, pluginId, StringComparison.OrdinalIgnoreCase)) continue;

            if (!plugin.TryGetProperty("services", out var services) || services.ValueKind != JsonValueKind.Array) continue;

            foreach (var service in services.EnumerateArray())
            {
                CollectNamed(service, "resources", "type", types);
                CollectNamed(service, "resources", "record", types);
                CollectNamed(service, "events", "payload_type", types);
                CollectNamed(service, "actions", "returns_type", types);
            }
        }

        return types;
    }

    private static void CollectNamed(JsonElement service, string arrayName, string key, List<string> types)
    {
        if (!service.TryGetProperty(arrayName, out var array) || array.ValueKind != JsonValueKind.Array) return;

        foreach (var item in array.EnumerateArray())
        {
            if (!item.TryGetProperty(key, out var value) || value.ValueKind != JsonValueKind.String) continue;

            string name = value.GetString() ?? "";
            if (name.Length > 0 && !types.Contains(name)) types.Add(name);
        }
    }

    /// <summary>
    /// The C# type an action returns. A record's fields become a generated response model, a scalar
    /// maps to its C# equivalent, and a list wraps whichever applies.
    /// </summary>
    private static string ResponseModelName(string svcPascal, ActionContractModel act)
    {
        if (string.IsNullOrEmpty(act.ReturnTypeName) || act.ReturnTypeName!.Contains("<"))
        {
            return $"{svcPascal}{ToPascalCase(act.Name)}Response";
        }

        // The manifest carries a fully-qualified name so the generated JSON context can resolve it;
        // the client model only needs the record's own name.
        string name = act.ReturnTypeName!.Replace("global::", "");
        int lastDot = name.LastIndexOf('.');

        return lastDot >= 0 ? name.Substring(lastDot + 1) : name;
    }

    private static string ResolveResponseModelName(
        string svcPascal,
        ActionContractModel act,
        Dictionary<string, string> emittedSignatures)
    {
        string baseName = ResponseModelName(svcPascal, act);
        string sig = string.Join("|", act.ReturnFields.Select(f => $"{f.Name}:{f.Type}"));

        if (emittedSignatures.TryGetValue(baseName, out var existingSig) && existingSig != sig)
        {
            return $"{svcPascal}{baseName}";
        }

        return baseName;
    }

    private static string ReturnTypeName(string svcPascal, ActionContractModel act, string? explicitResponseModelName = null)
    {
        string element;

        if (act.ReturnFields.Count > 0 || !string.IsNullOrEmpty(act.ReturnTypeName))
        {
            element = explicitResponseModelName ?? ResponseModelName(svcPascal, act);
        }
        else if (!string.IsNullOrEmpty(act.ReturnType) && act.ReturnType != "ok")
        {
            element = MapTypeToCSharp(act.ReturnType!);
        }
        else
        {
            element = "JsonElement";
        }

        return act.ReturnsList ? $"List<{element}>" : element;
    }

    /// <summary>
    /// The client subset of one service: player/global actions only, or null when none remain.
    /// Events stay with a kept service; a service dropped here has no client surface at all.
    /// </summary>
    private static ServiceContractModel? ClientVisibleService(ServiceContractModel service)
    {
        var actions = service.Actions.Where(IsClientAction).ToList();
        if (actions.Count == 0) return null;

        return new ServiceContractModel
        {
            Name = service.Name,
            Doc = service.Doc,
            Actions = actions,
            Events = service.Events,
            Resources = service.Resources,
            CustomInputs = service.CustomInputs
        };
    }

    public static bool IsClientVisibleService(ServiceContractModel service) =>
        service.Actions.Any(IsClientAction);

    /// <summary>
    /// Scopes a game client may call. <c>player</c> and <c>global</c> are the client surface;
    /// <c>studio</c>, <c>admin</c>, <c>server</c>, <c>service</c> and <c>webhook</c> are not.
    /// </summary>
    public static bool IsClientAction(ActionContractModel action)
    {
        string scope = (action.Scope ?? "").Trim().ToLowerInvariant();
        return scope is "" or "player" or "global";
    }

    /// <summary>Flags the fields the manifest lists as <c>Nullable&lt;T&gt;</c> in the plugin's own C#.</summary>
    private static void MarkNullable(List<ParamModel> fields, JsonElement owner, string key)
    {
        if (!owner.TryGetProperty(key, out var names) || names.ValueKind != JsonValueKind.Array) return;

        var set = new HashSet<string>(names.EnumerateArray().Select(n => n.GetString() ?? ""), StringComparer.Ordinal);
        foreach (var field in fields) field.Nullable = set.Contains(field.Name);
    }

    /// <summary>Applies <c>params_optional</c> and <c>params_defaults</c>: a parameter the caller may omit, and what the server then uses.</summary>
    private static void MarkParamDefaults(List<ParamModel> parameters, JsonElement action)
    {
        if (action.TryGetProperty("params_optional", out var optional) && optional.ValueKind == JsonValueKind.Array)
        {
            var names = new HashSet<string>(optional.EnumerateArray().Select(n => n.GetString() ?? ""), StringComparer.Ordinal);
            foreach (var p in parameters) p.Optional |= names.Contains(p.Name);
        }

        if (action.TryGetProperty("params_defaults", out var defaults) && defaults.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in parameters)
            {
                if (defaults.TryGetProperty(p.Name, out var value)) p.Default = value.GetRawText();
            }
        }
    }

    /// <summary>The initializer a request property gets: the server's own default when the contract carries one.</summary>
    private static string ParamInitializer(ParamModel p, string csType) =>
        p.Default is not null && csType.TrimEnd('?') is "int" or "long" or "double" or "bool" or "string" ? p.Default : "default!";

    /// <summary>A value type that may be null in the contract is <c>int?</c>, not <c>int</c>: a null would not deserialize.</summary>
    private static string WithNullable(string csType, bool nullable) =>
        nullable && csType is "int" or "long" or "double" or "bool" ? csType + "?" : csType;

    private static string MapTypeToCSharp(string type)
    {
        string lower = type.ToLowerInvariant().Trim();
        return lower switch
        {
            "string" or "binary" or "text" => "string",
            // "integer" is the Elixir/BEAM integer and stays 64-bit. "int"/"int32" come from C#
            // Int32 manifests and must keep their width instead of widening to long.
            "int" or "int32" => "int",
            "integer" or "int64" => "long",
            "float" or "double" or "number" => "double",
            "boolean" or "bool" => "bool",
            "map" or "object" or "term" => "JsonElement",
            "list_string" or "[:string]" => "List<string>",
            "list_int" or "[:int]" or "[:int32]" => "List<int>",
            "[:integer]" or "list_integer" or "[:int64]" => "List<long>",
            "list_map" or "[:map]" => "List<JsonElement>",
            _ => "JsonElement"
        };
    }

    public static string ToPascalCase(string text)
    {
        if (string.IsNullOrEmpty(text)) return "Unnamed";

        var sb = new StringBuilder();
        bool newWord = true;

        foreach (char c in text)
        {
            if (char.IsLetterOrDigit(c))
            {
                if (newWord)
                {
                    sb.Append(char.ToUpperInvariant(c));
                    newWord = false;
                }
                else
                {
                    sb.Append(c);
                }
            }
            else
            {
                newWord = true;
            }
        }

        string result = sb.ToString();
        if (result.Length == 0) return "Unnamed";
        if (char.IsDigit(result[0])) return "_" + result;
        return result;
    }

    public static string ToCamelCase(string text)
    {
        string pascal = ToPascalCase(text);
        if (string.IsNullOrEmpty(pascal)) return pascal;
        if (pascal.Length > 1 && pascal.StartsWith("_", StringComparison.Ordinal))
        {
            return "_" + char.ToLowerInvariant(pascal[1]) + pascal.Substring(2);
        }
        return char.ToLowerInvariant(pascal[0]) + pascal.Substring(1);
    }

    private static string EscapeIdentifier(string name)
    {
        return CsharpKeywords.Contains(name) ? $"@{name}" : name;
    }

    private static string SanitizeFieldName(string text)
    {
        if (string.IsNullOrEmpty(text)) return "_unnamed";
        var sb = new StringBuilder("_");
        foreach (char c in text)
        {
            if (char.IsLetterOrDigit(c)) sb.Append(char.ToLowerInvariant(c));
            else sb.Append('_');
        }
        return sb.ToString();
    }

    private static string SafePropertyName(string rawName, string enclosingTypeName, HashSet<string> usedNames)
    {
        string propName = ToPascalCase(rawName);
        if (string.Equals(propName, enclosingTypeName, StringComparison.Ordinal))
        {
            propName += "Value";
        }

        string candidate = propName;
        int suffix = 2;
        while (!usedNames.Add(candidate))
        {
            candidate = $"{propName}{suffix++}";
        }
        return candidate;
    }

    private static string SafeParamName(string rawName, HashSet<string> usedNames)
    {
        string param = ToCamelCase(rawName);
        if (string.IsNullOrEmpty(param)) param = "arg";
        if (char.IsDigit(param[0])) param = "_" + param;

        string candidate = param;
        int suffix = 2;
        while (!usedNames.Add(candidate))
        {
            candidate = $"{param}{suffix++}";
        }
        return candidate;
    }
}
