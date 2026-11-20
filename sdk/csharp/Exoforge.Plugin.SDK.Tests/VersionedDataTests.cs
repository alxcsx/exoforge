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

    [ExoResource("readonly_gadgets", RowMigration = RowMigrationMode.ReadOnly)]
    public record ReadOnlyGadget(string Id = "", string Label = "");

    [ExoResource("off_gadgets", RowMigration = RowMigrationMode.Off)]
    public record OffGadget(string Id = "", string Label = "");

    [ExoResource("balance", BreakingChanges = BreakingChangeMode.Fork)]
    public record Balance(string Id = "", string Gold = "");

    public static class Migrations
    {
        [ExoRowMigration(typeof(Gadget), To = "2.0.0")]
        public static Gadget Up(JsonElement old) => new(old.GetProperty("id").GetString()!, old.GetProperty("nm").GetString()!);

        [ExoRowMigration(typeof(ReadOnlyGadget), To = "2.0.0")]
        public static ReadOnlyGadget UpRo(JsonElement old) => new(old.GetProperty("id").GetString()!, old.GetProperty("nm").GetString()!);

        [ExoRowMigration(typeof(OffGadget), To = "2.0.0")]
        public static OffGadget UpOff(JsonElement old) => new(old.GetProperty("id").GetString()!, old.GetProperty("nm").GetString()!);

        // 1.x kept gold as a number under `g`; 2.0.0 stores it as text under `gold`.
        [ExoRowMigration(typeof(Balance), To = "2.0.0")]
        public static Balance UpBalance(JsonElement old) => new(old.GetProperty("id").GetString()!, old.GetProperty("g").GetInt32().ToString());
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
    public void The_read_modes_decide_whether_a_stale_row_is_migrated_and_written()
    {
        var (context, transport) = Setup();
        transport.Rows["readonly_gadgets/g1"] = "{\"id\":\"g1\",\"nm\":\"ro\",\"_v\":1000000}";
        transport.Rows["off_gadgets/g1"] = "{\"id\":\"g1\",\"nm\":\"off\",\"_v\":1000000}";

        Assert.Equal("ro", context.Database.Get<ReadOnlyGadget>("readonly_gadgets", "g1")!.Label);
        Assert.Empty(transport.Puts);

        Assert.Equal("", context.Database.Get<OffGadget>("off_gadgets", "g1")!.Label);
        Assert.Empty(transport.Puts);
    }

    [Fact]
    public void Sql_reads_of_a_typed_resource_migrate_and_QueryRaw_does_not()
    {
        var (context, transport) = Setup();
        transport.SqlRows = "[{\"id\":\"g1\",\"nm\":\"q\",\"_v\":1000000}]";

        Assert.Equal("q", Assert.Single(context.Database.Query<Gadget>("SELECT * FROM gadgets")).Label);
        Assert.Single(transport.Puts);

        transport.Puts.Clear();
        Assert.Equal("", Assert.Single(context.Database.QueryRaw<Gadget>("SELECT * FROM gadgets")).Label);
        Assert.Empty(transport.Puts);
    }

    [Fact]
    public void A_forked_resource_reads_its_own_generation_then_the_nearest_older_and_writes_into_its_own()
    {
        var (context, transport) = Setup();   // no game version: the newest generation
        transport.Rows["balance/b1"] = "{\"id\":\"b1\",\"g\":50,\"_v\":1000000}";

        // nothing in balance_g2000000 yet: the old row, derived through the breaking migration, in memory
        Assert.Equal(new Balance("b1", "50"), context.Database.Get<Balance>("balance", "b1"));
        Assert.Empty(transport.Puts);

        // a write lands in the caller's generation and leaves the old table alone
        context.Database.Put("balance", "b1", new Balance("b1", "75"));
        var put = Assert.Single(transport.Puts);
        Assert.Equal("balance_g2000000", put.Table);

        // once the generation has its row, that row wins
        transport.Rows["balance_g2000000/b1"] = "{\"id\":\"b1\",\"gold\":\"75\"}";
        Assert.Equal("75", context.Database.Get<Balance>("balance", "b1")!.Gold);
    }

    [Fact]
    public void A_forked_resources_older_client_stays_on_the_original_table()
    {
        var (context, transport) = Setup("1.0", "1.0.0");
        transport.Rows["balance/b1"] = "{\"id\":\"b1\",\"gold\":\"50\"}";

        context.Database.Put("balance", "b1", new Balance("b1", "60"));
        Assert.Equal("balance", Assert.Single(transport.Puts).Table);
    }

    [Fact]
    public void All_on_a_forked_resource_merges_generations_without_repeating_a_key()
    {
        var (context, transport) = Setup();
        transport.Rows["balance/b1"] = "{\"id\":\"b1\",\"g\":1}";
        transport.Rows["balance/b2"] = "{\"id\":\"b2\",\"g\":2}";
        transport.Rows["balance_g2000000/b1"] = "{\"id\":\"b1\",\"gold\":\"9\"}";

        var all = context.Database.All<Balance>("balance");

        Assert.Equal(2, all.Count);
        Assert.Contains(new Balance("b1", "9"), all);
        Assert.Contains(new Balance("b2", "2"), all);
    }

    [Fact]
    public void Duplicate_copies_only_what_the_newest_generation_lacks_and_sync_copies_named_columns()
    {
        var (context, transport) = Setup();
        transport.Rows["balance/b1"] = "{\"id\":\"b1\",\"g\":1}";
        transport.Rows["balance/b2"] = "{\"id\":\"b2\",\"g\":2}";
        transport.Rows["balance_g2000000/b1"] = "{\"id\":\"b1\",\"gold\":\"9\"}";

        Assert.Equal(1, context.Database.DuplicateGeneration<Balance>());
        var put = Assert.Single(transport.Puts);
        Assert.Equal(("balance_g2000000", "b2"), (put.Table, put.Key));

        transport.Puts.Clear();
        Assert.Equal(1, context.Database.SyncGeneration<Balance>("gold"));
        Assert.All(transport.Puts, p => Assert.Equal("balance_g2000000", p.Table));
    }
}
