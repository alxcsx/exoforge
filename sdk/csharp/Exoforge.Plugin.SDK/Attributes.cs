using System;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Declares a service contract provided by the plugin.
/// </summary>
[AttributeUsage(AttributeTargets.Class, Inherited = false, AllowMultiple = true)]
public class ExoServiceAttribute : Attribute
{
    public string Name { get; }
    public string? Version { get; set; }
    public Type[]? Resources { get; set; }
    public string? Category { get; set; }
    public string? Title { get; set; }
    public string? Icon { get; set; }
    public bool System { get; set; }

    public ExoServiceAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

/// <summary>
/// Execution mode for plugin actions.
/// </summary>
public enum ActionMode
{
    Sync,
    Async,
    Cast
}

/// <summary>
/// Preferred transport mechanism for dispatching an Exoforge action.
/// </summary>
public enum ActionTransport
{
    Auto,
    WebSocket,
    Http
}

/// <summary>
/// Marks a method as an invokable Exoforge Action.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
public class ExoActionAttribute : Attribute
{
    public string Name { get; }
    public ActionMode Mode { get; set; } = ActionMode.Sync;
    public string Scope { get; set; } = "global";
    public ActionTransport Transport { get; set; } = ActionTransport.Auto;

    public ExoActionAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

/// <summary>
/// Marks an event emitted or handled by the plugin.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method | AttributeTargets.Event | AttributeTargets.Struct, Inherited = false, AllowMultiple = true)]
public class ExoEventAttribute : Attribute
{
    public string Name { get; }
    public string? Topic { get; set; }
    public string Scope { get; set; } = "global";
    public Type? PayloadType { get; set; }

    public ExoEventAttribute(string name, Type? payloadType = null)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
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
    public bool Sortable { get; set; }
    public bool Filterable { get; set; }
    public bool Badge { get; set; }

    public ExoColumnAttribute()
    {
    }

    public ExoColumnAttribute(string name)
    {
        Name = name;
    }
}

/// <summary>
/// Marks a dependency to be injected into the plugin by the Exoforge container.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, Inherited = false, AllowMultiple = false)]
public class InjectAttribute : Attribute
{
    public string? ServiceName { get; }

    public InjectAttribute(string? serviceName = null)
    {
        ServiceName = serviceName;
    }
}

/// <summary>
/// Persistence modes for stateful entity actors.
/// </summary>
public enum PersistenceMode
{
    Memory,
    Snapshot,
    Relational
}

/// <summary>
/// Marks a class as a first-class stateful game entity actor.
/// </summary>
[AttributeUsage(AttributeTargets.Class, Inherited = false, AllowMultiple = false)]
public class EntityAttribute : Attribute
{
    public string Name { get; }
    public PersistenceMode Persist { get; set; } = PersistenceMode.Snapshot;
    public int TimeoutMs { get; set; } = 300_000;
    public int MaxHeapSizeBytes { get; set; } = 50 * 1024 * 1024;

    public EntityAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

