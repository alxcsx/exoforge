---
nav: The Arcade
group: Learn by example
icon: compass
summary: One enemy kill followed through real extensions.
---
# The Arcade, Piece by Piece

The [Exoforge Arcade](https://github.com/alxcsx/exoforge-arcade) is a set of small Unity games (a hub with a meme-stock market, a dungeon, a level sharer) that all run against **one** Exoforge backend. Its server side is eight native C# extensions; this chapter follows one event through them and shows each pattern in the code that actually runs. Every snippet below is copied unchanged from the repository; the path above each one is where to find it.

| Extension | What it does |
|---|---|
| `wallet` | Coins, shared by every game. |
| `achievements` | Counts events from the other extensions and unlocks achievements. |
| `adventure_world` | The dungeon's progress, and the events it raises. |
| `brainrot_market` | Meme-stock prices, trading, idle coins, a storefront webhook. |
| `daily_rewards`, `game_menu`, `level_share`, `world_boss` | Daily streaks, the hub menu, shared levels, a global boss. |

---

## 1. Follow one enemy kill

A dungeon game server (the sample mocks one) tells `adventure_world` that a player killed a slime. By the time the player's screen shows a toast, four different pieces of code have run.

![How one kill travels through the extensions and back to the player's screen](diagram:event-flow)

### The action: only a trusted server may call it

`ReportKill` is called by the game server, never by a player's client, so it asks for the `service` scope (see the scopes in the [attribute reference](guide:03_csharp_attributes#exoaction)). It stores the new progress and raises an event.

`extensions/adventure_world/src/AdventureWorldExtension.cs:9-17`
```csharp
    [ExoAction(Scope = "service")]
    public AdventurerProgress ReportKill(string playerId, string name, string enemy, string zone)
    {
        var progress = Load(playerId, name);
        progress = progress with { Kills = progress.Kills + 1, UpdatedAt = Now() };
        Exo.Database.Put(progress);
        Exo.Events.EmitAsync(new EnemySlain(playerId, name, enemy, zone, Now())).GetAwaiter().GetResult();
        return progress;
    }
```

### The event: declared by the extension that raises it

An `[ExoEvent]` record names the event on the wire and the topic clients and other extensions subscribe to. The record's fields are the payload.

`extensions/adventure_world/src/AdventureWorldExtension.cs:65-66`
```csharp
[ExoEvent("enemy_slain", Topic = "world:feed")]
public record EnemySlain(string PlayerId, string Name, string Enemy, string Zone, long Timestamp);
```

### The subscriber: another extension, no code dependency

`achievements` does not call `adventure_world` and does not reference its code. It declares the same event with only the fields it needs, and the host forwards matching events to its `OnEvent` method.

`extensions/achievements/src/AchievementsExtension.cs:69-70`
```csharp
[ExoEvent("enemy_slain", Topic = "world:feed")]
public record EnemySlain(string PlayerId);
```

`extensions/achievements/src/AchievementsExtension.cs:41-46`
```csharp
    public void OnEvent(string name, JsonElement payload)
    {
        if (name == "achievement_unlocked") return;
        if (!payload.TryGetProperty("player_id", out var id) || id.GetString() is not { Length: > 0 } playerId) return;
        Apply(playerId, name);
    }
```

`Apply` counts the event per player and unlocks every achievement whose threshold is reached, then raises its own event for the client:

`extensions/achievements/src/AchievementsExtension.cs:48-66`
```csharp
    private static void Apply(string playerId, string trigger)
    {
        if (!Exo.Database.All<AchievementDef>().Any(d => d.Trigger == trigger)) return;

        Exo.Logger.Info($"event {trigger} from {playerId}");
        var key = $"{playerId}:{trigger}";
        var count = (Exo.Database.Get<AchievementProgress>(key)?.Count ?? 0) + 1;
        Exo.Database.Put(new AchievementProgress(key, playerId, trigger, count));

        foreach (var def in Exo.Database.All<AchievementDef>().Where(d => d.Trigger == trigger && d.Count <= count))
        {
            var unlockKey = $"{playerId}:{def.Id}";
            if (Exo.Database.Get<AchievementUnlock>(unlockKey) != null) continue;

            Exo.Database.Put(new AchievementUnlock(unlockKey, playerId, def.Id, DateTime.UtcNow));
            Exo.Logger.Info($"unlocked {def.Id} for {playerId}");
            Exo.Events.EmitAsync(new AchievementUnlocked(playerId, def.Id, def.Title)).GetAwaiter().GetResult();
        }
    }
```

`extensions/achievements/src/AchievementsExtension.cs:80-81`
```csharp
[ExoEvent("achievement_unlocked", Topic = "achievements:feed")]
public record AchievementUnlocked(string PlayerId, string AchievementId, string Title);
```

### The client: just another subscriber

The Unity side never polls. A bridge component subscribes to the generated service and queues what arrives for the next `Update`:

`2d-echo-dungeon/Assets/Samples/EchoDungeon/DungeonBridge.cs:17-40`
```csharp
        private async void Connect()
        {
            var world = ExoServices.AdventureWorld;
            world.OnEnemySlain += e => _incoming.Enqueue($"{e.Name} slew a {e.Enemy} in {e.Zone}");
            world.OnChestOpened += e => _incoming.Enqueue($"{e.Name} opened a chest in {e.Zone} (+{e.Gold})");
            world.OnZoneEntered += e => _incoming.Enqueue($"{e.Name} entered {e.Zone}");

            try
            {
                await world.SubscribeAsync();
                var progress = await world.GetProgressAsync();
                _incoming.Enqueue($"welcome back: {progress.Kills} kills, {progress.Chests} chests");
            }
            catch (ExoActionException ex)
            {
                _incoming.Enqueue($"world unavailable [{ex.Code}]: {ex.Message}");
                Debug.LogWarning($"[Arcade] dungeon connect failed [{ex.Code}]: {ex.Message} (rid {ex.RequestId})");
            }
            catch (Exception ex)
            {
                _incoming.Enqueue($"world unavailable: {ex.Message}");
                Debug.LogError($"[Arcade] dungeon connect failed: {ex}");
            }
        }
```

`ExoServices.AdventureWorld` is a typed stub generated from the extension's manifest (`exo sync`); `ExoActionException` carries the error code and the request id (`rid`) that the server logs, so a failure in a player's log can be found on the server.

---

## 2. Declare an extension and its data

The first lines of `achievements` are the whole declaration: a service name, a version, a category, and the resources (tables) it owns.

`extensions/achievements/src/AchievementsExtension.cs:9-12`
```csharp
[ExoExtension("achievements", Version = "0.1.0", Category = "Game", Title = "Achievements", Icon = "🏆",
    Resources = [typeof(AchievementDef), typeof(AchievementProgress), typeof(AchievementUnlock)])]
public class AchievementsExtension
{
```

Each resource is a record. `[ExoColumn]` controls how the Studio shows it (`Label`, `Sortable`, `Filterable`) and the primary key says which property identifies a row. `AllowPlayerRead` lets players read the catalogue through the resource store; use it only for data that is public by design.

`extensions/achievements/src/AchievementsExtension.cs:83-89`
```csharp
[ExoResource("achievement_defs", PrimaryKey = nameof(Id), AllowPlayerRead = true)]
public record AchievementDef(
    [property: ExoColumn(Label = "Id")] string Id,
    [property: ExoColumn(Label = "Title", Sortable = true)] string Title,
    [property: ExoColumn(Label = "Description")] string Description,
    [property: ExoColumn(Label = "Event", Filterable = true)] string Trigger,
    [property: ExoColumn(Label = "Count needed", Sortable = true)] int Count);
```

Starting data belongs in `OnExtensionStart()`, which runs once after the extension is up. It must be safe to run on every start, which is why this one returns early when the table already has rows:

`extensions/achievements/src/AchievementsExtension.cs:30-39`
```csharp
    public void OnExtensionStart()
    {
        if (Exo.Database.All<AchievementDef>().Any()) return;

        Exo.Database.Put(new AchievementDef("slime_slayer", "Slime Slayer", "Defeat 3 slimes.", "enemy_slain", 3));
        Exo.Database.Put(new AchievementDef("treasure_hunter", "Treasure Hunter", "Open a chest.", "chest_opened", 1));
        Exo.Database.Put(new AchievementDef("explorer", "Explorer", "Enter 2 rooms.", "zone_entered", 2));
        Exo.Database.Put(new AchievementDef("diamond_hands", "Diamond Hands", "Make your first trade.", "trade_made", 1));
        Exo.Database.Put(new AchievementDef("level_maker", "Level Maker", "Publish a Doodle Dash level.", "level_published", 1));
    }
```

---

## 3. Call another extension

`brainrot_market` pays out through `wallet`. It does not open wallet's tables and does not know where it runs: it calls the typed stub `ExoServices.Wallet`, generated from wallet's manifest. The call goes through the same dispatcher and the same scope checks as a call from a client.

`extensions/brainrot_market/src/BrainrotMarketExtension.cs:185-189`
```csharp
    private static Task CreditAsync(string playerId, int amount, string reason) =>
        ExoServices.Wallet.CreditAsync(new WalletCreditRequest { PlayerId = playerId, Amount = amount, Reason = reason });

    private static Task DebitAsync(string playerId, int amount, string reason) =>
        ExoServices.Wallet.DebitAsync(new WalletDebitRequest { PlayerId = playerId, Amount = amount, Reason = reason });
```

---

## 4. Scheduled work

A cron is an action the server calls on a schedule (here every minute). It runs on the extension like any other action, so it can read and write the database and raise events.

`extensions/brainrot_market/src/BrainrotMarketExtension.cs:104-116`
```csharp
    [ExoCron("* * * * *", "tick_prices", Description = "Random-walks every meme stock and broadcasts the new prices.")]
    public async Task TickPrices()
    {
        var quotes = new List<Quote>();
        foreach (var stock in Exo.Database.All<MemeStock>())
        {
            var next = Walk(stock, Rng);
            Exo.Database.Put(next);
            quotes.Add(new Quote(next.Symbol, next.Price, stock.Price));
        }

        await Exo.Events.EmitAsync(new PricesTicked(quotes));
    }
```

---

## 5. Webhooks and secrets

An outside service (a store, a payment provider) cannot hold a player token, so a webhook action has its own scope and receives the raw request. This one checks an HMAC signature against a secret kept in a **singleton** resource (exactly one row, shown as a form in the Studio), refuses duplicates by receipt id, and only then credits the wallet.

`extensions/brainrot_market/src/BrainrotMarketExtension.cs:229-230`
```csharp
[ExoSingletonResource("storefront_config")]
public record StorefrontConfig(string Id, string Secret);
```

`extensions/brainrot_market/src/BrainrotMarketExtension.cs:118-135`
```csharp
    [ExoWebhook("storefront_purchase")]
    public async Task<WebhookResult> StorefrontPurchase(WebhookPayload payload)
    {
        var secret = Exo.Database.First<StorefrontConfig>()?.Secret ?? "";
        string? signature = null;
        payload.Headers?.TryGetValue("x-storefront-signature", out signature);
        if (!SignatureMatches(secret, payload.RawBody, signature))
            return new WebhookResult(401, "{\"error\":\"bad_signature\"}", false);

        var purchase = Receipt(payload.Json);
        if (Exo.Database.Get<StorefrontReceipt>(purchase.ReceiptId) != null)
            return new WebhookResult(200, "{\"status\":\"duplicate\"}", true);
        if (purchase.Coins <= 0 || string.IsNullOrEmpty(purchase.PlayerId))
            return new WebhookResult(400, "{\"error\":\"bad_receipt\"}", true);

        await CreditAsync(purchase.PlayerId, purchase.Coins, $"storefront_{purchase.ReceiptId}");
        Exo.Database.Put(purchase);
        return new WebhookResult(200, "{\"status\":\"credited\"}", true);
```

---

## Where to go next

- The [attribute reference](guide:03_csharp_attributes) lists every property used above.
- [Versions & Migrations](guide:04_versions_and_migrations) explains what happens when the data these extensions store has to change shape while players are online.
- The [standard extensions](guide:05_standard_extensions) list what ships with the server.
- Run the arcade yourself: clone the repository, build the extensions with `exo extension build`, push them with `exo extension push`, and open a project in Unity.
