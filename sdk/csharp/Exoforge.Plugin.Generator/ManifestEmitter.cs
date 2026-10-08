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
/// Emits the plugin manifest as JSON.
///
/// It used to be an Elixir map literal, which the server evaluated. That made the file readable by
/// exactly one language, so the C# tooling — which has to read a plugin's contracts to generate its
/// client stubs, and has no Elixir — could not read the only file the contracts were in. JSON is
/// readable by both, is not evaluated by either, and carries no atom syntax that has to be recreated
/// on the way in.
///
/// Which values are atoms in the server's terms is decided by the key, not by position, so the loader
/// needs no schema of its own. That is why the resource's C# record is called <c>record</c> rather
/// than <c>type</c>: <c>type</c> is an atom everywhere else, and one field that meant something else
/// would have cost a path-aware reader.
///
/// <c>type</c>, <c>version</c> and <c>entry_point</c> are placeholders: they depend on build settings
/// (native vs wasm, the build stamp) that the generator's per-file transform cannot see.
/// <see cref="Finalize"/> fills them in at output time.
/// </summary>
internal static class ManifestEmitter
{
    public const string TypePlaceholder = "__EXO_TYPE__";
    public const string VersionPlaceholder = "__EXO_VERSION__";
    public const string EntryPlaceholder = "__EXO_ENTRY__";

    /// <summary>The whole manifest. The top-level name is absent: it is the id, and two fields for one value is one to disagree with.</summary>
    public static string Manifest(
        string id,
        IEnumerable<string> provides,
        IEnumerable<string> dependencies,
        IEnumerable<ServiceModel> services,
        string? category,
        string? title,
        string? icon,
        bool system)
    {
        var sb = new StringBuilder();
        sb.Append("{\n");
        sb.Append($"  \"id\": {Str(id)},\n");
        sb.Append($"  \"type\": {Str(TypePlaceholder)},\n");
        sb.Append($"  \"version\": {Str(VersionPlaceholder)},\n");
        sb.Append("  \"context\": \"global\",\n");
        sb.Append($"  \"entry_point\": {Str(EntryPlaceholder)},\n");
        sb.Append($"  \"dependencies\": {Atoms(dependencies)},\n");
        sb.Append($"  \"provides\": {Atoms(provides)},\n");

        if (!string.IsNullOrEmpty(category)) sb.Append($"  \"category\": {Str(category!)},\n");
        if (system) sb.Append("  \"system\": true,\n");

        if (!string.IsNullOrEmpty(title))
        {
            sb.Append($"  \"dashboard_view\": {{\"id\": {Str(id)}, \"title\": {Str(title!)}, \"icon\": {Str(icon ?? "")}}},\n");
        }

        sb.Append("  \"services\": [\n");

        bool firstService = true;

        foreach (var service in services)
        {
            if (!firstService) sb.Append(",\n");
            firstService = false;

            sb.Append("    {\n");
            sb.Append($"      \"name\": {Str(service.Name)},\n");
            sb.Append("      \"actions\": [\n");

            for (int i = 0; i < service.Actions.Count; i++)
            {
                var action = service.Actions[i];
                string comma = i == service.Actions.Count - 1 ? "" : ",";
                string returnsType = action.ReturnsType is null ? "" : $", \"returns_type\": {Str(action.ReturnsType)}";

                sb.Append("        {");
                sb.Append($"\"name\": {Str(action.Name)}, ");
                sb.Append($"\"mode\": {Str(action.Mode)}, ");
                sb.Append($"\"scope\": {Str(action.Scope)}, ");
                sb.Append($"\"transport\": {Str(action.Transport)}, ");
                sb.Append($"\"arity\": {action.Params.Count}, ");
                sb.Append($"\"params\": {AtomMap(action.Params)}, ");
                sb.Append($"\"returns\": {Returns(action)}, ");
                sb.Append($"\"returns_list\": {Lower(action.ReturnsList)}{returnsType}}}");
                sb.Append(comma).Append('\n');
            }

            sb.Append("      ],\n");
            sb.Append("      \"events\": [\n");

            for (int i = 0; i < service.Events.Count; i++)
            {
                var evt = service.Events[i];
                string comma = i == service.Events.Count - 1 ? "" : ",";
                string topic = evt.Topic is null ? "" : $", \"topic\": {Str(evt.Topic)}";
                string payload = evt.Payload.Count == 0 ? "" : $", \"payload\": {AtomMap(evt.Payload)}";
                string payloadType = evt.PayloadTypeName is null ? "" : $", \"payload_type\": {Str(evt.PayloadTypeName)}";

                sb.Append($"        {{\"name\": {Str(evt.Name)}{topic}, \"scope\": {Str(evt.Scope)}{payload}{payloadType}}}");
                sb.Append(comma).Append('\n');
            }

            sb.Append("      ],\n");
            sb.Append("      \"resources\": [\n");

            for (int i = 0; i < service.Resources.Count; i++)
            {
                var resource = service.Resources[i];
                string comma = i == service.Resources.Count - 1 ? "" : ",";
                string record = resource.TypeName is null ? "" : $", \"record\": {Str(resource.TypeName)}";

                sb.Append("        {");
                sb.Append($"\"name\": {Str(resource.Name)}, ");
                sb.Append($"\"primary_key\": {Str(resource.PrimaryKey)}{record}, ");
                sb.Append($"\"drawer\": {Atoms(resource.Drawer)}, ");
                sb.Append($"\"actions\": {Atoms(resource.Actions)}, ");
                sb.Append("\"columns\": [");

                for (int c = 0; c < resource.Columns.Count; c++)
                {
                    var column = resource.Columns[c];
                    string columnComma = c == resource.Columns.Count - 1 ? "" : ", ";
                    string role = column.Role is null ? "" : $", \"role\": {Str(column.Role)}";

                    sb.Append($"{{{Column(column)}{role}}}");
                    sb.Append(columnComma);
                }

                sb.Append("]}");
                sb.Append(comma).Append('\n');
            }

            sb.Append("      ]\n");
            sb.Append("    }");
        }

        sb.Append("\n  ],\n");
        sb.Append("  \"entities\": []\n");
        sb.Append("}\n");
        return sb.ToString();
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

    private static string Column(ColumnModel column) =>
        $"\"name\": {Str(column.Name)}, \"type\": {Str(column.Type)}, \"label\": {Str(column.Label)}, " +
        $"\"sortable\": {Lower(column.Sortable)}, \"filterable\": {Lower(column.Filterable)}, \"badge\": {Lower(column.Badge)}";

    /// <summary>A scalar atom, or a record's fields as a map of name to atom.</summary>
    private static string Returns(ActionModel action) =>
        action.ReturnFields.Count > 0 ? AtomMap(action.ReturnFields) : Str(action.ReturnsScalar ?? "term");

    private static string AtomMap(IEnumerable<ParamModel> parameters) =>
        "{" + string.Join(", ", parameters.Select(p => Str(p.Name) + ": " + Str(p.Type))) + "}";

    private static string Atoms(IEnumerable<string> values) =>
        "[" + string.Join(", ", values.Select(Str)) + "]";

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
