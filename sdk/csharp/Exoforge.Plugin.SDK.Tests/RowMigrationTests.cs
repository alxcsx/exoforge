using System;
using System.Collections.Generic;
using System.Text.Json;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

/// <summary>
/// A row written under an older extension version is brought up to date the first time it is read, and
/// written back once, guarded by the stamp it was read at.
/// </summary>
[Collection("HostBridge")]
public class RowMigrationTests : IDisposable
{
    [ExoResource("pets")]
    public record Pet(string Id = "", string DisplayName = "", int Level = 1);

    public static class PetMigrations
    {
        // 1.x stored `nm`; 2.0.0 calls it display_name.
        [ExoRowMigration(typeof(Pet), To = "2.0.0")]
        public static Pet ToV2(JsonElement old) =>
            new(old.GetProperty("id").GetString()!, old.GetProperty("nm").GetString()!, old.TryGetProperty("level", out var l) ? l.GetInt32() : 1);

        // 2.1.0 starts everyone at level 5 who was below it.
        [ExoRowMigration(typeof(Pet), To = "2.1.0")]
        public static Pet ToV21(JsonElement row)
        {
            int level = row.GetProperty("level").GetInt32();
            return new(row.GetProperty("id").GetString()!, row.GetProperty("display_name").GetString()!, Math.Max(level, 5));
        }
    }

    private sealed class Transport : IPluginTransport
    {
        public string? Row { get; set; }
        public List<(string Key, string Json)> Puts { get; } = new();

        public bool EmitEvent(string topic, string evt, string payloadJson) => true;
        public string? CallAction(string service, string action, string payloadJson) => null;
        public void Log(int level, string message) { }
        public string? DbGet(string table, string key) => Row;
        public string? DbAll(string table) => Row is null ? "[]" : $"[{Row}]";
        public bool DbPut(string table, string key, string valueJson) { Puts.Add((key, valueJson)); return true; }
        public bool DbDelete(string table, string key) => true;
        public long ClockNow() => 0;
    }

    public RowMigrationTests() => RowMigrations.Reset();

    public void Dispose() => RowMigrations.Reset();

    private static (HostPluginContext Context, Transport Transport) Setup(string? row)
    {
        var transport = new Transport { Row = row };
        HostBridge.UseTransport(transport);
        return (new HostPluginContext("pets_ext"), transport);
    }

    [Fact]
    public void An_old_row_is_migrated_through_every_pending_step_and_written_back_once()
    {
        var (context, transport) = Setup("{\"id\":\"p1\",\"nm\":\"Rex\",\"level\":2,\"_v\":1000000}");

        var pet = context.Database.Get<Pet>("pets", "p1");

        Assert.Equal(new Pet("p1", "Rex", 5), pet);
        var put = Assert.Single(transport.Puts);
        Assert.Equal("p1", put.Key);
        using var written = JsonDocument.Parse(put.Json);
        Assert.Equal(1_000_000, written.RootElement.GetProperty("_if_v").GetInt64());
        Assert.Equal("Rex", written.RootElement.GetProperty("display_name").GetString());
    }

    [Fact]
    public void Only_the_steps_after_the_stored_stamp_run()
    {
        // already at 2.0.0: only 2.1.0 is pending, so `nm` (gone from this row) is never read
        var (context, transport) = Setup("{\"id\":\"p1\",\"display_name\":\"Rex\",\"level\":2,\"_v\":2000000}");

        var pet = context.Database.Get<Pet>("pets", "p1");

        Assert.Equal(new Pet("p1", "Rex", 5), pet);
        Assert.Single(transport.Puts);
    }

    [Fact]
    public void A_current_row_is_read_as_it_is_and_not_written()
    {
        var (context, transport) = Setup("{\"id\":\"p1\",\"display_name\":\"Rex\",\"level\":9,\"_v\":2001000}");

        Assert.Equal(new Pet("p1", "Rex", 9), context.Database.Get<Pet>("pets", "p1"));
        Assert.Empty(transport.Puts);
    }

    [Fact]
    public void A_row_without_a_stamp_comes_from_a_server_that_does_not_stamp_and_is_left_alone()
    {
        var (context, transport) = Setup("{\"id\":\"p1\",\"display_name\":\"Rex\",\"level\":1}");

        Assert.Equal(new Pet("p1", "Rex", 1), context.Database.Get<Pet>("pets", "p1"));
        Assert.Empty(transport.Puts);
    }

    [Fact]
    public void All_migrates_each_old_row()
    {
        var (context, transport) = Setup("{\"id\":\"p1\",\"nm\":\"Rex\",\"level\":1,\"_v\":0}");

        var pets = context.Database.All<Pet>("pets");

        Assert.Equal(new Pet("p1", "Rex", 5), Assert.Single(pets));
        Assert.Single(transport.Puts);
    }

    [Theory]
    [InlineData("2.1.0", 2_001_000)]
    [InlineData("0.1.0", 1_000)]
    [InlineData("10.20.30", 10_020_030)]
    [InlineData("1.4.0-beta.1", 1_004_000)]
    [InlineData("1.4.0+build5", 1_004_000)]
    [InlineData("nonsense", 0)]
    [InlineData("1.1000.0", 0)]
    [InlineData(null, 0)]
    public void Versions_encode_so_that_order_is_numeric_order(string? version, long expected) =>
        Assert.Equal(expected, ExoVersion.Encode(version));
}
