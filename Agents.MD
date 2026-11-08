# Exoforge Operating Manual (`Agents.MD`)

> **Branch**: `projetao_mvp`  
> **Status**: Kernel, 11 standard extensions, C# Client & Extension SDKs, C# Management Engine (`exo` CLI), Unity SDK (`com.exoforge.sdk` v0.1.6), Producer Studio and the extension runtime are **complete** — **318 Elixir + 121 C# = 439 tests passing**, plus a live E2E vertical slice of 6 tests against a running server.  
> **MVP Execution Plan**: Phase 0 (ADR 001) & Phase 1 (Extension Terminology Bulldozer) **Completed**.  
> **Verified SLA**: 0.07 ms fanout to 50 event subscribers over `:pg`.

---

## 0. Where Things Stand

ADR 001 locked the MVP doctrine: Unity-first, single-title per instance, native C# extensions, immutable deployed artifacts, and containerized VPS orchestration (see [`docs/adr/001-mvp-architecture.md`](docs/adr/001-mvp-architecture.md)).
Phase 1 bulldozed all platform terminology from "plugin" to "extension", purged legacy aliases (`plugins_csharp`, `PLUGINS_PATH`, `PluginRegistry`, `plugin_manager`), and moved Elixir extensions to `extensions/`.

`Exoforge.Plugin.SDK` is embedded in the Unity package (`NuGet~/`), and client stubs require no local cluster: **An extension manifest is JSON** — `manifest.json`, written by the extension's own Roslyn generator or by the Elixir manifest compiler, read by the server and C# tooling alike. Stub generation lays each built extension's manifest over the cluster export, so an extension that is built but not yet deployed still has typed stubs. See [`plan.md`](plan.md).

**Test data does not outlive the test.** An integration run creates accounts, and they used to land in
the developer's own database, indistinguishable from a player who signed up. Two things stop that: the
live-test recipes run the backend with `EXOFORGE_DATA_DIR` pointing at a temporary directory, and an
account a test or a demo makes says so — `auth.anonymous`/`auth.register` with `disposable: true` —
so `auth.purge_disposable` can remove exactly those.

**How a build input is found**, which is the rule the tooling follows: a project names no other
project's path. `Directory.Build.targets` at the repository root supplies an extension's SDK, generator
and manifest plumbing from the single declaration `<ExoforgePlugin>true</ExoforgePlugin>` — from
source when the SDK is beside it, from the package when it is not — and stages the compiled
libraries into the Unity package as a side effect of building them. `NuGet.config` adds the local
feed for anything under this repository; `EXOFORGE_FEED` points a workspace outside it at one.
`just unity-sync` places the built package into the sample, which names no path outside itself.

## 1. Architectural Doctrine: The Rule, and Its One Exception

> **The Rule**: Everything above the kernel is an extension.  
> **The Exception**: The kernel itself is not an extension.

The kernel is strictly limited to:
- [`ExtensionRegistry`](core/lib/extension_registry.ex): In-memory ETS catalog of service manifests and resources.
- [`ActionDispatcher`](core/lib/action_dispatcher.ex): Authorization scope checks and service action routing.
- [`EventDispatcher`](core/lib/event_dispatcher.ex): Real-time pub/sub bus with pattern matching and Registry fanout.
- [`WorkerRegistry`](core/lib/worker_registry.ex): Named singleton process locator.
- [`ExtensionSupervisor`](core/lib/extension_supervisor.ex) & [`ExtensionBootstrapper`](core/lib/extension_bootstrapper.ex): Topological DAG ordering and process lifecycle.
- DSL & Drivers: [`Exoforge.Contracts.Extension`](core/lib/contracts/extension.ex), [`Service`](core/lib/contracts/service.ex), [`ElixirExtensionRunner`](core/lib/drivers/runtime/elixir_extension_runner.ex), `NativeExtensionRunner`, and [`ExtensionProtocol`](core/lib/drivers/runtime/extension_protocol.ex) (the host side of the wire handshake).

### The 4-Question Litmus Test: "Should this be an extension?"
1. **Can two implementations be swapped?** (REST ↔ gRPC ↔ WebSocket, Postgres ↔ SQLite, web ↔ TUI) → **Extension**.
2. **Does something need to depend on it by contract?** → **Extension**.
3. **Would bootstrapping itself depend on it?** → **Kernel**.
4. **Is it only consumed by one domain extension?** → Keep it internal to that extension.

---

## 2. Monorepo Topology & Standard Extensions

These are **builtin and server-side**. They live in `extensions/` in this repository, they are not installed on a
game developer's machine, and their contracts reach the tooling over the wire. A team may remove or
replace any of them with its own services.

```
database ──▶ auth ──▶ player_data
               │
               ├──▶ http (:4001)
               └──▶ ws   (:4000)

dashboard (:4005) ──▶ dashboard_views
extension_manager ──▶ (independent root)
docs        ──▶ extension_manager
resources   ──▶ database
metering    ──▶ database
file_bucket ──▶ database
```

| Extension | Port / Role | Provides | Depends on | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `exoforge_std_database` | Storage | `database`, `lldb` | — | Per-extension schema isolation with Postgres and SQLite adapters. |
| `exoforge_std_auth` | Identity | `auth` | `database` | Token issuance, session verification, scope validation. |
| `exoforge_std_player_data` | Profiles | `player_data` | `database`, `auth` | Canonical player profile persistence and lifecycle events. |
| `exoforge_std_http` | REST (:4001) | `http` | `auth` | Dynamic OpenAPI routes derived from service contracts. |
| `exoforge_std_ws` | Realtime (:4000) | `ws` | `auth` | Low-latency JSON framing for actions and event pub/sub. |
| `exoforge_std_dashboard` | Studio (:4005) | `dashboard` | — | System extension hosting LiveView Producer Studio and Actor Inspector. |
| `exoforge_std_dashboard_views` | Studio Views | `dashboard_view` | `dashboard` | Decoupled UI components for player data, extension manager, auth. |
| `exoforge_std_extension_manager`| Lifecycle | `extension_manager` | — | Hot extension upload, reload, and manifest export. |
| `exoforge_std_docs` | Docs / Guide | `docs` | `extension_manager` | Dynamic cluster API catalog, markdown chapters, and native PDF export. |
| `exoforge_std_resources` | Store | `resource_store` | `database` | Schema-driven resource tables and generic CRUD. |
| `exoforge_std_file_bucket` | Storage / CDN | `file_bucket` | `database` | Pluggable binary/blob asset storage with tags, metadata, and HTTP file routes. |
| `exoforge_std_metering` | Operations | `metering` | `database` | Usage metering per extension and action, persisted on the instance. |
| `exoforge_std_transport` | Gateway Abstraction | `transport` | — | Common gateway abstraction, framing normalization, and RPC dispatching for network ingress. |
| `exoforge_std_cron` | Operations | `cron` | — | Scheduled background task execution and recurring cron runner. |

### Extension Placement Rules

**System-level extensions** (generic, reusable, demonstrates SDK features):
- Elixir extensions: `extensions/exoforge_std_*/`
- C# sample extensions: `extensions_csharp/` (e.g., `sample_plugin`)

**Game-specific extensions** (belong to the game project, NOT the system):
- Unity game projects: `<game>/Exoforge/extensions/`
- Example: `sdk/unity/sample_unity/Exoforge/extensions/snake_game/`
- The workspace (`exoforge.json` + `extensions/`) lives **outside** `Assets/`, so dotnet extension
  projects can target modern .NET/C# versions without Unity importing or compiling them.
  `ExoWorkspace.ExtensionsDir` = `extensions`, resolved against the workspace root.
- Only Unity-consumed artifacts stay inside `Assets/`: the generated client
  (`Assets/Exoforge/Generated/`) and the runtime config (`Assets/Resources/exoforge.json`).
  `ExoWorkspace` resolves any `Assets/...` config path against the project root automatically.
- **Caveat**: the workspace is invisible to Unity's AssetDatabase, so editor tooling must reach it
  through `System.IO` (`ExoWorkspace.ExtensionsPath`, `ExoDeployer`), never `AssetDatabase`/`Resources`.

> **Rule**: Game-specific extensions must NOT touch `core/`, `extensions/`, or `extensions_csharp/`. They live exclusively inside the game project and are built/deployed independently. The system `just build-extensions` only builds `extensions_csharp/`; game extensions are built within their own project (e.g., Unity Editor menu or the game's own build scripts).

### Extension Runtimes

| Runtime | Manifest `type` | Written in | Built by | Use for |
| :--- | :--- | :--- | :--- | :--- |
| **Native (.NET process)** | `:native` | C# | `exo extension build` → `dotnet publish` | First-party game servers. **Default.** |
| Elixir | `:elixir` | Elixir | `mix` | System extensions |

Native extensions are plain C# — no C, no extra toolchain. `exo extension build` compiles the extension to a
**framework-dependent** single file of a couple of hundred KB: the extension carries its own IL and
dependencies, and the runtime comes from the host, which is how UGS Cloud Code ships modules too
(a `.ccm` is a zip of the module DLL, its `deps.json`, its dependencies and its PDBs, with no
runtime in it). `manifest.json` and the entry point are written by the
`Exoforge.Plugin.Generator` source generator during that same compile — there is no separate manifest
tool. The Unity **Exoforge Studio ▸ Extensions** tab runs the same build and deploys the result, so game
teams never need the CLI. The
entry point and the action/event dispatch table are generated for you, so the host never reflects
over the extension's methods:

```csharp
// Exoforge.Generated.ExoforgeEntryPoint
public static void Main() => ExtensionHost.Run<MyExtension, MyJsonContext, ExoforgeDispatch>();
```

**Services** are declared two ways, and they compose:

```csharp
// The class is its own contract and implementation.
[ExoService("my_service", Category = "Game", Title = "My Service", Icon = "🎮")]
public partial class MyExtension
{
    [ExoAction] public int DoThing(int amount) => amount;
}

// Or the contract is a declared interface; the class implementing it is the extension's root.
[ExoService("my_contract")]
public interface IMyContract { [ExoAction] int DoThing(int amount); }

public partial class MyExtension : IMyContract { public int DoThing(int amount) => amount; }
```

A contract may also live in its **own assembly** — a shared contracts package — and the generator
reads it from there, so nothing in the extension's source names the service.

A class-declared service gets a contract interface generated for it
(`Exoforge.Generated.Contracts.I…`) and, when the class is `partial`, the generator makes the class
implement it — so the contract always exists as a named type and moves into a shared project
unchanged. Declare several `[ExoService]`s for several services; attribute an action or event with
`Service = "…"` when they belong to different ones. An extension runs one instance, so it has one root.

The host spawns the binary as an OS process (`Exoforge.Drivers.Runtime.NativeExtensionRunner`) and speaks
newline-delimited JSON over stdio. It opens with a `hello` frame declaring the protocol and the
frames it handles, and the SDK answers with its own before the first action is read, so a version or
capability mismatch is refused with a reason instead of fed frames that cannot be parsed.
Host capabilities are accessed directly via the static `Exo` holder (`Exo.Database`,
`Exo.Log`, `Exo.Events`, `Exo.Services`) with tree-shaking, or injected into the extension class via
`[Inject]` (`IDatabase`, `ILogger`, `IEventDispatcher`, …); `HostBridge` is the low-level layer
underneath them.

**The extension wire protocol.** One definition, implemented by
`Exoforge.Drivers.Runtime.ExtensionProtocol` on the host and `ExtensionHost`/`HostBridge` in the SDK;
`extension_protocol_test.exs` and `HandshakeTests.cs` pin each side's copy of it. Frames are
newline-delimited JSON with a `type`:

| type | direction | carries |
| :--- | :--- | :--- |
| `hello` | host → extension | `protocol`, `host`, `capabilities` |
| `hello` | extension → host | `protocol`, `extension`, `capabilities` |
| `action` / `action_result` | host → extension / back | `id`, `action`, `payload` / `status`, `data` or `error` |
| `event` | host → extension | `event`, `payload` |
| `host_call` / `host_call_result` | extension → host / back | `id`, `op`, `args` / `result` |
| `host_log` | extension → host | `level`, `message` |

Protocol `1`, handshake timeout five seconds. Capabilities are the frame types a side can
*receive*: the host declares `action_result`, `host_call`, `host_log`; an extension must declare
`action` and `event`. A protocol mismatch, a missing capability, or no answer at all is one log
line and a refusal - never a retry.

**Inbound events**: the runner subscribes to the events an extension declares in its manifest (with their declared
topic) and forwards them as `{"type":"event"}` frames. The extension handles them in an optional
`public void OnEvent(string name, TPayload payload)` — it is called even while an action is blocked on a
host call. The payload is deserialized to `TPayload`; register it on the extension's JSON context (below).

**Per-OS builds**: an extension is an assembly with a native apphost, so build for the deploy target:
`exo extension build <name> --rid linux-x64` (defaults to the host).

Extension payloads are **records**, not raw `JsonObject`/`JsonElement` — and the reason is the contract
rather than the runtime. A record has a *name*, and that name is what the manifest, the generated
client stub and the Studio describe; an anonymous object would serialise fine and be describable by
nobody. The SDK owns the JSON: action arguments and results, stored records, and event payloads are typed, and
`IDatabase` (accessed via `Exo.Database` or `[Inject]`) is a typed key/value store with a typed SQL runner.
Singleton configuration resources are declared with `[ExoSingletonResource]` and queried via `First<T>()`.

There is no `Main` to write and no `JsonSerializerContext` to declare — the generator emits the entry
point, and because an extension is framework-dependent, reflection serialises what it sends. An extension
that declares a context anyway is still honoured; nothing requires one.

```csharp
// Key/value via static Exo holder
var best = Exo.Database.Get<SnakeScoreRecord>("snake_scores", playerId);
Exo.Database.Put("snake_scores", playerId, record);

// Typed SQL: rows map onto records, args are positional ($1, $2, ...)
var top = Exo.Database.Query<SnakeScoreRecord>("SELECT * FROM snake_scores ORDER BY score DESC LIMIT $1", 10);
Exo.Database.Execute("DELETE FROM snake_scores WHERE score < $1", 0);
```

Keep `ExtensionHost.Run<...>()`'s `[DynamicallyAccessedMembers]` annotation intact — that is what keeps the
`[ExoAction]` methods and injected properties reachable. `JsonObject`/`JsonElement` remain available on
`HostBridge` for exotic cases, but extension code should not need them.

Action declarations follow conventions, so the attribute is usually bare:

- **Name** — `[ExoAction]` uses the method name in snake_case (`SubmitScore` → `submit_score`).
- **Mode** — inferred from the return type: `Task`/`Task<T>` → `:async`, anything concrete → `:sync`.
  (`ActionMode.Cast` is still explicit.)
- **Transport** — defaults to `:auto`.

Extensions call other services through **generated, region-agnostic stubs**: `exo extension stubs <name>`
reads the cluster contract export and writes `src/Generated/ExtensionServices.g.cs` (typed
request/response records + a typed client per service). Only the services in the extension's
`manifest.json` dependencies are generated (`--services a,b` overrides), so the file stays small. The host injects those clients (`[Inject("player_data")]
PlayerDataServiceClient PlayerData`), so extension code only deals with services and never touches
`IActionDispatcher`. The stubs depend on the service *contract*, never on the extension that implements it.

`ActionDispatcher` stays runtime-agnostic: every non-Elixir extension gets a generated proxy module
(`Exoforge.Drivers.Runtime.ExtensionProxy`) registered as its `entry_point`.

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
2. **Zero Module Coupling**: Extensions depend on **service atoms** (`:database`, `:auth`, `:player_data`), NEVER on another extension's Elixir module name. Use `ActionDispatcher.dispatch(service, action, payload)`.
3. **Pure C# Outside Mix**: External game developers and Unity designers do not have Elixir or Mix installed. All client tooling, scaffolding (`ExoScaffolder`), and code generation (`ExoCodeGenerator`) must remain pure C# (`netstandard2.1`).
4. **C# for Game Code**: Game extensions are written in C# and compiled to a framework-dependent .NET assembly. Keep the host boundary to newline-delimited JSON — that is what makes a different runtime a runner rather than a rewrite.
5. **No Distributed Locks**: State that has to be serialized belongs in an extension's own process. Do not introduce external distributed lock managers (no Redis locks, no ZooKeeper).
6. **Deletion Over Addition**: The best code is code you never had to write. Remove dead code, redundant wrappers, and unneeded abstractions ruthlessly.
7. **Test Small, Run Fast**: verify with the narrowest check that can fail - one test file, one
   suite, one build. Long operations - full suite sweeps, end-to-end runs, container and Unity
   builds - are unencouraged locally; they run in CI/CD, which does them faster and on every push.
   Write the wide tests and keep them green there, but do not pay for them on the developer's
   machine.

---

## 4. Commands Quick Reference

| Command | Action |
| :--- | :--- |
| `just test` | Run the whole test suite (core, extensions, system, C# SDKs) |
| `just test-e2e` | Run the live end-to-end vertical slice (WebSocket + extension + event loop) |
| `just dev` | Start backend development server (ports 4000, 4001, 4005) |
| `just build-extensions` | Build the system sample extension (`extensions_csharp/`) |
| `exo extension build <name>` | Build a game extension (framework-dependent .NET single file + `manifest.json`) |
| `exo extension push <name>` | Build and deploy an extension to a running cluster |
| `exo extension stubs <name>` | Generate typed service-call stubs from the cluster contracts |
| `just test-sdk` | Run the offline C# suite (`Exoforge.Client` unit, `Plugin.SDK`, `Generator`, `Management`) |
| `just compose-up` | Run full production stack with PostgreSQL via Docker Compose |
| `just compose-down` | Stop and tear down Compose stack |
| `just benchmark` | Run the cluster event fanout benchmark |
| `just sample-setup` | Rebuild the Unity Snake sample scene via the Unity CLI (idempotent) |
| `just sample-check` | Headless self-check for the Unity Snake sample (exit 0 = pass) |
| `just test-unity-package` | Clean Unity project integration test for package tarball, compilation check & live auth |

---

## 5. Agent & Contributor Guidelines

1. **Read before editing**: Inspect existing contracts and tests before adding new abstractions.
2. **Verify every change - with the smallest check that can fail**: run the relevant unit test file
   or one build, not the whole suite. The wide recipes (`just test`, `just test-e2e`) are CI's job:
   end-to-end integration is written here and run there, not locally.
3. **Honor the Rule**: Everything above the kernel is an extension.
4. **Shortest working diff wins**: Do not create speculative configuration, wrapper classes with one implementation, or premature abstractions.
5. **SDK Version Bumping**: Any changes to the Unity SDK or its bundled client libraries (`sdk/unity/Exoforge.SDK/` or `sdk/csharp/`) **must bump the version** in both [`sdk/unity/Exoforge.SDK/package.json`](sdk/unity/Exoforge.SDK/package.json) and [`ExoforgePackageVersion.cs`](sdk/unity/Exoforge.SDK/Editor/ExoforgePackageVersion.cs). This prevents stale package cache collisions in UPM (`Library/PackageCache/`), guarantees clean tarball releases via `just pack-unity`, and ensures cluster-to-editor update detection works reliably.
6. **UI Callouts, Banners & Contrast**: Never hardcode opaque or dark-on-dark text/background combinations (e.g. `text-blue-900`, `text-amber-950`, `text-rose-950`) without explicit dark variants (`dark:text-blue-200`, `dark:text-amber-200`, `dark:text-rose-200`) or theme-safe overrides in `exoforge-studio.css`. Prefer subtle alpha backgrounds with matching tinted borders (e.g. `bg-amber-500/10 border-amber-500/30 text-amber-950 dark:text-amber-200`) over opaque light backgrounds that turn illegible on dark surfaces.
7. **Placement of Disclaimers & Progressive Disclosure**: Disclaimers, architectural rationales, or contextual notes must **always come at the bottom** of the section content, never at the top. Never surprise the user with a prominent wall of text that preempts what they are actively seeking (code snippets, API catalog, or search bars). Put explanatory deep-dives and disclaimers under a collapsible fold (`<details>` / `<summary>`) so the primary flow stays uncluttered and direct.
