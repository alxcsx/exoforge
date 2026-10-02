using System;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Base class for first-class stateful game entity actors in Exoforge.
/// Implements host-authoritative persistence, lifecycle hooks, and ambient services.
/// </summary>
public abstract class Entity
{
    public string Id { get; set; } = string.Empty;
    public IPluginContext? Context { get; set; }
    public IDatabase? Db => Context?.Database;
    public IEntityManager? Entities => Context?.Entities;

    /// <summary>
    /// Lifecycle hook executed when the entity is activated for the very first time.
    /// </summary>
    public virtual Task OnCreateAsync() => Task.CompletedTask;

    /// <summary>
    /// Emits a cluster-wide event from this entity.
    /// </summary>
    public virtual void Emit(string eventName, object payload, string? topic = null)
    {
        Context?.Events.EmitAsync(eventName, payload, topic);
    }

    /// <summary>
    /// Persists the entity's current state back to the host store.
    /// </summary>
    public virtual void Save()
    {
        HostBridge.SetState($"entity:{Id}", this);
    }

    /// <summary>
    /// Immediately flushes the entity state snapshot to persistent storage.
    /// </summary>
    public virtual void SaveNow()
    {
        Save();
    }
}
