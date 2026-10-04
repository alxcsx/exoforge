using System;
using System.Reflection;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("sample_wasm", Version = "1.0.0")]
[ExoResource("counters", PrimaryKey = "counter_id", DrawerTabs = new[] { "overview", "attributes", "events" })]
public class SampleWasmPlugin : PluginBehaviour
{
    public override string Id => "sample_wasm";
    public override string Version => "1.0.0";

    [Inject("database")]
    public IDatabase? CustomDb { get; set; }

    [ExoAction("ping", Mode = ActionMode.Sync)]
    public int Ping() => 42;

    [ExoAction("increment", Mode = ActionMode.Sync, Scope = "global")]
    [ExoEvent("value_changed", Topic = "sample:events")]
    public int Increment(int counterId, int amount)
    {
        int newValue = amount > 0 ? amount : 1;
        HostBridge.EmitEvent("sample:events", "value_changed", new
        {
            counter_id = counterId,
            new_value = newValue
        });
        return newValue;
    }
}

public class CounterEntity
{
    [ExoColumn("counter_id", DataType = "integer", Sortable = true)]
    public int CounterId { get; set; }

    [ExoColumn("value", DataType = "integer", Sortable = true)]
    public int Value { get; set; }

    [ExoColumn("status", DataType = "string", Badge = true)]
    public string Status { get; set; } = "active";
}

[Entity("sample_guild", Persist = PersistenceMode.Snapshot, TimeoutMs = 60000)]
public class SampleGuildEntity : Entity
{
    public string Name { get; set; } = "ExoGuild";
    public int Level { get; set; } = 1;
}

[ExoResource("players", PrimaryKey = nameof(PlayerId), DrawerTabs = new[] { "overview", "inventory" })]
public record PlayerRecord(
    [property: PrimaryKey]
    int PlayerId,
    [property: ExoColumn(Label = "Display Name", Filterable = true)]
    string Name,
    [property: ExoColumn(Sortable = true)]
    int Level = 1,
    [property: ExoColumn(Badge = true)]
    string Status = "active"
);

public class PluginSdkTests
{
    [Fact]
    public void PluginAttributes_ExposeCorrectMetadata()
    {
        var type = typeof(SampleWasmPlugin);

        var serviceAttr = type.GetCustomAttribute<ExoServiceAttribute>();
        Assert.NotNull(serviceAttr);
        Assert.Equal("sample_wasm", serviceAttr.Name);
        Assert.Equal("1.0.0", serviceAttr.Version);

        var resourceAttr = type.GetCustomAttribute<ExoResourceAttribute>();
        Assert.NotNull(resourceAttr);
        Assert.Equal("counters", resourceAttr.Name);
        Assert.Equal("counter_id", resourceAttr.PrimaryKey);
        Assert.Contains("overview", resourceAttr.DrawerTabs!);

        var pingMethod = type.GetMethod(nameof(SampleWasmPlugin.Ping));
        Assert.NotNull(pingMethod);
        var pingAction = pingMethod.GetCustomAttribute<ExoActionAttribute>();
        Assert.NotNull(pingAction);
        Assert.Equal("ping", pingAction.Name);
        Assert.Equal(ActionMode.Sync, pingAction.Mode);

        var incrementMethod = type.GetMethod(nameof(SampleWasmPlugin.Increment));
        Assert.NotNull(incrementMethod);
        var incrementAction = incrementMethod.GetCustomAttribute<ExoActionAttribute>();
        Assert.NotNull(incrementAction);
        Assert.Equal("increment", incrementAction.Name);

        var eventAttr = incrementMethod.GetCustomAttribute<ExoEventAttribute>();
        Assert.NotNull(eventAttr);
        Assert.Equal("value_changed", eventAttr.Name);
        Assert.Equal("sample:events", eventAttr.Topic);
    }

    [Fact]
    public void ColumnAttributes_ExposeColumnMetadata()
    {
        var prop = typeof(CounterEntity).GetProperty(nameof(CounterEntity.CounterId));
        Assert.NotNull(prop);

        var col = prop.GetCustomAttribute<ExoColumnAttribute>();
        Assert.NotNull(col);
        Assert.Equal("counter_id", col.Name);
        Assert.Equal("integer", col.DataType);
        Assert.True(col.Sortable);
    }

    [Fact]
    public void PluginBehaviour_DefaultsAndExecution()
    {
        var plugin = new SampleWasmPlugin();
        Assert.Equal("sample_wasm", plugin.Id);
        Assert.Equal("1.0.0", plugin.Version);
        Assert.Equal(42, plugin.Ping());
        Assert.Equal(25, plugin.Increment(1, 25));
    }

    [Fact]
    public async Task PluginBehaviour_DependencyInjectionWiring()
    {
        var plugin = new SampleWasmPlugin();
        Assert.Null(plugin.CustomDb);

        var context = new HostPluginContext("test_plugin");
        await plugin.OnInitAsync(context);

        Assert.NotNull(plugin.CustomDb);
        Assert.Same(context.Database, plugin.CustomDb);
    }

    [Fact]
    public void HostBridge_SafeExecutionOutsideWasi()
    {
        // When executed in native test runner without wasi host, catches and handles gracefully
        bool eventResult = HostBridge.EmitEvent("topic", "event", new { a = 1 });
        Assert.False(eventResult); // graceful fallback

        HostBridge.LogInfo("Test info log");
        HostBridge.LogWarning("Test warning log");

        Assert.True(HostBridge.ClockNow() > 0);
        Assert.Null(HostBridge.DbGet("test", "key"));
        Assert.False(HostBridge.DbPut("test", "key", new { val = 1 }));
        Assert.False(HostBridge.DbDelete("test", "key"));
        Assert.Null(HostBridge.GetState("state_key"));
        Assert.False(HostBridge.SetState("state_key", "val"));
    }

    [Fact]
    public void Entity_MetadataAndStateLifecycle()
    {
        var type = typeof(SampleGuildEntity);
        var attr = type.GetCustomAttribute<EntityAttribute>();
        Assert.NotNull(attr);
        Assert.Equal("sample_guild", attr.Name);
        Assert.Equal(PersistenceMode.Snapshot, attr.Persist);
        Assert.Equal(60000, attr.TimeoutMs);

        var context = new HostPluginContext("guilds");
        var guild = new SampleGuildEntity
        {
            Id = "g_test",
            Context = context
        };

        Assert.Equal("g_test", guild.Id);
        Assert.NotNull(guild.Db);
        Assert.NotNull(context.Entities);

        // Safe fallback outside wasi host
        guild.Save();
        guild.SaveNow();
        guild.Emit("guild_created", new { id = guild.Id });
    }

    [Fact]
    public void ResourceRecord_DeclarationAndPropertyInspection()
    {
        var type = typeof(PlayerRecord);
        var resAttr = type.GetCustomAttribute<ExoResourceAttribute>();
        Assert.NotNull(resAttr);
        Assert.Equal("players", resAttr.Name);
        Assert.Equal(nameof(PlayerRecord.PlayerId), resAttr.PrimaryKey);
        Assert.Equal(new[] { "overview", "inventory" }, resAttr.DrawerTabs);

        var player = new PlayerRecord(101, "Hero", 5, "online");
        Assert.Equal(101, player.PlayerId);
        Assert.Equal("Hero", player.Name);
        Assert.Equal(5, player.Level);
        Assert.Equal("online", player.Status);
    }

    [Fact]
    public void Database_Query_MapsRowsToTypedRecords()
    {
        var transport = new FakeTransport
        {
            Response = "{\"rows\":[{\"player_id\":\"p1\",\"score\":9},{\"player_id\":\"p2\",\"score\":4}],\"num_rows\":2}"
        };

        HostBridge.UseTransport(transport);
        try
        {
            var db = new HostDatabase("snake_leaderboard");
            var rows = db.Query<TypedScoreRow>(
                "SELECT player_id, score FROM snake_scores ORDER BY score DESC LIMIT $1", 10);

            Assert.Equal("database", transport.Service);
            Assert.Equal("execute", transport.Action);
            Assert.Contains("\"plugin\":\"snake_leaderboard\"", transport.Payload);
            Assert.Contains("\"args\":[10]", transport.Payload);
            Assert.Contains("SELECT player_id", transport.Payload);

            Assert.Equal(2, rows.Count);
            Assert.Equal("p1", rows[0].PlayerId);
            Assert.Equal(9, rows[0].Score);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Database_Execute_ReturnsAffectedRows()
    {
        var transport = new FakeTransport { Response = "{\"rows\":[],\"num_rows\":3}" };

        HostBridge.UseTransport(transport);
        try
        {
            Assert.Equal(3, new HostDatabase("p").Execute("UPDATE t SET x = $1 WHERE y = $2", 1, "a"));
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Database_Query_ThrowsOnServiceError()
    {
        var transport = new FakeTransport { Response = "{\"error\":\"postgres_error: relation does not exist\"}" };

        HostBridge.UseTransport(transport);
        try
        {
            var error = Assert.Throws<InvalidOperationException>(() => new HostDatabase("p").Query<TypedScoreRow>("SELECT 1"));
            Assert.Contains("postgres_error", error.Message);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void ExoAction_DefaultsToInferredNameModeAndTransport()
    {
        var attr = new ExoActionAttribute();
        Assert.Null(attr.Name);
        Assert.Equal(ActionMode.Auto, attr.Mode);
        Assert.Equal(ActionTransport.Auto, attr.Transport);
    }

    [Fact]
    public void ExoNaming_UsesSnakeCase()
    {
        Assert.Equal("submit_score", ExoNaming.ToSnakeCase("SubmitScore"));
        Assert.Equal("get_leaderboard", ExoNaming.ToSnakeCase("GetLeaderboard"));
        Assert.Equal("snake_length", ExoNaming.ToSnakeCase("snakeLength"));
    }

    /// <summary>Captures the action call and returns a canned reply, so the SQL runner is testable off-host.</summary>
    private sealed class FakeTransport : IPluginTransport
    {
        public string? Service { get; private set; }
        public string? Action { get; private set; }
        public string? Payload { get; private set; }
        public string Response { get; set; } = "null";

        public bool EmitEvent(string topic, string evt, string payloadJson) => false;

        public string? CallAction(string service, string action, string payloadJson)
        {
            Service = service;
            Action = action;
            Payload = payloadJson;
            return Response;
        }

        public void Log(int level, string message) { }
        public string? DbGet(string table, string key) => null;
        public string? DbAll(string table) => null;
        public bool DbPut(string table, string key, string valueJson) => false;
        public bool DbDelete(string table, string key) => false;
        public string? GetState(string key) => null;
        public bool SetState(string key, string valueJson) => false;
        public long ClockNow() => 0;
    }
}

