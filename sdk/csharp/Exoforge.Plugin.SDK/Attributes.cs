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
/// Marks a method as an invokable Exoforge Action.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
public class ExoActionAttribute : Attribute
{
    public string Name { get; }
    public ActionMode Mode { get; set; } = ActionMode.Sync;
    public string Scope { get; set; } = "global";

    public ExoActionAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

/// <summary>
/// Marks an event emitted or handled by the plugin.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method | AttributeTargets.Event, Inherited = false, AllowMultiple = true)]
public class ExoEventAttribute : Attribute
{
    public string Name { get; }
    public string? Topic { get; set; }
    public string Scope { get; set; } = "global";

    public ExoEventAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

/// <summary>
/// Declares a metadata-driven Resource provided by the plugin for the Studio Dashboard.
/// </summary>
[AttributeUsage(AttributeTargets.Class, Inherited = false, AllowMultiple = true)]
public class ExoResourceAttribute : Attribute
{
    public string Name { get; }
    public string PrimaryKey { get; set; } = "id";
    public string[]? DrawerTabs { get; set; }

    public ExoResourceAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
    }
}

/// <summary>
/// Declares a column on a resource schema.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field, Inherited = false, AllowMultiple = false)]
public class ExoColumnAttribute : Attribute
{
    public string Name { get; }
    public string DataType { get; set; } = "string";
    public string? Label { get; set; }
    public bool Sortable { get; set; }
    public bool Filterable { get; set; }
    public bool Badge { get; set; }

    public ExoColumnAttribute(string name)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
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
