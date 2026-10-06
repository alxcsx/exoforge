# Exoforge Architecture & Simplification Plan (`plan.md`)

> **Status**: Monorepo Core Kernel, 7 Standard Plugins, C# Client SDK, C# Plugin SDK, C# Management Engine (`exo` CLI), Unity Engine SDK (`com.exoforge.sdk`), Game Producer Studio GUI, Distributed Clustering, and Production Kubernetes Manifests are **100% COMPLETE & VERIFIED** (**153 Elixir + 26 C# = 179 unit tests passing + live E2E vertical slice**).  
> **Verified Benchmarks**: 729,000 stateful actor calls/sec, 1.4 µs latency, 0.07 ms event fanout.

---

## 1. Ground Truth & Architectural Invariants

### The Rule, and Its One Exception
- **The Rule**: Everything above the kernel is a plugin.
- **The Exception**: The kernel itself is not a plugin (`PluginRegistry`, `ActionDispatcher`, `EventDispatcher`, `WorkerRegistry`, `DrawerRegistry`, `PluginSupervisor`, `PluginBootstrapper`, `Entities`).
- **Service Dependency Principle**: Plugins depend on **service atoms** (`:database`, `:auth`, `:player_data`), never on concrete Elixir module names. Swapping PostgreSQL for SQLite, or REST for gRPC, requires zero changes to consumer plugins.
- **Pure C# Outside Mix**: External game developers and Unity engineers do not have Elixir or Mix installed. All workspace initialization, plugin scaffolding, contract-to-client synthesis, and cluster deployments are written in pure C# (`netstandard2.1`).

### The Completed MVP Topology (Topological DAG)
```
database ──▶ auth ──▶ player_data
               │
               ├──▶ http (:4001)
               ├──▶ ws   (:4000)
               │
database ──────┴──▶ dashboard (:4005)
plugin_manager ───▶ (independent root)
```

---

## 2. Completed Milestones Ledger (M1–M23)

All 23 MVP milestones have been implemented, tested, and verified:

- [x] **M1–M6: Kernel Core, Contracts & Standard Plugins**: `PluginRegistry` ETS, `ActionDispatcher`, `EventDispatcher`, Bandit HTTP/WS ingress, WASM runtime (`wasmex`), SQLite DB, Auth, PlayerData.
- [x] **M7–M13: Studio LiveView, Distributed Actors & Clustering**: Phoenix LiveView Producer Studio (`:4005`), Horde delta-CRDT virtual actors, `:pg` cluster event fanout, 729k ops/sec cluster benchmark, Kubernetes manifests.
- [x] **M14–M17: DevEx, Typed Resources & Multi-Plugin WASM**: Global `Cmd+K` palette, live actor passivation, typed resource structs (`[ExoResource]`), dynamic action parameter forms, C# client generation.
- [x] **M18: Hardening, Zero Warnings & E2E Slice**: Cleaned all compiler warnings, integrated WebSocket `AuthenticateAsync`, restored green E2E test in 292 ms.
- [x] **M19: Standard Plugin Manager (`exoforge_std_plugin_manager`)**: `:plugin_manager` service contract, hot WASM upload (`\0asm` verification), runtime restart/reload, manifest export.
- [x] **M20: Standalone C# Management Engine (`Exoforge.Management` & `exo` CLI)**: Dual-targeted `netstandard2.1` / `net10.0` library, `exo` CLI tool (`init`, `plugin new`, `plugin build`, `plugin push`, `sync`, `status`), and dedicated Studio Plugin Manager GUI.
- [x] **M21: Unity Engine SDK (`com.exoforge.sdk`)**: Standard UPM layout, in-engine Control Center window (`Window > Exoforge > Control Center`), persistent `EditorPrefs`, one-click client code generation, and a shipped sample.
- [x] **M22: GameDev Control Center & Standalone Package**:
  - Gamedev-first Unity Editor window with live cluster ping, environment switcher, real-time event streaming monitor, in-engine RPC action sandbox, plugin manager, and typed client codegen. Now split across `ExoforgeControlCenter*.cs` partials.
  - Self-contained UPM distribution packaging target (`just pack-unity`) producing standalone `com.exoforge.sdk-0.1.0.tgz`.
  - Interactive `Samples~/BasicUsage` sample.

  > The LiveOps time primitives this milestone originally delivered (`Exoforge.TimeWindow`,
  > `schedule_timeline/1`, `calendar_view/1`, the schedule subtab, and `CombatDemoController`) were
  > **removed** in the simplification pass — see M25 below. The scaffolded `liveops` plugin template
  > that outlived them was removed with the DX pass (see `DX.md`).

---

## 3. Ponytail Architectural Simplification & Polish Opportunities

Following the **Ponytail** engineering doctrine (deletion over addition, standard library over dependencies, shortest working path), the following targeted simplifications are identified for ongoing polish:

### 1. Single Source of Truth for Client Code Generation [COMPLETED]
- **Status**: Completed. Deprecated and deleted `Mix.Tasks.Exo.Gen.Csharp`. Pure C# `ExoCodeGenerator.cs` in `Exoforge.Management` is the single authoritative compiler used by the `exo` CLI, Unity Editor, and automated CI workflows. Eliminates duplicate template maintenance across two languages.

### 2. Zero-Dependency WASM Host Boundary
- **Current State**: WASM plugins communicate with the host via JSON serialization over memory buffers.
- **Simplification**: Keep the WASM host boundary strictly to two functions:
  1. `host_dispatch(service, action, payload)` → calls the kernel.
  2. `host_emit_event(topic, payload)` → broadcasts through `EventDispatcher`.
  Avoid adding specialized C/FFI bindings per plugin. Uniform JSON/msgpack over raw memory pointers ensures any language that compiles to WASI (C#, Rust, Zig, C++) works immediately with zero host changes.

### 3. Native OTP Persistence Over Heavy ORMs
- **Current State**: `exoforge_std_database` supports PostgreSQL and a SQLite adapter.
- **Simplification**: In production, prefer raw SQL or light `:postgrex` query execution over heavy Ecto schemas inside standard plugins. Keep entity actor state boring: state is a serialized blob or JSON map persisted on passivation or periodic snapshot. Avoid complex relational object mappers for virtual actors.

### 4. Zero-Friction Container & Kubernetes Workflows
- **Current State**: Docker Compose and Kubernetes previously required 4-5 manual environment variables before starting.
- **Simplification**: Baked sensible local development defaults (`postgres` credentials, cluster cookies, secret keys) directly into `docker-compose.yml`, `deploy/k8s/secret.example.yaml`, and `Justfile`. Developers can run `just compose-up` or `just k8s-deploy` with zero environment configuration.

---

## 4. Post-MVP Growth Opportunities (Studio & Engine Expansion)

Future modular extensions to be built as plugins on top of the completed MVP kernel:

- [x] **M23: SQLite Local Mode** *(shipped)*
  - Delivered as `Exoforge.Std.Database.Adapters.Sqlite` plus the `:sqlite` driver, so an offline or
    single-node game needs no PostgreSQL daemon. This was listed as a future plugin; it is part of
    the standard database plugin instead.
- [ ] **M24: Unreal Engine SDK (`ExoforgeUE`)**
  - Native C++ client plugin for Unreal Engine 5 utilizing the same framed WebSocket protocol and code generation pipeline.
- [x] **M25: LiveOps Visual Flow & Rules Engine** *(withdrawn)*
  - The LiveOps surface (time windows, schedule timeline, calendar view) was **removed** in the
    simplification pass: it was speculative for a plugin platform whose game rules belong in the
    game, not in the backend. Kept here as a record of the decision, not as work to do. A game that
    wants scheduled content can express it as a plugin.
- [ ] **M26: Clustered Matchmaking & Lobby Plugin**
  - Authoritative matchmaking service plugin using Horde distributed state to group players into game sessions based on MMR and latency.

---

## 5. Current Milestone: M27 — Self-Contained Unity SDK & Runtime Hardening

> Registered in [`Agents.MD`](Agents.MD) §0 as the current task.
> Supersedes the packaging leftovers from [`DX.md`](DX.md) item 4.

### The rule this milestone establishes

**The Unity SDK package must be self-contained.** It ships as a UPM tarball into Unity projects that
have no Exoforge checkout anywhere near them. Everything the package needs at build time must live
inside the package, and nothing may assume this repository's layout.

- **No symlink may point outside the package.** The package is the unit of distribution; a link into
  `sdk/csharp/` is meaningless to a consumer.
- **No path may be resolved by walking up out of the package.** Reaching for `sdk/csharp/...` or a
  repo checkout is the same bug as a symlink, one directory removed.
- **No repo layout may appear in package code.** If a file is needed to build a plugin, it belongs
  inside the package.

Symlinks are acceptable *inside this repository* as a single-source-of-truth convenience for the
in-repo sample — `pack-unity` already materialises them into real files (`cp -RL`), verified. They
must never be load-bearing.

### Why now

The sample project is embedded in the source tree, so every path happens to resolve here and the
assumptions stay invisible. Two of them are already load-bearing:

| Where | Assumes |
| :--- | :--- |
| `ExoScaffolder.FindSdkProjectPath` | walks up for `sdk/csharp/Exoforge.Plugin.SDK/Exoforge.Plugin.SDK.csproj` or `csharp/Exoforge.Plugin.SDK/…` |
| `ExoDeployer.FindManifestGen` | walks up for `sdk/csharp/Exoforge.Management/Tools~/ManifestGen` |
| `pack-unity` output | carries **no** `Exoforge.Plugin.SDK` — a package-only user cannot build a plugin at all |

### Phase 1 — Make the package self-contained ✅

- [x] **1.1 The package is the source, not a copy of it.** `Runtime/*.cs` and
      `Editor/Management/*.cs` were symlinks into `sdk/csharp/` — meaningless to a consumer, and
      Unity could not reliably tell when the *target* of a link changed. They are now the real
      files, and they are canonical: `Exoforge.Client` and `Exoforge.Management` compile them
      directly rather than keeping a copy in step, so there is nothing to sync and nothing that can
      drift. A sync step would have meant the package was not what a client game actually gets.
      Verified: the package directory copied alone has zero symlinks and every source file, and
      `just clean-build` builds a plugin from a pristine export.
- [x] **1.2 The Plugin SDK is an explicit external dependency.** It is *not* bundled — it is the
      thing that must stay multiplatform, and a UPM tarball is the wrong channel for a `dotnet`
      package. A scaffolded plugin references the published `Exoforge.Plugin.SDK` and the generated
      csproj says so in a comment; pointing `EXOFORGE_PLUGIN_SDK` at a local checkout switches it
      to a `ProjectReference` and the comment changes to match. A bad override fails with the path
      it was given rather than a project that cannot restore.
- [x] **1.3 No path is resolved by walking out of the package.** `ExoDeployer.FindManifestGen` and
      `ExoScaffolder.FindSdkProjectPath` no longer climb the tree looking for `sdk/csharp`. The
      generator is found beside the assembly (the CLI copies it into its own output) or through an
      explicit path — the Unity editor resolves the package root with
      `PackageInfo.FindForAssembly` and passes it in.
- [x] **1.4 Failures name the file and the fix.** Missing toolchain says which path is absent, which
      env var overrides it, and where it ships.
- [x] **1.5 A packaging check.** `pack-unity` fails if the staged package resolves a path into this
      repository's layout (matching code shapes, not prose that mentions them). Verified it fires on
      an injected walk and passes on a clean package.
- [x] **1.6 `just unity-reimport`.** The only development convenience the package needs: clearing
      Unity's import caches so it re-reads the package. No generation step.

**Verified:** building `snake_leaderboard` through the Control Center's own code path now succeeds
end to end and writes `manifest.exs` — previously it failed with
`The provided file path does not exist: .../Packages/com.exoforge.sdk/Editor/Management/Tools~/ManifestGen`.

### Phase 2 — Runtime correctness

- [ ] **2.1 A failed connection is permanent.** `ExoforgeBehaviour` sets `_pendingConnect` once and
      never clears it; `ConnectAsync` catches and returns `false`, so the task completes
      *successfully* and every later `GetClientAsync()` re-throws. Backend down at boot = the game
      never connects, with no retry. Clear the field in a `finally`.
- [ ] **2.2 `_instance` is never cleared on destroy.** `OnDestroy` only disconnects, so
      `Current`/`Instance` return a destroyed object and game code gets a `MissingReferenceException`
      instead of the intended "no ExoforgeBehaviour in the scene".
- [ ] **2.3 Reconnect race in `ExoTransport.ConnectAsync`.** It cancels `_cts` and immediately
      replaces `_webSocket`, without awaiting the old receive loop. The old loop reads `_webSocket`
      through the field, so it can issue a second `ReceiveAsync` on the *new* socket, or fire a late
      `OnDisconnected`. Await the previous loop before swapping.
- [ ] **2.4 A stale display name survives reconnecting to another account.** `SaveSession` only
      writes the name when non-null, and `ExoforgeBehaviour.ConnectAsync` passes none — so a name
      from a previous account persists and `ExoSession.DisplayName` reports the wrong player.

### Phase 3 — DX

- [ ] **3.1 The HTTP port is invented, not configured.** `ExoClient.ConnectAsync` does
      `uri.Port == 4000 ? 4001 : uri.Port`. Wrong for any non-default gateway; when it fails the
      `catch { }` leaves `HttpBaseUri` null so HTTP transport is silently unavailable. Take it from
      `exoforge.json`, which already carries `http_url`.
- [ ] **3.2 Stop swallowing connect errors.** Three `catch { }` blocks on the connect path
      (`ExoClient`, `ExoTransport`, `ExoforgeBehaviourEditor`).
- [ ] **3.3 Make timeouts configurable.** `FromSeconds(5)` / `(5)` / `(10)` are magic numbers with no
      client-wide default, so a cold first call fails with a bare `TimeoutException`.
- [ ] **3.4 Reconnect with backoff.** `Update()` keeps pumping a dead dispatcher; nothing reconnects
      and nothing tells the game. Depends on 2.3.
- [ ] **3.5 `ExoTokenStore` writes to disk four times per `SaveSession`** (every setter calls
      `PlayerPrefs.Save()`), while `ExoDeviceId.Reset()` is the one place that does not save.
- [ ] **3.6 Scopes are stored comma-joined** and split on read — a scope containing a comma silently
      becomes two.

### Phase 4 — API shape

- [ ] **4.1 One way to get a client.** `ExoforgeBehaviour.Client` (public, nullable) and
      `ExoforgeSDK.Client` (throws) have different failure modes; the nullable one is more
      discoverable and the docs only ask nicely.
- [ ] **4.2 Encapsulate transport state.** `AuthToken`, `HttpBaseUri` and `HttpClient` are public
      settable on `ExoClient`, so game code can corrupt a live connection.
- [ ] **4.3 Drop the loose `SendActionAsync(object? payload)` overload.** It accepts anything and
      fails server-side; the typed overloads are the ones to reach for.

### How this milestone is verified

**Clean-room check** — the analogue of `just clean-build`, and the only test that proves the rule:

1. Build the UPM tarball.
2. Unpack it into a Unity project **outside this repository**.
3. Scaffold a plugin, build it, deploy it, call an action.
4. Nothing may reference this repo; no env var may be set.

Add it as `just clean-room-sdk` so it can run in CI alongside `clean-build`.

### Out of scope

Everything in `DX.md` items 1–21 is done. The resource-table primary-key bug (`DX.md` item 22) is a
kernel/database issue, not SDK packaging, and stays where it is.
