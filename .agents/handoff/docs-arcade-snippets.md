# Arcade snippets

### 1. service declaration
`extensions/achievements/src/AchievementsExtension.cs:9-12`
```csharp
[ExoExtension("achievements", Version = "0.1.0", Category = "Game", Title = "Achievements", Icon = "🏆",
    Resources = [typeof(AchievementDef), typeof(AchievementProgress), typeof(AchievementUnlock)])]
public class AchievementsExtension
{
```
One sentence shows the pattern.

### 2. action with non-default Scope
`extensions/adventure_world/src/AdventureWorldExtension.cs:8-13`
```csharp
{
    [ExoAction(Scope = "service")]
    public AdventurerProgress ReportKill(string playerId, string name, string enemy, string zone)
    {
        var progress = Load(playerId, name);
        progress = progress with { Kills = progress.Kills + 1, UpdatedAt = Now() };
```
One sentence shows the pattern.

### 3. resource record
`extensions/achievements/src/AchievementsExtension.cs:83-90`
```csharp
[ExoResource("achievement_defs", PrimaryKey = nameof(Id), AllowPlayerRead = true)]
public record AchievementDef(
    [property: ExoColumn(Label = "Id")] string Id,
    [property: ExoColumn(Label = "Title", Sortable = true)] string Title,
    [property: ExoColumn(Label = "Description")] string Description,
    [property: ExoColumn(Label = "Event", Filterable = true)] string Trigger,
    [property: ExoColumn(Label = "Count needed", Sortable = true)] int Count);

```
One sentence shows the pattern.

### 5. cron
`extensions/brainrot_market/src/BrainrotMarketExtension.cs:104-106`
```csharp
    [ExoCron("* * * * *", "tick_prices", Description = "Random-walks every meme stock and broadcasts the new prices.")]
    public async Task TickPrices()
    {
```
One sentence shows the pattern.

### 6. cross-extension call
`extensions/brainrot_market/src/BrainrotMarketExtension.cs:184-192`
```csharp

    private static Task CreditAsync(string playerId, int amount, string reason) =>
        ExoServices.Wallet.CreditAsync(new WalletCreditRequest { PlayerId = playerId, Amount = amount, Reason = reason });

    private static Task DebitAsync(string playerId, int amount, string reason) =>
        ExoServices.Wallet.DebitAsync(new WalletDebitRequest { PlayerId = playerId, Amount = amount, Reason = reason });
}

public record Portfolio(IReadOnlyList<Holding> Holdings, int FarmLevel, int PendingIdleCoins);
```
One sentence shows the pattern.

### 7. singleton config
`extensions/world_boss/src/BossModels.cs:6-16`
```csharp
[ExoSingletonResource("boss_state")]
public record BossState(string Id /*always "current"*/, string BossId /*"boss-<unixtime>-<gen>"*/, string Name, int MaxHp, int Hp,
    string Status /*"alive"|"defeated"*/, string PayoutState /*"none"|"claimed"|"paid"*/, int Inflight, int Pool, int Generation, long SpawnedAt, long DefeatedAt);

[ExoResource("boss_damage", PrimaryKey = nameof(Id))]
public record BossDamage(string Id /*"{BossId}:{PlayerId}"*/, [property: ExoColumn(Filterable = true)] string BossId, string PlayerId, string Name, int Damage, int Hits, int Coins);

public record HitAck(bool Accepted, int Hp, int MaxHp, string Status);

public record BossLeader(string PlayerId, string Name, int Damage, int Coins);

```
One sentence shows the pattern.

### 8. OnExtensionStart
`extensions/achievements/src/AchievementsExtension.cs:30-40`
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
One sentence shows the pattern.

### 4. event declared and raised / handled
`extensions/achievements/src/AchievementsExtension.cs:69-72`
```csharp
[ExoEvent("enemy_slain", Topic = "world:feed")]
public record EnemySlain(string PlayerId);
[ExoEvent("chest_opened", Topic = "world:feed")]
public record ChestOpened(string PlayerId);
```
`{path}:41-46`
```csharp
    public void OnEvent(string name, JsonElement payload)
    {
        if (name == "achievement_unlocked") return;
        if (!payload.TryGetProperty("player_id", out var id) || id.GetString() is not { Length: > 0 } playerId) return;
        Apply(playerId, name);
    }
```
One sentence shows events.

### 9. Unity side
`2d-echo-dungeon/Assets/Samples/EchoDungeon/DungeonBridge.cs:15-26`
```csharp
        private void Start() => SamplePlayer.WhenReady(_ => Connect());

        private async void Connect()
        {
            var world = ExoServices.AdventureWorld;
            world.OnEnemySlain += e => _incoming.Enqueue($"{e.Name} slew a {e.Enemy} in {e.Zone}");
            world.OnChestOpened += e => _incoming.Enqueue($"{e.Name} opened a chest in {e.Zone} (+{e.Gold})");
            world.OnZoneEntered += e => _incoming.Enqueue($"{e.Name} entered {e.Zone}");

            try
            {
                await world.SubscribeAsync();
```
One sentence shows bridge calling ExoServices.
