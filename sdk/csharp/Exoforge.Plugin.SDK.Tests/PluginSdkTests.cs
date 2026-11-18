using System;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("sample_plugin", Version = "1.0.0")]
[ExoResource("counters", PrimaryKey = "counter_id", DrawerTabs = new[] { "overview", "attributes", "events" })]
public class SamplePluginPlugin
{
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

/// <summary>What a wallet call answers; a failed debit must not come back as an empty one.</summary>
public class WalletBalance
{
    public long Coins { get; set; }
}

[ExoResource("players", PrimaryKey = nameof(PlayerId), DrawerTabs = new[] { "overview", "inventory" })]
public record PlayerRecord(
    [property: ExoColumn(PrimaryKey = true)]
    int PlayerId,
    [property: ExoColumn(Label = "Display Name", Filterable = true)]
    string Name,
    [property: ExoColumn(Sortable = true)]
    int Level = 1,
    [property: ExoColumn(Badge = true)]
    string Status = "active"
);

/// <summary>Stand-in for a generated service client (same (IActionDispatcher) constructor shape).</summary>
public class InjectedServiceClient
{
    public InjectedServiceClient(IActionDispatcher dispatcher) => Dispatcher = dispatcher;

    public IActionDispatcher Dispatcher { get; }
}

/// <summary>A stored settings record: SQLite holds its booleans as 1/0, or as text in older rows.</summary>
public record BooleanSettingsRow
{
    public string PlayerId { get; init; } = "";
    public bool ColorBlind { get; init; }
    public bool? Muted { get; init; }
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(BooleanSettingsRow))]
internal partial class BooleanSettingsRowContext : JsonSerializerContext
{
}

public class PluginSdkTests
{
    [Fact]
    public void PluginAttributes_ExposeCorrectMetadata()
    {
        var type = typeof(SamplePluginPlugin);

        var serviceAttr = type.GetCustomAttribute<ExoServiceAttribute>();
        Assert.NotNull(serviceAttr);
        Assert.Equal("sample_plugin", serviceAttr.Name);
        Assert.Equal("1.0.0", serviceAttr.Version);

        var resourceAttr = type.GetCustomAttribute<ExoResourceAttribute>();
        Assert.NotNull(resourceAttr);
        Assert.Equal("counters", resourceAttr.Name);
        Assert.Equal("counter_id", resourceAttr.PrimaryKey);
        Assert.Contains("overview", resourceAttr.DrawerTabs!);

        var pingMethod = type.GetMethod(nameof(SamplePluginPlugin.Ping));
        Assert.NotNull(pingMethod);
        var pingAction = pingMethod.GetCustomAttribute<ExoActionAttribute>();
        Assert.NotNull(pingAction);
        Assert.Equal("ping", pingAction.Name);
        Assert.Equal(ActionMode.Sync, pingAction.Mode);

        var incrementMethod = type.GetMethod(nameof(SamplePluginPlugin.Increment));
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
        Assert.False(resAttr.AllowPlayerRead);

        var publicResource = new ExoResourceAttribute("public_players") { AllowPlayerRead = true };
        Assert.True(publicResource.AllowPlayerRead);

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
    public void Database_Query_DecodesSqliteBooleanSpellings()
    {
        var transport = new FakeTransport
        {
            Response = """
            {"rows":[
                {"player_id":"p1","color_blind":1,"muted":0},
                {"player_id":"p2","color_blind":"true","muted":"false"},
                {"player_id":"p3","color_blind":0,"muted":null}
            ],"num_rows":3}
            """
        };

        HostBridge.UseTransport(transport);
        try
        {
            var rows = new HostDatabase("player_settings")
                .Query<BooleanSettingsRow>("SELECT * FROM player_settings");

            Assert.Equal(3, rows.Count);
            Assert.True(rows[0].ColorBlind);
            Assert.False(rows[0].Muted);
            Assert.True(rows[1].ColorBlind);
            Assert.False(rows[1].Muted);
            Assert.False(rows[2].ColorBlind);
            Assert.Null(rows[2].Muted);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Database_Query_DecodesBooleans_WithSourceGeneratedContext()
    {
        PluginJson.UseContext(new BooleanSettingsRowContext());

        var transport = new FakeTransport
        {
            Response = "{\"rows\":[{\"player_id\":\"p1\",\"color_blind\":1,\"muted\":\"false\"}]}"
        };

        HostBridge.UseTransport(transport);
        try
        {
            var rows = new HostDatabase("player_settings")
                .Query<BooleanSettingsRow>("SELECT * FROM player_settings");

            Assert.Single(rows);
            Assert.True(rows[0].ColorBlind);
            Assert.False(rows[0].Muted);
        }
        finally
        {
            HostBridge.UseTransport(null);
            PluginJson.UseContext(null);
        }
    }

    [Fact]
    public void Database_GetAndAll_DecodeSqliteBooleanSpellings()
    {
        var transport = new FakeTransport
        {
            DbGetResponse = "{\"player_id\":\"p1\",\"color_blind\":1,\"muted\":\"true\"}",
            DbAllResponse = "[{\"player_id\":\"p2\",\"color_blind\":\"false\",\"muted\":0}]"
        };

        HostBridge.UseTransport(transport);
        try
        {
            var db = new HostDatabase("player_settings");

            var one = db.Get<BooleanSettingsRow>("player_settings", "p1");
            Assert.NotNull(one);
            Assert.True(one!.ColorBlind);
            Assert.True(one.Muted);

            var all = db.All<BooleanSettingsRow>("player_settings");
            Assert.Single(all);
            Assert.False(all[0].ColorBlind);
            Assert.False(all[0].Muted);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void ActionPayloads_StillRequireJsonBooleans()
    {
        Assert.Throws<JsonException>(() =>
            PluginJson.Deserialize<BooleanSettingsRow>("{\"player_id\":\"p1\",\"color_blind\":1}"));
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
    public void ExoColumn_Role_And_ReferencesType_Work()
    {
        var col = new ExoColumnAttribute
        {
            Role = ExoRole.PlayerId,
            ReferencesType = typeof(PlayerRecord)
        };

        Assert.Equal("user_id", col.Role);
        Assert.Equal(typeof(PlayerRecord), col.ReferencesType);
    }

    [Fact]
    public void ExoNaming_UsesSnakeCase()
    {
        Assert.Equal("submit_score", ExoNaming.ToSnakeCase("SubmitScore"));
        Assert.Equal("get_leaderboard", ExoNaming.ToSnakeCase("GetLeaderboard"));
        Assert.Equal("snake_length", ExoNaming.ToSnakeCase("snakeLength"));
        Assert.Equal("id", ExoNaming.ToSnakeCase("ID"));
        Assert.Equal("player_id", ExoNaming.ToSnakeCase("PlayerID"));
        Assert.Equal("http_code", ExoNaming.ToSnakeCase("HTTPCode"));
    }

    [Fact]
    public void PluginServiceRegistry_ResolvesRegisteredServiceClients()
    {
        PluginServiceRegistry.Register(d => new InjectedServiceClient(d));

        var context = new HostPluginContext("svc_plugin");
        bool created = PluginServiceRegistry.TryCreate(typeof(InjectedServiceClient), context.Actions, out var client);

        Assert.True(created);
        Assert.NotNull(client);
        Assert.Same(context.Actions, ((InjectedServiceClient)client!).Dispatcher);
    }

    /// <summary>
    /// A failed extension-to-extension call must not look like an empty answer: it throws with the
    /// code the callee threw, so a caller can distinguish "no funds" from "no balance".
    /// </summary>
    [Fact]
    public void A_failed_extension_call_throws_the_callee_code_and_message()
    {
        var transport = new FakeTransport
        {
            Response = "{\"error\":{\"code\":\"insufficient_funds\",\"message\":\"You need 10 coins\"}}"
        };

        HostBridge.UseTransport(transport);

        try
        {
            var typed = Assert.Throws<ExoActionException>(() =>
                HostBridge.CallAction<object>("wallet", "debit", new { amount = 10 }));
            Assert.Equal("insufficient_funds", typed.Code);
            Assert.Equal("You need 10 coins", typed.Message);

            var plain = Assert.Throws<ExoActionException>(() =>
                HostBridge.CallAction("wallet", "debit", new { amount = 10 }));
            Assert.Equal("insufficient_funds", plain.Code);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void A_successful_extension_call_still_returns_its_result()
    {
        var transport = new FakeTransport { Response = "{\"coins\":90}" };
        HostBridge.UseTransport(transport);

        try
        {
            var balance = HostBridge.CallAction<WalletBalance>("wallet", "get_balance", new { });

            Assert.NotNull(balance);
            Assert.Equal(90, balance!.Coins);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
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
        public string? DbGetResponse { get; set; }
        public string? DbAllResponse { get; set; }
        public string? DbGet(string table, string key) => DbGetResponse;
        public string? DbAll(string table) => DbAllResponse;
        public bool DbPut(string table, string key, string valueJson) => false;
        public bool DbDelete(string table, string key) => false;
        public long ClockNow() => 0;
    }
}

