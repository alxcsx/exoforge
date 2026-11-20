using System;
using System.Collections.Generic;
using System.Text.Json;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

/// <summary>Plugs are middleware: they wrap the extension's actions and database calls, first registered outermost.</summary>
[Collection("HostBridge")]
public class PlugTests : IDisposable
{
    public PlugTests() => ExoPlugs.Clear();

    public void Dispose() => ExoPlugs.Clear();

    private sealed class Tag(string tag, List<string> log) : IActionPlug
    {
        public object? Invoke(ActionCall call, Func<object?> next)
        {
            log.Add(tag + ">");
            var result = next();
            log.Add("<" + tag);
            return result;
        }
    }

    private sealed class Refuse : IActionPlug
    {
        public object? Invoke(ActionCall call, Func<object?> next) =>
            call.GameVersion == "0.9" ? throw new ExoActionException("upgrade_required", "too old") : next();
    }

    private static ActionCall Call(string? gameVersion = null) =>
        new("ping", default, "p1", new[] { "player" }, gameVersion);

    [Fact]
    public void Action_plugs_wrap_in_registration_order_and_can_change_the_result()
    {
        var log = new List<string>();
        ExoPlugs.Use(new Tag("a", log));
        ExoPlugs.Use(new Tag("b", log));

        var result = ExoPlugs.RunAction(Call(), () => { log.Add("core"); return 42; });

        Assert.Equal(42, result);
        Assert.Equal(new[] { "a>", "b>", "core", "<b", "<a" }, log);
    }

    [Fact]
    public void An_action_plug_can_refuse_a_call_without_running_the_action()
    {
        ExoPlugs.Use(new Refuse());
        bool ran = false;

        var error = Assert.Throws<ExoActionException>(() => ExoPlugs.RunAction(Call("0.9"), () => { ran = true; return 1; }));

        Assert.Equal("upgrade_required", error.Code);
        Assert.False(ran);
        Assert.Equal(1, ExoPlugs.RunAction(Call("1.0"), () => 1));
    }

    private sealed class Prefix : IDatabasePlug
    {
        public string? Get(string table, string key, Func<string, string, string?> next) => next(table, "x-" + key);
        public bool Put(string table, string key, string json, Func<string, string, string, bool> next) => next(table, "x-" + key, json);
    }

    private sealed class Transport : IPluginTransport
    {
        public Dictionary<string, string> Rows { get; } = new();

        public bool EmitEvent(string topic, string evt, string payloadJson) => true;
        public string? CallAction(string service, string action, string payloadJson) => null;
        public void Log(int level, string message) { }
        public string? DbGet(string table, string key) => Rows.TryGetValue(table + "/" + key, out var json) ? json : null;
        public string? DbAll(string table) => "[]";
        public bool DbPut(string table, string key, string valueJson) { Rows[table + "/" + key] = valueJson; return true; }
        public bool DbDelete(string table, string key) => true;
        public long ClockNow() => 0;
    }

    public record Note(string Id = "", string Text = "");

    [Fact]
    public void A_database_plug_sees_and_rewrites_the_calls_the_extension_makes()
    {
        var transport = new Transport();
        HostBridge.UseTransport(transport);
        var db = new HostPluginContext("plugs").Database;
        ExoPlugs.Use(new Prefix());

        db.Put("notes", "n1", new Note("n1", "hello"));

        Assert.True(transport.Rows.ContainsKey("notes/x-n1"));
        Assert.Equal("hello", db.Get<Note>("notes", "n1")!.Text);
    }

    [Fact]
    public void With_no_plugs_the_calls_pass_straight_through()
    {
        var transport = new Transport();
        HostBridge.UseTransport(transport);
        var db = new HostPluginContext("plugs").Database;

        db.Put("notes", "n1", new Note("n1", "hi"));

        Assert.True(transport.Rows.ContainsKey("notes/n1"));
    }
}
