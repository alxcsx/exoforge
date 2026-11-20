using System;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Declares a service contract provided by the plugin.
///
/// On a <b>class</b> the class is its own contract and implementation: its <c>[ExoAction]</c> and
/// <c>[ExoEvent]</c> members are the service's. On an <b>interface</b> the interface is the contract
/// and the class that implements it is the plugin's implementation, which is how one plugin provides
/// several services or shares a contract with another project.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoServiceAttribute : Attribute
{
    public string Name { get; }
    public string? Version { get; set; }
    public Type[]? Resources { get; set; }
    public string? Category { get; set; }
    public string? Title { get; set; }
    public string? Icon { get; set; }
    public bool System { get; set; }
    public string? DashboardElement { get; set; }
    public string? DashboardEntry { get; set; }

    public ExoServiceAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

/// <summary>
/// Declares an extension service contract provided by the extension.
/// Standardized alias for <see cref="ExoServiceAttribute"/>.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoExtensionAttribute : ExoServiceAttribute
{
    public ExoExtensionAttribute(string name) : base(name) { }
}

/// <summary>
/// Execution mode for plugin actions.
/// </summary>
public enum ActionMode
{
    Sync,
    Async,
    Cast,

    /// <summary>
    /// Resolved at manifest time from the method's return type: a <see cref="System.Threading.Tasks.Task"/>
    /// return means <see cref="Async"/>, anything else means <see cref="Sync"/>. This is the default.
    /// </summary>
    Auto
}

/// <summary>
/// Preferred transport mechanism for dispatching an Exoforge action.
/// </summary>
public enum ActionTransport
{
    Auto,
    WebSocket,
    Http,
    Webhook
}

/// <summary>
/// Marks a method as an invokable Exoforge Action.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class | AttributeTargets.Struct | AttributeTargets.Interface, Inherited = false, AllowMultiple = false)]
public class ExoActionAttribute : Attribute
{
    /// <summary>Action name on the wire. When omitted, the method name is used in snake_case.</summary>
    public string? Name { get; }

    /// <summary>Defaults to <see cref="ActionMode.Auto"/> (inferred from the return type).</summary>
    public ActionMode Mode { get; set; } = ActionMode.Auto;

    /// <summary>Defaults to "player" (requires player or higher authentication).</summary>
    public string Scope { get; set; } = "player";
    public ActionTransport Transport { get; set; } = ActionTransport.Auto;

    /// <summary>
    /// The service this action belongs to, when the plugin provides more than one. Defaults to the
    /// plugin's first <see cref="ExoServiceAttribute"/>.
    /// </summary>
    public string? Service { get; set; }

    public ExoActionAttribute(string? name = null)
    {
        Name = name;
    }
}

/// <summary>
/// Marks a method as an inbound webhook handler.
/// Webhooks are dispatched via HTTP from external providers (e.g. Stripe, GitHub, Discord)
/// with raw request payloads and headers.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
public class ExoWebhookAttribute : Attribute
{
    /// <summary>Webhook action name on the wire. When omitted, the method name is used in snake_case.</summary>
    public string? Name { get; }

    /// <summary>The service this webhook belongs to. Defaults to the plugin's first <see cref="ExoServiceAttribute"/>.</summary>
    public string? Service { get; set; }

    /// <summary>Action scope required to invoke this webhook. Defaults to "webhook".</summary>
    public string Scope { get; set; } = "webhook";

    public ExoWebhookAttribute(string? name = null)
    {
        Name = name;
    }
}

/// <summary>
/// Marks a method as a scheduled recurring background task (cron job).
/// Executed periodically by the cluster scheduler according to the specified cron expression.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
public class ExoCronAttribute : Attribute
{
    /// <summary>
    /// Standard 5-field cron expression (e.g. "0 0 * * *" for daily at midnight,
    /// "*/5 * * * *" for every 5 minutes, "0 * * * *" for hourly).
    /// </summary>
    public string Schedule { get; }

    /// <summary>Unique task name on the wire. When omitted, the method name is used in snake_case.</summary>
    public string? Name { get; }

    /// <summary>Human-readable description of what this recurring task does.</summary>
    public string? Description { get; set; }

    /// <summary>
    /// Whether the task runs immediately when the extension starts, before the first cron trigger.
    /// Defaults to false.
    /// </summary>
    public bool RunOnStartup { get; set; }

    /// <summary>
    /// The service this cron job belongs to, when the plugin provides more than one.
    /// Defaults to the plugin's first <see cref="ExoServiceAttribute"/>.
    /// </summary>
    public string? Service { get; set; }

    public ExoCronAttribute(string schedule, string? name = null)
    {
        Schedule = schedule ?? throw new ArgumentNullException(nameof(schedule));
        Name = name;
    }
}

/// <summary>
/// Marks an event emitted or handled by the plugin.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method | AttributeTargets.Event | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public class ExoEventAttribute : Attribute
{
    public string? Name { get; }
    public string? Topic { get; set; }
    public string Scope { get; set; } = "global";
    public Type? PayloadType { get; set; }

    /// <summary>
    /// The service this event belongs to, when the plugin provides more than one. Defaults to the
    /// plugin's first <see cref="ExoServiceAttribute"/>.
    /// </summary>
    public string? Service { get; set; }

    public ExoEventAttribute(string? name = null, Type? payloadType = null)
    {
        Name = name;
        PayloadType = payloadType;
    }
}

/// <summary>
/// Declares a metadata-driven Resource provided by the plugin for the Studio Dashboard.
/// Can be applied to domain records, classes, or referenced on service classes.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoResourceAttribute : Attribute
{
    public string? Name { get; set; }
    public string? PrimaryKey { get; set; }
    public string[]? DrawerTabs { get; set; }
    public Type? ResourceType { get; set; }

    /// <summary>
    /// The table this resource is stored in. Defaults to the resource's own name, so a resource is a
    /// real table unless it says otherwise - which is what makes it queryable: typed columns, an
    /// index, and <c>WHERE</c>/<c>ORDER BY</c> in SQL rather than in the plugin.
    /// </summary>
    public string? Source { get; set; }

    /// <summary>
    /// Indicates whether this resource is a singleton (only one record stored).
    /// </summary>
    public bool Singleton { get; set; }

    /// <summary>
    /// Allows player-scoped callers to read this resource through <c>resource_store.list</c> and
    /// <c>resource_store.get</c>. The whole resource becomes readable, not just the caller's rows;
    /// enable it only for data that is public by design (leaderboards, catalogues, config).
    /// </summary>
    public bool AllowPlayerRead { get; set; }

    public ExoResourceAttribute()
    {
    }

    public ExoResourceAttribute(string name)
    {
        Name = name;
    }

    public ExoResourceAttribute(Type resourceType)
    {
        ResourceType = resourceType;
    }
}

/// <summary>
/// Declares a Singleton Resource (exactly one record stored).
/// Creates a default record when queried if none exists yet in the database.
/// In Studio Dashboard, it is presented as a direct configuration form without row table visualization.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoSingletonResourceAttribute : ExoResourceAttribute
{
    public ExoSingletonResourceAttribute()
    {
        Singleton = true;
    }

    public ExoSingletonResourceAttribute(string name) : base(name)
    {
        Singleton = true;
    }

    public ExoSingletonResourceAttribute(Type resourceType) : base(resourceType)
    {
        Singleton = true;
    }
}

/// <summary>
/// Declares a column on a resource schema. Supports smart defaults and type inference.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, Inherited = false, AllowMultiple = false)]
public class ExoColumnAttribute : Attribute
{
    public string? Name { get; set; }
    public string? DataType { get; set; }
    public string? Label { get; set; }

    /// <summary>Marks this column as the primary key of the resource table.</summary>
    public bool PrimaryKey { get; set; }

    /// <summary>Marks this column as unique.</summary>
    public bool Unique { get; set; }

    /// <summary>Marks this column as indexed.</summary>
    public bool Indexed { get; set; }

    /// <summary>Marks this column as a foreign key reference.</summary>
    public bool ForeignKey { get; set; }

    /// <summary>Target referenced table and column (e.g. "player_data.id").</summary>
    public string? References { get; set; }

    /// <summary>
    /// Type of the referenced <see cref="ExoResourceAttribute"/> entity record or class.
    /// When specified, <see cref="ForeignKey"/> is automatically inferred as true, and
    /// <see cref="References"/> is automatically inferred from the target resource's table name and primary key.
    /// </summary>
    public Type? ReferencesType { get; set; }

    /// <summary>
    /// Semantic role of the value (e.g. from <see cref="ExoRole"/>), which the Studio renders specially.
    /// </summary>
    public string? Role { get; set; }

    public bool Sortable { get; set; }
    public bool Filterable { get; set; }
    public bool Badge { get; set; }

    /// <summary>Target bucket name when referencing a file in a bucket.</summary>
    public string? Bucket { get; set; }

    /// <summary>
    /// Preferred Studio Dashboard input widget for editing this column (e.g. from <see cref="ExoStandardInput"/>).
    /// </summary>
    public string? InputType { get; set; }

    /// <summary>Convenience property to mark this column as a file reference.</summary>
    public bool FileReference
    {
        get => Role == "file_reference";
        set { if (value) Role = "file_reference"; }
    }

    public ExoColumnAttribute()
    {
    }

    public ExoColumnAttribute(string name)
    {
        Name = name;
    }
}

/// <summary>
/// Built-in standard dashboard input widget types for <see cref="ExoColumnAttribute.InputType"/>.
/// </summary>
public static partial class ExoInput
{
    public const string Text = "text";
    public const string Color = "color";
    public const string Date = "date";
    public const string Time = "time";
    public const string DateTimeLocal = "datetime_local";
    public const string Textarea = "textarea";
    public const string Email = "email";
    public const string Url = "url";
    public const string Tel = "tel";
    public const string Password = "password";
    public const string Range = "range";
    public const string Json = "json";
    public const string List = "list";
    public const string Checkbox = "checkbox";
    public const string Select = "select";
    public const string FileReference = "file_reference";
}

/// <summary>
/// Backward-compatible alias for <see cref="ExoInput"/>.
/// </summary>
public static class ExoStandardInput
{
    public const string Text = ExoInput.Text;
    public const string Color = ExoInput.Color;
    public const string Date = ExoInput.Date;
    public const string Time = ExoInput.Time;
    public const string DateTimeLocal = ExoInput.DateTimeLocal;
    public const string Textarea = ExoInput.Textarea;
    public const string Email = ExoInput.Email;
    public const string Url = ExoInput.Url;
    public const string Tel = ExoInput.Tel;
    public const string Password = ExoInput.Password;
    public const string Range = ExoInput.Range;
    public const string Json = ExoInput.Json;
    public const string List = ExoInput.List;
    public const string Checkbox = ExoInput.Checkbox;
    public const string Select = ExoInput.Select;
    public const string FileReference = ExoInput.FileReference;
}

/// <summary>
/// Built-in semantic roles for <see cref="ExoColumnAttribute.Role"/>.
/// Turns values into deep links, specialized editors, or chips in the Studio Dashboard.
/// </summary>
public static class ExoRole
{
    public const string UserId = "user_id";
    public const string PlayerId = "user_id";
    public const string FileReference = "file_reference";
    public const string Currency = "currency";
    public const string Status = "status";
    public const string Timestamp = "timestamp";
    public const string Title = "title";
    public const string Description = "description";
}

/// <summary>
/// Declares a plugin dependency on another service.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoDependencyAttribute : Attribute
{
    public string? ServiceName { get; }
    public Type? ServiceType { get; }

    public ExoDependencyAttribute(string serviceName)
    {
        ServiceName = serviceName ?? throw new ArgumentNullException(nameof(serviceName));
    }

    public ExoDependencyAttribute(Type serviceType)
    {
        ServiceType = serviceType ?? throw new ArgumentNullException(nameof(serviceType));
    }
}

/// <summary>
/// Declares a type-safe plugin dependency on a service contract.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoDependencyAttribute<TService> : ExoDependencyAttribute
{
    public ExoDependencyAttribute() : base(typeof(TService))
    {
    }
}

/// <summary>
/// Declares read-only SQL access to another extension's tables.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class DbReadAttribute : Attribute
{
    public string? ExtensionId { get; }
    public Type? MarkerType { get; }

    public DbReadAttribute(string extensionId)
    {
        ExtensionId = extensionId ?? throw new ArgumentNullException(nameof(extensionId));
    }

    public DbReadAttribute(Type markerType)
    {
        MarkerType = markerType ?? throw new ArgumentNullException(nameof(markerType));
    }
}

/// <summary>
/// Declares type-safe read-only SQL access to another extension's tables via a marker type.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class DbReadAttribute<TMarker> : DbReadAttribute
{
    public DbReadAttribute() : base(typeof(TMarker))
    {
    }
}

/// <summary>
/// Marks a resource column as a foreign key referencing <typeparamref name="TRecord"/>.
/// When <typeparamref name="TRecord"/> belongs to another extension, also grants read access via <c>db_read</c>.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, Inherited = false, AllowMultiple = false)]
public class ExoForeignKeyAttribute<TRecord> : Attribute
{
    public string Column { get; }

    public ExoForeignKeyAttribute(string column = "id")
    {
        Column = string.IsNullOrWhiteSpace(column) ? "id" : column;
    }
}

/// <summary>
/// Marks a resource column as a file reference pointing to a file in a storage bucket.
/// Renders direct preview and search/select file picker in Studio Dashboard.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, Inherited = false, AllowMultiple = false)]
public class ExoFileReferenceAttribute : Attribute
{
    public string? Bucket { get; set; }

    public ExoFileReferenceAttribute(string? bucket = null)
    {
        Bucket = bucket;
    }
}


/// <summary>
/// Registers a custom Studio form input widget provided by this plugin.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface, Inherited = false, AllowMultiple = true)]
public class ExoInputTypeAttribute : Attribute
{
    public string Id { get; }
    public string Element { get; set; } = "";
    public string Entry { get; set; } = "";

    public ExoInputTypeAttribute(string id)
    {
        Id = id ?? throw new ArgumentNullException(nameof(id));
    }
}

/// <summary>
/// Canonical action exception thrown by Exoforge extensions to fail an action invocation with an error code and message.
/// Propagates to callers (Unity SDK, Web, Dashboard) as an error response instead of an unexpected crash.
/// </summary>
public class ExoActionException : Exception
{
    public string Code { get; }

    public ExoActionException(string code, string message) : base(message)
    {
        Code = string.IsNullOrWhiteSpace(code) ? "action_failed" : code;
    }

    public ExoActionException(string message) : this("action_failed", message) { }
}

/// <summary>
/// Inbound webhook payload dispatched from external HTTP providers (e.g. Stripe, Steam, Discord).
/// Carries raw body text, request headers, HTTP method, and query parameters.
/// </summary>
public class WebhookPayload
{
    public string Body { get; set; } = "";
    public string RawBody { get; set; } = "";
    public System.Text.Json.JsonElement Json { get; set; } = default;
    public System.Collections.Generic.IReadOnlyDictionary<string, string>? Headers { get; set; }
    public string Method { get; set; } = "POST";
    public System.Collections.Generic.IReadOnlyDictionary<string, string>? Query { get; set; }
}

/// <summary>
/// Optional response structure for inbound webhook handlers.
/// </summary>
public class WebhookResult
{
    public int StatusCode { get; set; } = 200;
    public string? Body { get; set; }
    public bool Verified { get; set; } = true;

    public WebhookResult() { }

    public WebhookResult(int statusCode, string? body = null, bool verified = true)
    {
        StatusCode = statusCode;
        Body = body;
        Verified = verified;
    }
}

/// <summary>
/// Marks a method as the extension's seed hook.
/// Executed once on every extension start after <c>OnExtensionStart</c>.
/// The method must be parameterless, return <c>void</c> or <c>Task</c>, and reside on the extension root.
/// Must be idempotent by contract: extensions check whether initial rows exist before inserting.
/// A throwing seed logs and fails the lifecycle handshake.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
public class ExoSeedAttribute : Attribute
{
}






/// <summary>The column types a migration can convert a column to. They are the manifest's logical storage types.</summary>
public enum ExoType
{
    Text, Int16, Int32, Int64, Float32, Float64, Decimal, Bool, Uuid, Timestamp, Bytes, Json
}

/// <summary>
/// Describes how a resource's table changes on the way to an extension version, as a list of operations given by
/// the attributes on the same class (<see cref="ExoRenameAttribute"/>, <see cref="ExoConvertAttribute"/>,
/// <see cref="ExoFillAttribute"/>, <see cref="ExoDropAttribute"/>, <see cref="ExoSetNotNullAttribute"/>),
/// applied in the order they are written. Put each migration in its own file. Nothing here runs: the generator
/// reads the attributes, and the server applies them as plain <c>ALTER TABLE</c> statements.
/// </summary>
/// <example>
/// <code>
/// [ExoMigration(typeof(Item), To = "1.2.0")]
/// [ExoRename("nm", "name")]
/// [ExoConvert("price", ExoType.Decimal)]
/// public static class ItemsV2 { }
/// </code>
/// </example>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, Inherited = false, AllowMultiple = false)]
public sealed class ExoMigrationAttribute : Attribute
{
    public Type Resource { get; }

    /// <summary>
    /// The extension version this migration brings the table to ("1.2.0"). It runs on a deploy of that
    /// version or later when the table is still behind it, in the order of <c>To</c>.
    /// </summary>
    public string To { get; set; } = "";

    public ExoMigrationAttribute(Type resource) => Resource = resource;
}

/// <summary>
/// Marks a static method that brings one stored row up to the shape of extension version <see cref="To"/>:
/// <c>static T Up(JsonElement oldRow)</c>. The row arrives as stored (old columns included) and the method
/// returns the current record. A row is migrated the first time it is read after the deploy, and written back
/// stamped with the new version, so the rows of players who never return are never touched.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
public sealed class ExoRowMigrationAttribute : Attribute
{
    public Type Resource { get; }

    /// <summary>The extension version whose shape the method returns ("2.0.0").</summary>
    public string To { get; set; } = "";

    public ExoRowMigrationAttribute(Type resource) => Resource = resource;
}

/// <summary>The stored form of an extension version: <c>major * 1_000_000 + minor * 1_000 + patch</c>.</summary>
public static class ExoVersion
{
    /// <summary>0 for anything that is not <c>MAJOR.MINOR.PATCH</c> with minor and patch under 1000.</summary>
    public static long Encode(string? version)
    {
        if (string.IsNullOrWhiteSpace(version)) return 0;

        // "1.4.0-beta" and "1.4.0+build" are the 1.4.0 release for ordering purposes.
        int cut = version!.IndexOfAny(new[] { '-', '+' });
        string[] parts = (cut < 0 ? version : version.Substring(0, cut)).Split('.');
        if (parts.Length != 3 ||
            !long.TryParse(parts[0], out long major) ||
            !long.TryParse(parts[1], out long minor) ||
            !long.TryParse(parts[2], out long patch) ||
            major < 0 || minor is < 0 or > 999 || patch is < 0 or > 999)
        {
            return 0;
        }

        return major * 1_000_000 + minor * 1_000 + patch;
    }
}

/// <summary>Renames a column (<c>ALTER TABLE .. RENAME COLUMN</c>).</summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public sealed class ExoRenameAttribute : Attribute
{
    public string From { get; }
    public string To { get; }
    public ExoRenameAttribute(string from, string to) { From = from; To = to; }
}

/// <summary>
/// Changes a column's type with the conversion PostgreSQL defines between the two
/// (<c>ALTER COLUMN .. TYPE .. USING column::type</c>). A conversion it does not define needs a migration function.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public sealed class ExoConvertAttribute : Attribute
{
    public string Column { get; }
    public ExoType To { get; }
    public ExoConvertAttribute(string column, ExoType to) { Column = column; To = to; }
}

/// <summary>Adds a column that every existing row gets <paramref name="value"/> for (<c>ADD COLUMN .. NOT NULL DEFAULT</c>).</summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public sealed class ExoFillAttribute : Attribute
{
    public string Column { get; }
    public object? Value { get; }
    public ExoFillAttribute(string column, object? value) { Column = column; Value = value; }
}

/// <summary>Drops a column and the data in it (<c>DROP COLUMN</c>).</summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public sealed class ExoDropAttribute : Attribute
{
    public string Column { get; }
    public ExoDropAttribute(string column) => Column = column;
}

/// <summary>Makes a column <c>NOT NULL</c>, first giving rows that have none <see cref="Fill"/>.</summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public sealed class ExoSetNotNullAttribute : Attribute
{
    public string Column { get; }
    public object? Fill { get; set; }
    public ExoSetNotNullAttribute(string column) => Column = column;
}
