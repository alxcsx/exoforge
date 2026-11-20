# Exoforge Arcade — worker brief

You are building one slice of **Exoforge Arcade**, a set of small game samples for the Exoforge
SDK. The games and their contracts are in **`/Users/alexcs/projects/exoforge-arcade/README.md`**.
Read it first, then your slice below.

There are two goals, equally important:
1. The samples work for a developer who has **only the SDK tarball**: no Exoforge repository.
2. Every inconsistency, contradiction, confusing point or wrong statement you hit — in the docs, the
   SDK, the CLI or the existing samples — is written down.

## Where things are

| What | Where |
| :--- | :--- |
| Samples project (Unity 6000.6, 2D URP, installed from the tarball) | `/Users/alexcs/projects/exoforge-arcade` |
| The SDK as the user gets it | `Packages/com.exoforge.sdk-0.1.41.tgz`, unpacked in `Library/PackageCache/com.exoforge.sdk@*/` |
| Docs the user gets | the package's `README.md`, `Agents~/AGENTS.md`, `Agents~/skills/*`, `Samples~/`, and the docs the cluster serves (Studio ▸ Docs, `http://localhost:4005`) |
| CLI the user gets | `./exo` at the project root if the SDK installed it, else `dotnet Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll` |
| Exoforge source (**read-only reference**) | `/Users/alexcs/projects/exoforge` |
| Temporary backend, already running | ws `ws://localhost:4000/ws`, http `http://localhost:4001`, Studio `http://localhost:4005`; admin `admin@arcade.local` / `arcade-admin-pass` |
| Your findings file | `/Users/alexcs/projects/exoforge/.agents/samples-findings/<your-slice>.md` |
| Findings already known (don't duplicate) | `/Users/alexcs/projects/exoforge/.agents/SAMPLES_FINDINGS.md` |

## Rules

1. **Tarball only.** Nothing in `exoforge-arcade` may reference a path in the Exoforge repo, use the
   repo's CLI (`dotnet run --project …/Exoforge.CLI`), its `just` recipes, or its NuGet feed. Build and
   deploy with the package's `exo`. Read the repo's source **only** to explain why something
   doesn't work, and log what you had to look up: a user couldn't have.
2. **Docs first, then code.** Write each piece the way the package docs say. When that fails or
   behaves differently, log a finding with the exact error, then do what actually works. Never pick
   the working variant silently.
3. **Don't edit the Exoforge repo** — except your own findings file. If a sample can't work without
   an SDK or server change, log it (`bug` / `missing`), skip that piece, and tell the orchestrator.
4. **Don't restart, reset or point anything at another backend.** Uploaded extensions disappear on a
   backend restart. Never use the `default` environment in `/Users/alexcs/projects/exotest` — it's a
   real remote cluster.
5. **Unity runs only through `tools/unity.sh`** (`tools/unity.sh` compiles; `tools/unity.sh Class.Method`
   runs an editor method). It serializes Unity runs. Never launch Unity any other way.
6. **Stay in your folders** (ownership below). Shared files have one owner; ask the orchestrator
   for a change to anything else.
7. Style, matching the SDK's Snake sample: minimal, readable, no comment noise, records for payloads,
   IMGUI, Input System (`Keyboard.current`), primitive shapes, no art. Extension classes end in
   `Extension`. Player-facing actions take identity from the caller context, never a `player_id`
   parameter. Trusted results (kills, chests) come only through `service`-scoped actions.
8. Gameplay never holds a client or token: one `…Bridge` per scene calls `ExoServices.*`.
9. **Tests:** each extension gets an xunit project `Exoforge/extensions/<name>.Tests/` using the SDK's
   `ExoTestHost` / `InMemory*` fakes, if a tarball user can reach them (log it if not). Then
   deploy to the backend and exercise it with `exo call`, and add your demo script as a function in
   `tools/smoke/<slice>.sh`.
10. **Don't commit.** The orchestrator verifies and commits.
11. When done or stuck: `hc send t7 "REPORT <slice>: <done|blocked>, tests: <cmd → result>, findings: <n>, notes: <file>"`.

## Findings format (your file)

```
### <slice>-<n> — <one-line title>
- **Kind**: bug | contradiction | confusing | doc-wrong | missing
- **Where**: doc or file:line, and what it disagrees with
- **What**: said vs. true, with evidence (command + output, or a code quote)
- **Impact**: who trips on it, how
- **Workaround in the sample**: none / what we did
- **Suggested fix**: one line
```

## Ownership

| Slice | Owner | Owns |
| :--- | :--- | :--- |
| orchestrator | t7 | `Assets/Samples/Common/`, `Assets/Editor/ArcadeSetup.cs`, `Exoforge/exoforge.json`, `Exoforge/extensions/*.sln`, `Assets/Exoforge/Generated/` (run `exo sync` freely; it is regenerated from the cluster), `tools/unity.sh`, `tools/smoke.sh`, `README.md` (send corrections) |
| economy | w-economy | `wallet`, `daily_rewards`, `brainrot_market` (+ `.Tests`), `Assets/Samples/BrainrotExchange/`, `tools/smoke/economy.sh` |
| dungeon | w-dungeon | `adventure_world` (+ `.Tests`), `Assets/Samples/EchoDungeon/` (incl. Editor-only `MockGameServer`), `tools/smoke/dungeon.sh` |
| doodle | w-doodle | `level_share` (+ `.Tests`), `Assets/Samples/DoodleDash/`, `tools/smoke/doodle.sh` |
| achievements | w-achievements | `achievements` (+ `.Tests`), `Assets/Samples/Common/AchievementToast.cs` (the one exception in Common), `tools/smoke/achievements.sh` |
| menu | w-menu | `game_menu` (+ `.Tests`), `Assets/Samples/MainMenu/`, `tools/smoke/menu.sh`, the debugging walkthrough in README §0 |
| audit | agy | read-only: `.agents/samples-findings/audit.md` |

Each scene folder holds its own `Editor/<Scene>Setup.cs` with a static `SetUp()` that builds
`Assets/Scenes/<Scene>.unity` from code (the Snake sample's `ExoforgeSampleSetup` is the pattern) and
is found by name: the class must be `Arcade.<Scene>.Editor.<Scene>Setup` (e.g. `Arcade.EchoDungeon.Editor.EchoDungeonSetup`).
`tools/unity.sh ArcadeSetup.SetUpAll` builds every scene that has a setup and the build settings list.
Scene code lives in namespace `Arcade.<Scene>`, with an asmdef `Samples.<Scene>` (+ `Samples.<Scene>.Editor`).
`Assets/csc.rsp` enables nullable reference types.

Shared pieces in `Assets/Samples/Common/` (orchestrator, ready before you need them):
`SamplePlayer` (two-stage sign-in with its own name prompt, survives scene loads; call
`SamplePlayer.WhenReady(session => …)` from your bridge), `Samples.Common.asmdef`.
Your scene's asmdef references it and `Exoforge.Generated`.

## Slices

**economy** — `wallet` first, and as early as possible: others depend on its contract.
Build it, then tell t7 so the others can generate stubs. Then `daily_rewards` and `brainrot_market`
per README §1. Questions to answer and log: which scope a call from one native extension to another
carries, and how to make `wallet.credit/debit` callable by extensions but not players; how a
client reads an `AllowPlayerRead` resource; how an `[ExoWebhook]` handler sees headers and the raw
body (verify the signature); `[ExoCron]` on a native extension (registration, `RunOnStartup`, running
it from Studio). Tests: claim twice, streak reset, idle cap from server time, buy/sell with and
without funds, price tick bounds, webhook signature valid/invalid, `debit` never negative.

**dungeon** — `adventure_world` per README §2, and the Echo Dungeon scene: a top-down room, sword,
slimes, chests, doors, and a feed of world events. The Editor-only `MockGameServer` (`#if UNITY_EDITOR`)
holds a `service`-role token read from a file under `Exoforge/` (never `Assets/`), reports the local
player's kills, and runs 2–3 bot adventurers on a timer. Questions: how to issue a `service` token
(`auth.issue_token`?), its lifetime, and where a developer is told about it; dynamic topics and who
may subscribe to what; whether `OnEvent` receives events from another *native* extension, and how
the manifest declares that. Tests: a player token is refused (`forbidden_scope`), events are emitted,
progress accumulates.

**doodle** — `level_share` per README §4, and the Doodle Dash scene: paint 32×18 on a `Texture2D`,
play it (simple platformer physics on the grid), publish, browse, play others' levels, rate.
`LevelImage` (pixels ↔ tiles) is pure and covered by a check. Questions: uploading to the file bucket
from Unity (tags, metadata, size limit, download by id); which HTTP route lists `browse` for `curl`.
Tests: publishing needs a recorded clear, rating averages, one rating per player per level, browse
sort and tag.

**achievements** — `achievements` per README §2: listens through `OnEvent` to `adventure_world`
(`enemy_slain`, `chest_opened`, `zone_entered`), `brainrot_market` (a trade event; agree on its name
with w-economy), and `level_share` (`level_published`). Definitions are Studio-editable rows seeded
in `OnExtensionStart`; each unlocks exactly once and raises `achievement_unlocked`.
`AchievementToast` is a drop-in component any scene adds. Start now against the contracts in the
README; build once the event sources exist. Coordinate event names directly
(`hc send w-economy …`, `hc send w-dungeon …`, `hc send w-doodle …`).

**menu** — `game_menu` per README §0 and the MainMenu scene: the hub that opens every other scene,
the news banner from the player-readable `menu_news`, name and coins (`wallet` — wait for w-economy's
contract), settings saved per player, and *Claim Gift*, which fails because of a Studio data row.
Write the debugging walkthrough in README §0 as the exact clicks, done for real against the Studio:
request id in the Unity log → timeline → capture → fix the row → replay.

**audit** (read-only) — Without building anything, read every doc a tarball user gets (package
`README.md`, `Agents~/**`, `Samples~/**`, the docs chapters the cluster serves) next to the SDK and
CLI code. Re-check F1–F12 in `SAMPLES_FINDINGS.md` and mark each *confirmed* / *resolved* / *changed*,
with evidence. Then log new findings: examples that don't compile, commands or flags that don't
exist, contradictions between docs, docs that need the repo. Also answer: how do two players run on
one machine with device-keyed login, and what does the developer have to do?
