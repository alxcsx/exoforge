using System;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Canonical base class for implementing Exoforge plugins in C#.
/// </summary>
public abstract class PluginBehaviour : IExoforgePlugin
{
    private IPluginContext? _context;

    public virtual string Id => GetType().Name.ToLowerInvariant();
    public virtual string Version => "0.1.0";

    protected IPluginContext Context
    {
        get => _context ??= HostPluginContext.Default;
        private set => _context = value;
    }

    protected IDatabase Database => Context.Database;
    protected IDatabase Db => Database;
    protected ILogger Logger => Context.Logger;
    protected IActionDispatcher Actions => Context.Actions;
    protected IEventDispatcher Events => Context.Events;
    protected IEntityManager Entities => Context.Entities;

    public virtual Task OnInitAsync(IPluginContext context)
    {
        Context = context ?? throw new ArgumentNullException(nameof(context));
        HostPluginContext.Wire(this, context);
        return Task.CompletedTask;
    }

    public virtual Task OnShutdownAsync()
    {
        return Task.CompletedTask;
    }

    protected Task EmitEventAsync(string eventName, object payload, string? topic = null)
    {
        return Events.EmitAsync(eventName, payload, topic);
    }

    protected Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload)
    {
        return Actions.CallActionAsync<TResponse>(service, action, payload);
    }
}
