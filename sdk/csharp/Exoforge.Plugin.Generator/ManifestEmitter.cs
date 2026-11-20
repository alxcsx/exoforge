using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Exoforge.Plugin.Generator;

/// <summary><c>Default</c> is the C# default as JSON text, set only for a parameter that declares one.</summary>
internal sealed record ParamModel(string Name, string Type, bool Nullable = false, bool Optional = false, string? Default = null);

/// <summary>An enum a column is typed as: its type, and its members with the names the schema uses.</summary>
internal sealed record EnumModel(string Type, List<KeyValuePair<string, string>> Members);

internal sealed record ColumnModel(
    string Name,
    string Type,
    string Label,
    bool Sortable,
    bool Filterable,
    bool Badge,
    string? Role,
    string? Default,
    List<string>? Choices,
    string? Bucket = null,
    string? Input = null,
    bool ForeignKey = false,
    string? References = null,
    bool Nullable = false,
    string Storage = "text",
    bool PrimaryKey = false,
    bool Unique = false,
    bool Indexed = false,
    string? Decl = null);

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
    string Source,
    string PrimaryKey,
    string[] Drawer,
    List<string> Actions,
    List<ColumnModel> Columns,
    string? TypeName,
    bool Singleton = false,
    bool AllowPlayerRead = false,
    int Version = 1);

/// <summary>One step of a migration, ready to write: the operation and its arguments as JSON values.</summary>
internal sealed record MigrationOp(string Op, string? Column, string? From, string? To, string? ValueJson);

/// <summary>A resource's change from one version to the next, found on a class marked <c>[ExoMigration]</c>.</summary>
internal sealed record MigrationModel(string Resource, int From, int To, List<MigrationOp> Ops, string? Decl);

internal sealed record CronModel(
    string Name,
    string Schedule,
    bool RunOnStartup,
    string? Description = null);

internal sealed record ServiceModel(
    string Name,
    List<ActionModel> Actions,
    List<EventModel> Events,
    List<ResourceModel> Resources,
    string? Category,
    string? Title,
    string? Icon,
    bool System,
    string? DashboardElement = null,
    string? DashboardEntry = null,
    List<CronModel>? Crons = null)
{
    public List<CronModel> Crons { get; init; } = Crons ?? new();
}

internal sealed record InputTypeModel(string Id, string Element, string Entry);

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
/// (the plugin kind, the build stamp) that the generator's per-file transform cannot see.
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
        bool system,
        IEnumerable<InputTypeModel>? inputTypes = null,
        IEnumerable<string>? dbRead = null,
        IEnumerable<MigrationModel>? migrations = null)
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
        sb.Append($"  \"db_read\": {Atoms(dbRead ?? Array.Empty<string>())},\n");
        sb.Append($"  \"migrations\": {Migrations(migrations)},\n");

        string effectiveCategory = !string.IsNullOrEmpty(category) ? category! : (system ? "System" : "Game");
        string effectiveTitle = !string.IsNullOrEmpty(title) ? title! : FormatTitle(id);
        string effectiveIcon = !string.IsNullOrEmpty(icon) ? icon! : (system ? "⚙️" : "🧩");

        sb.Append($"  \"category\": {Str(effectiveCategory)},\n");
        sb.Append($"  \"title\": {Str(effectiveTitle)},\n");
        sb.Append($"  \"icon\": {Str(effectiveIcon)},\n");
        if (system) sb.Append("  \"system\": true,\n");

        if (!system || !string.IsNullOrEmpty(title) || !string.IsNullOrEmpty(icon))
        {
            var primary = services.FirstOrDefault();
            string extra = "";
            if (!string.IsNullOrEmpty(primary?.DashboardElement)) extra += $", \"element\": {Str(primary!.DashboardElement!)}";
            if (!string.IsNullOrEmpty(primary?.DashboardEntry)) extra += $", \"entry\": {Str(primary!.DashboardEntry!)}";
            sb.Append($"  \"dashboard_view\": {{\"id\": {Str(id)}, \"title\": {Str(effectiveTitle)}, \"icon\": {Str(effectiveIcon)}{extra}}},\n");
        }

        if (inputTypes != null && inputTypes.Any())
        {
            sb.Append("  \"input_types\": {\n");
            var itList = inputTypes.ToList();
            for (int i = 0; i < itList.Count; i++)
            {
                var it = itList[i];
                string comma = i == itList.Count - 1 ? "" : ",";
                sb.Append($"    {Str(it.Id)}: {{\"element\": {Str(it.Element)}, \"entry\": {Str(it.Entry)}}}{comma}\n");
            }
            sb.Append("  },\n");
        }

        sb.Append("  \"services\": [\n");

        bool firstService = true;

        foreach (var service in services)
        {
            if (!firstService) sb.Append(",\n");
            firstService = false;

            sb.Append("    {\n");
            sb.Append($"      \"name\": {Str(service.Name)},\n");
            if (!string.IsNullOrEmpty(service.Category)) sb.Append($"      \"category\": {Str(service.Category!)},\n");
            if (!string.IsNullOrEmpty(service.Title)) sb.Append($"      \"title\": {Str(service.Title!)},\n");
            if (!string.IsNullOrEmpty(service.Icon)) sb.Append($"      \"icon\": {Str(service.Icon!)},\n");
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
                sb.Append($"\"params\": {AtomMap(action.Params)}{ParamHints(action.Params)}, ");
                sb.Append($"\"returns\": {Returns(action)}, ");
                sb.Append($"\"returns_list\": {Lower(action.ReturnsList)}{returnsType}{NullableNames("returns_nullable", action.ReturnFields)}}}");
                sb.Append(comma).Append('\n');
            }

            sb.Append("      ],\n");
            sb.Append("      \"events\": [\n");

            for (int i = 0; i < service.Events.Count; i++)
            {
                var evt = service.Events[i];
                string comma = i == service.Events.Count - 1 ? "" : ",";
                string topic = evt.Topic is null ? "" : $", \"topic\": {Str(evt.Topic)}";
                string payload = evt.Payload.Count == 0 ? "" : $", \"payload\": {AtomMap(evt.Payload)}{NullableNames("payload_nullable", evt.Payload)}";
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
                if (resource.Singleton)
                {
                    sb.Append("\"singleton\": true, \"kind\": \"singleton\", ");
                }
                if (resource.AllowPlayerRead)
                {
                    sb.Append("\"allow_player_read\": true, ");
                }
                // The shape `Exoforge.Std.Resources.normalize_source/1` reads. A bare string would not
                // match, and a resource with no source is stored as an opaque key-value document.
                sb.Append($"\"source\": {{\"table\": {Str(resource.Source)}}}, ");
                sb.Append($"\"version\": {resource.Version}, ");
                sb.Append($"\"schema_hash\": {Str(SchemaHash(resource))}, ");
                sb.Append($"\"drawer\": {Atoms(resource.Drawer)}, ");
                sb.Append($"\"actions\": {Atoms(resource.Actions)}, ");
                sb.Append("\"columns\": [");

                for (int c = 0; c < resource.Columns.Count; c++)
                {
                    var column = resource.Columns[c];
                    if (!column.PrimaryKey && string.Equals(column.Name, resource.PrimaryKey, StringComparison.OrdinalIgnoreCase))
                    {
                        column = column with { PrimaryKey = true };
                    }
                    string columnComma = c == resource.Columns.Count - 1 ? "" : ", ";
                    string role = column.Role is null ? "" : $", \"role\": {Str(column.Role)}";
                    string bucket = column.Bucket is null ? "" : $", \"bucket\": {Str(column.Bucket)}";
                    string fallback = column.Default is null ? "" : $", \"default\": {Str(column.Default)}";
                    string choices = column.Choices is null ? "" : $", \"choices\": {Atoms(column.Choices)}";
                    string fk = column.ForeignKey ? ", \"foreign_key\": true" : "";
                    string refs = column.References is null ? "" : $", \"references\": {Str(column.References)}";

                    sb.Append($"{{{Column(column)}{role}{bucket}{fallback}{choices}{fk}{refs}}}");
                    sb.Append(columnComma);
                }

                sb.Append("]}");
                sb.Append(comma).Append('\n');
            }

            sb.Append("      ]");

            if (service.Crons != null && service.Crons.Count > 0)
            {
                sb.Append(",\n      \"crons\": [\n");
                for (int i = 0; i < service.Crons.Count; i++)
                {
                    var cron = service.Crons[i];
                    string comma = i == service.Crons.Count - 1 ? "" : ",";
                    string desc = cron.Description is null ? "" : $", \"description\": {Str(cron.Description)}";
                    sb.Append($"        {{\"name\": {Str(cron.Name)}, \"schedule\": {Str(cron.Schedule)}, \"run_on_startup\": {Lower(cron.RunOnStartup)}{desc}}}");
                    sb.Append(comma).Append('\n');
                }
                sb.Append("      ]\n");
                sb.Append("    }");
            }
            else
            {
                sb.Append("\n    }");
            }
        }

        sb.Append("\n  ]\n");
        sb.Append("}\n");
        return sb.ToString();
    }

    /// <summary>Fills in the build-dependent fields.</summary>
    public static string Finalize(string manifest, string id, string version, string pluginType, string? buildStamp)
    {
        // The plugin's binary, named after it. A runtime that needs a different entry point - a
        // different artifact extension, say - is a change here and a runner module in the kernel.
        string stamped = string.IsNullOrEmpty(buildStamp) ? version : version + "+" + buildStamp;

        return manifest
            .Replace(TypePlaceholder, pluginType)
            .Replace(VersionPlaceholder, stamped)
            .Replace(EntryPlaceholder, id);
    }

    private static string Column(ColumnModel column)
    {
        string baseJson = $"\"name\": {Str(column.Name)}, \"type\": {Str(column.Type)}, \"storage\": {Str(column.Storage)}, \"label\": {Str(column.Label)}, " +
            $"\"primary_key\": {Lower(column.PrimaryKey)}, \"unique\": {Lower(column.Unique)}, \"indexed\": {Lower(column.Indexed)}, " +
            $"\"sortable\": {Lower(column.Sortable)}, \"filterable\": {Lower(column.Filterable)}, \"badge\": {Lower(column.Badge)}";

        if (!string.IsNullOrEmpty(column.Input))
        {
            baseJson += $", \"input\": {Str(column.Input!)}";
        }

        if (column.Nullable) baseJson += ", \"nullable\": true";

        // Where the property is declared, so a schema change can say where to look. Not part of schema_hash.
        if (!string.IsNullOrEmpty(column.Decl)) baseJson += $", \"decl\": {Str(column.Decl!)}";

        return baseJson;
    }

    private static string Migrations(IEnumerable<MigrationModel>? migrations)
    {
        var list = (migrations ?? Array.Empty<MigrationModel>())
            .OrderBy(m => m.Resource, StringComparer.Ordinal).ThenBy(m => m.From)
            .ToList();

        if (list.Count == 0) return "[]";

        var items = list.Select(m =>
        {
            string decl = string.IsNullOrEmpty(m.Decl) ? "" : $", \"decl\": {Str(m.Decl!)}";
            string ops = string.Join(", ", m.Ops.Select(Op));
            return $"{{\"resource\": {Str(m.Resource)}, \"from\": {m.From}, \"to\": {m.To}{decl}, \"ops\": [{ops}]}}";
        });

        return "[\n    " + string.Join(",\n    ", items) + "\n  ]";
    }

    private static string Op(MigrationOp op)
    {
        string column = op.Column is null ? "" : $", \"column\": {Str(op.Column)}";
        string from = op.From is null ? "" : $", \"from\": {Str(op.From)}";
        string to = op.To is null ? "" : $", \"to\": {Str(op.To)}";
        string value = op.ValueJson is null ? "" : $", \"value\": {op.ValueJson}";
        return $"{{\"op\": {Str(op.Op)}{column}{from}{to}{value}}}";
    }

    internal static string SchemaHash(ResourceModel resource)
    {
        var sb = new StringBuilder();
        sb.Append(resource.Source).Append('\n');
        foreach (var col in resource.Columns.OrderBy(c => c.Name, StringComparer.Ordinal))
        {
            bool isPk = col.PrimaryKey || string.Equals(col.Name, resource.PrimaryKey, StringComparison.OrdinalIgnoreCase);
            string choices = col.Choices is null ? "" : string.Join(",", col.Choices);
            string def = col.Default is null ? "" : Str(col.Default);
            sb.Append(col.Name).Append('|')
              .Append(col.Storage).Append('|')
              .Append(Lower(col.Nullable)).Append('|')
              .Append(Lower(isPk)).Append('|')
              .Append(Lower(col.Unique)).Append('|')
              .Append(Lower(col.Indexed)).Append('|')
              .Append(def).Append('|')
              .Append(choices).Append('\n');
        }

        using var sha = System.Security.Cryptography.SHA256.Create();
        byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(sb.ToString()));
        var hex = new StringBuilder(64);
        foreach (byte b in hash) hex.Append(b.ToString("x2"));
        return hex.ToString();
    }

    /// <summary>A scalar atom, or a record's fields as a map of name to atom.</summary>
    private static string Returns(ActionModel action) =>
        action.ReturnFields.Count > 0 ? AtomMap(action.ReturnFields) : Str(action.ReturnsScalar ?? "term");

    /// <summary>
    /// The fields that are <c>Nullable&lt;T&gt;</c> in C#: the type atom stays <c>integer</c>, so a client
    /// needs this beside it to know a <c>null</c> is a legal value rather than a malformed response.
    /// </summary>
    private static string NullableNames(string key, IEnumerable<ParamModel> fields)
    {
        var names = fields.Where(f => f.Nullable).Select(f => f.Name).ToList();
        return names.Count == 0 ? "" : $", \"{key}\": {Atoms(names)}";
    }

    /// <summary>
    /// What the type atom cannot say about a parameter: which ones a caller may leave out, which may be
    /// null, and what the server uses when they are absent - so a stub can offer the same default.
    /// </summary>
    private static string ParamHints(IEnumerable<ParamModel> parameters)
    {
        var list = parameters.ToList();
        var sb = new StringBuilder();
        if (list.Any(p => p.Optional)) sb.Append(", \"params_optional\": ").Append(Atoms(list.Where(p => p.Optional).Select(p => p.Name)));
        sb.Append(NullableNames("params_nullable", list));
        var defaults = list.Where(p => p.Default is not null).ToList();
        if (defaults.Count > 0) sb.Append(", \"params_defaults\": {").Append(string.Join(", ", defaults.Select(p => Str(p.Name) + ": " + p.Default))).Append('}');
        return sb.ToString();
    }

    private static string AtomMap(IEnumerable<ParamModel> parameters) =>
        "{" + string.Join(", ", parameters.Select(p => Str(p.Name) + ": " + Str(p.Type))) + "}";

    private static string Atoms(IEnumerable<string> values) =>
        "[" + string.Join(", ", values.Select(Str)) + "]";

    /// <summary>A JSON string literal. The only values here that are not identifiers are labels and topics.</summary>
    internal static string Str(string value)
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

    private static string FormatTitle(string id)
    {
        if (string.IsNullOrEmpty(id)) return id;
        string[] parts = id.Split(new[] { '_', '-' }, StringSplitOptions.RemoveEmptyEntries);
        for (int i = 0; i < parts.Length; i++)
        {
            if (parts[i].Length > 0)
                parts[i] = char.ToUpperInvariant(parts[i][0]) + parts[i].Substring(1);
        }
        return string.Join(" ", parts);
    }
}
