# Snowball Siege: implementation plan

Repo `A=/Users/alexcs/projects/exoforge-arcade`, SDK repo `E=/Users/alexcs/projects/exoforge`. Spec: `A/README.md` section 3. Paths are relative to `A`. **NEW** = file does not exist yet.
Facts that drove the design (verified):
- `Exo.Database.Execute(sql, args)` returns the affected row count (`E/sdk/csharp/Exoforge.Plugin.SDK/Interfaces.cs:50`). Both adapters run one statement atomically: the SQLite adapter serializes through one connection per extension, Postgres takes a row lock. **There is no transaction API.**
- `InMemoryDatabase.Execute` returns 0 and `Query` returns nothing (`Testing.cs:75-79`), so SQL cannot be unit-tested. Every SQL path sits behind `IBossStore` and is proven by `boss.sh` on a real cluster.
- `wallet.credit` takes no idempotency key and is `Scope="server"` (extensions only). The payout key therefore needs a NEW wallet action `credit_once`.
- No cluster is running at plan time (`curl :4001` returned 000). Cluster steps belong to the orchestrator.

## 1. Contract: extension `world_boss` (NEW `extensions/world_boss/`)
`[ExoDependency("wallet")] [ExoExtension("world_boss", Version="0.1.0", Category="Game", Title="World Boss", Icon="❄️", Resources=[typeof(BossState), typeof(BossDamage)])]`, namespace `Exoforge.Extensions`, class `WorldBossExtension`.

Records (ints are INTEGER, times are unix seconds `long`/BIGINT, no bool or DateTime columns, so SQLite and Postgres map identically):
```csharp
[ExoSingletonResource("boss_state")]
public record BossState(string Id /*always "current"*/, string BossId /*"boss-<unixtime>-<gen>"*/, string Name, int MaxHp, int Hp,
  string Status /*"alive"|"defeated"*/, string PayoutState /*"none"|"claimed"|"paid"*/, int Inflight, int Pool, int Generation, long SpawnedAt, long DefeatedAt);
[ExoResource("boss_damage", PrimaryKey = nameof(Id))]
public record BossDamage(string Id /*"{BossId}:{PlayerId}"*/, [property: ExoColumn(Filterable = true)] string BossId, string PlayerId, string Name, int Damage, int Hits, int Coins);
public record HitAck(bool Accepted, int Hp, int MaxHp, string Status);
public record BossLeader(string PlayerId, string Name, int Damage, int Coins);
public record BossView(string BossId, string Name, int MaxHp, int Hp, string Status, string PayoutState, long SpawnedAt, int TotalDamage, int MyDamage, int MyCoins, IReadOnlyList<BossLeader> Top /*5, damage desc then player_id asc*/);
[ExoEvent("boss_spawned",  Topic="world_boss:live")] public record BossSpawned(string BossId, string Name, int MaxHp, long Timestamp);
[ExoEvent("boss_damaged",  Topic="world_boss:live")] public record BossDamaged(string BossId, string PlayerId, string Name, int Damage, int Hp, int MaxHp, long Timestamp);
[ExoEvent("boss_defeated", Topic="world_boss:live")] public record BossDefeated(string BossId, string Name, int MaxHp, int TotalDamage, int Pool, IReadOnlyList<BossLeader> Payouts, long Timestamp);
```
Constants: `MaxHit=100`, `DefaultMaxHp=1000`, `DefaultPool=1000`, `StaleSeconds=60`, `BossNames={"Frostbeard","Sir Meltsalot","Old Man Winter"}` (`Generation % 3`). `public static Func<long> Now` is overridable by tests. `BossStore.Current` is a static `IBossStore`, default `SqlBossStore`.

Actions:
| action | scope | signature | behaviour |
| :-- | :-- | :-- | :-- |
| `report_hit` | service | `Task<HitAck> ReportHit(string playerId, string name, int damage)` | `damage` outside 1..MaxHit throws `invalid_damage`; empty `playerId` throws `invalid_player`. No boss or not alive: `Accepted=false` (no exception, no event). Otherwise the hit sequence below. |
| `get_state` | player | `Task<BossView> GetState()` | caller from `Exo.Context.CallerPlayerId` (empty throws `unauthorized`). No boss row: spawn first. Reads only. |
| `spawn_boss` | service | `Task<BossView> SpawnBoss(int maxHp, bool force)` | NOT in the README table (deviation, added to it in WP10). Needed so `boss.sh` has a deterministic boss. maxHp 100..100000 else `invalid_hp`. Without force it only spawns when no boss, or defeated and paid; otherwise throws `boss_alive`. |
| `respawn_boss` | cron | `[ExoCron("*/10 * * * *","respawn_boss")] Task RespawnBoss()` | The same code runs from `OnExtensionStart()`. No boss: spawn. Alive: leave it (no hits means nothing happens: no payout, no event, hp stays). Defeated and `none` older than StaleSeconds: force-claim and pay. Defeated and `claimed` older than StaleSeconds: re-run payout (wallet dedupes). Defeated and `paid`: spawn the next generation. |

Hit sequence (all SQL uses `$1..$n`, no GREATEST/LEAST/RETURNING/bool; CASE only, so it runs unchanged on both adapters):
1. `b = store.Current()`. `store.TryApplyHit(b.BossId, damage, now)` runs
   `UPDATE boss_state SET hp = CASE WHEN hp > $2 THEN hp - $2 ELSE 0 END, status = CASE WHEN hp > $2 THEN 'alive' ELSE 'defeated' END, defeated_at = CASE WHEN hp > $2 THEN defeated_at ELSE $3 END, inflight = inflight + 1 WHERE id='current' AND boss_id=$1 AND status='alive'`.
   It returns `Execute(...)==1`. 0 means `Accepted=false`. HP is floored at 0 by the CASE, and a hit on a dead boss matches no row. Credited damage is the reported damage (smoke uses multiples so the total equals MaxHp).
2. `AddDamage` upserts the ledger: `INSERT INTO boss_damage (id,boss_id,player_id,name,damage,hits,coins) VALUES ($1,$2,$3,$4,$5,1,0) ON CONFLICT(id) DO UPDATE SET damage = boss_damage.damage + excluded.damage, hits = boss_damage.hits + 1, name = excluded.name`.
3. `Release`: `UPDATE boss_state SET inflight = inflight - 1 WHERE id='current' AND boss_id=$1`. Emit `boss_damaged` with a re-read `Current()` for hp.
4. `TryClaimPayout(bossId, force:false)`: `UPDATE boss_state SET payout_state='claimed' WHERE id='current' AND boss_id=$1 AND status='defeated' AND payout_state='none' AND inflight=0`. The `force` variant (cron only, after StaleSeconds) drops the `inflight=0` clause. Exactly one caller sees 1; that caller pays. The `inflight` counter keeps the winner from reading the ledger before a slower accepted hit has written its row.
5. Payout (`Pay(bossId)`, idempotent, re-runnable): `rows = Ledger(bossId)` ordered damage desc then player_id asc, `total = sum(Damage)`, and `total==0` means no payouts. `share_i = floor(Pool * Damage_i / total)` (use `long` arithmetic). The remainder `Pool - sum(share)` goes to rows[0], so the shares sum to exactly Pool. Rows with a share of 0 are skipped. For each: `await ExoServices.Wallet.CreditOnceAsync(new WalletCreditOnceRequest{PlayerId, Amount, Reason="world_boss:"+bossId, Key="payout:"+bossId+":"+playerId})`, then `SetLedgerCoins`. Finally `MarkPaid` (`UPDATE ... SET payout_state='paid' WHERE ... AND payout_state='claimed'`, 1 means emit `boss_defeated` with Payouts). Exactly-once rests on the single claim winner plus the wallet key. The remaining crash window (credit applied, key not yet stored) is sub-millisecond and documented in the code comment.
6. Spawn (`store.Spawn(next)` is `Exo.Database.Put(next)`): `Hp=MaxHp, Status="alive", PayoutState="none", Inflight=0, Pool=DefaultPool, Generation+1`, then emit `boss_spawned`.

Adapter choice: single conditional `UPDATE` statements, with `Execute`'s row count as the winner signal, rather than read-modify-write with `Put` (a lost update under concurrency) or a lock table (needs a transaction). `Put` is only used for first spawn/respawn. Typed columns come from the declared resources, so raw SQL needs real tables (the adapters fall back to the `kv` table only for undeclared tables, `sqlite.ex:187-197`). Risk: an `Execute` that returns rows instead of a count (see Risks).

`wallet.credit_once` (WP1, `Scope="server"`): `WalletBalance CreditOnce(string playerId, int amount, string reason, string key)`. Empty key throws `invalid_key`; amount<=0 throws `invalid_amount`; if `Exo.Database.Get<WalletCreditKey>(key)` exists it returns the current balance unchanged. Otherwise credit, then `Put(new WalletCreditKey(key, playerId, amount, now))`. New resource `[ExoResource("wallet_credit_keys", PrimaryKey=nameof(Key))] record WalletCreditKey(string Key, string PlayerId, int Amount, long At)`. `credit` and `debit` are untouched, so the other stubs stay valid.

## 2. Unity project `3d-snowball-siege` (NEW)
- **Pipeline**: built-in 3D (`Unity -createProject` default). URP (what the 2D projects carry) buys nothing for primitives and needs a pipeline asset to avoid pink materials. IMGUI works in either. Input System 1.20.0 (`activeInputHandler: 1`, the 2D projects' value).
- **Packages**: `Packages/manifest.json` = the 2d-echo-dungeon manifest minus every `com.unity.2d.*` key and `com.unity.render-pipelines.universal`. It keeps `"com.exoforge.sdk": "file:com.exoforge.sdk-0.1.52.tgz"` and `"com.exoforge.arcade.common": "file:../../packages/exoforge.arcade.common"`. The shared package is reused (`SamplePlayer`, `AchievementToast`; it only needs the Input System). `tools/sync-sdk.sh` and `tools/unity.sh` pick the project up through their `*/Packages/manifest.json` and `*/ProjectSettings` globs, so **no tooling change**.
- **Files** (all NEW, folder `Assets/Samples/SnowballSiege/`, namespace `Arcade.SnowballSiege`): `Samples.SnowballSiege.asmdef` (refs Exoforge.SDK, Exoforge.Generated, Samples.Common, Unity.InputSystem; copy the echo one), `BossGame.cs`, `PlayerRig.cs`, `Snowball.cs`, `BossTarget.cs`, `BossBridge.cs`, `MockGameServer.cs`, `Editor/Samples.SnowballSiege.Editor.asmdef`, `Editor/SnowballSiegeSetup.cs`, `Assets/Editor/ArcadeSetup.cs` (echo copy, `SceneOrder={"SnowballSiege"}`), `Assets/csc.rsp` (`-nullable:enable`), `Exoforge/exoforge.json.example` (echo copy, `project_name` `ExoforgeArcadeSnowballSiege`), `Assets/Resources/exoforge.json` (echo copy). Generated by tools and then committed: `Assets/Exoforge/Generated/*`, `Exoforge/.contracts_cache.json`, `Packages/packages-lock.json`, `Assets/Scenes/SnowballSiege.unity`, `ProjectSettings/*`, and the SDK-written `.gitignore`.
- **Gameplay** (Snake-sized, about 350 lines in all, no art assets):
  - `BossGame : MonoBehaviour` holds `[SerializeField] Material snowballMaterial`; `public bool BossAlive`, `int Hp, MaxHp`, `string BossName`; `event Action<int,string> SnowballHit` (damage, part); `void ApplyState(string name,int hp,int maxHp,bool alive)`, `PushFeed(string)` (8 lines), `ShowPayout(int coins)` (toast 6 s). `OnGUI`: boss bar (`GUI.DrawTexture` + `Texture2D.whiteTexture`) with name and "hp/max", crosshair, feed bottom-left, payout toast top-center, a "MOCK GAME SERVER (editor only)" label, `SamplePlayer.Instance.Status`.
  - `PlayerRig`: WASD (`Keyboard.current`) at 6 m/s clamped to radius 18, look from `Mouse.current.delta` (0.1 deg/px, pitch ±80), left click fires with a 0.4 s cooldown, Esc releases the cursor and a click re-locks it. Fire = `GameObject.CreatePrimitive(Sphere)` scale 0.3, `Rigidbody` (mass 0.2, continuous), velocity `camera.forward*24`, `Destroy(go,5)`, material `snowballMaterial`.
  - `Snowball.OnCollisionEnter`: with a `BossTarget` and `game.BossAlive`, it calls `game.SnowballHit?.Invoke(target.Damage, target.Part)` and destroys itself. Head damage 30, body 10, base 5. **Hit detection is local**, so it stands in for the dedicated server's verdict. Only `MockGameServer` listens to `SnowballHit`.
  - `BossBridge : MonoBehaviour` is the **only** caller of `ExoServices.*`. `SamplePlayer.WhenReady` then `ExoServices.WorldBoss.OnBossSpawned/OnBossDamaged/OnBossDefeated` push onto a `ConcurrentQueue`. `await SubscribeAsync(); var s = await GetStateAsync();` and `Update()` drains the queue into `game.ApplyState/PushFeed/ShowPayout`. The payout toast shows when `Payouts` contains `session.PlayerId`. Same shape as `2d-echo-dungeon/Assets/Samples/EchoDungeon/DungeonBridge.cs`. Verify the exact generated member names with `grep -n "WorldBoss" Assets/Exoforge/Generated/ExoforgeServices.g.cs`.
  - `MockGameServer` is `#if UNITY_EDITOR`, class summary "Stands in for the dedicated game server; never ships", with a copy of the echo `MockGameServer.cs` structure. It reads `Exoforge/mock-game-server.token` (git-ignored, project root, never `Assets/`), `ExoClient{HttpBaseUri}.UseToken(token)`, listens to `game.SnowballHit` and calls `SendActionAsync<HitAck>("world_boss","report_hit",{player_id,name,damage})` for the real player. Every 1.5 s ±50 % it reports a hit from `bot-0..2` ("Bot Ada/Brom/Cinder", damage 10 or 30). Without the token it logs a warning and disables itself, so the game runs offline. **Token path**: the orchestrator copies `2d-hub/Exoforge/mock-game-server.token` (the same service account; created once with `./exo user create ... --role service`, see `tools/smoke/dungeon.sh`) into `3d-snowball-siege/Exoforge/`. It is covered by the existing `**/Exoforge/mock-game-server.token` ignore rule. The token is editor-only: a player build has none, by design.
  - `SnowballSiegeSetup.SetUp()` (`[MenuItem("Arcade/Set Up Snowball Siege")]`): `EditorSceneManager.NewScene(NewSceneSetup.EmptyScene)`; materials as assets in `Assets/Samples/SnowballSiege/Materials/` (white snow, orange carrot, black coal, blue ground; Standard shader via `AssetDatabase.CreateAsset`); ground cube `(40,1,40)` at y -0.5; boss at `(0,0,12)` from 3 spheres (body scale 6 y 3, torso 4.5 y 7.5, head 3 y 10.6 = Head part), two coal spheres, a carrot cylinder, all with `SphereCollider` + `BossTarget`; a directional light; the rig `Player` at `(0,1.7,-8)` with a child Camera (tag MainCamera) and a launcher cylinder at `(0.35,-0.3,0.6)`; a `SnowballSiege` object with `BossGame`, `PlayerRig`, `BossBridge`, `MockGameServer`, `AchievementToast` (via `Type.GetType` as in echo); serialized references via `SerializedObject`; saves `Assets/Scenes/SnowballSiege.unity`.
  - Headless: `tools/unity.sh 3d-snowball-siege ArcadeSetup.SetUpAll` ends with `[Arcade] SnowballSiege: set up`.

## 3. Smoke: `tools/smoke/boss.sh` (NEW) and wiring
Same structure as `tools/smoke/dungeon.sh`: `boss(){...}` with the `post/login/ok/fail` helpers, token from `${SMOKE_PROJECT:-2d-hub}/Exoforge/mock-game-server.token`, `[ "${BASH_SOURCE[0]}" = "$0" ] && boss`. Steps, each asserting:
1. Three disposable players A, B, C log in (`/api/auth/anonymous`), each with its own token, and each records `wallet/get_balance` coins (c0).
2. A player token on `world_boss/report_hit` or `spawn_boss` is refused with `forbidden_scope`.
3. `spawn_boss {max_hp:300,force:true}` as the server; `get_state` as A has `hp==300 status==alive`.
4. **Concurrent burst**: 40 `report_hit` calls with damage 10 (A x20, B x12, C x8) fired with `&` and `wait`. Afterwards: accepted == 30, rejected == 10, `hp==0` and never negative.
5. Poll `get_state` (up to 10 s) until `payout_state=="paid"`. Assert `status==defeated`, `total_damage==300`, and the Top leaders' `damage` values sum to 300.
6. Python recomputes the payout (formula above, pool 1000, remainder to the top damager, tie broken by player_id asc). Each player's balance delta must equal the expected share, and the Top `coins` must match.
7. Exactly once: 5 more hits are all rejected, sleep 2 s, and balances are unchanged.
`tools/smoke.sh`: the default list becomes `economy dungeon achievements doodle menu boss` (and the header comment). Nothing else changes. Run `tools/smoke.sh boss` against the cluster on **SQLite** (default, with `EXOFORGE_DATA_DIR` set to a temp dir), then once on **Postgres** (`just compose-up` in `E`; the justfile at `E/justfile:170-205`), both must print `=== boss: ok`.

## 4. Docs and tooling
- No SDK change, no `exoforge` AGENTS.md change, no tooling change (arcade has no AGENTS.md; confirm with `ls A/AGENTS.md`). README touch-ups are in WP10.

## 5. Work packages
Format: owner | files (may create or edit, nothing else) | deps | parallel | acceptance.

**WP1 wallet.credit_once** | agy:gpt-oss | `extensions/wallet/src/WalletExtension.cs`, `extensions/wallet.Tests/WalletTests.cs` | none | yes
Add `CreditOnce` plus the `WalletCreditKey` resource (section 1) and tests: same key twice credits once, empty key throws `invalid_key`.
`cd extensions && dotnet test wallet.Tests` prints `Passed!` with 0 failed.

**WP2 world_boss models and store** | agy:sonnet | NEW `extensions/world_boss/src/world_boss.csproj` (copy adventure_world's, `ExoforgeExtension`, `Exoforge.Plugin.SDK` Version equals the other csprojs), NEW `extensions/world_boss/src/BossModels.cs` (records and events, section 1), NEW `extensions/world_boss/src/BossStore.cs` (`IBossStore` and `SqlBossStore`), `extensions/Exoforge.Extensions.sln` | none | yes
```csharp
public interface IBossStore { BossState? Current(); bool TryApplyHit(string bossId,int damage,long now); void AddDamage(string bossId,string playerId,string name,int damage);
  void Release(string bossId); bool TryClaimPayout(string bossId,bool force); IReadOnlyList<BossDamage> Ledger(string bossId);
  void SetLedgerCoins(string bossId,string playerId,int coins); bool MarkPaid(string bossId); void Spawn(BossState next); }
```
The SQL is exactly as in section 1. `Current` is `Exo.Database.First<BossState>()`. Add the project with `dotnet sln extensions/Exoforge.Extensions.sln add extensions/world_boss/src/world_boss.csproj`.
`cd extensions && dotnet build world_boss/src/world_boss.csproj` prints `0 Error(s)`.

**WP3 WorldBossExtension logic** | agy:sonnet | NEW `extensions/world_boss/src/WorldBossExtension.cs` | WP2, WP1 stubs (WP2b below) | no
Actions, cron, `OnExtensionStart`, hit sequence, payout and spawn exactly as in section 1. `public static IBossStore Store {get;set;} = new SqlBossStore(); public static Func<long> Now {get;set;}`. Every payout step carries the crash-window comment.
`dotnet build world_boss/src/world_boss.csproj` is clean and `extensions/world_boss/manifest.json` lists `report_hit`, `get_state`, `spawn_boss` and cron `respawn_boss`: `python3 -c "import json;m=json.load(open('extensions/world_boss/manifest.json'));print([a['name'] for a in m['services'][0]['actions']])"`.

**WP2b world_boss stubs** | agy:sonnet | NEW `extensions/world_boss/src/Generated/PluginServices.g.cs` | WP1, WP2 | no (blocks WP3, which uses `ExoServices.Wallet`)
Build wallet (so its manifest has `credit_once`), then `cd 2d-hub && ./exo extension stubs world_boss --dir Exoforge`. If that needs a cluster, start it, or hand-copy `extensions/brainrot_market/src/Generated/PluginServices.g.cs` (header intact) and add `WalletCreditOnceRequest{PlayerId,Amount,Reason,Key}` plus `CreditOnceAsync` to `IWalletService` and its client.
`grep -c CreditOnceAsync extensions/world_boss/src/Generated/PluginServices.g.cs` prints `2` or more.

**WP4 world_boss tests** | copilot | NEW `extensions/world_boss.Tests/world_boss.Tests.csproj` (copy brainrot_market.Tests', reference `../world_boss/src/world_boss.csproj`), NEW `extensions/world_boss.Tests/WorldBossTests.cs`, `extensions/Exoforge.Extensions.sln` | WP3 | yes (with WP5)
Test-only `MemoryBossStore : IBossStore` (a `lock` implements the same semantics) and a `FakeWallet : IWalletService` that dedupes by `Key` (style of `BrainrotMarketTests.cs`). Tests: HP floor at 0 and a hit on a dead boss is `Accepted=false`; no hits means no events and no payout; a 100 Task burst gives exactly one `boss_defeated` and the credits sum to Pool; the remainder goes to the top damager; the 3 payout shares for damage 100/100/100 and Pool 1000 are 334/333/333; `respawn_boss` leaves an alive boss alone and spawns after paid; player scope refused for `report_hit` (scope check via manifest attribute only); `spawn_boss` without force on an alive boss throws `boss_alive`.
`cd extensions && dotnet test world_boss.Tests` prints `Passed!` with at least 8 tests, and `dotnet test Exoforge.Extensions.sln` ends with 0 failed.

**WP5 smoke script** | agy:gpt-oss | NEW `tools/smoke/boss.sh`, `tools/smoke.sh` | WP3 (to run live; may be written earlier) | yes
Implement section 3. `bash -n tools/smoke/boss.sh` prints nothing. Live (orchestrator): `tools/smoke.sh boss` ends with `all samples ok`.

**WP6 Unity project scaffold** | agy:sonnet | the project root folder and the files in section 2 that are neither C# gameplay nor generated: `3d-snowball-siege/Packages/manifest.json`, asmdefs, `Assets/csc.rsp`, `Assets/Resources/exoforge.json`, `Exoforge/exoforge.json.example`, `Assets/Editor/ArcadeSetup.cs` | none | yes
1. `/Applications/Unity/Hub/Editor/6000.6.3f1/Unity.app/Contents/MacOS/Unity -batchmode -nographics -quit -createProject /Users/alexcs/projects/exoforge-arcade/3d-snowball-siege -logFile -`.
2. Replace the manifest with the filtered echo manifest (a python filter), then `grep -n activeInputHandler 3d-snowball-siege/ProjectSettings/ProjectSettings.asset`. If it is not 1, `sed -i '' 's/activeInputHandler: .*/activeInputHandler: 1/'` on that file.
3. `cp 2d-echo-dungeon/Packages/com.exoforge.sdk-0.1.52.tgz /tmp/sdk.tgz`, then `tools/sync-sdk.sh /tmp/sdk.tgz`. **Never pass a tarball that lives inside a project: the script `rm`s it first.**
4. `tools/unity.sh 3d-snowball-siege` ends with `exit 0`. The compile will only pass once the asmdef references exist (WP7).
`grep -c com.exoforge.sdk 3d-snowball-siege/Packages/manifest.json` prints `1`, and `./exo` appears at the project root after the first open.

**WP7 cluster deploy and client generation** | agy:sonnet using the cluster recipe of `.agents/tasks/arcade-postgres-3.json` (fresh data dir + fresh service token; the orchestrator reviews) | NEW `3d-snowball-siege/Assets/Exoforge/Generated/*`, `3d-snowball-siege/Exoforge/.contracts_cache.json` | WP1, WP3, WP6 | no
In `3d-snowball-siege`: `./exo connect ... --save --dir Exoforge`; push `wallet` then `world_boss` (`./exo extension push <e> --dir Exoforge`); `./exo sync --dir Exoforge`; `cp 2d-hub/Exoforge/mock-game-server.token Exoforge/`.
`grep -c "WorldBoss" 3d-snowball-siege/Assets/Exoforge/Generated/ExoforgeServices.g.cs` prints at least 1.

**WP8 gameplay** | agy:sonnet | NEW `BossGame.cs`, `PlayerRig.cs`, `Snowball.cs`, `BossTarget.cs` (folder `3d-snowball-siege/Assets/Samples/SnowballSiege/`) | WP6 | yes
Exactly as in section 2 (about 220 lines in all). No file here may mention `Exoforge.Client` or `ExoServices`: `grep -rn "ExoServices\|Exoforge.Client" 3d-snowball-siege/Assets/Samples/SnowballSiege/{BossGame,PlayerRig,Snowball,BossTarget}.cs` prints nothing.

**WP9 bridge and mock server** | agy:sonnet | NEW `BossBridge.cs`, `MockGameServer.cs` (same folder) | WP7, WP8 | yes (with WP10)
Section 2. `grep -rln "ExoServices" 3d-snowball-siege/Assets/Samples` lists only `BossBridge.cs`, and `grep -c "UNITY_EDITOR" MockGameServer.cs` prints 2 or more. `tools/unity.sh 3d-snowball-siege` ends with no `error CS` lines and `exit 0`.

**WP10 scene setup** | agy:sonnet | NEW `Editor/SnowballSiegeSetup.cs` | WP8, WP9 | no
Section 2. `tools/unity.sh 3d-snowball-siege ArcadeSetup.SetUpAll` prints `[Arcade] SnowballSiege: set up` and `Assets/Scenes/SnowballSiege.unity` exists.

**WP11 docs** | agy:gpt-oss | `README.md`, `packages/exoforge.arcade.common/package.json` | none | yes
README: row 3 and the section-3 table gain `spawn_boss` (service), `boss_spawned`, and `wallet.credit_once`; the wallet row of section 1 gains `credit_once` (extensions only); the Layout block gains `3d-snowball-siege/`; the Running step 3 gains `tools/unity.sh 3d-snowball-siege ArcadeSetup.SetUpAll`; "all five samples" becomes "all six"; the test count is updated to the real number from `dotnet test`. The package description changes to "shared by the arcade projects". Keep "It's a separate project because this one is set up for 2D rendering only". No co-author trailers.
`grep -c "3d-snowball-siege" README.md` prints 3 or more.

## 6. Merge order
WP1 + WP2 + WP6 + WP11 (parallel) → WP2b → WP3 → WP4 + WP5 + WP8 (parallel) → WP7 (orchestrator, cluster) → WP9 → WP10 → final gate: `cd extensions && dotnet test Exoforge.Extensions.sln`, `tools/smoke.sh` on SQLite and again on Postgres, then `tools/unity.sh 3d-snowball-siege ArcadeSetup.SetUpAll`. One commit per WP, no co-author trailers. Run Unity once at a time (the `tools/unity.sh` lock).

## 7. Risks (and how to check)
1. **`Execute` row count on the real adapters**: SQLite `num_rows = max(rows, changes)` (`sqlite.ex:107`), so a statement that also returns rows could misreport. The statements are plain UPDATE/INSERT, so counts should be right; the burst in `boss.sh` (accepted must be exactly 30) is the proof, on both SQLite and Postgres.
2. **Unit tests cannot see SQL**: `MemoryBossStore` proves the state machine only. Insist that `boss.sh` ran against both adapters before sign-off.
3. **Table not typed**: if the `boss_damage` upsert reports a missing column, the resource table was not created from the manifest (a stale deploy). Check with `./exo call` on the Studio data view, then redeploy `world_boss`.
4. **Stub generation offline**: `exo extension stubs` may need the cluster; the hand-copy fallback exists. Check that `world_boss` compiles against `ExoServices.Wallet.CreditOnceAsync`.
5. **Unity compile before client generation**: the asmdef references `Exoforge.Generated`, which only exists after WP7. Do not ask agents to compile before then; gameplay files stay free of Exoforge types.
6. **`-createProject` template and input handler**: the default may be "both" or the old handler. The `grep activeInputHandler` step in WP6 is mandatory, or `Keyboard.current` is null and the player cannot move.
7. **Materials lost on save**: scene-embedded `new Material` is not serialized. The setup must create material assets (above); open the scene and check nothing is pink.
8. **sync-sdk deleting its own source** (WP6 step 3), and `README` counts going stale.
9. **Idle boss**: an alive boss never respawns by design. If `get_state` shows `alive` after the 10 minute cron, that is correct, not a bug; `boss.sh` forces a spawn.
10. **Concurrency in the native host**: if the host serializes sync actions, the burst proves little. The `inflight` counter remains correct either way; check that the smoke ran with `&` (really parallel) by looking at the timestamps in the extension logs.

## 8. NEW files (list)
`extensions/world_boss/src/{world_boss.csproj,BossModels.cs,BossStore.cs,WorldBossExtension.cs,Generated/PluginServices.g.cs}`, `extensions/world_boss.Tests/{world_boss.Tests.csproj,WorldBossTests.cs}`, `tools/smoke/boss.sh`, and under `3d-snowball-siege/`: `Packages/manifest.json`, `Assets/csc.rsp`, `Assets/Resources/exoforge.json`, `Exoforge/exoforge.json.example`, `Assets/Editor/ArcadeSetup.cs`, `Assets/Samples/SnowballSiege/{Samples.SnowballSiege.asmdef,BossGame.cs,PlayerRig.cs,Snowball.cs,BossTarget.cs,BossBridge.cs,MockGameServer.cs,Editor/Samples.SnowballSiege.Editor.asmdef,Editor/SnowballSiegeSetup.cs}`, plus generated: `Assets/Exoforge/Generated/*`, `Assets/Scenes/SnowballSiege.unity`, `ProjectSettings/*`.
Existing files edited: `extensions/wallet/src/WalletExtension.cs`, `extensions/wallet.Tests/WalletTests.cs`, `extensions/Exoforge.Extensions.sln`, `tools/smoke.sh`, `README.md`, `packages/exoforge.arcade.common/package.json`.
