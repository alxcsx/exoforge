# Exoforge Operating Manual (`AGENTS.md`)

> **Branch**: `projetao_mvp`  
> **Status**: Kernel, 7 standard plugins, C# Client & Plugin SDKs, C# Management Engine (`exo` CLI), Unity SDK (`com.exoforge.sdk`), Producer Studio and the stateful entity runtime are **complete** — **230 Elixir + 47 C# = 277 tests passing**, plus a live E2E vertical slice.  
> **Verified SLAs**: 729k stateful actor ops/sec, 1.4 µs latency, 0.07 ms 50x event fanout.

---

## 0. Current Milestone: M28 — SDK Runtime Hardening

**See [`plan.md`](plan.md) §6.** The Unity + C# SDK worked, but four correctness bugs and six DX
problems made it behave badly the moment anything went wrong.

**Every code item is done**, each with a test that fails when the fix is reverted:

| | |
| :--- | :--- |
| 2.1 | a failed connection was permanent — `_pendingConnect` was never cleared |
| 2.2 | a destroyed behaviour stayed reachable as `Instance` |
| 2.3 | reconnecting could leave two readers on one socket and report two disconnects |
| 2.4 | a display name survived reconnecting to a different account |
| 3.1–3.3 | the HTTP port is configured, silent failures surface, timeouts are settable |
| 3.4 | reconnect with exponential backoff, from a failed first connect too |
| 3.5, 4.1, 4.2 | one disk write per session; `AuthToken` is not publicly settable; `ExoforgeSDK.Client` no longer hands back a dead client |

Three items turned out to be **review corrections** rather than defects (3.6, 4.1 partly, 4.3) —
recorded in `plan.md` rather than acted on. `ExoTokenStore.Scopes` is never read; there is no extra
`SendActionAsync` overload; and `ExoforgeBehaviour.Client` has legitimate users.

**One item remains, and it is release work, not code:** publish `Exoforge.Plugin.SDK`. A scaffolded
plugin references it and the build fails with `NU1101`. The code path is proven — a local feed makes
`just clean-room-sdk` pass — but nothing is on a feed, so a consumer can scaffold but not build.

**Test infrastructure built during this milestone:**

- `Exoforge.Client.Tests` — `StubWebSocketServer` + `TransportTests` + `BackoffTests`. The client and
  transport are Unity-free, so they are pinned here.
- `Assets/Tests/PlayMode` — `just sample-play-tests`. `ExoforgeBehaviour` is Unity-only and `Awake`
  does not run in the editor, so its lifecycle is only observable in play mode.

---

## 1. Architectural Doctrine: The Rule, and Its One Exception

> **The Rule**: Everything above the kernel is a plugin.  
> **The Exception**: The kernel itself is not a plugin.

The kernel is strictly limited to:
- [`PluginRegistry`](core/lib/plugin_registry.ex): In-memory ETS catalog of service manifests and resources.
- [`ActionDispatcher`](core/lib/action_dispatcher.ex): Authorization scope checks and service action routing.
- [`EventDispatcher`](core/lib/event_dispatcher.ex): Real-time pub/sub bus with pattern matching and Registry fanout.
- [`WorkerRegistry`](core/lib/worker_registry.ex): Named singleton process locator.
- [`PluginSupervisor`](core/lib/plugin_supervisor.ex) & [`PluginBootstrapper`](core/lib/plugin_bootstrapper.ex): Topological DAG ordering and process lifecycle.
- [`Entities`](core/lib/entities.ex): Clustered stateful virtual actors (Horde + `:pg`).
- DSL & Drivers: [`Exoforge.Plugin`](core/lib/plugin.ex), [`Service`](core/lib/contracts/service.ex), [`ElixirPluginRunner`](core/lib/drivers/runtime/elixir_plugin_runner.ex), and `WasmPluginRunner`.

### The 4-Question Litmus Test: "Should this be a plugin?"
1. **Can two implementations be swapped?** (REST ↔ gRPC ↔ WebSocket, Postgres ↔ SQLite, web ↔ TUI) → **Plugin**.
2. **Does something need to depend on it by contract?** → **Plugin**.
3. **Would bootstrapping itself depend on it?** → **Kernel**.
4. **Is it only consumed by one domain plugin?** → Keep it internal to that plugin.

---

## 2. Monorepo Topology & Standard Plugins

```
database ──▶ auth ──▶ player_data
               │
               ├──▶ http (:4001)
               ├──▶ ws   (:4000)

dashboard (:4005) ──▶ dashboard_views
plugin_manager ───▶ (independent root)
```

| Plugin | Port / Role | Provides | Depends on | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `exoforge_std_database` | Storage | `database`, `lldb` | — | Per-plugin schema isolation with Postgres and Sandbox adapters. |
| `exoforge_std_auth` | Identity | `auth` | `database` | Token issuance, session verification, scope validation. |
| `exoforge_std_player_data` | Profiles | `player_data` | `database`, `auth` | Canonical player profile persistence and lifecycle events. |
| `exoforge_std_http` | REST (:4001) | `http` | `auth` | Dynamic OpenAPI routes derived from service contracts. |
| `exoforge_std_ws` | Realtime (:4000) | `ws` | `auth` | Low-latency binary/JSON framing for actions and event pub/sub. |
| `exoforge_std_dashboard` | Studio (:4005) | `dashboard` | — | System plugin hosting LiveView Producer Studio and Actor Inspector. |
| `exoforge_std_dashboard_views` | Studio Views | `dashboard_view` | `dashboard` | Decoupled UI components for player data, plugin manager, auth. |
| `exoforge_std_plugin_manager`| Lifecycle | `plugin_manager` | — | Hot WASM/Elixir plugin upload, reload, and manifest export. |

### Plugin Placement Rules

**System-level plugins** (generic, reusable, demonstrates SDK features):
- Elixir plugins: `plugins/exoforge_std_*/`
- C# WASM sample plugins: `plugins_csharp/` (e.g., `sample_wasm`)

**Game-specific plugins** (belong to the game project, NOT the system):
- Unity game projects: `<game>/Exoforge/plugins/`
- Example: `sdk/unity/sample_unity/Exoforge/plugins/snake_game/`
- The workspace (`exoforge.json` + `plugins/`) lives **outside** `Assets/`, so dotnet/WASM plugin
  projects can target modern .NET/C# versions without Unity importing or compiling them.
  `ExoWorkspace.PluginsDir` = `plugins`, resolved against the workspace root.
- Only Unity-consumed artifacts stay inside `Assets/`: the generated client
  (`Assets/Exoforge/Generated/`) and the runtime config (`Assets/Resources/exoforge.json`).
  `ExoWorkspace` resolves any `Assets/...` config path against the project root automatically.
- **Caveat**: the workspace is invisible to Unity's AssetDatabase, so editor tooling must reach it
  through `System.IO` (`ExoWorkspace.PluginsPath`, `ExoDeployer`), never `AssetDatabase`/`Resources`.

> **Rule**: Game-specific plugins must NOT touch `core/`, `plugins/`, or `plugins_csharp/`. They live exclusively inside the game project and are built/deployed independently. The system `just build-wasm` only builds `plugins_csharp/`; game plugins are built within their own project (e.g., Unity Editor menu or the game's own build scripts).

### Plugin Runtimes

| Runtime | Manifest `type` | Written in | Built by | Use for |
| :--- | :--- | :--- | :--- | :--- |
| **Native (AOT process)** | `:native` | C# | `exo plugin build` → `dotnet publish -p:PublishAot=true` | First-party game servers. **Default.** |
| WASM reactor | `:wasm` | C# contract + C guest | `build.sh` (needs wasi-sdk) | Sandboxed / third-party guests |
| Elixir | `:elixir` | Elixir | `mix` | System plugins |

Native plugins are plain C# — **no C, no WASI toolchain**. `exo plugin build` compiles the plugin to a
self-contained ~2 MB binary and generates `manifest.exs` from the C# attributes. The Unity
**Control Center ▸ Plugins** tab runs the same build (`dotnet publish -p:PublishAot=true` + ManifestGen)
and deploys the result, so game teams never need the CLI. The plugin's entry point is:

```csharp
public static void Main() => PluginHost.Run<MyPlugin>();
```

The host spawns the binary as an OS process (`Exoforge.Drivers.Runtime.NativePluginRunner`) and speaks
newline-delimited JSON over stdio. Host capabilities are injected into the plugin (`IDatabase`, `ILogger`,
`IEventDispatcher`, …) and answered by the runner synchronously; `HostBridge` is the low-level layer
underneath them.

**Inbound events**: the runner subscribes to the events a plugin declares in its manifest (with their declared
topic) and forwards them as `{"type":"event"}` frames. The plugin handles them in an optional
`public void OnEvent(string name, TPayload payload)` — it is called even while an action is blocked on a
host call. The payload is deserialized to `TPayload`; register it on the plugin's JSON context (below).

**Per-OS builds**: plugins ship as native binaries, so build for the deploy target:
`exo plugin build <name> --rid linux-x64` (defaults to the host).

Because NativeAOT trims reflection, plugin payloads are **records**, not raw `JsonObject`/`JsonElement`. The
SDK owns the JSON: action arguments and results, stored records, and event payloads are typed, and
`IDatabase` (injected as `[Inject]`) is a typed key/value store with a typed SQL runner. Register the
record types on a source-generated `JsonSerializerContext` and start the plugin with the context-aware
runner:

```csharp
[JsonSerializable(typeof(SnakeScoreRecord))]
internal partial class SnakeJsonContext : JsonSerializerContext { }

public static void Main() => PluginHost.Run<SnakeLeaderboardPlugin, SnakeJsonContext>();

// Key/value
var best = Database!.Get<SnakeScoreRecord>("snake_scores", playerId);
Database.Put("snake_scores", playerId, record);

// Typed SQL: rows map onto records, args are positional ($1, $2, ...)
var top = Database.Query<SnakeScoreRecord>("SELECT * FROM snake_scores ORDER BY score DESC LIMIT $1", 10);
Database.Execute("DELETE FROM snake_scores WHERE score < $1", 0);
```

Keep `PluginHost.Run<...>()`'s `[DynamicallyAccessedMembers]` annotation intact — that is what keeps the
`[ExoAction]` methods and injected properties reachable. `JsonObject`/`JsonElement` remain available on
`HostBridge` for exotic cases, but plugin code should not need them.

Action declarations follow conventions, so the attribute is usually bare:

- **Name** — `[ExoAction]` uses the method name in snake_case (`SubmitScore` → `submit_score`).
- **Mode** — inferred from the return type: `Task`/`Task<T>` → `:async`, anything concrete → `:sync`.
  (`ActionMode.Cast` is still explicit.)
- **Transport** — defaults to `:auto`.

Plugins call other services through **generated, region-agnostic stubs**: `exo plugin stubs <name>`
reads the cluster contract export and writes `src/Generated/PluginServices.g.cs` (typed
request/response records + a typed client per service). Only the services in the plugin's
`manifest.exs` dependencies are generated (`--services a,b` overrides), so the file — and the NativeAOT
build — stay small. The host injects those clients (`[Inject("player_data")]
PlayerDataServiceClient PlayerData`), so plugin code only deals with services and never touches
`IActionDispatcher`. The stubs depend on the service *contract*, never on the plugin that implements it.

`ActionDispatcher` stays runtime-agnostic: every non-Elixir plugin gets a generated proxy module
(`Exoforge.Drivers.Runtime.PluginProxy`) registered as its `entry_point`.

### Unity SDK Surface (game-facing)

Game code talks to exactly one entry point:

```csharp
var session = await ExoforgeSDK.Auth.LoginAnonymously();          // stage 1: enter/register the account
if (!session.HasDisplayName) session = await ExoforgeSDK.Auth.SetDisplayName("Viper");   // stage 2
var board   = await ExoforgeSDK.Client.SnakeLeaderboard().GetLeaderboardAsync(10);
```

- `ExoforgeSDK.Auth.LoginAnonymously()` — **stage 1**. Signs in, keyed by the device (the PlayFab
  `CustomId` pattern): `ExoDeviceId` derives a stable, hashed id from
  `SystemInfo.deviceUniqueIdentifier` and caches it, and that id is the account key — so the same
  machine always resolves to the same player even if the stored credential is lost. It does **not**
  assign a display name; a new account comes back with `ExoSession.HasDisplayName == false`.
  `LogoutAndForgetDevice()` claims a fresh account.
- `ExoforgeSDK.Auth.SetDisplayName(name)` — **stage 2**. Names the signed-in player (the server takes
  the player from the caller's identity, so a player can only name themselves).
- `ExoTokenStore` is public but **low-level** — use `ExoforgeSDK.Auth`. Exposed only for custom
  credential storage and tooling.
- `ExoforgeSDK.Client` — the connected `ExoClient`; use the **generated** service extensions
  (`Client.PlayerData()`, `Client.SnakeLeaderboard()`, …) rather than hand-written calls.
- `ExoforgeSDK.ConnectAsync()` — idempotent connect. `ExoforgeBehaviour` is created on demand if no
  Exoforge prefab is in the scene, so a game needs no scene wiring to use the SDK.

Gameplay must not hold a client, an endpoint, or a token. It publishes hooks (e.g.
`SnakeGameController.RunEnded`) and a game-side controller bridges them to `ExoforgeSDK.Client`.

---

## 3. Ponytail Engineering Principles (Points to Simplify & Polish)

1. **Stdlib & OTP First**: Reach for Erlang/Elixir built-ins (`:ets`, `:pg`, `Registry`, `DynamicSupervisor`) before adding third-party dependencies.
2. **Zero Module Coupling**: Plugins depend on **service atoms** (`:database`, `:auth`, `:player_data`), NEVER on another plugin's Elixir module name. Use `ActionDispatcher.dispatch(service, action, payload)`.
3. **Pure C# Outside Mix**: External game developers and Unity designers do not have Elixir or Mix installed. All client tooling, scaffolding (`ExoScaffolder`), and code generation (`ExoCodeGenerator`) must remain pure C# (`netstandard2.1`).
4. **C# for Game Code**: First-party game plugins are written in C# and compiled to a NativeAOT binary — never hand-written C, and never a WASI toolchain. Keep the host boundary to newline-delimited JSON. Reserve the WASM reactor runtime for sandboxed or third-party guests.
5. **Virtual Actors over Distributed Locks**: Use Horde process registries and `:pg` groups. Do not introduce external distributed lock managers (no Redis locks, no ZooKeeper).
6. **Deletion Over Addition**: The best code is code you never had to write. Remove dead code, redundant wrappers, and unneeded abstractions ruthlessly.

---

## 4. Commands Quick Reference

| Command | Action |
| :--- | :--- |
| `just test` | Run entire test suite (Core, Plugins, System, C# SDKs — 164 tests) |
| `just test-e2e` | Run live end-to-end vertical slice (WebSocket + WASM + Event loop) |
| `just dev` | Start backend development server (ports 4000, 4001, 4005) |
| `just dev-reset` | Stop the dev server and wipe all dev data (SQLite databases + uploaded plugins) |
| `just build-wasm` | Compile the **system** WASM samples (`plugins_csharp/*/build.sh`) |
| `exo plugin build <name>` | Build a game plugin (NativeAOT binary + `manifest.exs`) |
| `exo plugin push <name>` | Build and deploy a plugin to a running cluster |
| `exo plugin stubs <name>` | Generate typed service-call stubs from the cluster contracts |
| `just test-sdk` | Run C# test suite (`Exoforge.Client`, `Plugin.SDK`, `Management`) |
| `just compose-up` | Run full production stack with PostgreSQL via Docker Compose |
| `just compose-down` | Stop and tear down Compose stack |
| `just k8s-deploy` | Deploy cluster to Kubernetes via Kustomize (with sensible defaults) |
| `just benchmark` | Run stateful entity cluster performance benchmark |
| `just sample-setup` | Rebuild the Unity Snake sample scene via the Unity CLI (idempotent) |
| `just sample-check` | Headless self-check for the Unity Snake sample (exit 0 = pass) |

---

## 5. Agent & Contributor Guidelines

1. **Read before editing**: Inspect existing contracts and tests before adding new abstractions.
2. **Verify every change**: Always run `just test` or the relevant unit suite (`just test-core`, `just test-plugins`, `just test-sdk`).
3. **Honor the Rule**: Everything above the kernel is a plugin.
4. **Shortest working diff wins**: Do not create speculative configuration, wrapper classes with one implementation, or premature abstractions.
