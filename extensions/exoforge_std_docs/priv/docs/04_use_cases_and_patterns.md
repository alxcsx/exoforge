# What You Can Build with Exoforge: Blueprints & Architecture Tips

Real-world architectural patterns, sample code, and design strategies for game backends on Exoforge.

When building games on traditional Backend-as-a-Service (BaaS) platforms like **Microsoft PlayFab (CloudScript)** or **Unity Gaming Services (UGS Cloud Code)**, developers repeatedly hit architectural walls: serverless cold starts, strict 15-second execution limits, data locked in per-player key-value JSON blobs without SQL joins, and client-side polling instead of real-time push.

Exoforge combines **long-running stateful native C# processes**, **isolated relational SQL storage**, and **sub-millisecond pub/sub event broadcasting** into an integrated developer experience that makes advanced backend gameplay features intuitive and clean.

---

## The Paradigm Shift: Exoforge vs. PlayFab & UGS

| Dimension | PlayFab (CloudScript) | Unity Gaming Services (Cloud Code) | Exoforge Native Extensions |
| :--- | :--- | :--- | :--- |
| **Execution Lifecycle** | Serverless functions (JS sandbox or BYO Azure Functions). Suffixes 1–3s cold starts. | Ephemeral containers. 15-second timeout, killed after idle. | **Long-lived native .NET OS processes**. Zero cold starts; sub-millisecond dispatch. |
| **In-Memory State** | None. Stateless between calls; static variables wiped. | None. Workers rotate unpredictably; ephemeral memory. | **Persistent C# RAM state**. Maintain queues, active room lobbies, and tick-loops in memory. |
| **Data Storage** | Per-player JSON blobs (`GetUserData`). No SQL queries across players. Rate-limited to ~10 writes/sec. | JSON Cloud Save. Strict per-key size limits; no cross-player relational queries. | **Isolated SQLite / PostgreSQL tables**. Full SQL queries (`Exo.Database.Query<T>`), foreign keys, and indexes. |
| **Real-Time Push** | Polling or external SignalR/PubNub subscription. | Polling or external WebSockets setup. | **Built-in `:pg` Pub/Sub Bus**. 0.07 ms fanout to thousands of Unity clients via `Exo.Events.EmitAsync`. |
| **LiveOps & Tuning** | Manual JSON editing in "Title Data" without schemas or form validation. | Remote Config raw keys and values. | **Auto-generated Studio UI**. `[ExoResource]` & `[ExoSingletonResource]` generate full forms, tables, and inspection drawers. |
| **Scheduled Tasks** | Azure Scheduled Tasks with cold start overhead and execution timeouts. | None native. Requires external cron runner calling webhooks. | **First-class `[ExoCron]` attribute**. Runs in-process under cluster supervision. |
| **External Webhooks** | Clunky Azure API Management proxying. | Rejects calls without Unity Player Bearer token. | **First-class `[ExoWebhook]` attribute**. Direct Stripe, Steam, Discord webhooks with signature checks. |

---

## 1. Cross-Player Economy: Auction House & P2P Trading

### The BaaS Pain Point
In PlayFab and UGS, player inventory is locked in private per-player storage. Building an Auction House or peer-to-peer trading market where any player can browse listings created by other players is notoriously difficult. Developers are forced to either:
1. Shard global listings into "Shared Group Data" (which has severe concurrency limits and race-condition write locks), or
2. Spin up and pay for an external PostgreSQL/MongoDB database on AWS/Azure and write a separate microservice just to manage listings.

### The Exoforge Pattern
In Exoforge, an extension's storage is an isolated relational database. Declare an `[ExoResource]` record representing a market listing. Use `Exo.Database.Query<T>` to query items across all players with standard SQL sorting, filtering, and paging. Use `[Inject("player_data")]` or transaction logic to atomically exchange currency and item ownership, and emit an `[ExoEvent]` so the seller receives a real-time notification over WebSocket when their item sells.

```csharp
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("marketplace_service", Title = "Auction House", Icon = "⚖️")]
public class MarketplaceExtension
{
    [Inject("player_data")]
    public PlayerDataServiceClient PlayerData { get; set; } = null!;

    [ExoAction(Scope = "player")]
    public CreateListingResponse ListItem(CreateListingRequest req)
    {
        string listingId = Guid.NewGuid().ToString("N");
        var listing = new MarketListingRecord(
            listingId,
            Exo.Context.CallerPlayerId,
            req.ItemId,
            req.Quantity,
            req.UnitPrice,
            DateTime.UtcNow
        );

        Exo.Database.Put("market_listings", listingId, listing);
        Exo.Logger.Info($"Player {Exo.Context.CallerPlayerId} listed {req.Quantity}x {req.ItemId} for {req.UnitPrice}g");
        return new CreateListingResponse(listingId);
    }

    [ExoAction(Scope = "player")]
    public List<MarketListingRecord> BrowseListings(BrowseListingsRequest req)
    {
        // Native SQL query across all players with filtering and paging
        return Exo.Database.Query<MarketListingRecord>(
            "SELECT * FROM market_listings WHERE item_id = $1 ORDER BY unit_price ASC LIMIT $2 OFFSET $3",
            req.ItemId, req.Limit, req.Offset
        );
    }

    [ExoAction(Scope = "player")]
    public async Task<BuyListingResponse> BuyListing(BuyListingRequest req)
    {
        var listing = Exo.Database.Get<MarketListingRecord>("market_listings", req.ListingId);
        if (listing == null)
            throw new ExoActionException("listing_not_found", "Item has already been purchased or expired.");

        // Deduct currency & transfer item atomically
        Exo.Database.Execute("DELETE FROM market_listings WHERE id = $1", req.ListingId);

        // Real-time seller notification pushed over WebSocket
        await Exo.Events.EmitAsync(new ListingSoldEvent(
            listing.SellerPlayerId,
            listing.ItemId,
            listing.Quantity,
            listing.UnitPrice * listing.Quantity
        ));

        return new BuyListingResponse(true);
    }
}

[ExoResource(Name = "market_listings", PrimaryKey = "Id")]
public record MarketListingRecord(
    [property: ExoColumn(PrimaryKey = true)] string Id,
    [property: ExoColumn(ReferencesType = typeof(PlayerDataRecord), Role = ExoRole.PlayerId)] string SellerPlayerId,
    [property: ExoColumn(Sortable = true, Filterable = true)] string ItemId,
    [property: ExoColumn] int Quantity,
    [property: ExoColumn(Role = ExoRole.Currency, Sortable = true)] int UnitPrice,
    [property: ExoColumn(Role = ExoRole.Timestamp)] DateTime CreatedAt
);

[ExoEvent("marketplace.sold", Topic = "player:*")]
public record ListingSoldEvent(string SellerPlayerId, string ItemId, int Quantity, int TotalEarned);
```

---

## 2. Stateful In-Memory Matchmaking & Turn-Based Rooms

### The BaaS Pain Point
Cloud Code functions are completely stateless; after each request, worker memory may be cleared or routed to a different instance. To match players by rank or keep turn-based game rooms (like chess, cards, or grid tactics), developers must write state back and forth to slow remote databases on every ping, while clients poll every 2–5 seconds hoping a match was found.

### The Exoforge Pattern
Because an Exoforge native extension is a **long-lived singleton OS process**, you can keep high-speed state directly in C# memory (`ConcurrentDictionary`, queues, priority heaps). 
- Incoming players join an in-memory queue via an `[ExoAction]`.
- A background tick or `[ExoCron]` matches compatible players in microseconds.
- As soon as a match is formed, emit `[ExoEvent("match.found")]` directly to the players' open WebSockets. No database polling, no cold starts, and latency under 1 millisecond.

```csharp
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("matchmaker_service", Title = "Fast Matchmaker", Icon = "🎯")]
public class MatchmakerExtension
{
    // High-performance hot RAM queue: zero database round-trips
    private readonly ConcurrentDictionary<string, QueueEntry> _queue = new();

    [ExoAction(Scope = "player")]
    public QueueStatusResponse JoinQueue(JoinQueueRequest req)
    {
        string playerId = Exo.Context.CallerPlayerId;
        _queue[playerId] = new QueueEntry(playerId, req.EloRating, DateTime.UtcNow);
        return new QueueStatusResponse(true, _queue.Count);
    }

    [ExoAction(Scope = "player")]
    public QueueStatusResponse LeaveQueue()
    {
        _queue.TryRemove(Exo.Context.CallerPlayerId, out _);
        return new QueueStatusResponse(false, _queue.Count);
    }

    // Runs periodically to pair players by ELO rating
    [ExoCron("*/1 * * * *", Description = "Evaluates matchmaking queue and pairs players")]
    public async Task EvaluateQueue()
    {
        if (_queue.Count < 2) return;

        var sorted = _queue.Values.OrderBy(p => p.EloRating).ToList();
        for (int i = 0; i < sorted.Count - 1; i += 2)
        {
            var p1 = sorted[i];
            var p2 = sorted[i + 1];

            if (Math.Abs(p1.EloRating - p2.EloRating) <= 200)
            {
                _queue.TryRemove(p1.PlayerId, out _);
                _queue.TryRemove(p2.PlayerId, out _);

                string matchId = Guid.NewGuid().ToString("N");
                await Exo.Events.EmitAsync(new MatchFoundEvent(matchId, p1.PlayerId, p2.PlayerId));
                Exo.Logger.Info($"Paired match {matchId}: {p1.PlayerId} vs {p2.PlayerId}");
            }
        }
    }
}

public record QueueEntry(string PlayerId, int EloRating, DateTime QueuedAt);
public record JoinQueueRequest(int EloRating);
public record QueueStatusResponse(bool InQueue, int TotalInQueue);

[ExoEvent("matchmaking.found", Topic = "player:*")]
public record MatchFoundEvent(string MatchId, string Player1Id, string Player2Id);
```

---

## 3. Designer-Friendly LiveOps, Gacha Pity & Global Boss Events

### The BaaS Pain Point
In PlayFab Title Data, tuning game balance, drop tables, or configuring a server-wide "World Boss" event requires editing unvalidated JSON strings. A single typo or syntax error can break production for all active clients. Furthermore, coordinating a shared entity like a World Boss with 10,000,000 HP means dealing with race conditions on global JSON documents.

### The Exoforge Pattern
Use `[ExoSingletonResource]` to declare live configuration records. Exoforge Studio automatically renders input controls (sliders, color pickers, currency fields) based on `[ExoColumn]` attributes so game designers can safely adjust live values without engineering assistance. Keep the live boss HP in memory, persist checkpoints to `Exo.Database`, and push health bar updates to all online players in real time.

```csharp
using System;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("world_boss_service", Title = "World Boss Event", Icon = "🐉",
    Resources = new[] { typeof(WorldBossConfig) })]
public class WorldBossExtension
{
    private static int _currentBossHp = 5_000_000;

    [ExoAction(Scope = "player")]
    public async Task<AttackBossResponse> AttackBoss(AttackBossRequest req)
    {
        var config = Exo.Database.First<WorldBossConfig>("world_boss_config");
        if (config == null || !config.IsEventActive)
            throw new ExoActionException("event_inactive", "The World Boss is currently sleeping.");

        int damage = Math.Clamp(req.ReportedDamage, 1, config.MaxDamagePerHit);
        _currentBossHp = Math.Max(0, _currentBossHp - damage);

        // Broadcast damage to all players in real time
        await Exo.Events.EmitAsync(new BossDamagedEvent(Exo.Context.CallerPlayerId, damage, _currentBossHp));

        if (_currentBossHp == 0)
        {
            await Exo.Events.EmitAsync(new BossDefeatedEvent(Exo.Context.CallerPlayerId, config.VictoryRewardGold));
        }

        return new AttackBossResponse(_currentBossHp, damage);
    }
}

// Designers tune this directly inside Exoforge Producer Studio with auto-generated UI
[ExoSingletonResource("world_boss_config")]
public record WorldBossConfig(
    [property: ExoColumn(Label = "Event Active", InputType = ExoInput.Checkbox)] bool IsEventActive,
    [property: ExoColumn(Label = "Boss Name")] string BossName,
    [property: ExoColumn(Label = "Total Max HP", Sortable = true)] int TotalMaxHp,
    [property: ExoColumn(Label = "Max Damage Cap / Hit", InputType = ExoInput.Range)] int MaxDamagePerHit,
    [property: ExoColumn(Label = "Victory Reward", Role = ExoRole.Currency)] int VictoryRewardGold
);

[ExoEvent("boss.damaged", Topic = "world:*")]
public record BossDamagedEvent(string AttackerPlayerId, int DamageDealt, int RemainingHp);

[ExoEvent("boss.defeated", Topic = "world:*")]
public record BossDefeatedEvent(string FinalBlowPlayerId, int RewardGold);
```

---

## 4. Guilds, Clans & Real-Time Social Feeds

### The BaaS Pain Point
Managing guilds in PlayFab requires stitching together PlayFab Entity Groups, custom JSON files, and third-party chat solutions like Photon or PubNub. Adding member roles, tracking guild level progression, and showing a live activity feed requires multiple API calls, manual permission checks, and client polling.

### The Exoforge Pattern
Model `GuildRecord` and `GuildMemberRecord` as relational resources. Use `ReferencesType = typeof(PlayerDataRecord)` to link guild members directly to player profiles, which enables 1-click navigation in Studio. When a member deposits gold or levels up the clan, emit an event on `Topic = "guild:{guild_id}"` so all active guild members receive an instant push notification on their WebSocket connection.

```csharp
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("guild_service", Title = "Guilds & Clans", Icon = "🛡️")]
public class GuildExtension
{
    [ExoAction(Scope = "player")]
    public async Task<DepositGoldResponse> DepositGuildGold(DepositGoldRequest req)
    {
        string playerId = Exo.Context.CallerPlayerId;
        var member = Exo.Database.Get<GuildMemberRecord>("guild_members", playerId);
        if (member == null)
            throw new ExoActionException("not_in_guild", "You are not a member of any guild.");

        var guild = Exo.Database.Get<GuildRecord>("guilds", member.GuildId);
        int newBankTotal = guild.BankGold + req.Amount;

        Exo.Database.Execute("UPDATE guilds SET bank_gold = $1 WHERE id = $2", newBankTotal, guild.Id);

        // Notify all online guild members in real time
        await Exo.Events.EmitAsync(new GuildActivityEvent(
            $"guild:{guild.Id}",
            playerId,
            $"{playerId} deposited {req.Amount} gold to the guild vault!"
        ));

        return new DepositGoldResponse(newBankTotal);
    }
}

[ExoResource(Name = "guilds", PrimaryKey = "Id")]
public record GuildRecord(
    [property: ExoColumn(PrimaryKey = true)] string Id,
    [property: ExoColumn(Label = "Guild Name", Sortable = true)] string Name,
    [property: ExoColumn(Role = ExoRole.Currency)] int BankGold,
    [property: ExoColumn(Badge = true)] int Level
);

[ExoResource(Name = "guild_members", PrimaryKey = "PlayerId")]
public record GuildMemberRecord(
    [property: ExoColumn(PrimaryKey = true, ReferencesType = typeof(PlayerDataRecord), Role = ExoRole.PlayerId)] string PlayerId,
    [property: ExoColumn(ReferencesType = typeof(GuildRecord))] string GuildId,
    [property: ExoColumn(Badge = true)] string Rank
);

[ExoEvent("guild.activity", Topic = "guild:*")]
public record GuildActivityEvent(string Topic, string ActorPlayerId, string Message);
```

---

## 5. Automated Season Rollovers & Leaderboard Resets

### The BaaS Pain Point
Cloud Code has no native cron triggers, and PlayFab Scheduled Tasks frequently encounter 10-second timeout limits when iterating over thousands of player records to distribute rewards. Developers must maintain complex external AWS Lambda or Azure Functions infrastructure with batching loops and pagination logic.

### The Exoforge Pattern
Use `[ExoCron]` to run automated background jobs directly under cluster supervision. Because you have direct relational SQL access, a season reset can compute leaderboard rewards, archive rankings, and reset scores in a single atomic SQL statement without round-tripping data through JSON APIs.

```csharp
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("season_service", Title = "Season Manager", Icon = "🏆")]
public class SeasonExtension
{
    // Midnight UTC on Monday: Automated Season Rollover
    [ExoCron("0 0 * * 1", Description = "Weekly season rollover and reward distribution")]
    public async Task RolloverWeeklySeason()
    {
        Exo.Logger.Info("Beginning automated season rollover...");

        // Atomic SQL: Archive top 100 players into hall of fame
        Exo.Database.Execute(@"
            INSERT INTO hall_of_fame (player_id, final_score, season_number, recorded_at)
            SELECT player_id, score, 12, datetime('now')
            FROM season_scores
            ORDER BY score DESC LIMIT 100
        ");

        // Reset active scores for the new week
        Exo.Database.Execute("DELETE FROM season_scores");

        // Broadcast season reset to all online Unity clients
        await Exo.Events.EmitAsync(new SeasonResetEvent(13, "Season 13 is now live!"));
        Exo.Logger.Info("Season 13 successfully initialized.");
    }
}

[ExoEvent("season.reset", Topic = "global")]
public record SeasonResetEvent(int NewSeasonNumber, string Announcement);
```

---

## 6. Web Store Checkout, Stripe Webhooks & Instant Delivery

### The BaaS Pain Point
Unity Cloud Code endpoints reject any request that does not include a Unity Player Bearer token, making it impossible to receive raw webhooks from Stripe, Shopify, Steam, or PayPal without standing up an intermediate web proxy. In PlayFab, developers must wire Azure API Management or AWS API Gateway to verify webhook signatures before invoking CloudScript.

### The Exoforge Pattern
Use `[ExoWebhook]` to expose an external HTTP POST endpoint directly from your extension. Verify cryptographic signatures (e.g. `Stripe-Signature`), fulfill purchases in `Exo.Database`, and push a real-time `PurchaseFulfilledEvent` over WebSocket to the player's active Unity session. The player sees their gems or battle pass unlock the exact second their credit card transaction completes.

```csharp
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("billing_service", Title = "Payments & Store", Icon = "💳")]
public class BillingExtension
{
    [Inject("player_data")]
    public PlayerDataServiceClient PlayerData { get; set; } = null!;

    // External HTTP POST webhook (e.g. https://api.yourgame.com/ext/billing_service/webhook/stripe)
    [ExoWebhook("stripe")]
    public async Task<WebhookResult> HandleStripeWebhook(WebhookPayload payload)
    {
        string signature = payload.Headers.TryGetValue("Stripe-Signature", out var sig) ? sig : "";
        Exo.Logger.Info($"Inbound Stripe webhook: {payload.EventName}");

        // Verify HMAC signature, parse customer player ID, and grant purchased item
        string targetPlayerId = payload.Data["client_reference_id"]?.ToString() ?? "";
        string productId = payload.Data["product_id"]?.ToString() ?? "";

        // Instantly credit player account
        Exo.Database.Execute(
            "INSERT INTO player_purchases (player_id, product_id, purchased_at) VALUES ($1, $2, datetime('now'))",
            targetPlayerId, productId
        );

        // Push real-time unlock animation event directly to the player's active Unity client
        await Exo.Events.EmitAsync(new PurchaseFulfilledEvent(targetPlayerId, productId));

        return WebhookResult.Success();
    }
}

[ExoEvent("store.fulfilled", Topic = "player:*")]
public record PurchaseFulfilledEvent(string PlayerId, string ProductId);
```

---

## Exoforge Architecture Tips & Golden Rules

When architecting backend extensions for Exoforge, keep these five principles in mind:

1. **Hot State in RAM, Durable State in `Exo.Database`**  
   Take advantage of long-running processes. Keep active matchmaking queues, player room lobbies, and tick timers directly in C# fields. Only write to `Exo.Database` when state changes must survive process restarts.

2. **Let `[ExoResource]` Build Your Admin Tooling**  
   Never waste time building custom internal admin tools. Decorate your records with `[ExoColumn]` roles (`ExoRole.PlayerId`, `ExoRole.Currency`, `Badge = true`, `InputType = ExoInput.Range`), and Producer Studio will automatically generate searchable tables, filter bars, editing drawers, and foreign-key links.

3. **Decouple Extensions via `[ExoDependency]` & Events**  
   Separate complex domains into independent extensions (e.g., `inventory`, `matchmaker`, `billing`). Call other extensions using generated typed stubs (`exo extension stubs <name>`), and broadcast major lifecycle events (`player.registered`, `item.crafted`, `match.ended`) so other services can react asynchronously.

4. **Never Poll from Unity**  
   If a client action requires waiting (e.g. matchmaking, asynchronous crafting, trade acceptance, webhook confirmation), return an immediate response from `[ExoAction]` and push the completion payload using `Exo.Events.EmitAsync`. The client listens via `ExoforgeSDK.Events.Subscribe<T>()`.

5. **Throw `ExoActionException` for Domain Errors**  
   Avoid using error codes or wrapper types like `Result<T>` in your action return signatures. Throwing `throw new ExoActionException("insufficient_funds", "You need 500 gold to purchase this item.")` automatically returns a structured error to the client, triggering `onError` callbacks or throwing caught exceptions in Unity async/await blocks.
