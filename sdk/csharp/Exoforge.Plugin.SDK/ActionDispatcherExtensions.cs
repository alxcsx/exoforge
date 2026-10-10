using System;
using System.Reflection;
using System.Threading.Tasks;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Type-safe extension methods for <see cref="IActionDispatcher"/> to call actions
/// without magic strings. Resolves service and action name from <see cref="ExoActionAttribute"/>
/// and <see cref="ExoServiceAttribute"/> on the request type.
/// </summary>
public static class ActionDispatcherExtensions
{
    /// <summary>
    /// Calls another service's action asynchronously using a typed request object.
    /// Infers service and action name from attributes on <typeparamref name="TRequest"/>.
    /// </summary>
    public static Task<TResponse?> CallActionAsync<TRequest, TResponse>(
        this IActionDispatcher actions,
        TRequest request)
    {
        if (actions == null) throw new ArgumentNullException(nameof(actions));
        if (request == null) throw new ArgumentNullException(nameof(request));

        string service = ActionRequestMetadata<TRequest>.Service;
        string action = ActionRequestMetadata<TRequest>.Action;

        return actions.CallActionAsync<TResponse>(service, action, request);
    }

    /// <summary>
    /// Calls another service's action synchronously using a typed request object.
    /// Infers service and action name from attributes on <typeparamref name="TRequest"/>.
    /// </summary>
    public static TResponse? CallAction<TRequest, TResponse>(
        this IActionDispatcher actions,
        TRequest request)
    {
        if (actions == null) throw new ArgumentNullException(nameof(actions));
        if (request == null) throw new ArgumentNullException(nameof(request));

        string service = ActionRequestMetadata<TRequest>.Service;
        string action = ActionRequestMetadata<TRequest>.Action;

        return actions.CallAction<TResponse>(service, action, request);
    }
}

internal static class ActionRequestMetadata<TRequest>
{
    public static readonly string Service;
    public static readonly string Action;

    static ActionRequestMetadata()
    {
        var type = typeof(TRequest);
        var actionAttr = type.GetCustomAttribute<ExoActionAttribute>();
        var serviceAttr = type.GetCustomAttribute<ExoServiceAttribute>();

        // 1. Resolve service
        if (actionAttr != null && !string.IsNullOrWhiteSpace(actionAttr.Service))
        {
            Service = actionAttr.Service!;
        }
        else if (serviceAttr != null && !string.IsNullOrWhiteSpace(serviceAttr.Name))
        {
            Service = serviceAttr.Name;
        }
        else
        {
            Service = "";
        }

        // 2. Resolve action name
        if (actionAttr != null && !string.IsNullOrWhiteSpace(actionAttr.Name))
        {
            Action = actionAttr.Name!;
        }
        else
        {
            Action = ExoNaming.ToSnakeCase(type.Name);
        }

        if (string.IsNullOrWhiteSpace(Service))
        {
            throw new InvalidOperationException(
                $"Cannot determine target Service for request type '{type.FullName}'. " +
                $"Decorate the request type with [ExoAction(Service = \"service_name\")] or [ExoService(\"service_name\")].");
        }
    }
}
