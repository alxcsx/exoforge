using System.Reflection;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("combat", Version = "1.0.0")]
[ExoResource("combatants", PrimaryKey = "entity_id", DrawerTabs = new[] { "overview", "attributes", "events" })]
public class SampleCombatPlugin : PluginBehaviour
{
    public override string Id => "sample_combat";
    public override string Version => "1.0.0";

    [Inject("database")]
    public IDatabase? CustomDb { get; set; }

    [ExoAction("ping", Mode = ActionMode.Sync)]
    public int Ping() => 42;

    [ExoAction("attack", Mode = ActionMode.Sync, Scope = "global")]
    [ExoEvent("player_damaged", Topic = "combat:events")]
    public int Attack(int attackerId, int targetId, int damage)
    {
        int applied = damage > 0 ? damage : 1;
        HostBridge.EmitEvent("combat:events", "player_damaged", new
        {
            attacker_id = attackerId,
            target_id = targetId,
            damage = applied
        });
        return applied;
    }
}

public class CombatantEntity
{
    [ExoColumn("entity_id", DataType = "integer", Sortable = true)]
    public int EntityId { get; set; }

    [ExoColumn("health", DataType = "integer", Sortable = true)]
    public int Health { get; set; }

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
        var type = typeof(SampleCombatPlugin);

        var serviceAttr = type.GetCustomAttribute<ExoServiceAttribute>();
        Assert.NotNull(serviceAttr);
        Assert.Equal("combat", serviceAttr.Name);
        Assert.Equal("1.0.0", serviceAttr.Version);

        var resourceAttr = type.GetCustomAttribute<ExoResourceAttribute>();
        Assert.NotNull(resourceAttr);
        Assert.Equal("combatants", resourceAttr.Name);
        Assert.Equal("entity_id", resourceAttr.PrimaryKey);
        Assert.Contains("overview", resourceAttr.DrawerTabs!);

        var pingMethod = type.GetMethod(nameof(SampleCombatPlugin.Ping));
        Assert.NotNull(pingMethod);
        var pingAction = pingMethod.GetCustomAttribute<ExoActionAttribute>();
        Assert.NotNull(pingAction);
        Assert.Equal("ping", pingAction.Name);
        Assert.Equal(ActionMode.Sync, pingAction.Mode);

        var attackMethod = type.GetMethod(nameof(SampleCombatPlugin.Attack));
        Assert.NotNull(attackMethod);
        var attackAction = attackMethod.GetCustomAttribute<ExoActionAttribute>();
        Assert.NotNull(attackAction);
        Assert.Equal("attack", attackAction.Name);

        var eventAttr = attackMethod.GetCustomAttribute<ExoEventAttribute>();
        Assert.NotNull(eventAttr);
        Assert.Equal("player_damaged", eventAttr.Name);
        Assert.Equal("combat:events", eventAttr.Topic);
    }

    [Fact]
    public void ColumnAttributes_ExposeColumnMetadata()
    {
        var prop = typeof(CombatantEntity).GetProperty(nameof(CombatantEntity.EntityId));
        Assert.NotNull(prop);

        var col = prop.GetCustomAttribute<ExoColumnAttribute>();
        Assert.NotNull(col);
        Assert.Equal("entity_id", col.Name);
        Assert.Equal("integer", col.DataType);
        Assert.True(col.Sortable);
    }

    [Fact]
    public void PluginBehaviour_DefaultsAndExecution()
    {
        var plugin = new SampleCombatPlugin();
        Assert.Equal("sample_combat", plugin.Id);
        Assert.Equal("1.0.0", plugin.Version);
        Assert.Equal(42, plugin.Ping());
        Assert.Equal(25, plugin.Attack(1, 2, 25));
    }

    [Fact]
    public async Task PluginBehaviour_DependencyInjectionWiring()
    {
        var plugin = new SampleCombatPlugin();
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
}

