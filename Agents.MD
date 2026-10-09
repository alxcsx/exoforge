# Exoforge Operating Manual (`AGENTS.md`)

> **Branch**: `projetao_mvp`  
> **Status**: Kernel, 10 standard plugins, C# Client & Plugin SDKs, C# Management Engine (`exo` CLI), Unity SDK (`com.exoforge.sdk`), Producer Studio and the plugin runtime are **complete** — **266 Elixir + 81 C# = 347 tests passing**, plus a live E2E vertical slice of 6 tests against a running server.  
> **Verified SLA**: 0.07 ms fanout to 50 event subscribers over `:pg`.

---

## 0. Where Things Stand

No open task. The two that were outstanding are settled: `Exoforge.Plugin.SDK` is not being
published (the local feed covers development, and `just clean-room-sdk` proves the consumer path),
and client stubs no longer need a cluster. **A plugin manifest is JSON** — `manifest.json`, written by
the plugin's own generator or by the Elixir manifest compiler, read by the server and by the C#
tooling alike. It was an Elixir map literal that the server evaluated, which is why the C# side could
not read the only copy of a plugin's contracts. Stub generation lays each built plugin's manifest
over the cluster export, so a plugin that is built but not deployed still has stubs. See
[`plan.md`](plan.md) §4.

**Test data does not outlive the test.** An integration run creates accounts, and they used to land in
the developer's own database, indistinguishable from a player who signed up. Two things stop that: the
live-test recipes run the backend with `EXOFORGE_DATA_DIR` pointing at a temporary directory, and an
account a test or a demo makes says so — `auth.anonymous`/`auth.register` with `disposable: true` —
so `auth.purge_disposable` can remove exactly those.

**How a build input is found**, which is the rule the tooling follows: a project names no other
project's path. `Directory.Build.targets` at the repository root supplies a plugin's SDK, generator
and manifest plumbing from the single declaration `<ExoforgePlugin>true</ExoforgePlugin>` — from
source when the SDK is beside it, from the package when it is not — and stages the compiled
libraries into the Unity package as a side effect of building them. `NuGet.config` adds the local
feed for anything under this repository; `EXOFORGE_FEED` points a workspace outside it at one.
`just unity-sync` places the built package into the sample, which names no path outside itself.

## 1. Architectural Doctrine: The Rule, and Its One Exception

> **The Rule**: Everything above the kernel is a plugin.  
> **The Exception**: The kernel itself is not a plugin.

The kernel is strictly limited to:
- [`PluginRegistry`](core/lib/plugin_registry.ex): In-memory ETS catalog of service manifests and resources.
- [`ActionDispatcher`](core/lib/action_dispatcher.ex): Authorization scope checks and service action routing.
- [`EventDispatcher`](core/lib/event_dispatcher.ex): Real-time pub/sub bus with pattern matching and Registry fanout.
- [`WorkerRegistry`](core/lib/worker_registry.ex): Named singleton process locator.
- [`PluginSupervisor`](core/lib/plugin_supervisor.ex) & [`PluginBootstrapper`](core/lib/plugin_bootstrapper.ex): Topological DAG ordering and process lifecycle.
- DSL & Drivers: [`Exoforge.Plugin`](core/lib/plugin.ex), [`Service`](core/lib/contracts/service.ex), [`ElixirPluginRunner`](core/lib/drivers/runtime/elixir_plugin_runner.ex), and `NativePluginRunner`.

### The 4-Question Litmus Test: "Should this be a plugin?"
1. **Can two implementations be swapped?** (REST ↔ gRPC ↔ WebSocket, Postgres ↔ SQLite, web ↔ TUI) → **Plugin**.
2. **Does something need to depend on it by contract?** → **Plugin**.
3. **Would bootstrapping itself depend on it?** → **Kernel**.
4. **Is it only consumed by one domain plugin?** → Keep it internal to that plugin.

---

## 2. Monorepo Topology & Standard Plugins

These are **builtin and server-side**. They live in this repository, they are not installed on a
game developer's machine, and their contracts reach the tooling over the wire. A team may remove or
replace any of them with its own services.

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
| `exoforge_std_plugin_manager`| Lifecycle | `plugin_manager` | — | Hot plugin upload, reload, and manifest export. |

### Plugin Placement Rules

**System-level plugins** (generic, reusable, demonstrates SDK features):
- Elixir plugins: `plugins/exoforge_std_*/`
- C# sample plugins: `plugins_csharp/` (e.g., `sample_plugin`)

**Game-specific plugins** (belong to the game project, NOT the system):
- Unity game projects: `<game>/Exoforge/plugins/`
- Example: `sdk/unity/sample_unity/Exoforge/plugins/snake_game/`
- The workspace (`exoforge.json` + `plugins/`) lives **outside** `Assets/`, so dotnet plugin
  projects can target modern .NET/C# versions without Unity importing or compiling them.
  `ExoWorkspace.PluginsDir` = `plugins`, resolved against the workspace root.
- Only Unity-consumed artifacts stay inside `Assets/`: the generated client
  (`Assets/Exoforge/Generated/`) and the runtime config (`Assets/Resources/exoforge.json`).
  `ExoWorkspace` resolves any `Assets/...` config path against the project root automatically.
- **Caveat**: the workspace is invisible to Unity's AssetDatabase, so editor tooling must reach it
  through `System.IO` (`ExoWorkspace.PluginsPath`, `ExoDeployer`), never `AssetDatabase`/`Resources`.

> **Rule**: Game-specific plugins must NOT touch `core/`, `plugins/`, or `plugins_csharp/`. They live exclusively inside the game project and are built/deployed independently. The system `just build-plugins` only builds `plugins_csharp/`; game plugins are built within their own project (e.g., Unity Editor menu or the game's own build scripts).

### Plugin Runtimes

| Runtime | Manifest `type` | Written in | Built by | Use for |
| :--- | :--- | :--- | :--- | :--- |
| **Native (.NET process)** | `:native` | C# | `exo plugin build` → `dotnet publish` | First-party game servers. **Default.** |
| Elixir | `:elixir` | Elixir | `mix` | System plugins |

Native plugins are plain C# — no C, no extra toolchain. `exo plugin build` compiles the plugin to a
**framework-dependent** single file of a couple of hundred KB: the plugin carries its own IL and
dependencies, and the runtime comes from the host, which is how UGS Cloud Code ships modules too
(a `.ccm` is a zip of the module DLL, its `deps.json`, its dependencies and its PDBs, with no
runtime in it). `manifest.json` and the entry point are written by the
`Exoforge.Plugin.Generator` source generator during that same compile — there is no separate manifest
tool. The Unity **Exoforge Studio ▸ Plugins** tab runs the same build and deploys the result, so game
teams never need the CLI. The
entry point and the action/event dispatch table are generated for you, so the host never reflects
over the plugin's methods:

```csharp
// Exoforge.Generated.ExoforgeEntryPoint
public static void Main() => PluginHost.Run<MyPlugin, MyJsonContext, ExoforgeDispatch>();
```

**Services** are declared two ways, and they compose:

```csharp
// The class is its own contract and implementation.
[ExoService("my_service", Category = "Game", Title = "My Service", Icon = "🎮")]
public partial class MyPlugin
{
    [ExoAction] public int DoThing(int amount) => amount;
}

// Or the contract is a declared interface; the class implementing it is the plugin's root.
[ExoService("my_contract")]
public interface IMyContract { [ExoAction] int DoThing(int amount); }

public partial class MyPlugin : IMyContract { public int DoThing(int amount) => amount; }
```

A contract may also live in its **own assembly** — a shared contracts package — and the generator
reads it from there, so nothing in the plugin's source names the service.

A class-declared service gets a contract interface generated for it
(`Exoforge.Generated.Contracts.I…`) and, when the class is `partial`, the generator makes the class
implement it — so the contract always exists as a named type and moves into a shared project
unchanged. Declare several `[ExoService]`s for several services; attribute an action or event with
`Service = "…"` when they belong to different ones. A plugin runs one instance, so it has one root.

The host spawns the binary as an OS process (`Exoforge.Drivers.Runtime.NativePluginRunner`) and speaks
newline-delimited JSON over stdio. It opens with a `hello` frame declaring the protocol and the
frames it handles, and the SDK answers with its own before the first action is read, so a version or
capability mismatch is refused with a reason instead of fed frames that cannot be parsed.
Host capabilities are injected into the plugin (`IDatabase`, `ILogger`,
`IEventDispatcher`, …) and answered by the runner synchronously; `HostBridge` is the low-level layer
underneath them.

**The plugin wire protocol.** One definition, implemented by
`Exoforge.Drivers.Runtime.PluginProtocol` on the host and `PluginHost`/`HostBridge` in the SDK;
`plugin_protocol_test.exs` and `HandshakeTests.cs` pin each side's copy of it. Frames are
newline-delimited JSON with a `type`:

| type | direction | carries |
| :--- | :--- | :--- |
| `hello` | host → plugin | `protocol`, `host`, `capabilities` |
| `hello` | plugin → host | `protocol`, `plugin`, `capabilities` |
| `action` / `action_result` | host → plugin / back | `id`, `action`, `payload` / `status`, `data` or `error` |
| `event` | host → plugin | `event`, `payload` |
| `host_call` / `host_call_result` | plugin → host / back | `id`, `op`, `args` / `result` |
| `host_log` | plugin → host | `level`, `message` |

Protocol `1`, handshake timeout five seconds. Capabilities are the frame types a side can
*receive*: the host declares `action_result`, `host_call`, `host_log`; a plugin must declare
`action` and `event`. A protocol mismatch, a missing capability, or no answer at all is one log
line and a refusal - never a retry.

**Inbound events**: the runner subscribes to the events a plugin declares in its manifest (with their declared
topic) and forwards them as `{"type":"event"}` frames. The plugin handles them in an optional
`public void OnEvent(string name, TPayload payload)` — it is called even while an action is blocked on a
host call. The payload is deserialized to `TPayload`; register it on the plugin's JSON context (below).

**Per-OS builds**: a plugin is an assembly with a native apphost, so build for the deploy target:
`exo plugin build <name> --rid linux-x64` (defaults to the host).

Plugin payloads are **records**, not raw `JsonObject`/`JsonElement` — and the reason is the contract
rather than the runtime. A record has a *name*, and that name is what the manifest, the generated
client stub and the Studio describe; an anonymous object would serialise fine and be describable by
nobody. The
SDK owns the JSON: action arguments and results, stored records, and event payloads are typed, and
`IDatabase` (injected as `[Inject]`) is a typed key/value store with a typed SQL runner.

There is no `Main` to write and no `JsonSerializerContext` to declare — the generator emits the entry
point, and because a plugin is framework-dependent, reflection serialises what it sends. A plugin
that declares a context anyway is still honoured; nothing requires one.

```csharp
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
`manifest.json` dependencies are generated (`--services a,b` overrides), so the file stays small. The host injects those clients (`[Inject("player_data")]
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
- `ExoforgeSDK.ConnectAsync()` — idempotent connect. `ExoforgeManager` is created on demand if no
  Exoforge prefab is in the scene, so a game needs no scene wiring to use the SDK.

Gameplay must not hold a client, an endpoint, or a token. It publishes hooks (e.g.
`SnakeGameController.RunEnded`) and a game-side controller bridges them to `ExoforgeSDK.Client`.

---

## 3. Ponytail Engineering Principles (Points to Simplify & Polish)

1. **Stdlib & OTP First**: Reach for Erlang/Elixir built-ins (`:ets`, `:pg`, `Registry`, `DynamicSupervisor`) before adding third-party dependencies.
2. **Zero Module Coupling**: Plugins depend on **service atoms** (`:database`, `:auth`, `:player_data`), NEVER on another plugin's Elixir module name. Use `ActionDispatcher.dispatch(service, action, payload)`.
3. **Pure C# Outside Mix**: External game developers and Unity designers do not have Elixir or Mix installed. All client tooling, scaffolding (`ExoScaffolder`), and code generation (`ExoCodeGenerator`) must remain pure C# (`netstandard2.1`).
4. **C# for Game Code**: Game plugins are written in C# and compiled to a framework-dependent .NET assembly. Keep the host boundary to newline-delimited JSON — that is what makes a different runtime a runner rather than a rewrite.
5. **No Distributed Locks**: State that has to be serialized belongs in a plugin's own process. Do not introduce external distributed lock managers (no Redis locks, no ZooKeeper).
6. **Deletion Over Addition**: The best code is code you never had to write. Remove dead code, redundant wrappers, and unneeded abstractions ruthlessly.

---

## 4. Commands Quick Reference

| Command | Action |
| :--- | :--- |
| `just test` | Run the whole test suite (core, plugins, system, C# SDKs) |
| `just test-e2e` | Run the live end-to-end vertical slice (WebSocket + plugin + event loop) |
| `just dev` | Start backend development server (ports 4000, 4001, 4005) |
| `just dev-reset` | Stop the dev server and wipe all dev data (SQLite databases + uploaded plugins) |
| `just build-plugins` | Build the system sample plugin (`plugins_csharp/`) |
| `exo plugin build <name>` | Build a game plugin (framework-dependent .NET single file + `manifest.json`) |
| `exo plugin push <name>` | Build and deploy a plugin to a running cluster |
| `exo plugin stubs <name>` | Generate typed service-call stubs from the cluster contracts |
| `just test-sdk` | Run C# test suite (`Exoforge.Client`, `Plugin.SDK`, `Management`) |
| `just compose-up` | Run full production stack with PostgreSQL via Docker Compose |
| `just compose-down` | Stop and tear down Compose stack |
| `just k8s-deploy` | Deploy cluster to Kubernetes via Kustomize (with sensible defaults) |
| `just benchmark` | Run the cluster event fanout benchmark |
| `just sample-setup` | Rebuild the Unity Snake sample scene via the Unity CLI (idempotent) |
| `just sample-check` | Headless self-check for the Unity Snake sample (exit 0 = pass) |

---

## 5. Agent & Contributor Guidelines

1. **Read before editing**: Inspect existing contracts and tests before adding new abstractions.
2. **Verify every change**: Always run `just test` or the relevant unit suite (`just test-core`, `just test-plugins`, `just test-sdk`).
3. **Honor the Rule**: Everything above the kernel is a plugin.
4. **Shortest working diff wins**: Do not create speculative configuration, wrapper classes with one implementation, or premature abstractions.
