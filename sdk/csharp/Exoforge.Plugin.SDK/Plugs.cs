using System;
using System.Collections.Generic;
using System.Text.Json;

namespace Exoforge.Plugin.SDK;

/// <summary>What an action plug sees about the call it wraps.</summary>
public sealed class ActionCall
{
    public ActionCall(string action, JsonElement payload, string? playerId, IReadOnlyList<string> scopes, string? gameVersion)
    {
        Action = action;
        Payload = payload;
        PlayerId = playerId;
        Scopes = scopes;
        GameVersion = gameVersion;
    }

    public string Action { get; }
    public JsonElement Payload { get; }
    public string? PlayerId { get; }
    public IReadOnlyList<string> Scopes { get; }

    /// <summary>The caller's game version, when the client sent one.</summary>
    public string? GameVersion { get; }
}

/// <summary>
/// Middleware around every action of the extension. A plug may inspect the call, answer without calling
/// <paramref name="next"/>, change the result, or throw an <see cref="ExoActionException"/> to refuse it.
/// Plugs run outside the action's own code, first registered first.
/// </summary>
public interface IActionPlug
{
    object? Invoke(ActionCall call, Func<object?> next);
}

/// <summary>
/// Middleware around the extension's key-value database calls (<c>Get</c>, <c>All</c>, <c>Put</c>, <c>Delete</c>), on
/// the stored JSON, below row migration. Override only what the plug needs; the rest passes through.
/// </summary>
public interface IDatabasePlug
{
    string? Get(string table, string key, Func<string, string, string?> next) => next(table, key);
    string? All(string table, Func<string, string?> next) => next(table);
    bool Put(string table, string key, string json, Func<string, string, string, bool> next) => next(table, key, json);
    bool Delete(string table, string key, Func<string, string, bool> next) => next(table, key);
}

/// <summary>
/// Where an extension adds its own optional workflows on top of the SDK: register plugs once, for example from
/// <c>OnExtensionStart()</c>. The SDK itself ships none; versioning features that not every game needs are meant
/// to be written this way.
/// </summary>
public static class ExoPlugs
{
    private static readonly object Gate = new();
    private static IActionPlug[] _actions = Array.Empty<IActionPlug>();
    private static IDatabasePlug[] _databases = Array.Empty<IDatabasePlug>();

    public static void Use(IActionPlug plug)
    {
        if (plug == null) throw new ArgumentNullException(nameof(plug));
        lock (Gate) _actions = Append(_actions, plug);
    }

    public static void Use(IDatabasePlug plug)
    {
        if (plug == null) throw new ArgumentNullException(nameof(plug));
        lock (Gate) _databases = Append(_databases, plug);
    }

    /// <summary>Forgets every plug (tests).</summary>
    public static void Clear()
    {
        lock (Gate)
        {
            _actions = Array.Empty<IActionPlug>();
            _databases = Array.Empty<IDatabasePlug>();
        }
    }

    private static T[] Append<T>(T[] list, T item)
    {
        var next = new T[list.Length + 1];
        Array.Copy(list, next, list.Length);
        next[list.Length] = item;
        return next;
    }

    internal static object? RunAction(ActionCall call, Func<object?> core)
    {
        var plugs = _actions;
        if (plugs.Length == 0) return core();

        Func<object?> chain = core;
        for (int i = plugs.Length - 1; i >= 0; i--)
        {
            var plug = plugs[i];
            var next = chain;
            chain = () => plug.Invoke(call, next);
        }

        return chain();
    }

    internal static string? Get(string table, string key, Func<string, string, string?> core)
    {
        var plugs = _databases;
        if (plugs.Length == 0) return core(table, key);

        Func<string, string, string?> chain = core;
        for (int i = plugs.Length - 1; i >= 0; i--)
        {
            var plug = plugs[i];
            var next = chain;
            chain = (t, k) => plug.Get(t, k, next);
        }

        return chain(table, key);
    }

    internal static string? All(string table, Func<string, string?> core)
    {
        var plugs = _databases;
        if (plugs.Length == 0) return core(table);

        Func<string, string?> chain = core;
        for (int i = plugs.Length - 1; i >= 0; i--)
        {
            var plug = plugs[i];
            var next = chain;
            chain = t => plug.All(t, next);
        }

        return chain(table);
    }

    internal static bool Put(string table, string key, string json, Func<string, string, string, bool> core)
    {
        var plugs = _databases;
        if (plugs.Length == 0) return core(table, key, json);

        Func<string, string, string, bool> chain = core;
        for (int i = plugs.Length - 1; i >= 0; i--)
        {
            var plug = plugs[i];
            var next = chain;
            chain = (t, k, j) => plug.Put(t, k, j, next);
        }

        return chain(table, key, json);
    }

    internal static bool Delete(string table, string key, Func<string, string, bool> core)
    {
        var plugs = _databases;
        if (plugs.Length == 0) return core(table, key);

        Func<string, string, bool> chain = core;
        for (int i = plugs.Length - 1; i >= 0; i--)
        {
            var plug = plugs[i];
            var next = chain;
            chain = (t, k) => plug.Delete(t, k, next);
        }

        return chain(table, key);
    }
}
