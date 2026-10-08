using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Exoforge.Plugin.Generator;

internal sealed record ParamModel(string Name, string Type);

internal sealed record ColumnModel(
    string Name,
    string Type,
    string Label,
    bool Sortable,
    bool Filterable,
    bool Badge,
    string? Role);

internal sealed record ActionModel(
    string Name,
    string Mode,
    string Scope,
    string Transport,
    List<ParamModel> Params,
    string? ReturnsScalar,
    List<ParamModel> ReturnFields,
    bool ReturnsList,
    string? ReturnsType)
{
    /// <summary>
    /// The return type as Elixir: an atom for a scalar, a map literal for a record. Rendered here
    /// rather than carried around pre-rendered, because the JSON twin needs the same data.
    /// </summary>
    public string ReturnsExs => ReturnFields.Count > 0
        ? "%{" + string.Join(", ", ReturnFields.Select(f => f.Name + ": :" + f.Type)) + "}"
        : ":" + (ReturnsScalar ?? "term");
}

internal sealed record EventModel(
    string Name,
    string? Topic,
    string Scope,
    List<ParamModel> Payload,
    string? PayloadTypeName);

internal sealed record ResourceModel(
    string Name,
    string PrimaryKey,
    string[] Drawer,
    List<string> Actions,
    List<ColumnModel> Columns,
    string? TypeName);

internal sealed record ServiceModel(
    string Name,
    List<ActionModel> Actions,
    List<EventModel> Events,
    List<ResourceModel> Resources,
    string? Category,
    string? Title,
    string? Icon,
    bool System);

/// <summary>
/// Emits the Elixir manifest. The output is byte-for-byte what ManifestGen produced, so a plugin
/// built before and after the switch to the generator deploys identically.
///
/// <c>type</c>, <c>version</c> and <c>entry_point</c> are placeholders: they depend on build
/// settings (native vs wasm, the build stamp) that the generator's per-file transform cannot see.
/// <see cref="Finalize"/> fills them in at output time.
/// </summary>
internal static class ManifestEmitter
{
    public const string TypePlaceholder = "__EXO_TYPE__";
    public const string VersionPlaceholder = "__EXO_VERSION__";
    public const string EntryPlaceholder = "__EXO_ENTRY__";

    /// <summary>One service's <c>%{...},</c> entry inside <c>services: [...]</c>.</summary>
    public static string Service(ServiceModel service)
    {
        var sb = new StringBuilder();
        sb.AppendLine("    %{");
        sb.AppendLine($"      name: :{service.Name},");

        sb.AppendLine("      actions: [");
        foreach (var action in service.Actions)
        {
            string paramList = string.Join(", ", action.Params.Select(p => $"{p.Name}: :{p.Type}"));
            string returnsList = action.ReturnsList ? ", returns_list: true" : "";
            string returnsType = action.ReturnsType is null ? "" : $", returns_type: \"{action.ReturnsType}\"";
            sb.AppendLine($"        %{{name: :{action.Name}, mode: :{action.Mode}, scope: :{action.Scope}, transport: :{action.Transport}, arity: {action.Params.Count}, params: [{paramList}], returns: {action.ReturnsExs}{returnsList}{returnsType}}},");
        }

        sb.AppendLine("      ],");

        sb.AppendLine("      events: [");
        foreach (var evt in service.Events)
        {
            string topic = evt.Topic is null ? "" : $", topic: \"{evt.Topic}\"";
            string payload = evt.Payload.Count > 0
                ? $", payload: [{string.Join(", ", evt.Payload.Select(p => $"{p.Name}: :{p.Type}"))}]"
                : "";
            string payloadType = evt.PayloadTypeName is null ? "" : $", payload_type: \"{evt.PayloadTypeName}\"";
            sb.AppendLine($"        %{{name: :{evt.Name}{topic}, scope: :{evt.Scope}{payload}{payloadType}}},");
        }

        sb.AppendLine("      ],");

        sb.AppendLine("      resources: [");
        foreach (var resource in service.Resources)
        {
            sb.AppendLine("        %{");
            sb.AppendLine($"          name: :{resource.Name},");
            sb.AppendLine($"          primary_key: :{resource.PrimaryKey},");

            // The C# record behind the resource, when there is one: the client's stub generator names
            // its model after it and registers it for source-generated JSON.
            if (resource.TypeName is not null) sb.AppendLine($"          type: \"{resource.TypeName}\",");
            sb.AppendLine($"          drawer: [{string.Join(", ", resource.Drawer.Select(d => $":{d}"))}],");
            sb.AppendLine($"          actions: [{string.Join(", ", resource.Actions.Select(a => $":{a}"))}],");
            sb.AppendLine("          columns: [");
            foreach (var column in resource.Columns)
            {
                string role = column.Role is null ? "" : $", role: \"{column.Role}\"";
                sb.AppendLine($"            %{{name: :{column.Name}, type: :{column.Type}, label: \"{column.Label}\", sortable: {Lower(column.Sortable)}, filterable: {Lower(column.Filterable)}, badge: {Lower(column.Badge)}{role}}},");
            }

            sb.AppendLine("          ]");
            sb.AppendLine("        },");
        }

        sb.AppendLine("      ]");
        sb.AppendLine("    },");
        return sb.ToString();
    }

    /// <summary>The manifest header, up to and including <c>services: [</c>.</summary>
    public static string Header(
        string id,
        IEnumerable<string> provides,
        IEnumerable<string> dependencies,
        ServiceModel? primary)
    {
        var sb = new StringBuilder();
        sb.AppendLine("%{");
        sb.AppendLine($"  id: :{id},");
        sb.AppendLine($"  name: \"{id}\",");
        sb.AppendLine($"  type: :{TypePlaceholder},");
        sb.AppendLine($"  version: \"{VersionPlaceholder}\",");
        sb.AppendLine("  context: :global,");
        sb.AppendLine($"  entry_point: \"{EntryPlaceholder}\",");
        sb.AppendLine($"  dependencies: [{string.Join(", ", dependencies.Select(d => $":{d}"))}],");
        sb.AppendLine($"  provides: [{string.Join(", ", provides.Select(p => $":{p}"))}],");

        if (!string.IsNullOrEmpty(primary?.Category)) sb.AppendLine($"  category: \"{primary!.Category}\",");

        if (primary?.System == true) sb.AppendLine("  system: true,");

        if (!string.IsNullOrEmpty(primary?.Title))
        {
            sb.AppendLine($"  dashboard_view: %{{id: :{primary!.Name}, title: \"{primary!.Title}\", icon: \"{primary!.Icon}\"}},");
        }

        sb.AppendLine("  services: [");
        return sb.ToString();
    }

    /// <summary>The manifest tail after the service entries.</summary>
    public static string Footer()
    {
        return "  ],\n  entities: []\n}\n";
    }

    /// <summary>Fills in the build-dependent fields.</summary>
    public static string Finalize(string manifest, string id, string version, string pluginType, string? buildStamp)
    {
        string entry = pluginType == "native" ? id : id + ".wasm";
        string stamped = string.IsNullOrEmpty(buildStamp) ? version : version + "+" + buildStamp;

        return manifest
            .Replace(TypePlaceholder, pluginType)
            .Replace(VersionPlaceholder, stamped)
            .Replace(EntryPlaceholder, entry);
    }

    /// <summary>
    /// The same contracts as JSON, in the shape <c>plugin_manager.export_plugin_info</c> returns.
    ///
    /// The manifest is Elixir source and the tooling that generates client stubs is pure C# — a game
    /// developer has no Elixir toolchain — so it cannot read one. This is the same information in a
    /// form it can, written beside the manifest: a plugin that is built but not deployed then still
    /// has a contract to generate against.
    ///
    /// Written by hand rather than with a serializer because this is a Roslyn component on
    /// netstandard2.0 with one dependency, and the shape is fixed.
    /// </summary>
    public static string Contracts(
        string id,
        IEnumerable<string> provides,
        IEnumerable<string> dependencies,
        IEnumerable<ServiceModel> services)
    {
        var sb = new StringBuilder();
        sb.Append("{\n  \"export\": {\n    \"plugins\": [\n      {\n");
        sb.Append($"        \"id\": {Str(id)},\n");
        sb.Append($"        \"name\": {Str(id)},\n");
        sb.Append($"        \"version\": {Str(VersionPlaceholder)},\n");
        sb.Append($"        \"type\": {Str(TypePlaceholder)},\n");
        sb.Append($"        \"entry_point\": {Str(EntryPlaceholder)},\n");
        sb.Append($"        \"provides\": [{string.Join(", ", provides.Select(Str))}],\n");
        sb.Append($"        \"dependencies\": [{string.Join(", ", dependencies.Select(Str))}],\n");
        sb.Append("        \"services\": [\n");

        bool firstService = true;

        foreach (var service in services)
        {
            if (!firstService) sb.Append(",\n");
            firstService = false;

            sb.Append("          {\n");
            sb.Append($"            \"name\": {Str(service.Name)},\n");

            sb.Append("            \"actions\": [\n");
            for (int i = 0; i < service.Actions.Count; i++)
            {
                var action = service.Actions[i];
                string comma = i == service.Actions.Count - 1 ? "" : ",";
                string returnsType = action.ReturnsType is null ? "" : ", \"returns_type\": " + Str(action.ReturnsType);
                string returns = action.ReturnFields.Count > 0
                    ? ParamMap(action.ReturnFields)
                    : Str(action.ReturnsScalar ?? "term");

                sb.Append("              {\n");
                sb.Append($"                \"name\": {Str(action.Name)},\n");
                sb.Append($"                \"mode\": {Str(action.Mode)},\n");
                sb.Append($"                \"scope\": {Str(action.Scope)},\n");
                sb.Append($"                \"transport\": {Str(action.Transport)},\n");
                sb.Append($"                \"arity\": {action.Params.Count},\n");
                sb.Append($"                \"params\": {ParamMap(action.Params)},\n");
                sb.Append($"                \"returns\": {returns},\n");
                sb.Append($"                \"returns_list\": {Lower(action.ReturnsList)}{returnsType}\n");
                sb.Append($"              }}{comma}\n");
            }

            sb.Append("            ],\n");

            sb.Append("            \"events\": [\n");
            for (int i = 0; i < service.Events.Count; i++)
            {
                var evt = service.Events[i];
                string comma = i == service.Events.Count - 1 ? "" : ",";
                string topic = evt.Topic is null ? "" : ", \"topic\": " + Str(evt.Topic);
                string payload = evt.Payload.Count == 0 ? "" : ", \"payload\": " + ParamMap(evt.Payload);
                string payloadType = evt.PayloadTypeName is null ? "" : ", \"payload_type\": " + Str(evt.PayloadTypeName);

                sb.Append($"              {{\"name\": {Str(evt.Name)}{topic}, \"scope\": {Str(evt.Scope)}{payload}{payloadType}}}{comma}\n");
            }

            sb.Append("            ],\n");

            sb.Append("            \"resources\": [\n");
            for (int i = 0; i < service.Resources.Count; i++)
            {
                var resource = service.Resources[i];
                string comma = i == service.Resources.Count - 1 ? "" : ",";
                string type = resource.TypeName is null ? "" : "\"type\": " + Str(resource.TypeName) + ",\n                ";

                sb.Append("              {\n");
                sb.Append($"                \"name\": {Str(resource.Name)},\n");
                sb.Append($"                \"primary_key\": {Str(resource.PrimaryKey)},\n");
                sb.Append("                ");
                sb.Append(type);
                sb.Append($"\"drawer\": [{string.Join(", ", resource.Drawer.Select(Str))}],\n");
                sb.Append($"                \"actions\": [{string.Join(", ", resource.Actions.Select(Str))}],\n");
                sb.Append("                \"columns\": [\n");

                for (int c = 0; c < resource.Columns.Count; c++)
                {
                    var column = resource.Columns[c];
                    string columnComma = c == resource.Columns.Count - 1 ? "" : ",";
                    string role = column.Role is null ? "" : ", \"role\": " + Str(column.Role);

                    sb.Append($"                  {{\"name\": {Str(column.Name)}, \"type\": {Str(column.Type)}, \"label\": {Str(column.Label)}, \"sortable\": {Lower(column.Sortable)}, \"filterable\": {Lower(column.Filterable)}, \"badge\": {Lower(column.Badge)}{role}}}{columnComma}\n");
                }

                sb.Append("                ]\n");
                sb.Append($"              }}{comma}\n");
            }

            sb.Append("            ]\n");
            sb.Append("          }");
        }

        sb.Append("\n        ],\n");
        sb.Append("        \"entities\": []\n");
        sb.Append("      }\n    ]\n  }\n}\n");
        return sb.ToString();
    }

    /// <summary>
    /// A <c>{"name": "type"}</c> object. A keyword list in the manifest is what a map becomes once
    /// it has been through <c>PluginRegistry.sanitize_for_json/1</c>, which is the shape the client
    /// generator reads.
    /// </summary>
    private static string ParamMap(IEnumerable<ParamModel> parameters) =>
        "{" + string.Join(", ", parameters.Select(p => Str(p.Name) + ": " + Str(p.Type))) + "}";

    /// <summary>A JSON string literal. The only values here that are not identifiers are labels and topics.</summary>
    private static string Str(string value)
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
                    if (c < ' ') sb.Append("\\u").Append(((int)c).ToString("x4"));
                    else sb.Append(c);
                    break;
            }
        }

        sb.Append('"');
        return sb.ToString();
    }

    private static string Lower(bool value) => value ? "true" : "false";
}
