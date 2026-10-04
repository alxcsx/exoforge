# Sample Unity Snake — AGENTS.md

A 2D Snake game that shows the whole Exoforge loop end to end: sign a player in, play locally,
and keep the high score on the server so the leaderboard is **shared between every player**.

The game itself is a normal Unity project. Everything Exoforge-specific is either a thin
controller, the workspace folder, or the server plugin.

---

## 1. What the game does

1. **Prompt for a name.** On start the player is signed in anonymously and, if the account has no
   display name yet, asked for one. This is the only thing the player is asked before playing.
2. **Play.** Classic Snake — grid movement, apples, wall/self collision. Runs entirely in Unity.
3. **Score.** When a run ends the score is sent to the server. The server keeps each player's
   **best** score and serves a leaderboard that all players see.

So: the *name* and the *high score* live on the server; the *game loop* lives in Unity.

---

## 2. Structure

```
sample_unity/
├── Assets/
│   ├── SnakeGame/
│   │   ├── SnakePlayerController.cs   stage 1+2 sign-in, gates gameplay until named
│   │   └── SnakeGameController.cs     the game loop + RunEnded(score, length) hook
│   ├── Exoforge/Generated/
│   │   └── ExoforgeServices.g.cs      GENERATED — do not hand-edit
│   ├── Resources/exoforge.json        workspace config linked for runtime (generated)
│   ├── Scenes/SampleScene.unity       Player + Gameplay + camera/light
│   ├── Editor/ExoforgeSampleSetup.cs  one-shot scene wiring (see §5)
│   └── csc.rsp                        -nullable:enable for Assembly-CSharp
│
├── Exoforge/                          the Exoforge workspace (OUTSIDE Assets/)
│   ├── exoforge.json                  environments + codegen paths
│   └── plugins/snake_leaderboard/     the server plugin (a dotnet project)
│       ├── SnakeLeaderboardPlugin.cs  the whole plugin, in C#
│       ├── snake_leaderboard          the built NativeAOT binary
│       └── manifest.exs               GENERATED from the C# attributes
└── Packages/manifest.json             references com.exoforge.sdk (file:../../Exoforge.SDK)
```

**Why the workspace is outside `Assets/`:** plugin sources are ordinary `dotnet` projects
(`net10.0`, NativeAOT). Keeping them out of `Assets/` means Unity never imports, compiles, or
adds `.meta` files to them, and they can use any .NET/C# version. Only two things must live under
`Assets/`: the **generated client** and the **runtime config**.

### Scene

| Object | Component | Role |
| :--- | :--- | :--- |
| `Player` | `SnakePlayerController` | signs in, prompts for the name, activates `Gameplay` |
| `Gameplay` | `SnakeGameController` | the game; starts **inactive** until the player is named |
| `Main Camera`, `Global Light 2D` | — | 2D scene furniture |

There is **no Exoforge prefab in the scene** — `ExoforgeSDK` creates the runtime host on demand.
Adding one is optional and only needed to override connection settings per scene.

---

## 3. The sign-in flow (two stages)

```csharp
// Stage 1 — enter or register the account. Keyed by the device, not the name.
var session = await ExoforgeSDK.Auth.LoginAnonymously();

// Stage 2 — only if this account has no display name yet.
if (!session.HasDisplayName)
    session = await ExoforgeSDK.Auth.SetDisplayName("Viper");
```

- `LoginAnonymously()` never asks for a name. `ExoDeviceId` derives a stable, hashed id from
  `SystemInfo.deviceUniqueIdentifier` and caches it, and that id is the account key — the same
  machine always resolves to the same player, even after losing local storage.
- `SetDisplayName(name)` names the signed-in player. The server takes the player from the caller's
  identity, so a player can only name themselves.
- Gameplay stays disabled until both stages succeed (`SnakePlayerController.enableOnReady`).

`ExoTokenStore` is public but low-level — use `ExoforgeSDK.Auth`.

---

## 4. The server side

`snake_leaderboard` is a **native C# plugin** (no WASM, no C). It is the only server code:

| Action | Params | Behaviour |
| :--- | :--- | :--- |
| `submit_score` | `player_id, name, score, snake_length` | stores the run, keeps the player's **best** score, returns it |
| `get_leaderboard` | `limit` | returns the top-`limit` rows, highest score first |

Rows live in the plugin's isolated database (through the host KV bridge) under the `snake_scores`
resource, so the Studio also shows a table. The leaderboard is therefore **shared state**: every
player reads and writes the same ranking.

`player_id` is taken from the caller's identity, so a client can only submit its own score.

---

## 5. Working on it

```bash
just dev                      # backend on :4000 (ws) / :4001 (http) / :4005 (studio)

# The `exo` CLI is not installed on PATH — run it from the repo:
CLI="dotnet run --project <repo>/sdk/csharp/Exoforge.CLI --"

$CLI plugin build snake_leaderboard    # NativeAOT binary + manifest.exs from the C# attributes
$CLI plugin push  snake_leaderboard    # build + deploy to the running cluster
$CLI sync                              # regenerate Assets/Exoforge/Generated/ExoforgeServices.g.cs
```

From the Unity Editor, `Tools ▸ Exoforge ▸ …` covers the same ground: **Sync Client Bindings**
(regenerate), **Add Exoforge to Scene** (add the optional prefab), **Control Center** (connect,
deploy, inspect).

`ExoforgeSampleSetup` has no menu item — it is a one-shot batch entry point, only needed to rebuild
the scene from scratch:

```bash
Unity -batchmode -quit -projectPath <this project> -executeMethod ExoforgeSampleSetup.SetUp
```

The committed scene is already wired, so a normal session never runs it.

Rules of thumb:

- **Never hand-edit** `Assets/Exoforge/Generated/ExoforgeServices.g.cs` or
  `Exoforge/plugins/*/manifest.exs` — regenerate them (`$CLI sync`, `$CLI plugin build`).
- **Gameplay must not hold a client, an endpoint, or a token.** Publish a hook
  (`SnakeGameController.RunEnded`) and let a controller bridge it to `ExoforgeSDK.Client`.
- Call the server through the **generated** clients:
  `ExoforgeSDK.Client.SnakeLeaderboard().SubmitScoreAsync(...)`.
- Plugin payloads are `JsonObject` — NativeAOT trims reflection-based JSON.
- Plugins build per OS: `$CLI plugin build snake_leaderboard --rid linux-x64` for a Linux deploy.

> Not wired yet: `SnakeGameController.RunEnded` → `snake_leaderboard.submit_score`, and the
> leaderboard UI. The hook, the plugin, and the SDK call all exist; the bridge between them does not.
