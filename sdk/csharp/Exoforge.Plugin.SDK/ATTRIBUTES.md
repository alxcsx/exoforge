# Exoforge Extension SDK — C# Attributes Reference

Comprehensive reference for all core attributes provided by `Exoforge.Plugin.SDK` (`Attributes.cs`), analyzed and processed by the Roslyn Source Generator (`Exoforge.Plugin.Generator`) at compile time.

---

## 1. `[ExoExtension]` / `[ExoService]`

**Target:** `Class` or `Interface`  
**Namespace:** `Exoforge.Plugin.SDK`

Declares an extension service contract provided by the native extension. On a **class**, the class is its own contract and implementation: its `[ExoAction]`, `[ExoCron]`, and `[ExoEvent]` members belong to the service. On an **interface**, the interface is the contract and the implementing class is the extension root.

### Parameters & Properties

| Parameter | Type | Required / Default | Description |
|---|---|---|---|
| `name` (positional) | `string` | **Required** | Unique identifier of the service / extension (e.g. `"inventory_service"`). Used for RPC routing, CLI targeting, and log grouping. |
| `Title` | `string?` | Optional (`null`) | Human-readable title displayed in the Studio Dashboard, cards, and API documentation (e.g. `"Inventory Manager"`). |
| `Icon` | `string?` | Optional (`"⚙️"`) | Icon or emoji displayed on extension cards and navigation tabs in Studio (e.g. `"🎒"`, `"🎮"`). |
| `Category` | `string?` | Optional (`"Extension"`) | Classification category in Studio (e.g. `"Game"`, `"Economy"`, `"Social"`, `"Operations"`, `"System"`). |
| `Version` | `string?` | Optional (`"0.1.0"`) | Semantic version string. Checked during client stub generation, hot-reloads, and migrations. |
| `Resources` | `Type[]?` | Optional (`[]`) | Array of C# record or class types managed by this service. The source generator automatically extracts column schemas and creates database tables. |
| `System` | `bool` | Optional (`false`) | Marks this as an essential system-level extension. Grouped into the System registry table in Studio. |
| `DashboardElement` | `string?` | Optional (`null`) | Custom HTML web-component / microfrontend tag name for the Studio dashboard view (e.g. `"inventory-studio-view"`). |
| `DashboardEntry` | `string?` | Optional (`null`) | JavaScript entry bundle path for custom Studio microfrontend views. |

### Example

```csharp
[ExoExtension("inventory_service", 
    Title = "Inventory & Equipment", 
    Icon = "🎒", 
    Category = "Game", 
    Version = "1.0.0", 
    Resources = new[] { typeof(ItemRecord) })]
public class InventoryExtension
{
    // Actions, events, and recurring cron jobs
}
```

---

## 2. `[ExoAction]`

**Target:** `Method`  
**Namespace:** `Exoforge.Plugin.SDK`

Exposes a public class method as a callable RPC action endpoint over WebSocket, HTTP, and internal IPC. Arguments are automatically deserialized from incoming JSON payloads, and return values are serialized back to the caller.

### How `Mode` Works in Native C# Extensions

C# native extensions execute out-of-process and communicate with the Erlang/OTP host via standard I/O newline-delimited JSON. By default, `Mode` is set to `ActionMode.Auto`:
* **`Task` / `Task<T>` return type**: Inferred as `ActionMode.Async` (`"async"`). The extension runtime awaits the asynchronous task before replying with an `action_result` frame.
* **Concrete return type (`int`, `record`, `void`)**: Inferred as `ActionMode.Sync` (`"sync"`). The extension runtime executes the method synchronously and replies immediately.
* **`ActionMode.Cast`**: Explicit fire-and-forget. The host dispatches the frame without blocking callers or awaiting an `action_result`.

### Parameters & Properties

| Parameter | Type | Required / Default | Description |
|---|---|---|---|
| `name` (positional) | `string?` | Optional (method name) | Wire action name. When omitted, automatically converted from method PascalCase to `snake_case` (e.g. `TransferItem` → `transfer_item`). |
| `Mode` | `ActionMode` | Optional (`ActionMode.Auto`) | Execution mode (`Auto`, `Sync`, `Async`, `Cast`). `Auto` infers from return type: `Task`/`Task<T>` becomes `:async`, concrete returns become `:sync`. Set `Cast` for fire-and-forget. |
| `Scope` | `string` | Optional (`"global"`) | Minimum authorization scope required to invoke (`"guest"`, `"player"`, `"admin"`, `"studio"`). Enforced by ActionDispatcher before IPC invocation. |
| `Transport` | `ActionTransport` | Optional (`ActionTransport.Auto`) | Preferred transport mechanism (`Auto`, `WebSocket`, `Http`, `Webhook`). |
| `Service` | `string?` | Optional (`null`) | The owning service name when a single extension provides multiple `[ExoService]` contracts. Defaults to the primary service. |

### Example

```csharp
[ExoAction(Scope = "player")]
public TransferItemResponse TransferItem(TransferItemRequest req)
{
    if (req.Quantity <= 0)
        throw new ExoActionException("invalid_quantity", "Must transfer at least 1 item.");

    return new TransferItemResponse(req.ItemId, req.Quantity, true);
}
```

---

## 3. `[ExoCron]`

**Target:** `Method`  
**Namespace:** `Exoforge.Plugin.SDK`

Marks a method as a scheduled recurring background task (cron job). Executed periodically by the Erlang/OTP cluster scheduler according to the specified cron expression.

### Parameters & Properties

| Parameter | Type | Required / Default | Description |
|---|---|---|---|
| `schedule` (positional 0) | `string` | **Required** | Standard 5-field cron expression in UTC (`minute hour day-of-month month day-of-week`). Examples: `"0 0 * * *"` (midnight daily), `"*/5 * * * *"` (every 5 minutes), `"0 * * * *"` (hourly), `"0 12 * * 1-5"` (weekdays at noon). |
| `name` (positional 1 or named) | `string?` | Optional (method name) | Unique task name on the wire. When omitted, defaults to the method name in `snake_case`. |
| `Description` | `string?` | Optional (`null`) | Human-readable description of what this recurring task accomplishes. Surfaced in Studio Dashboard operations and telemetry views. |
| `RunOnStartup` | `bool` | Optional (`false`) | Whether the task executes immediately when the extension starts, before the first cron trigger. Useful for seeding or cache pre-warming. |
| `Service` | `string?` | Optional (`null`) | The service this cron job belongs to, when multiple services are provided. Defaults to the primary service. |

### Example

```csharp
[ExoCron("0 0 * * *", Description = "Rolls over daily leaderboards at midnight UTC", RunOnStartup = false)]
public void RolloverDailyLeaderboards()
{
    // Automated cluster-supervised task
}
```

---

## 4. `[ExoEvent]`

**Target:** `Class`, `Record`, `Struct`  
**Namespace:** `Exoforge.Plugin.SDK`

Marks a **record, class, or struct** as an **event schema** emitted or received on the cluster pub/sub bus.

> [!IMPORTANT]
> `[ExoEvent]` is used to describe an **event schema** on records or classes, **NOT** to annotate a listener function.
> * To **define an event schema**: Decorate the record with `[ExoEvent]`. Public properties become the payload contract.
> * To **listen to events** in a C# extension: Implement `public void OnEvent(string name, TPayload payload)` on your extension root class.
> * To **publish events** in C#: Call `Exo.Events.Publish("topic", eventRecord)`.
> * To **subscribe** in Unity: Call `ExoforgeSDK.Events.Subscribe<TEvent>("topic", handler)`.

### Parameters & Properties

| Parameter | Type | Required / Default | Description |
|---|---|---|---|
| `name` (positional 0) | `string?` | Optional (record name) | Event name on the wire and bus (e.g. `"player.registered"`). When omitted, derived from the class/record name in `snake_case`. |
| `Topic` | `string?` | Optional (`null`) | Pub/sub broadcast topic pattern (e.g. `"player:*"` or `"leaderboard.weekly"`). |
| `Scope` | `string` | Optional (`"global"`) | Minimum authorization scope required to receive or publish this event. |
| `PayloadType` | `Type?` | Optional (`null`) | Explicit payload type (used when `[ExoEvent]` is placed on a service class instead of directly on the event record). |
| `Service` | `string?` | Optional (`null`) | Owning service when an extension provides multiple `[ExoService]` contracts. |

### Example

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

## 5. `[ExoResource]` & `[ExoColumn]`

**Target:** `Class`, `Record`, `Struct` (Resource) / `Property`, `Parameter` (Column)  
**Namespace:** `Exoforge.Plugin.SDK`

Declares a metadata-driven database entity mapped to SQLite or PostgreSQL storage. The Roslyn generator extracts typed columns, indexes, and primary keys to produce database tables without manual migration files.

### `[ExoResource]` Parameters & Properties

| Parameter | Type | Required / Default | Description |
|---|---|---|---|
| `name` (positional or named) | `string?` | Optional (record name) | Database table name. When omitted, defaults to the record name in `snake_case` (e.g. `PlayerScoreRecord` → `player_scores`). |
| `PrimaryKey` | `string?` | Optional (`"id"`) | Name of the primary key column. Can also be designated on a property using `[PrimaryKey]`. |
| `Source` | `string?` | Optional (same as `Name`) | The table or view this resource is stored in. Real database table queryable via SQL (`WHERE`, `ORDER BY`). |
| `Singleton` | `bool` | Optional (`false`) | Indicates whether this resource stores exactly one record (e.g. server configuration). Creates a default record when empty and renders as a single form in Studio. (Or use `[ExoSingletonResource]`). |
| `DrawerTabs` | `string[]?` | Optional (`["overview"]`) | Tab sections displayed when inspecting a row in the Studio drawer (e.g. `new[] { "overview", "attributes" }`). |
| `ResourceType` | `Type?` | Optional (`null`) | Explicit record type when declared on a service class via `[ExoService(Resources = ...)]`. |

### `[ExoColumn]` Parameters & Properties

| Parameter | Type | Required / Default | Description |
|---|---|---|---|
| `name` (positional or named) | `string?` | Optional (property name) | Column name in the database table in snake_case. |
| `Label` | `string?` | Optional (property name) | User-friendly header label rendered in Studio Dashboard data tables and drawer forms. |
| `DataType` | `string?` | Optional (auto-inferred) | Explicit SQL data type override (`"text"`, `"integer"`, `"float"`, `"boolean"`, `"datetime"`, `"json"`). Inferred from C# type. |
| `Role` | `string?` | Optional (`null`) | Semantic role for special Studio UI presentation (e.g. `"user_id"`, `"file_reference"`, `"currency"`). |
| `InputType` | `string?` | Optional (`"text"`) | Form input widget from `ExoInput` (`Text`, `Color`, `Date`, `Time`, `DateTimeLocal`, `Textarea`, `Email`, `Url`, `Password`, `Range`, `Json`, `List`, `Checkbox`, `Select`, `FileReference`). |
| `Sortable` | `bool` | Optional (`true`) | Enables column click-sorting in Studio data tables. |
| `Filterable` | `bool` | Optional (`true`) | Enables quick search & filtering on this column in Studio. |
| `Badge` | `bool` | Optional (`false`) | Renders the column value as a distinct colored badge chip in Studio. |
| `Bucket` | `string?` | Optional (`null`) | Target storage bucket name when referencing binary/blob assets from `file_bucket`. |
| `FileReference` | `bool` | Optional (`false`) | Convenience shorthand for `Role = "file_reference"`. |

### Example

```csharp
[ExoResource(Name = "player_scores", PrimaryKey = "id")]
public record PlayerScoreRecord(
    [property: PrimaryKey] string Id,
    [property: ExoColumn(Role = "user_id", Label = "Player ID")] string PlayerId,
    [property: ExoColumn(Label = "Score", Sortable = true)] int Score,
    [property: ExoColumn(Badge = true, InputType = ExoInput.Color)] string TierBadge,
    DateTime CreatedAt
);
```
