using System;
using System.Collections.Generic;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Registry of generated service clients, so a plugin can inject a typed client directly
/// (<c>[Inject("player_data")] public static PlayerDataServiceClient PlayerData</c>) and never touch
/// <see cref="IActionDispatcher"/>. Generated stubs register their clients from a module initializer,
/// which also keeps the client constructors rooted for NativeAOT.
/// </summary>
public static class PluginServiceRegistry
{
    private static readonly Dictionary<Type, Func<IActionDispatcher, object>> Factories = new();

    /// <summary>Registers how to build a typed service client from the ambient dispatcher.</summary>
    public static void Register<TClient>(Func<IActionDispatcher, TClient> factory) where TClient : class
    {
        Factories[typeof(TClient)] = dispatcher => factory(dispatcher);
    }

    /// <summary>Builds the registered client for <paramref name="clientType"/>, if any.</summary>
    public static bool TryCreate(Type clientType, IActionDispatcher dispatcher, out object? client)
    {
        if (clientType != null && Factories.TryGetValue(clientType, out var factory))
        {
            client = factory(dispatcher);
            return true;
        }

        client = null;
        return false;
    }
}
