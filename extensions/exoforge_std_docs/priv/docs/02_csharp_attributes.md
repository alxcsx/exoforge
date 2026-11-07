# C# Attributes Reference

Comprehensive reference for all core attributes provided by the Exoforge Extension SDK (`Exoforge.Plugin.SDK`). Analyzed and converted into cluster contracts by the Roslyn Source Generator (`Exoforge.Plugin.Generator`) at compile time.

---

## [ExoExtension] / [ExoService]

**Source / Provider:** Kernel & Extension Manager (`core/`, `exoforge_std_extension_manager`)

Identifies a C# class as a cluster-supervised native headless service.

The `[ExoExtension]` attribute (standard alias for `[ExoService]`) is the root entry point for backend features in Exoforge. Classes marked with this attribute are automatically registered into the server extension supervisor, inspected for exported RPC actions, and linked into client code generators.

| Property | Type | Default | Description |
|---|---|---|---|
| id (positional) | string | **Required** | Unique identifier of the service / extension (e.g. `"inventory_service"`). Used for RPC routing, CLI targeting, and log grouping. |
| Title | string | `null` | Human-readable title displayed in the Studio Dashboard, cards, and API catalog (e.g. `"Inventory Manager"`). |
| Icon | string | `"⚙️"` | Icon or emoji displayed on extension cards and navigation tabs in Studio (e.g. `"🎒"`, `"🎮"`). |
| Category | string | `"Extension"` | Classification category in Studio (e.g. `"Game"`, `"Economy"`, `"Social"`, `"Operations"`, `"System"`). |
| Version | string | `"0.1.0"` | Semantic version string. Checked during client synchronization, hot-reloads, and migrations. |
| Resources | Type[] | `[]` | Array of C# record or class types managed by this service. The source generator automatically extracts column schemas and creates database tables. |
| System | bool | `false` | Marks this as an essential system-level extension. Grouped into the System registry table in Studio. |
| DashboardElement | string | `null` | Custom HTML web-component / microfrontend tag name for the Studio dashboard view (e.g. `"inventory-studio-view"`). |
| DashboardEntry | string | `null` | JavaScript entry bundle path for custom Studio microfrontend views. |

```csharp
[ExoExtension("inventory_service", 
    Title = "Inventory & Equipment", 
    Icon = "🎒", 
    Category = "Game", 
    Version = "1.0.0", 
    Resources = new[] { typeof(ItemRecord) })]
public class InventoryExtension
{
    // Actions, events, and background cron routines
}
```

---

## [ExoAction]

**Source / Provider:** Kernel ActionDispatcher & Transports (`core/`, implemented via `exoforge_std_ws`, `exoforge_std_http`)

Exposes public class methods as callable RPC endpoints over WebSocket, HTTP, and internal IPC.

Decorate any public method with `[ExoAction]` to make it callable from Unity clients, Web UI, and CLI. Method arguments are automatically deserialized from incoming payloads, and return values are serialized back to the caller.

### What `Mode` Implies in C# Extensions

> [!NOTE]
> **Client vs Server Execution**: When invoked from game clients (Unity over WebSocket or HTTP), **every request works asynchronously** across the network transport (`await client.MyActionAsync(...)` or callbacks).
> The `Mode` attribute exclusively dictates **server-side execution** and **extension-to-extension / in-cluster IPC** semantics (`ActionDispatcher.dispatch`).

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
| Scope | string | `"global"` | Minimum authorization scope required to invoke (`"guest"`, `"player"`, `"admin"`, `"studio"`). Enforced by ActionDispatcher before IPC invocation. |
| Transport | ActionTransport | `ActionTransport.Auto` | Preferred transport mechanism (`Auto`, `WebSocket`, `Http`, `Webhook`). |
| Service | string | `null` | Owning service name when a single extension provides multiple `[ExoService]` contracts. Defaults to the primary service. |

```csharp
[ExoAction(Scope = "player")]
public TransferItemResponse TransferItem(TransferItemRequest req)
{
    if (req.Quantity <= 0)
        throw new ExoActionException("invalid_quantity", "Must transfer at least 1 item.");

    return new TransferItemResponse(req.ItemId, req.Quantity, true);
}
```

> [!CAUTION]
> Throwing `new ExoActionException(code, message)` ensures structured error payloads propagate through the WebSocket layer with consistent error codes and clear user-facing messages.

---

## [ExoCron]

**Source / Provider:** Cron Extension (`exoforge_std_cron`)

Executes scheduled recurring background tasks via the cluster scheduler.

Decorate any service method with `[ExoCron("schedule")]` to turn it into an automated background job. Ideal for leaderboard rollovers, daily resets, state sweepers, and periodic syncs.

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
    // Executes automatically at midnight UTC under cluster supervisor
}
```

---

## [ExoEvent]

**Source / Provider:** Kernel EventDispatcher & Realtime Transport (`core/`, pushed via `exoforge_std_ws`)

Declares an **event schema** on records, classes, or structs emitted or received on the cluster pub/sub bus.

> [!IMPORTANT]
> `[ExoEvent]` is used to describe an **event schema** on records or classes, **NOT** to annotate a listener function.
> * To **define an event schema**: Decorate a record/class with `[ExoEvent]`. Public properties become the payload contract.
> * To **listen to events** in a C# extension: Implement `public void OnEvent(string name, TPayload payload)` on your extension root class.
> * To **publish events** in C#: Call `Exo.Events.Publish("topic", eventRecord)`.
> * To **subscribe** in Unity: Call `ExoforgeSDK.Events.Subscribe<TEvent>("topic", handler)`.

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
Exo.Events.Publish($"player:{player.Id}", new PlayerRegisteredEvent(player.Id, player.Name, DateTime.UtcNow));

// 3. Receive Inbound Event in Extension Class
public class MyExtension
{
    public void OnEvent(string name, PlayerRegisteredEvent evt)
    {
        Exo.Log.Info($"Player registered: {evt.DisplayName}");
    }
}
```

---

## [ExoResource] & [ExoColumn]

**Source / Provider:** Database & Resource Store Extensions (`exoforge_std_database`, `exoforge_std_resources`)

Declares a typed entity record mapped directly to SQLite / PostgreSQL storage. The Roslyn generator extracts typed columns, indexes, and primary keys to produce database tables without manual migration files.

### [ExoResource] Parameters

| Property | Type | Default | Description |
|---|---|---|---|
| name (positional) | string | Record name | Database table name. When omitted, defaults to the record name in `snake_case` (e.g. `PlayerScoreRecord` → `player_scores`). |
| PrimaryKey | string | `"id"` | Name of the primary key column. Can also be designated on a column using `[ExoColumn(PrimaryKey = true)]` or automatically inferred from property name `Id`. |
| Source | string | Same as `Name` | The table or view this resource is stored in. Real database table queryable via SQL (`WHERE`, `ORDER BY`). |
| Singleton | bool | `false` | Indicates whether this resource stores exactly one record (e.g. server configuration). Creates a default record when empty and renders as a single form in Studio. (Or use `[ExoSingletonResource]`). |
| DrawerTabs | string[] | `["overview"]` | Tab sections displayed when inspecting a row in the Studio drawer (e.g. `new[] { "overview", "attributes" }`). |
| ResourceType | Type | `null` | Explicit record type when declared on a service class via `[ExoService(Resources = ...)]`. |

### [ExoColumn] Parameters

| Property | Type | Default | Description |
|---|---|---|---|
| name (positional) | string | Property name | Column name in the database table in snake_case. |
| PrimaryKey | bool | `false` | Marks this column as the primary key of the resource table. (Properties named `Id` are automatically inferred as primary keys). |
| ForeignKey | bool | `false` | Marks this column as a foreign key reference. Inferred automatically when `ReferencesType` is specified. |
| ReferencesType | Type | `null` | Entity record/class type referenced by this column. Automatically infers `ForeignKey = true` and target table/key `References` (e.g. `ReferencesType = typeof(PlayerDataRecord)`). |
| References | string | `null` | Target referenced table and column (e.g. `"player_data.id"`). Inferred automatically from `ReferencesType` when provided. |
| Label | string | Property name | User-friendly header label rendered in Studio Dashboard data tables and drawer forms. |
| DataType | string | Auto-inferred | Explicit SQL data type override (`"text"`, `"integer"`, `"float"`, `"boolean"`, `"datetime"`, `"json"`). Inferred from C# type. |
| Role | string | `null` | Semantic role for special Studio UI presentation from `ExoRole` (`ExoRole.PlayerId`, `ExoRole.FileReference`, `ExoRole.Currency`, `ExoRole.Status`, `ExoRole.Timestamp`, `ExoRole.Title`, `ExoRole.Description`). |
| InputType | string | `"text"` | Form input widget from `ExoInput` (`Text`, `Color`, `Date`, `Time`, `DateTimeLocal`, `Textarea`, `Email`, `Url`, `Password`, `Range`, `Json`, `List`, `Checkbox`, `Select`, `FileReference`). |
| Sortable | bool | `true` | Enables column click-sorting in Studio data tables. |
| Filterable | bool | `true` | Enables quick search & filtering on this column in Studio. |
| Badge | bool | `false` | Renders the column value as a distinct colored badge chip in Studio. |
| Bucket | string | `null` | Target storage bucket name when referencing binary/blob assets from `file_bucket`. |
| FileReference | bool | `false` | Convenience shorthand for `Role = ExoRole.FileReference`. |

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
