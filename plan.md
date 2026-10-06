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

## 2. Completed Milestones Ledger

Delivered, tested and verified. Numbers are historical identifiers, not a sequence to keep in step —
they are referenced from `Agents.MD`, `DX.md` and commit messages.

- [x] **M1–M6: Kernel Core, Contracts & Standard Plugins**: `PluginRegistry` ETS, `ActionDispatcher`, `EventDispatcher`, Bandit HTTP/WS ingress, WASM runtime (`wasmex`), SQLite DB, Auth, PlayerData.
- [x] **M7–M13: Studio LiveView, Distributed Actors & Clustering**: Phoenix LiveView Producer Studio (`:4005`), Horde delta-CRDT virtual actors, `:pg` cluster event fanout, 729k ops/sec cluster benchmark, Kubernetes manifests.
- [x] **M14–M17: DevEx, Typed Resources & Multi-Plugin WASM**: Global `Cmd+K` palette, live actor passivation, typed resource structs (`[ExoResource]`), dynamic action parameter forms, C# client generation.
- [x] **M18: Hardening, Zero Warnings & E2E Slice**: Cleaned all compiler warnings, integrated WebSocket `AuthenticateAsync`, restored green E2E test in 292 ms.
- [x] **M19: Standard Plugin Manager (`exoforge_std_plugin_manager`)**: `:plugin_manager` service contract, hot WASM upload (`\0asm` verification), runtime restart/reload, manifest export.
- [x] **M20: Standalone C# Management Engine (`Exoforge.Management` & `exo` CLI)**: dual-targeted
  `netstandard2.1` / `net10.0` library and the `exo` CLI (`init`, `plugin new|build|push|dev|reload|
  logs|stubs|list|remove`, `sync`, `status`). `push` builds, deploys and then **verifies the version
  the cluster is actually running**; `dev` watches sources and redeploys; `logs` reads back what the
  plugin emitted. The library compiles its sources from the Unity package (see M27) rather than
  keeping a copy, and `Exoforge.Plugin.SDK` is packable.
- [x] **M21: Unity Engine SDK (`com.exoforge.sdk`)**: UPM package, **self-contained** — its files
  are the source of truth, with no symlinks and no assumption about this repository's layout (M27).
  One game-facing entry point (`ExoforgeSDK.Auth` / `.Client` / `.ConnectAsync`), a device-keyed
  two-stage anonymous sign-in, a standard prefab created on demand when absent, and
  `Samples~/BasicUsage`.
- [x] **M22: Producer Studio Surface (Unity Editor)**: the Control Center window — live cluster ping,
  environment switcher, event stream monitor, action sandbox, plugin scaffold/build/deploy/logs, and
  typed client codegen. Split across `ExoforgeControlCenter*.cs` partials so the tab you work on is
  the file you open. `just pack-unity` produces the standalone tarball.

  > The LiveOps time primitives this milestone originally delivered (`Exoforge.TimeWindow`,
  > `schedule_timeline/1`, `calendar_view/1`, the schedule subtab, and `CombatDemoController`) were
  > **removed** in the simplification pass — see M25. The scaffolded `liveops` plugin template that
  > outlived them was removed with the DX pass (see `DX.md`).

- [x] **M23: SQLite Local Mode**: delivered as `Exoforge.Std.Database.Adapters.Sqlite` plus the
  `:sqlite` driver, so an offline or single-node game needs no PostgreSQL daemon. Listed for a long
  time as a future plugin; it belongs in the standard database plugin instead.
- [x] **M24: Plugin Tooling DX** ([`DX.md`](DX.md)): a DevEx pass over plugin creation, upload and
  management — `push` no longer uploads the previous binary after a failed build, the Action Sandbox
  reads its catalog from the live export instead of a stale hardcoded one, plugin logs became
  reachable, and the CLI gained per-subcommand help, `--json` and actionable errors.
- [x] **M25: LiveOps Visual Flow & Rules Engine** *(withdrawn)*: the LiveOps surface (time windows,
  schedule timeline, calendar view) was **removed** in the simplification pass — it was speculative
  for a platform whose game rules belong in the game. Recorded as a decision, not as work to do.

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

## 4. Future Work (not yet numbered)

Listed by name. Numbering speculative work is what produced the duplicate and mis-stated entries this
ledger used to carry; number it when it starts.

- [ ] **Unreal Engine SDK (`ExoforgeUE`)**
  - Native C++ client plugin for Unreal Engine 5 using the same framed WebSocket protocol and code
    generation pipeline.
- [ ] **Clustered Matchmaking & Lobby Plugin**
  - Authoritative matchmaking service plugin using Horde distributed state to group players into game
    sessions based on MMR and latency.

## 5. Current Milestone: M27 — Self-Contained Unity SDK & Runtime Hardening

> Registered in [`Agents.MD`](Agents.MD) §0.
> **Phase 1 is done and verified.** Phases 2–4 are ready to execute; each item below says what
> proves it finished.

### The invariant

**The Unity package is the unit of distribution and must work exactly as it is shipped.** It is
installed into Unity projects that have no Exoforge checkout anywhere near them.

1. **No symlink leaves the package.** The package's files are the source; there is nothing to sync
   and nothing that can drift.
2. **No path is resolved by walking out of the package.** Reaching for `sdk/csharp/...` is the same
   bug as a symlink, one directory removed.
3. **Nothing in package code names this repository's layout.**
4. **`Exoforge.Plugin.SDK` is an explicit external dependency**, not something the package carries.

### Phase 1 — Make the package self-contained ✅

Done and verified. What it changed, for reference:

| Was | Is |
| :--- | :--- |
| `Runtime/*.cs`, `Editor/Management/*.cs` symlinked into `sdk/csharp/` | real files in the package, and canonical |
| `Exoforge.Client` / `Exoforge.Management` held the sources | they compile the package's files (`<Compile Include>`) |
| `FindManifestGen` / `FindSdkProjectPath` walked up for `sdk/csharp` | resolved beside the assembly, or passed in explicitly |
| scaffolder emitted a `ProjectReference` to a repo path | emits the published `PackageReference`, or a local one via `EXOFORGE_PLUGIN_SDK` |
| the manifest generator lived in `sdk/csharp` and was copied | lives only at `Editor/Management/Tools~/ManifestGen` |

Verified by `just clean-build` (pristine export builds a plugin), `just pack-unity` (asserts the
package resolves nothing into this repo), and `just clean-room-sdk` (a new Unity project installs
the tarball and builds a plugin). Running the last one found and fixed `ExoWorkspace.Initialize`
writing `exoforge.json` into a directory it never created — the first action a new developer takes.

---

### Phase 2 — Runtime correctness

Do these in order: 2.1 and 2.2 are one-liners that make the SDK behave correctly the first time
someone tries it, 2.4 is a data-correctness bug, and 2.3 is a prerequisite for 3.4.

- [ ] **2.1 A failed connection is permanent.**
      `ExoforgeBehaviour` sets `_pendingConnect` once and never clears it; `ConnectAsync` catches and
      returns `false`, so the task completes *successfully* and every later `GetClientAsync()`
      re-throws "not connected". Backend down at boot means the game never connects and cannot retry.
      *Done when:* a second `GetClientAsync()` after a failed connect actually retries.
      *Proves it:* `ExoforgeSampleCheck` — point the sample at a dead port and call twice.
- [ ] **2.2 `_instance` is never cleared on destroy.**
      `OnDestroy` only disconnects, so `Current`/`Instance` return a destroyed object and game code
      gets a `MissingReferenceException` instead of the intended "no ExoforgeBehaviour in the scene".
      *Done when:* after the behaviour is destroyed, `Instance` throws the intended message.
      *Proves it:* `ExoforgeSampleCheck`.
- [ ] **2.3 Reconnect race in `ExoTransport.ConnectAsync`.**
      It cancels `_cts` and immediately replaces `_webSocket`, without awaiting the old receive loop.
      The old loop reads `_webSocket` through the field, so it can issue a second `ReceiveAsync` on
      the *new* socket, or fire a late `OnDisconnected` that a reconnect handler misreads.
      *Done when:* connecting twice in a row leaves exactly one receive loop running.
      *Proves it:* `Exoforge.Client.Tests` — the transport is Unity-free, so this belongs there.
- [ ] **2.4 A stale display name survives reconnecting to another account.**
      `SaveSession` only writes the name when non-null, and `ExoforgeBehaviour.ConnectAsync` passes
      none — so a name from a previous account persists and `ExoSession.DisplayName` reports the
      wrong player. In the sample that puts someone else's name on the leaderboard.
      *Done when:* a session with no name clears the stored one.
      *Proves it:* `Exoforge.Client.Tests` or `ExoforgeSampleCheck`.

### Phase 3 — DX

- [ ] **3.1 The HTTP port is invented, not configured.**
      `ExoClient.ConnectAsync` does `uri.Port == 4000 ? 4001 : uri.Port`. Wrong for any non-default
      gateway, and when it fails the `catch { }` leaves `HttpBaseUri` null so HTTP transport is
      silently unavailable. `exoforge.json` already carries `http_url`.
      *Done when:* the HTTP base comes from config, and its absence is reported.
      *Proves it:* `Exoforge.Client.Tests`.
- [ ] **3.2 Stop swallowing connect errors.** Three `catch { }` on the connect path (`ExoClient`,
      `ExoTransport`, `ExoforgeBehaviourEditor`) — a mistyped URL fails with no explanation anywhere.
      *Proves it:* `Exoforge.Client.Tests`.
- [ ] **3.3 Make timeouts configurable.** `FromSeconds(5)` / `(5)` / `(10)` are magic numbers with no
      client-wide default, so a cold first call fails with a bare `TimeoutException`.
      *Proves it:* `Exoforge.Client.Tests`.
- [ ] **3.4 Reconnect with backoff.** `Update()` keeps pumping a dead dispatcher; nothing reconnects
      and nothing tells the game. **Depends on 2.3** — reconnecting is unsafe until the old receive
      loop is awaited.
      *Proves it:* `Exoforge.Client.Tests` against a stub server that drops the connection.
- [ ] **3.5 `ExoTokenStore` writes to disk four times per `SaveSession`** (every setter calls
      `PlayerPrefs.Save()`), while `ExoDeviceId.Reset()` is the one place that does *not* save.
      *Proves it:* `ExoforgeSampleCheck` — assert one save per session.
- [ ] **3.6 Scopes are stored comma-joined** and split on read — a scope containing a comma silently
      becomes two. Store them as JSON, or reject commas.
      *Proves it:* `Exoforge.Client.Tests` (the encode/decode pair is Unity-free if it moves to
      `ExoSession`).

### Phase 4 — API shape

- [ ] **4.1 One way to get a client.** `ExoforgeBehaviour.Client` (public, nullable) and
      `ExoforgeSDK.Client` (throws) have different failure modes; the nullable one is more
      discoverable and the docs only ask nicely.
      *Done when:* there is one documented way to get a client, and the other is internal.
- [ ] **4.2 Encapsulate transport state.** `AuthToken`, `HttpBaseUri` and `HttpClient` are public
      settable on `ExoClient`, so game code can corrupt a live connection.
- [ ] **4.3 Drop the loose `SendActionAsync(object? payload)` overload.** It accepts anything and
      fails server-side; the typed overloads are the ones to reach for.

### Release work (not code)

- [ ] **Publish `Exoforge.Plugin.SDK`.** A scaffolded plugin references it and the build fails with
      `NU1101: Unable to find package Exoforge.Plugin.SDK`. The code path is proven — a local feed
      makes `just clean-room-sdk` pass — but nothing is published, so a consumer cannot build a
      plugin yet. `dotnet pack sdk/csharp/Exoforge.Plugin.SDK` produces the package.

---

### How this milestone is verified

| Check | Covers | Runs |
| :--- | :--- | :--- |
| `just test` | kernel, plugins, SDK libraries | always |
| `just clean-build` | a pristine export of HEAD builds a plugin | always |
| `just pack-unity` | the package resolves nothing into this repo | always |
| `just clean-room-sdk` | a new Unity project installs the tarball and builds a plugin | slow (creates a project + NativeAOT publish) |
| `just sample-check` | the sample scene, board maths, leaderboard parsing | fast |
| `Exoforge.Client.Tests` | transport and client behaviour | fast |

**Two gaps in that table, which Phases 2–4 depend on:**

1. **`ExoClient` / `ExoTransport` have no unit coverage** — only `VerticalSliceIntegrationTests`,
   which needs a live cluster. They are Unity-free, so reconnect, timeout and error-surfacing
   behaviour belongs in `Exoforge.Client.Tests` behind a small local WebSocket stub. **Write the stub
   first**: 2.3, 3.1, 3.2, 3.3 and 3.4 are all otherwise unverifiable.
2. **`ExoforgeBehaviour` is Unity-only**, so it cannot be unit-tested here. It is covered by
   `ExoforgeSampleCheck`, which already runs headless through the Unity CLI — extend it for 2.1, 2.2,
   2.4 and 3.5 rather than inventing a test framework.

**Not yet covered at all:** `Sync Client Bindings` needs a live cluster, so nothing proves the
generated client compiles inside a fresh project. A fresh project compiles `Assets/` as **C# 9**
(hit while writing the clean-room probe) and the generated client avoids C# 10+ features — but that
should be asserted, not assumed. Extend `clean-room-sdk` to run against a server.

### Non-goals

- The resource-table primary-key bug ([`DX.md`](DX.md) item 22) is a kernel/database issue, not SDK
  packaging. It stays where it is.
- Nothing in `DX.md` items 1–21; that milestone is done.
- No new runtime dependency, and no test framework beyond the two above.
