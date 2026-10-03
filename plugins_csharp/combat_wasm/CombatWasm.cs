using System;
using System.Runtime.InteropServices;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.Combat;

/// <summary>
/// Exoforge Combat WASM Plugin.
/// Implements sandboxed combat gameplay logic: attack calculations and ping.
/// Emits combat events back to Exoforge Kernel via host imports.
/// <summary>
/// Domain resource representing an active combatant in the arena.
/// </summary>
[ExoResource("combatants", PrimaryKey = "entity_id", DrawerTabs = new[] { "overview", "attributes", "events" })]
public record Combatant
{
    [ExoColumn(Label = "Entity ID", Sortable = true, Filterable = true)]
    public int EntityId { get; init; }

    [ExoColumn(Label = "Health Points", Sortable = true)]
    public int Health { get; init; }

    [ExoColumn(Label = "Combat Status", Badge = true)]
    public string Status { get; init; } = "ready";
}

/// <summary>
/// Exoforge Combat WASM Plugin.
/// Implements sandboxed combat gameplay logic: attack calculations and ping.
/// Emits combat events back to Exoforge Kernel via host imports.
/// </summary>
[ExoService("combat", Version = "0.1.0", Resources = new[] { typeof(Combatant) }, Category = "Gameplay", Title = "Combat Sandbox", Icon = "⚔️")]
public static class CombatPlugin
{
    [Inject("database")]
    public static IDatabase? Database { get; set; }

    /// <summary>
    /// Ping action returning status 42 (pong).
    /// </summary>
    [ExoAction("ping", Mode = ActionMode.Sync)]
    [UnmanagedCallersOnly(EntryPoint = "ping")]
    public static int Ping()
    {
        return 42;
    }

    /// <summary>
    /// Executes an attack action against a target entity, calculating damage
    /// and emitting a `player_damaged` event to topic `combat:events`.
    /// </summary>
    [ExoAction("attack", Mode = ActionMode.Sync, Scope = "global")]
    [ExoEvent("player_damaged", Topic = "combat:events")]
    [UnmanagedCallersOnly(EntryPoint = "attack")]
    public static int Attack(int attackerId, int targetId, int damage)
    {
        int appliedDamage = damage > 0 ? damage : 1;

        HostBridge.EmitEvent("combat:events", "player_damaged", new
        {
            attacker_id = attackerId,
            target_id = targetId,
            damage = appliedDamage
        });

        return appliedDamage;
    }

    public static void Main()
    {
    }
}
