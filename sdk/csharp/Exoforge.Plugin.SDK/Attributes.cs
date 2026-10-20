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

    public string Scope { get; set; } = "global";
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
/// Explicitly marks a property or parameter as the primary key of a resource.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, Inherited = false, AllowMultiple = false)]
public class PrimaryKeyAttribute : Attribute
{
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

    /// <summary>Semantic role of the value (e.g. "user_id"), which the Studio renders specially.</summary>
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


