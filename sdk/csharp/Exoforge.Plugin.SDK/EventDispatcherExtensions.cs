using System;
using System.Reflection;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Type-safe extension methods for <see cref="IEventDispatcher"/> to emit cluster events
/// without magic strings. Infers the event name and default topic from <see cref="ExoEventAttribute"/>
/// or the payload type name.
/// </summary>
public static class EventDispatcherExtensions
{
    /// <summary>
    /// Emits a typed event payload. Resolves event name and topic from <see cref="ExoEventAttribute"/>
    /// on <typeparamref name="T"/>, falling back to <c>typeof(T).Name.ToSnakeCase()</c>.
    /// </summary>
    public static Task EmitAsync<T>(this IEventDispatcher events, T payload, string? topic = null)
    {
        if (events == null) throw new ArgumentNullException(nameof(events));
        if (payload == null) throw new ArgumentNullException(nameof(payload));

        string eventName = EventMetadata<T>.EventName;
        string? effectiveTopic = topic ?? EventMetadata<T>.DefaultTopic;

        return events.EmitAsync(eventName, payload, effectiveTopic);
    }

    /// <summary>
    /// Resolves the event wire name for type <typeparamref name="T"/>.
    /// </summary>
    public static string EventName<T>() => EventMetadata<T>.EventName;
}

internal static class EventMetadata<T>
{
    public static readonly string EventName;
    public static readonly string? DefaultTopic;

    static EventMetadata()
    {
        var type = typeof(T);
        var attr = type.GetCustomAttribute<ExoEventAttribute>();

        if (attr != null)
        {
            EventName = !string.IsNullOrWhiteSpace(attr.Name) ? attr.Name : ExoNaming.ToSnakeCase(type.Name);
            DefaultTopic = attr.Topic;
        }
        else
        {
            EventName = ExoNaming.ToSnakeCase(type.Name);
            DefaultTopic = null;
        }
    }
}
