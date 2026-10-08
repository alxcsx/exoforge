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
    string Returns,
    bool ReturnsList,
    string? ReturnsType);

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
            sb.AppendLine($"        %{{name: :{action.Name}, mode: :{action.Mode}, scope: :{action.Scope}, transport: :{action.Transport}, arity: {action.Params.Count}, params: [{paramList}], returns: {action.Returns}{returnsList}{returnsType}}},");
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

    private static string Lower(bool value) => value ? "true" : "false";
}
