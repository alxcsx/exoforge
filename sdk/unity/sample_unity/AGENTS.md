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
│   │   ├── SnakeGameController.cs   the game loop; raises RunEnded(score, length). No rendering.
│   │   ├── SnakeGameView.cs         board + HUD + name prompt + leaderboard panel (IMGUI)
│   │   ├── SnakeLeaderboard.cs      the ONLY file that talks to Exoforge
│   │   └── SnakePlayerController.cs stage 1+2 sign-in, gates gameplay until named
│   ├── Exoforge/Generated/
│   │   └── ExoforgeServices.g.cs    GENERATED — do not hand-edit
│   ├── Resources/exoforge.json      workspace config linked for runtime (generated)
│   ├── Scenes/SampleScene.unity     built from code, not hand-edited
│   ├── Editor/
│   │   ├── ExoforgeSampleSetup.cs   builds the scene (idempotent, CLI-driven)
│   │   └── ExoforgeSampleCheck.cs   headless self-check
│   └── csc.rsp                      -nullable:enable for Assembly-CSharp
│
├── Exoforge/                        the Exoforge workspace (OUTSIDE Assets/)
│   ├── exoforge.json                environments + codegen paths
│   └── plugins/snake_leaderboard/   the server plugin (a dotnet project)
│       ├── snake_leaderboard.slnx     the plugin's own solution
│       ├── src/
│       │   ├── snake_leaderboard.csproj
│       │   ├── SnakeScore.cs          stored row + leaderboard entry records
│       │   ├── SnakeJsonContext.cs    JSON metadata for this plugin's own records (NativeAOT)
│       │   ├── SnakeLeaderboardPlugin.cs  the actions (talk to IDatabase directly)
│       │   └── Generated/PluginServices.g.cs  typed player_data stubs (generated)
│       ├── snake_leaderboard          built NativeAOT binary (generated, git-ignored)
│       └── manifest.exs               GENERATED from the C# attributes
└── Packages/manifest.json           references com.exoforge.sdk (file:../../Exoforge.SDK)
```

**Why the workspace is outside `Assets/`:** plugin sources are ordinary `dotnet` projects
(`net10.0`, NativeAOT). Keeping them out of `Assets/` means Unity never imports, compiles, or
adds `.meta` files to them, and they can use any .NET/C# version. Only two things must live under
`Assets/`: the **generated client** and the **runtime config**.

### Scene

Built by `ExoforgeSampleSetup.SetUp`, never by hand.

| Object | Component(s) | Role |
| :--- | :--- | :--- |
| `Exoforge` | `ExoforgeBehaviour` (prefab) | the runtime host. **Exactly one** — the setup deletes duplicates. |
| `Player` | `SnakePlayerController` | signs in, prompts for the name, activates `Gameplay` |
| `Gameplay` | `SnakeGameController` | the game. Starts **inactive**. |
| `Hud` | `SnakeGameView` + `SnakeLeaderboard` | everything on screen. Stays active. |
| `Main Camera`, `Global Light 2D` | — | furniture; the board is drawn in screen space |

`Hud` has to be active before gameplay is: the name prompt appears *before* the player is ready.

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

## 4. The screen

No art, no prefabs, no Canvas — deliberately primitive, so the sample stays about the Exoforge
integration:

- **The board is a `gridWidth × gridHeight` `Texture2D`**, `FilterMode.Point`, where **one pixel is
  one coloured square**. `SnakeGameView.BuildPixels()` paints it from the controller's state: a
  checkerboard background, then body / head / food. Empty cells alternate so the grid reads as a
  grid even when it is empty.
- **The panels are IMGUI** (`OnGUI`): score, state, the name prompt, the ranking. IMGUI needs no
  scene wiring and gives text fields and buttons for free.
- Cell `y` grows **upward**, matching the texture's bottom-left origin. (The old IMGUI board used a
  downward `y`; that flip is the easiest thing to get wrong here, hence the check below.)

Input uses the **Input System package** (`Keyboard.current`) — this project is set to
`activeInputHandler: 1`, so the legacy `UnityEngine.Input` class throws at runtime.

---

## 5. The server side

`snake_leaderboard` is a **native C# plugin** (no WASM, no C). It is the only server code:

| Action | Params | Behaviour |
| :--- | :--- | :--- |
| `submit_score` | `player_id, name, score, snake_length` | stores the run, keeps the player's **best** score, returns it. `name` is accepted for wire compatibility but ignored |
| `get_leaderboard` | `limit` | returns the top-`limit` rows, highest score first, with each player's **current** display name |

Rows live in the plugin's isolated database (through the injected `IDatabase`) under the `snake_scores`
resource, so the Studio also shows a table. The leaderboard is therefore **shared state**: every
player reads and writes the same ranking.

**The display name is not stored.** `get_leaderboard` joins each row with the `player_data` profile
(`player_data.get_player`) at read time, so renaming a player updates the board immediately and no
stale name can survive. `submit_score` therefore takes a `name` only for wire compatibility.

The typed `player_data` call comes from `src/Generated/PluginServices.g.cs`, generated from the
cluster contracts with `exo plugin stubs snake_leaderboard`. Only the services listed in the plugin's
`manifest.exs` dependencies are generated (override with `--services a,b`), so the file stays small.
The stubs depend only on the service contract (`PlayerDataServiceClient`,
`PlayerDataGetPlayerRequest/Response`, `PlayerDataPlayer`) — never on the Elixir `PlayerData` module.
The host injects the client directly (`[Inject("player_data")] PlayerDataServiceClient PlayerData`),
so plugin code never touches `IActionDispatcher`.

`player_id` is taken from the caller's identity, so a client can only submit its own score.

`SnakeLeaderboard` is the bridge: it listens for `SnakeGameController.RunEnded`, submits the score,
and refreshes the ranking. Gameplay never holds a client or a token — delete that one component and
Snake still runs.

---

## 6. Working on it

```bash
just dev                # backend on :4000 (ws) / :4001 (http) / :4005 (studio)
just sample-setup       # rebuild the scene via the Unity CLI (idempotent)
just sample-check       # headless self-check; exit 0 = pass
```

`just sample-check` runs `ExoforgeSampleCheck.Run`, which covers the two fiddly bits — the board's
pixel index maths and the leaderboard JSON parsing. Both are pure functions on purpose so they can
be checked headlessly. Override the editor with `UNITY_PATH=... just sample-check`.

Deploy the plugin and regenerate the client:

```bash
# Option A — Unity Editor: Tools ▸ Exoforge ▸ Exoforge Studio ▸ Plugins ▸ Build & Deploy

# Option B — CLI. The `exo` CLI is not installed on PATH — run it from the repo:
CLI="dotnet run --project <repo>/sdk/csharp/Exoforge.CLI --"

$CLI plugin push snake_leaderboard      # build (NativeAOT) + deploy to the running cluster
$CLI sync                               # regenerate Assets/Exoforge/Generated/ExoforgeServices.g.cs
```

From the Unity Editor, everything else lives in **Exoforge Studio** (`Tools ▸ Exoforge ▸ Exoforge Studio`):
**Overview** syncs contracts, the C# client and plugin stubs; **Plugins** scaffolds, builds and
deploys; **Settings** holds paths and credentials. Only `Tools ▸ Exoforge ▸ Add Exoforge to Scene`
stays a menu item, since it is a one-off scene edit. In the **Plugins** tab, every folder in
`Exoforge/plugins/` gets a **Build**, **Build & Deploy**, **Deploy**, and **Stubs** button (plus
**Sync Stubs** to regenerate every plugin at once). Stub generation fetches the live contracts and
writes each plugin's `src/Generated/PluginServices.g.cs`. Native builds run `dotnet publish` (AOT)
and regenerate `manifest.exs`; set a **Native RID** (e.g. `linux-x64`) to build for a non-host deploy
target. If Unity can't find `dotnet` (GUI apps often don't inherit your shell PATH), set
**Dotnet Path** in the Settings tab.

Rules of thumb:

- **Never hand-edit** `Assets/Exoforge/Generated/ExoforgeServices.g.cs`, `Exoforge/plugins/*/manifest.exs`,
  or `Assets/Scenes/SampleScene.unity` — regenerate them (`$CLI sync`, `$CLI plugin build`,
  `just sample-setup`).
- **Gameplay must not hold a client, an endpoint, or a token.** Publish a hook
  (`SnakeGameController.RunEnded`) and let `SnakeLeaderboard` bridge it to `ExoforgeSDK.Client`.
- Call the server through the **generated** clients:
  `ExoforgeSDK.Client.SnakeLeaderboard().SubmitScoreAsync(...)`.
- Plugin payloads are **records**, not raw JSON: `SnakeScoreRecord` flows through the injected
  `IDatabase`, and `get_leaderboard` returns `List<SnakeScoreRecord>`. Register those types on the
  plugin's `SnakeJsonContext` (`[JsonSerializable]`) and start it with
  `PluginHost.Run<SnakeLeaderboardPlugin, SnakeJsonContext>()` — NativeAOT trims reflection-based JSON.
- Plugins build per OS: `$CLI plugin build snake_leaderboard --rid linux-x64` for a Linux deploy.
- Uploaded plugins **do not survive a server restart** — re-`push` after restarting the backend.
