---
nav: C# attributes
group: Build
icon: file
summary: Every attribute and property, and how to access the database.
---
# C# Attributes Reference

Comprehensive reference for all core attributes provided by the Exoforge Extension SDK (`Exoforge.Plugin.SDK`). Analyzed and converted into server contracts by the Roslyn Source Generator (`Exoforge.Plugin.Generator`) at compile time.

---

## [ExoService] / [ExoExtension]

Identifies a C# class or interface as a server-supervised native headless service contract and implementation.

The `[ExoService]` attribute (and its standardized alias `[ExoExtension]`) is the root entry point for backend features in Exoforge.
- On a **class**: The class is its own contract and implementation. Its `[ExoAction]`, `[ExoCron]`, and `[ExoEvent]` members define the service.
- On an **interface**: The interface is the contract and the class implementing it is the extension's root. This allows one extension to provide several services or share contracts via shared packages.

| Property | Type | Default | Description |
|---|---|---|---|
| name (positional) | string | **Required** | Unique identifier of the service (e.g. `"inventory_service"`). Used for RPC routing, CLI targeting, and log grouping. |
| Title | string | `null` | Human-readable title displayed in the Studio Dashboard, cards, and API catalog (e.g. `"Inventory Manager"`). |
| Icon | string | `null` | Icon or emoji displayed on extension cards and navigation tabs in Studio. The generator defaults to `⚙️` for system extensions and `🧩` for game extensions. |
| Category | string | `null` | Classification category in Studio (e.g. `"Game"`, `"Economy"`, `"Social"`, `"Operations"`). The generator defaults to `"Game"`, or `"System"` when `System = true`. |
| Version | string | `"0.1.0"` | Semantic version string. Checked during client synchronization, hot-reloads, and migrations. |
| Resources | Type[] | `[]` | Array of C# record or class types managed by this service. The source generator automatically extracts column schemas and creates database tables. |
| System | bool | `false` | Marks this as an essential system-level extension. Grouped into the System registry table in Studio. |
| DashboardElement | string | `null` | Custom HTML web-component / microfrontend tag name for the Studio dashboard view (e.g. `"inventory-studio-view"`). |
| DashboardEntry | string | `null` | JavaScript entry bundle path for custom Studio microfrontend views. |

```csharp
using Exoforge.Plugin.SDK;

[ExoService("inventory_service", 
    Title = "Inventory & Equipment", 
    Icon = "🎒", 
    Category = "Game", 
    Version = "0.1.0", 
    Resources = new[] { typeof(ItemRecord) })]
public class InventoryExtension
{
    // Actions, events, and background cron routines
}
```

---

## `OnExtensionStart()` lifecycle hook

Not an attribute: declare a parameterless public or private method named `OnExtensionStart` on the extension root. It may return `void` or `Task`.

The host asks the extension to run it once after the protocol handshake and after its resource tables have been migrated. It is optional; an extension without the method starts normally. Keep the hook idempotent because it runs again after a process restart. If it throws, the extension is marked crashed with a structured startup error and is not considered ready for actions.

```csharp
public class InventoryExtension
{
    public void OnExtensionStart()
    {
        var table = Exo.Database.Table<InventoryItemRecord>();
        if (!table.All().Any())
        {
            Exo.Database.Put(new InventoryItemRecord("starter-sword", "Starter Sword", 1));
        }
    }
}
```

`OnExtensionStart()` is not an action and is not callable from clients. Do not use `[ExoAction]` for it.

---

## [ExoAction]

Exposes public class methods as callable RPC endpoints over WebSocket, HTTP, and internal IPC.

Decorate any public method with `[ExoAction]` to make it callable from Unity clients, Web UI, and CLI. Method arguments are automatically deserialized from incoming payloads, and return values are serialized back to the caller.

### What `Mode` Implies in C# Extensions

> [!NOTE]
> **Client vs Server Execution**: When invoked from game clients (Unity over WebSocket or HTTP), **every request works asynchronously** across the network transport (`await client.MyActionAsync(...)` or callbacks).
> The `Mode` attribute exclusively dictates **server-side execution** and **extension-to-extension / in-server IPC** semantics (`ActionDispatcher.dispatch`).

By default, `Mode` is set to `ActionMode.Auto`, which is recommended for almost all methods:
* **`Task` / `Task<T>` returns**: Inferred as `ActionMode.Async` (`"async"`).
* **Concrete returns (`int`, `record`, `void`)**: Inferred as `ActionMode.Sync` (`"sync"`).
* **Fire-and-forget**: Set `Mode = ActionMode.Cast` for one-way notifications without caller replies.

<details>
<summary><strong>Detailed Server-Side Execution Semantics (Sync vs Async vs Cast)</strong></summary>

* **`ActionMode.Sync` (Request / Response — Synchronous Inline)**:
  * **What it implies**: Runs synchronously on the extension dispatch thread and replies immediately with the return payload. In extension-to-extension communication, the calling process waits inline for the reply.
  * **Best for**: Fast in-memory computations, state lookups, math, and validations (< 1ms).
* **`ActionMode.Async` (Request / Response — Asynchronous Non-Blocking)**:
  * **What it implies**: The method returns `Task` or `Task<T>`. The extension process does not block its dispatch thread while awaiting I/O operations (database queries, external webhooks). Once the Task resolves, the result is serialized and returned to the caller.
  * **Best for**: Database operations, external API calls, or multi-step async workflows.
* **`ActionMode.Cast` (One-Way — Fire-and-Forget)**:
  * **What it implies**: One-way dispatch without awaiting any return value or completion confirmation. No response frame is sent over the wire back to the client.
  * **Best for**: Telemetry, analytics, player position pings, event logging, or fire-and-forget notifications where low latency is critical and no response payload is needed.

</details>

| Property | Type | Default | Description |
|---|---|---|---|
| Name (positional) | string | Method name | Wire action name. When omitted, automatically converted from method PascalCase to `snake_case` (e.g. `TransferItem` → `transfer_item`). |
| Mode | ActionMode | `ActionMode.Auto` | Execution mode (`Auto`, `Sync`, `Async`, `Cast`). `Auto` infers from return type: `Task`/`Task<T>` becomes `:async`, concrete returns become `:sync`. Set `Cast` for fire-and-forget. |
| Scope | string | `"player"` | Minimum authorization scope required to invoke (`"guest"`, `"player"`, `"service"`, `"studio"`, `"admin"`; `"service"` is for trusted servers such as a game server or a CI job, and sits below `studio`; the dispatcher also knows `"global"`, no role required, and `"server"`, which no transport can reach: only calls from inside the server). The dispatcher enforces it before the action runs; internal calls bypass it. |
| Service | string | `null` | Owning service name when a single extension provides multiple `[ExoService]` contracts. Defaults to the primary service. |
| FromVersion | string | `null` | Starts an action *revision* at this extension version (`"2.0.0"`). Several methods may share one action name when each has its own `FromVersion`: a caller whose game version locks the extension below it gets the previous revision, everyone else the newest. See [Versions & Migrations](guide:04_versions_and_migrations). |

```csharp
/// <summary>Moves items between two players' inventories.</summary>
[ExoAction(Scope = "player")]
public TransferItemResponse TransferItem(TransferItemRequest req)
{
    if (req.Quantity <= 0)
        throw new ExoActionException("invalid_quantity", "Must transfer at least 1 item.");

    return new TransferItemResponse(req.ItemId, req.Quantity, true);
}
```

> [!TIP]
> The `///` summary above an action method, and above an `[ExoEvent]` record, is shown next to it in the [API catalog](guide:catalog) and in the extension's page. Write it as one sentence about what the action does for its caller.

> [!CAUTION]
> Throwing `new ExoActionException(code, message)` ensures structured error payloads propagate through the WebSocket layer with consistent error codes and clear user-facing messages.

### Typed stubs for nested values

The generated stubs (the typed plugin stubs and the Unity client) mirror what an action takes and returns, not just the top level. A return such as

```csharp
public record Item(int Slot, string? Name, Rarity Rarity, List<Item> Children);
public record Inventory(string Id, long Gold, List<Item> Items, Dictionary<string, int> Counts, Owner? Owner);

[ExoAction] public Inventory GetInventory(string owner) => ...;
```

becomes `Inventory { string Id; long Gold; List<Item> Items; Dictionary<string, int> Counts; Owner? Owner; }` in the stubs, with a class for each nested record (named as in your C#). A `JsonElement` is left only for what is dynamic: `object`, `JsonElement`, `dynamic`, a type with no public properties, or one nested more than 16 levels deep. Enums travel as their snake_case names and are `string` in the stubs. A record that contains itself is fine.

The build writes this into `manifest.json` next to the keys that were always there (older tools keep reading those and ignore the new ones):

- `returns_shape` (on an action): the whole return as a shape, when it is a list, dictionary or record.
- `returns_shapes` (on an action): the shape of each return field that is a list, dictionary, record or enum, by field name.
- `params_shapes` (on an action): the same for the parameters.
- `payload_shapes` (on an event): the same for the event payload fields.
- `types` (on a service): the records those shapes refer to, by type name, for example `{"Item": {"fields": {"slot": {...}}}}`, each field a shape.

A shape is `{"type": ..., "nullable": true, "items": ..., "values": ..., "ref": "Item", "choices": [...]}` where only the keys that apply are present. `type` is one of `string`, `int` (32-bit), `integer` (64-bit), `float`, `decimal`, `boolean`, `uuid`, `datetime`, `timespan`, `binary`, `json` (dynamic), `list` (its element is `items`), `map` (string keys, its value is `values`) or `record` (`ref` is a key of `types`). Two different C# types with the same name get distinct keys.

---

## [ExoCron]

Executes scheduled recurring background tasks via the server scheduler.

Decorate any service method with `[ExoCron("schedule")]` to turn it into an automated background job. Ideal for leaderboard rollovers, daily resets, state sweepers, and periodic syncs.

> [!IMPORTANT]
> A cron method is registered as an action with scope `"server"`: the scheduler invokes it with internal
> dispatch, but no transport can — a player or HTTP request to it is refused with `forbidden_scope`.

| Property | Type | Default | Description |
|---|---|---|---|
| schedule (positional 0) | string | **Required** | Standard 5-field cron expression in UTC (`minute hour day-of-month month day-of-week`). Examples: `"0 0 * * *"` (midnight daily), `"*/5 * * * *"` (every 5 min), `"0 * * * *"` (hourly), `"0 12 * * 1-5"` (weekdays at noon). |
| name (positional 1) | string | Method name | Wire task identifier. When omitted, defaults to method name in `snake_case`. |
| Description | string | `null` | Human-readable description of what this recurring task accomplishes. Surfaced in Studio Dashboard operations and telemetry views. |
| RunOnStartup | bool | `false` | Whether the task executes immediately when the extension starts, before the first cron trigger. Useful for seeding or cache pre-warming. |
| Service | string | `null` | The service this cron job belongs to, when multiple services are provided. Defaults to the primary service. |

```csharp
[ExoCron("0 0 * * *", Description = "Rolls over daily leaderboards at midnight UTC", RunOnStartup = false)]
public void RolloverDailyLeaderboards()
{
    // Executes automatically at midnight UTC under server supervisor
}
```

---

## [ExoEvent]

Declares an **event schema** on records, classes, or structs emitted or received on the server pub/sub bus.

> [!IMPORTANT]
> `[ExoEvent]` is used to describe an **event schema** on records or classes, **NOT** to annotate a listener function.
> * To **define an event schema**: Decorate a record/class with `[ExoEvent]`. Public properties become the payload contract.
> * To **listen to events** in a C# extension: Implement `public void OnEvent(string name, TPayload payload)` on your extension root class.
> * To **publish events** in C#: Call `await Exo.Events.EmitAsync(new MyEvent(...))`.
> * To **subscribe** in Unity: subscribe the generated service client with `await ExoServices.<Service>.SubscribeAsync("topic")`, then handle its `On<Event>` event.

| Property | Type | Default | Description |
|---|---|---|---|
| name (positional 0) | string | Record name | Event name on the wire and bus (e.g. `"player.registered"`). When omitted, derived from the class/record name in `snake_case`. |
| Topic | string | `null` | Pub/sub broadcast topic pattern (e.g. `"player:*"` or `"leaderboard.weekly"`). |
| Scope | string | `"global"` | Minimum authorization scope required to receive or publish this event. |
| PayloadType | Type | `null` | Explicit payload type (used when `[ExoEvent]` is placed on a service class instead of directly on the event record). |
| Service | string | `null` | Owning service when an extension provides multiple `[ExoService]` contracts. |

```csharp
// 1. Describe Event Schema (Record)
[ExoEvent("player.registered", Topic = "player:*")]
public record PlayerRegisteredEvent(string PlayerId, string DisplayName, DateTime RegisteredAt);

// 2. Publish Event from Server
await Exo.Events.EmitAsync(new PlayerRegisteredEvent(player.Id, player.Name, DateTime.UtcNow));

// 3. Receive Inbound Event in Extension Class
public class MyExtension
{
    public void OnEvent(string name, PlayerRegisteredEvent evt)
    {
        Exo.Logger.Info($"Player registered: {evt.DisplayName}");
    }
}

// 4. Subscribe from Unity through the generated service client
await ExoServices.PlayerData.SubscribeAsync("player_data:*");
ExoServices.PlayerData.OnPlayerCreated += evt => Debug.Log(evt.PlayerId);
```

---

## [ExoResource] & [ExoColumn]

Declares a typed entity record mapped directly to PostgreSQL storage. The Roslyn generator extracts typed columns, indexes, and primary keys to create and evolve the database tables. Safe changes (a new column, a rename) apply on deploy; a change that would destroy data is refused until you declare it with an `[ExoMigration]` (see [Versions & Migrations](guide:04_versions_and_migrations)).

### [ExoResource] Parameters

| Property | Type | Default | Description |
|---|---|---|---|
| name (positional) | string | Record name | Database table name. When omitted, defaults to the record name in `snake_case` (e.g. `PlayerScoreRecord` → `player_scores`). |
| PrimaryKey | string | `"id"` | Name of the primary key column. Can also be designated on a column using `[ExoColumn(PrimaryKey = true)]` or automatically inferred from property name `Id`. |
| Source | string | Same as `Name` | The table or view this resource is stored in. Real database table queryable via SQL (`WHERE`, `ORDER BY`). |
| Singleton | bool | `false` | Indicates whether this resource stores exactly one record (e.g. server configuration). Creates a default record when empty and renders as a single form in Studio. (Or use `[ExoSingletonResource]`). |
| DrawerTabs | string[] | `["overview"]` | Tab sections displayed when inspecting a row in the Studio drawer (e.g. `new[] { "overview", "attributes" }`). |
| ResourceType | Type | `null` | Explicit record type when declared on a service class via `[ExoService(Resources = ...)]`. |
| SchemaVersioningMode | SchemaVersioningMode | `Auto` | `Auto`: Exoforge keeps the table in line with the declaration (row stamps, migrations, deploy gates). `Manual`: your studio owns the table and its SQL migrations; Exoforge only checks at deploy that it matches. See [Versions & Migrations](guide:04_versions_and_migrations). |
| AllowPlayerRead | bool | `false` | Makes the whole resource readable by player-scoped callers through `resource_store.list`/`get`. Enable only for public data (leaderboards, catalogues, config); it is not row-scoped. |

### [ExoColumn] Parameters

| Property | Type | Default | Description |
|---|---|---|---|
| name (positional) | string | Property name | Column name in the database table in snake_case. |
| PrimaryKey | bool | `false` | Marks this column as the primary key of the resource table. (Properties named `Id` are automatically inferred as primary keys). |
| Unique | bool | `false` | Adds a unique constraint on this column. |
| Indexed | bool | `false` | Adds a (non-unique) index on this column, for columns you filter or sort on in queries. |
| ForeignKey | bool | `false` | Marks this column as a foreign key reference. Inferred automatically when `ReferencesType` is specified. |
| ReferencesType | Type | `null` | Entity record/class type referenced by this column. Automatically infers `ForeignKey = true` and target table/key `References` (e.g. `ReferencesType = typeof(PlayerDataRecord)`). |
| References | string | `null` | Target referenced table and column (e.g. `"player_data.id"`). Inferred automatically from `ReferencesType` when provided. |
| Label | string | Property name | User-friendly header label rendered in Studio Dashboard data tables and drawer forms. |
| DataType | string | Auto-inferred | Explicit type override (`"text"`, `"integer"`, `"float"`, `"boolean"`, `"datetime"`, `"map"`, `"list"`, `"binary"`). Inferred from the C# property type when omitted. |
| Role | string | `null` | Semantic role for special Studio UI presentation from `ExoRole` (`ExoRole.PlayerId`, `ExoRole.FileReference`, `ExoRole.Currency`, `ExoRole.Status`, `ExoRole.Timestamp`, `ExoRole.Title`, `ExoRole.Description`). `ExoRole.PlayerId` is the same value as `ExoRole.UserId` (`"user_id"`). |
| InputType | string | `"text"` | Form input widget from `ExoInput` (`Text`, `Color`, `Date`, `Time`, `DateTimeLocal`, `Textarea`, `Email`, `Url`, `Tel`, `Password`, `Range`, `Json`, `List`, `Checkbox`, `Select`, `FileReference`). |
| Sortable | bool | `false` | Enables column click-sorting in Studio data tables. |
| Filterable | bool | `false` | Enables quick search & filtering on this column in Studio. |
| Badge | bool | `false` | Renders the column value as a distinct colored badge chip in Studio. |
| Bucket | string | `null` | Target storage bucket name when referencing binary/blob assets from `file_bucket`. |

```csharp
[ExoResource(Name = "player_scores")]
public record PlayerScoreRecord(
    [property: ExoColumn(PrimaryKey = true)] string Id,
    [property: ExoColumn(ReferencesType = typeof(PlayerDataRecord), Role = ExoRole.PlayerId, Label = "Player ID")] string PlayerId,
    [property: ExoColumn(Label = "Score", Sortable = true)] int Score,
    [property: ExoColumn(Badge = true, InputType = ExoInput.Color)] string TierBadge,
    DateTime CreatedAt
);
```

---

## [ExoFileReference]

Marks a resource column as a file reference pointing at a bucket object. Studio renders a preview and a file picker instead of a plain text field.

| Property | Type | Default | Description |
|---|---|---|---|
| bucket (positional) | string? | `null` | Bucket that stores the file. Omit to let the Store resolve it from the bucket metadata. |

```csharp
[ExoFileReference("avatars")]
public string AvatarFileId { get; set; } = "";
```

---

## [ExoInputType]

Registers a custom Studio form input widget. A resource column references it with `InputType = "<id>"`.

| Property | Type | Default | Description |
|---|---|---|---|
| id (positional) | string | **Required** | Widget id referenced by `ExoColumn.InputType`. |
| Element | string | `""` | Custom element tag name rendered by the Studio input host. |
| Entry | string | `""` | JavaScript entry module that defines the element. |

```csharp
[ExoInputType("map_picker", Element = "x-map-picker", Entry = "inputs/map.js")]
public class MapExtension
{
    [ExoResource("regions")]
    public class Region
    {
        [ExoColumn(InputType = "map_picker")]
        public string Center { get; set; } = "";
    }
}
```

---

## [ExoForeignKey<T>]

Marks a column as a foreign key to another record type: `[ExoForeignKey<AchievementDef>]` on a `string AchievementId` property points at the `id` column of the `achievement_defs` table (pass a column name to point at another one). When the target record belongs to **another** extension, the attribute also grants this extension read access to that table (a `db_read` grant), so the foreign key can be joined without opening up anything else. The same relation can be written with `[ExoColumn(ReferencesType = typeof(T))]`.

---

## [ExoNavigation]

Declares a **virtual** property that holds the record a foreign key points at, the way an ORM navigation property does. The foreign key stays an ordinary stored column; the navigation exists only because of `Include`:

```csharp
[ExoResource("loja_ofertas")]
public class LojaOferta
{
    [ExoColumn(ForeignKey = true, References = "itens.id")]
    public string ItemId { get; set; } = "";

    [ExoNavigation(nameof(ItemId))]
    public Item? Item { get; set; }          // not a column, not stored, null until included
}

var ofertas = ExoServices.Database.Table<LojaOferta>().Include(o => o.Item).Where(o => o.Ativo).ToList();
```

The argument names the foreign-key property; a navigation that points at a missing property, or one that is not a declared foreign key, is a build error. The related rows are loaded by the server in one extra query for all the rows, also when they belong to **another** extension, and a player only gets the ones the referenced resource lets players read. A row that does not exist, or that the caller may not read, leaves the navigation `null`.

---

## [ExoSeed]

Marks a parameterless method (`void` or `Task`) on the extension root that creates the data the extension needs to start with. It runs once after `OnExtensionStart()` on **every** start, so it must be idempotent: check whether the rows exist before inserting. A seed that throws fails the lifecycle handshake and the extension does not come up.

```csharp
[ExoSeed]
public void SeedDefaults()
{
    if (Exo.Database.All<AchievementDef>().Any()) return;
    Exo.Database.Put(new AchievementDef("explorer", "Explorer", "Enter 2 rooms.", "zone_entered", 2));
}
```

---

## [ExoDependency] & [ExoDependency<T>]

Declares an explicit runtime dependency on another service contract, determining topological boot order and client stub generation scope.

```csharp
[ExoService("guild_service")]
[ExoDependency("player_data")]
[ExoDependency("auth")]
public class GuildExtension
{
    // Boots after player_data and auth are initialized
}
```

---

## [ExoWebhook]

Marks a method as an inbound external webhook receiver (e.g. Stripe, GitHub, Discord) routed over HTTP POST. The handler's single parameter is a `WebhookPayload` bound to the whole request: `Body`/`RawBody`, `Json`, `Headers`, `Method` and `Query`.

```csharp
[ExoWebhook("stripe_payment")]
public async Task HandleStripeWebhook(WebhookPayload payload)
{
    // Verify payload.Headers["stripe-signature"] against payload.RawBody before trusting payload.Json.
    Exo.Logger.Info($"Received payment event at {payload.Method} {payload.Query?.Count ?? 0} query keys");
}
```

---

## [ExoSingletonResource]

Convenience attribute for configuration entities that store exactly one record (e.g. server settings, seasonal balance tuning). Rendered in Studio as a direct single-form editor rather than a multi-row table.

```csharp
[ExoSingletonResource("season_settings")]
public record SeasonSettings(
    [property: ExoColumn(Label = "Current Season")] int SeasonNumber,
    [property: ExoColumn(Label = "Double XP Active")] bool DoubleXpEnabled
);
```

---

## Static `Exo` & `ExoServices` Capabilities Reference

Extensions access the ambient server environment through the static `Exo` holder:

| Capability | Property | Usage Example |
|---|---|---|
| **Database** | `Exo.Database` | `Exo.Database.Get<PlayerScore>("player_scores", id)`, `Exo.Database.Put(record)`, `Exo.Database.Query<T>("SELECT ... WHERE id = $1", id)` |
| **Events** | `Exo.Events` | `await Exo.Events.EmitAsync(new PlayerRegisteredEvent(id, name))` |
| **Logger** | `Exo.Logger` | `Exo.Logger.Info("Player logged in")`, `Exo.Logger.Error("Operation failed")` |
| **Inter-Service Actions** | `Exo.Actions` | `var res = await Exo.Actions.CallActionAsync<TReq, TRes>(req)` |
| **Context** | `Exo.Context` | `Exo.Context.CallerPlayerId`, `Exo.Context.CallerScopes` |


## Database Access Paradigms: Table Repository vs. Parameterized SQL

Exoforge provides two complementary database paradigms to eliminate ORM bloat and keep runtime memory minimal.

:::tabs
:::tab Table repository
```csharp
using System;
using Exoforge.Plugin.SDK;

// Pattern 1: Type-Safe Table Repository (No raw SQL strings)
public class EconomyService
{
    public void ManageListing(string listingId, string sellerId, int price)
    {
        // Strongly typed table repository for MarketListingRecord
        var table = Exo.Database.Table<MarketListingRecord>();

        // 1. Get by primary key
        var item = table.Get(listingId);

        // 2. Put / Upsert entity (auto-resolves table name & primary key)
        table.Put(new MarketListingRecord(listingId, sellerId, "sword_01", 1, price, DateTime.UtcNow));

        // 3. Retrieve all records
        var all = table.All();

        // 4. Delete by ID
        table.Delete(listingId);

        // 5. Singleton config resource
        var config = Exo.Database.First<EconomyConfigRecord>();
    }
}
```
:::tab Parameterized SQL
```csharp
using System;
using System.Collections.Generic;
using Exoforge.Plugin.SDK;

// Pattern 2: Parameterized Raw SQL (Queries, Joins, Aggregates & Atomic In-Place Updates)
public class EconomyService
{
    public List<MarketListingRecord> SearchListings(string itemId, int maxPrice, int limit)
    {
        // Positional parameters ($1, $2, ...) prevent SQL injection
        // Result rows map directly to immutable C# records
        return Exo.Database.Query<MarketListingRecord>(
            "SELECT * FROM market_listings WHERE item_id = $1 AND unit_price <= $2 ORDER BY unit_price ASC LIMIT $3",
            itemId, maxPrice, limit
        );
    }

    public void AtomicGoldTransfer(string senderId, string receiverId, int gold)
    {
        // Atomic in-place updates eliminate read-modify-write race conditions
        Exo.Database.Execute("UPDATE players SET gold = gold - $1 WHERE id = $2 AND gold >= $1", gold, senderId);
        Exo.Database.Execute("UPDATE players SET gold = gold + $1 WHERE id = $2", gold, receiverId);
    }
}
```

> [!TIP]
> **Architecture Note: Why Exoforge avoids complex Query Builders**

**No runtime query builders — by deliberate design.** Complex query builders (like EF Core or LINQ-to-Entities) introduce runtime expression compilation, large binary size, and high garbage collection pressure. Instead, Exoforge gives you two native, zero-overhead primitives:

- **Type-Safe Table Repository (`Exo.Database.Table<T>()`):** Pure C# CRUD with auto-resolved table names, primary keys, and singleton lookups. Zero SQL strings needed.
- **Parameterized Raw SQL (`Exo.Database.Query<T>()`):** High-performance SQL queries with positional `$1, $2, ...` arguments, automatic record mapping, and atomic in-place updates.

**Reading a foreign key's row with the query (`include` on `database.execute`).** The `database.execute` action takes an optional `include: [{"column": "item_id"}]` next to the SQL. Each column must be a foreign key your own resources declare (`ForeignKey` with `References` or `ReferencesType`); the referenced resource may belong to another extension. The host collects the distinct non-null values of that column in the result, reads them from the owner with one query, and answers with `included: {"item_id": {"<value>": <row>}}` next to `rows`. A row that does not exist, or that the original caller may not read, is simply absent, so the navigation stays null: a player's request can include only a resource marked `AllowPlayerRead`, while server, studio and internal callers can include any. A column that is not a declared foreign key fails with `invalid_include`. A reference to a resource no deployed extension declares does not fail: that column is left out of `included` and a `warnings` entry with code `missing_reference` names it. The query itself still reads only your own tables; filtering or ordering by a column of the included table is not supported.

:::end

## Plugs

A plug is middleware you write around the SDK: it sees every action call or every database call of your extension and can log, change, refuse or answer it. Register plugs once, for example in `OnExtensionStart()`; the first registered runs outermost, and with none registered a call goes straight through.

```csharp
public sealed class AuditPlug : IActionPlug
{
    public object? Invoke(ActionCall call, Func<object?> next)
    {
        Exo.Logger.Info($"{call.Action} by {call.PlayerId ?? "anonymous"} (game {call.GameVersion ?? "unknown"})");
        return next();   // or throw new ExoActionException("code", "message") to refuse the call
    }
}

// in OnExtensionStart():
ExoPlugs.Use(new AuditPlug());
```

`IActionPlug` wraps every action; `IDatabasePlug` wraps `Get`, `All`, `Put` and `Delete` on the stored JSON, and you override only the calls you need. Plugs run outside the built-in row migration, so they see rows as stored.
