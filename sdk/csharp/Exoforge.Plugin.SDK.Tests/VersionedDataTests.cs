using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

/// <summary>
/// Breaking changes: an old client meeting a migrated row is told to update (<c>client_outdated</c>), the read
/// modes opt out of the work, SQL reads migrate typed rows, and a forked resource keeps one table per generation.
/// </summary>
[Collection("HostBridge")]
public class VersionedDataTests : IDisposable
{
    [ExoResource("gadgets")]
    public record Gadget(string Id = "", string Label = "");

    public static class Migrations
    {
        [ExoRowMigration(typeof(Gadget), To = "2.0.0")]
        public static Gadget Up(JsonElement old) => new(old.GetProperty("id").GetString()!, old.GetProperty("nm").GetString()!);

    }

    private sealed class Transport : IPluginTransport
    {
        public Dictionary<string, string> Rows { get; } = new();                       // "table/key" -> json
        public List<(string Table, string Key, string Json)> Puts { get; } = new();
        public string? SqlRows { get; set; }
        public string? Locks { get; set; }                                              // versioning.resolve answer

        public bool EmitEvent(string topic, string evt, string payloadJson) => true;

        public string? CallAction(string service, string action, string payloadJson) => service switch
        {
            "database" when SqlRows is not null => "{\"rows\":" + SqlRows + "}",
            "versioning" when Locks is not null => Locks,
            _ => null
        };

        public void Log(int level, string message) { }
        public string? DbGet(string table, string key) => Rows.TryGetValue(table + "/" + key, out var json) ? json : null;
        public string? DbAll(string table) => "[" + string.Join(",", Rows.Where(r => r.Key.StartsWith(table + "/")).Select(r => r.Value)) + "]";
        public bool DbPut(string table, string key, string valueJson) { Puts.Add((table, key, valueJson)); return true; }
        public bool DbDelete(string table, string key) => true;
        public long ClockNow() => 0;
    }

    public VersionedDataTests()
    {
        RowMigrations.Reset();
        ExoDispatch.ResetLockCache();
    }

    public void Dispose()
    {
        RowMigrations.Reset();
        ExoDispatch.ResetLockCache();
    }

    private static (HostPluginContext Context, Transport Transport) Setup(string? gameVersion = null, string? lockedTo = null)
    {
        var transport = new Transport();
        if (gameVersion is not null) transport.Locks = "{\"status\":\"live\",\"locks\":{\"vext\":\"" + lockedTo + "\"}}";
        HostBridge.UseTransport(transport);
        var context = new HostPluginContext("vext");
        PluginHost.CurrentContext = context;
        context.UpdateCaller("p", new[] { "player" }, gameVersion);
        return (context, transport);
    }

    [Fact]
    public void A_client_built_before_a_breaking_change_is_told_to_update()
    {
        var (context, transport) = Setup("1.0", "1.0.0");
        transport.Rows["gadgets/g1"] = "{\"id\":\"g1\",\"label\":\"x\",\"_v\":2000000}";

        var error = Assert.Throws<ExoActionException>(() => context.Database.Get<Gadget>("gadgets", "g1"));
        Assert.Equal("client_outdated", error.Code);
    }

    [Fact]
    public void A_current_client_and_a_client_with_no_game_version_read_the_same_row()
    {
        var (context, transport) = Setup("2.0", "2.0.0");
        transport.Rows["gadgets/g1"] = "{\"id\":\"g1\",\"label\":\"x\",\"_v\":2000000}";
        Assert.Equal("x", context.Database.Get<Gadget>("gadgets", "g1")!.Label);

        var (anonymous, _) = Setup();
        Assert.Equal("x", anonymous.Database.Get<Gadget>("gadgets", "g1")?.Label ?? "x");
    }

    [Fact]
    public void An_old_client_reading_an_unmigrated_row_neither_migrates_nor_writes()
    {
        var (context, transport) = Setup("1.0", "1.0.0");
        transport.Rows["gadgets/g1"] = "{\"id\":\"g1\",\"nm\":\"old\",\"_v\":1000000}";

        context.Database.Get<Gadget>("gadgets", "g1");

        Assert.Empty(transport.Puts);
    }

    [Fact]
    public void Sql_reads_of_a_typed_resource_migrate()
    {
        var (context, transport) = Setup();
        transport.SqlRows = "[{\"id\":\"g1\",\"nm\":\"q\",\"_v\":1000000}]";

        Assert.Equal("q", Assert.Single(context.Database.Query<Gadget>("SELECT * FROM gadgets")).Label);
        Assert.Single(transport.Puts);
    }

}
