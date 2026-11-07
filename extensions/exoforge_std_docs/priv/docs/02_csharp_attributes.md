# C# Attributes Reference

Comprehensive reference for all core attributes provided by the Exoforge Extension SDK.

---

## [ExoExtension]

Identifies a C# class as a cluster-supervised native headless service.

The `[ExoExtension]` attribute is the root entry point for backend features in Exoforge. Classes marked with this attribute are automatically registered into the server extension supervisor, inspected for exported RPC actions, and linked into client code generators.

| Property | Type | Default | Description |
|---|---|---|---|
| id (positional) | string | Required | Unique identifier of the extension (e.g. `"inventory_service"`). Used for RPC routing and log grouping. |
| Version | string | `"0.1.0"` | Semantic version string. Checked during client synchronization and hot-reload. |
| Resources | Type[] | `[]` | Array of C# record types managed by this extension. Auto-creates database schemas and exposes entries in the Studio dashboard. |

```csharp
[ExoExtension("inventory_service", Version = "1.2.0", Resources = new[] { typeof(ItemRecord) })]
public class InventoryExtension
{
    // Actions, events, and background cron routines
}
```

---

## [ExoAction]

Exposes public class methods as callable RPC endpoints over WebSocket and HTTP.

Decorate any public method with `[ExoAction]` to make it callable from Unity clients, Web UI, and CLI. Method arguments are automatically deserialized from incoming payloads, and return values are serialized back to the caller.

| Property | Type | Default | Description |
|---|---|---|---|
| Mode | string | `"sync"` | `"sync"` awaits execution and returns a result payload. `"async"` triggers background processing and returns immediately. |
| Scope | string | `"guest"` | Minimum authorization scope needed to invoke (`"guest"`, `"player"`, `"admin"`). The cluster enforces this before invoking the extension. |

```csharp
[ExoAction(Mode = "sync", Scope = "player")]
public EquipItemResponse EquipItem(EquipItemRequest req)
{
    if (string.IsNullOrEmpty(req.ItemId))
        throw new ExoActionException("invalid_item", "ItemId cannot be blank.");

    return new EquipItemResponse(req.ItemId, true);
}
```

> [!CAUTION]
> Throwing `new ExoActionException(code, message)` ensures structured error payloads propagate through the WebSocket layer with consistent error codes and clear user-facing messages.

---

## [ExoCron]

Executes scheduled recurring background jobs via the Erlang/OTP cluster scheduler.

Decorate any service method with `[ExoCron("schedule")]` to turn it into an automated background job. Ideal for leaderboard rollovers, daily resets, state sweepers, and periodic syncs.

| Property | Type | Default | Description |
|---|---|---|---|
| schedule (positional) | string | Required | Standard 5-field cron expression (e.g. `"0 0 * * *"` for midnight UTC, `"*/5 * * * *"` for every 5 minutes). |

```csharp
[ExoCron("0 0 * * *")]
public void RolloverDailyLeaderboards()
{
    // Executes automatically at midnight UTC under cluster supervisor
}
```

---

## [ExoEvent]

Subscribes to cluster-wide real-time events published via `EventDispatcher` or other extensions.

| Property | Type | Default | Description |
|---|---|---|---|
| topic (positional) | string | Required | Event topic pattern to subscribe to (e.g. `"player.registered"`, `"combat:*"`). |

```csharp
[ExoEvent("player.registered")]
public void OnPlayerRegistered(PlayerRegisteredEvent evt)
{
    // React to cluster events asynchronously
}
```

---

## [ExoResource]

Declares a typed entity record mapped directly to SQLite / PostgreSQL storage.

```csharp
[ExoResource(Name = "player_items", PrimaryKey = "id")]
public record ItemRecord(string Id, string PlayerId, string ItemType, int Quantity);
```
