# Exoforge Architecture & Plan (`plan.md`)

> **Status**: Kernel, 7 standard plugins, C# Client SDK, C# Plugin SDK, C# Management Engine (`exo` CLI),
> Unity SDK (`com.exoforge.sdk`), Producer Studio, clustering and Kubernetes manifests are **complete**
> — **230 Elixir + 47 C# = 277 tests passing**, plus a live E2E vertical slice.
> **Benchmarks**: 729k stateful actor ops/sec, 1.4 µs latency, 0.07 ms 50x event fanout.

---

## 1. Ground Truth & Invariants

**The Rule**: everything above the kernel is a plugin.
**The Exception**: the kernel is not — `PluginRegistry`, `ActionDispatcher`, `EventDispatcher`,
`WorkerRegistry`, `PluginSupervisor`, `PluginBootstrapper`, `Entities`.

- **Service atoms, never module names.** Plugins depend on `:database`, `:auth`, `:player_data`.
  Swapping PostgreSQL for SQLite changes no consumer.
- **Pure C# outside Mix.** Game developers have no Elixir toolchain. Workspace init, scaffolding,
  codegen and deploy are pure C# (`netstandard2.1`).
- **The Unity package is the unit of distribution.** It ships into projects with no Exoforge checkout
  anywhere near them, so it must work exactly as it is shipped. See M27.

```
database ──▶ auth ──▶ player_data
               │
               ├──▶ http (:4001)
               ├──▶ ws   (:4000)
database ──────┴──▶ dashboard (:4005)
plugin_manager ───▶ (independent root)
```

---

## 2. Completed Milestones

Numbers are historical identifiers, not a sequence to maintain — they are referenced from
`Agents.MD`, `DX.md` and commit messages.

| M | Delivered |
| :--- | :--- |
| **M1–M6** | Kernel (`PluginRegistry` ETS, `ActionDispatcher`, `EventDispatcher`), Bandit HTTP/WS ingress, WASM runtime (`wasmex`), SQLite DB, Auth, PlayerData |
| **M7–M13** | Producer Studio (LiveView, `:4005`), Horde delta-CRDT virtual actors, `:pg` event fanout, cluster benchmark, Kubernetes manifests |
| **M14–M17** | `Cmd+K` palette, actor passivation, typed resources (`[ExoResource]`), dynamic action forms, C# client generation |
| **M18** | Zero compiler warnings, WebSocket `AuthenticateAsync`, green E2E slice |
| **M19** | `exoforge_std_plugin_manager`: hot WASM upload, runtime reload, manifest export |
| **M20** | C# Management engine + `exo` CLI — `init`, `plugin new\|build\|push\|dev\|reload\|logs\|stubs\|list\|remove`, `sync`, `status`. `push` verifies the deployed version; `dev` redeploys on save; `logs` reads back plugin output |
| **M21** | Unity SDK `com.exoforge.sdk` — one game-facing entry point (`ExoforgeSDK.Auth`/`.Client`/`.ConnectAsync`), device-keyed two-stage anonymous sign-in, prefab created on demand, `Samples~/BasicUsage` |
| **M22** | Control Center window — cluster ping, environment switcher, event monitor, action sandbox, plugin scaffold/build/deploy/logs, typed codegen. Split across `ExoforgeControlCenter*.cs` partials; `just pack-unity` builds the tarball |
| **M23** | SQLite local mode — `Exoforge.Std.Database.Adapters.Sqlite` + `:sqlite` driver, no PostgreSQL daemon needed |
| **M24** | Plugin Tooling DX ([`DX.md`](DX.md)) — 21 fixes across plugin creation, upload and management |
| **M25** | LiveOps *(withdrawn)* — time windows, schedule timeline and calendar view removed; game rules belong in the game, not the platform |

---

## 3. Standing Principles

Following the Ponytail doctrine — deletion over addition, standard library over dependencies,
shortest working path.

- **One code generator.** Pure C# `ExoCodeGenerator` is the single source for client bindings; the
  old Mix task is gone.
- **Keep the WASM host boundary small.** JSON over memory buffers, no per-plugin FFI bindings, so any
  WASI language works unchanged.
- **No heavy ORMs.** Raw SQL or light `:postgrex`; actor state is a serialized blob, not a relational
  object graph.
- **Zero-config containers.** Local defaults are baked into `docker-compose.yml`, the K8s manifests
  and the `Justfile`, so `just compose-up` needs no environment setup.

---

## 4. Future Work (not yet numbered)

Listed by name — numbering speculative work is what produced the duplicate and mis-stated entries this
ledger used to carry. Number it when it starts.

- [ ] **Unreal Engine SDK (`ExoforgeUE`)** — native C++ client on the same framed WebSocket protocol
      and code generation pipeline.
- [ ] **Clustered Matchmaking & Lobby Plugin** — Horde-backed matchmaking by MMR and latency.

---

## 5. M27 — Self-Contained Unity Package ✅

**Done and verified.** The invariant it establishes:

1. **No symlink leaves the package.** Its files are the source; nothing to sync, nothing to drift.
2. **No path is resolved by walking out of the package.**
3. **Nothing in package code names this repository's layout.**
4. **`Exoforge.Plugin.SDK` is an explicit external dependency**, not something the package carries.

| Was | Is |
| :--- | :--- |
| `Runtime/*.cs`, `Editor/Management/*.cs` symlinked into `sdk/csharp/` | real files in the package, and canonical |
| `Exoforge.Client` / `Exoforge.Management` held the sources | they compile the package's files |
| `FindManifestGen` / `FindSdkProjectPath` walked up for `sdk/csharp` | resolved beside the assembly, or passed in |
| scaffolder emitted a `ProjectReference` to a repo path | the published `PackageReference`, or a local one via `EXOFORGE_PLUGIN_SDK` |
| the manifest generator lived in `sdk/csharp` and was copied | lives only at `Editor/Management/Tools~/ManifestGen` |

Running `just clean-room-sdk` for the first time found and fixed `ExoWorkspace.Initialize` writing
`exoforge.json` into a directory it never created — the first action a new developer takes.

---

## 6. M28 — SDK Runtime Hardening

> Registered in [`Agents.MD`](Agents.MD) §0 as the current task. Each item says what proves it
> finished.

**Order matters.** Do 2.1–2.2 first (one-liners that make the SDK work the first time someone tries
it), then 2.4, then 2.3 — which gates reconnect.

### Correctness

- [x] **2.1 A failed connection is permanent.** `_pendingConnect` was set once and never cleared, so
      every later `GetClientAsync()` awaited the same finished task. Cleared in a `finally`.
      *Proven by:* `SessionLifecycleTests.A_failed_connection_can_be_retried` — and it fails when that
      line is reverted, because the second call then never attempts a connection.
- [x] **2.2 `_instance` is never cleared on destroy.** `OnDestroy` only disconnected, so
      `Current`/`Instance` returned a destroyed object. Cleared first, before the teardown awaits.
      *Proven by:* `SessionLifecycleTests.Instance_is_cleared_when_the_behaviour_is_destroyed`.
- [ ] **2.3 Reconnect race in `ExoTransport.ConnectAsync`.** It cancels `_cts` and immediately
      replaces `_webSocket` without awaiting the old receive loop, which reads `_webSocket` through
      the field — so it can issue a second `ReceiveAsync` on the *new* socket, or fire a late
      `OnDisconnected`. *Done when:* connecting twice leaves one receive loop.
      *Proves it:* `Exoforge.Client.Tests`.
- [x] **2.4 A stale display name survives reconnecting to another account.** `SaveSession` now clears
      the name when the player id changes — a reconnect as the same player keeps it, a different
      account cannot inherit it. *Proven by:* two `SessionLifecycleTests` cases.

### DX

- [ ] **3.1 The HTTP port is invented, not configured.** `uri.Port == 4000 ? 4001 : uri.Port` is wrong
      for any non-default gateway, and when it fails a `catch { }` leaves `HttpBaseUri` null so HTTP
      transport is silently unavailable. `exoforge.json` already carries `http_url`.
      *Proves it:* `Exoforge.Client.Tests`.
- [ ] **3.2 Stop swallowing connect errors.** Three `catch { }` on the connect path (`ExoClient`,
      `ExoTransport`, `ExoforgeBehaviourEditor`) — a mistyped URL fails with no explanation anywhere.
- [ ] **3.3 Make timeouts configurable.** `FromSeconds(5)`/`(5)`/`(10)` are magic numbers with no
      client-wide default, so a cold first call fails with a bare `TimeoutException`.
- [ ] **3.4 Reconnect with backoff.** `Update()` keeps pumping a dead dispatcher; nothing reconnects
      and nothing tells the game. **Depends on 2.3.** Two notes from building the tests:
      `OnDisconnected` is delivered *through the dispatcher*, so once `Update()` stops being called
      (behaviour disabled or destroyed) disconnect notifications stop too — a reconnect timer must not
      depend on the pump. And `ConnectAsync` logs a failed attempt with `Debug.LogError`, so a retry
      loop would put a red error in the console per attempt; that should become a warning.
- [ ] **3.5 `ExoTokenStore` writes to disk four times per `SaveSession`** (every setter calls
      `PlayerPrefs.Save()`), while `ExoDeviceId.Reset()` is the one place that does *not* save.
      *Proves it:* `ExoforgeSampleCheck`.
- [ ] **3.6 Scopes are stored comma-joined** and split on read — a scope containing a comma silently
      becomes two. Store as JSON, or reject commas.

### API shape

- [ ] **4.1 One way to get a client.** `ExoforgeBehaviour.Client` (public, nullable) and
      `ExoforgeSDK.Client` (throws) have different failure modes; the nullable one is more
      discoverable and the docs only ask nicely.
- [ ] **4.2 Encapsulate transport state.** `AuthToken`, `HttpBaseUri` and `HttpClient` are public
      settable on `ExoClient`, so game code can corrupt a live connection.
- [ ] **4.3 Drop the loose `SendActionAsync(object? payload)` overload.** It accepts anything and fails
      server-side; the typed overloads are the ones to reach for.

### Release work (not code)

- [ ] **Publish `Exoforge.Plugin.SDK`.** A scaffolded plugin references it and the build fails with
      `NU1101`. The code path is proven — a local feed makes `just clean-room-sdk` pass — but nothing
      is published, so a consumer can scaffold but not build. `dotnet pack sdk/csharp/Exoforge.Plugin.SDK`.

### How this is verified

| Check | Covers | Speed |
| :--- | :--- | :--- |
| `just test` | kernel, plugins, SDK libraries | fast |
| `just clean-build` | a pristine export of HEAD builds a plugin | slow |
| `just pack-unity` | the package resolves nothing into this repo | fast |
| `just clean-room-sdk` | a new Unity project installs the tarball and builds a plugin | slow |
| `just sample-check` | sample scene, board maths, leaderboard parsing | fast |
| `just sample-play-tests` | `ExoforgeBehaviour` lifecycle, token store | medium |
| `Exoforge.Client.Tests` | transport and client behaviour | fast |

**Two gaps this milestone depends on:**

1. ~~**`ExoClient` / `ExoTransport` have no unit coverage.**~~ **Done** — `StubWebSocketServer` plus
   `TransportTests` (connect, action round trip, server error, dropped connection). They are
   Unity-free, so this is where reconnect, timeout and error-surfacing get pinned.
2. ~~**`ExoforgeBehaviour` is Unity-only.**~~ **Done** — `Assets/Tests/PlayMode` on the Unity test
   framework (`just sample-play-tests`). Play mode, not edit: `Awake` does not run in the editor, so
   the behaviour is inert there and none of its lifecycle is observable. `ExoforgeSampleCheck` stays
   for the headless parts. Note for 3.5: the framework fails a test on an unexpected
   `Debug.LogError`, so a test expecting a failed connect must declare it.

**Not covered at all:** `Sync Client Bindings` needs a live cluster, so nothing proves the generated
client compiles inside a fresh project. A fresh project compiles `Assets/` as **C# 9** and the
generated client avoids C# 10+ features — assert it rather than assume it.

### Non-goals

- The resource-table primary-key bug ([`DX.md`](DX.md) item 22) is a kernel/database issue.
- No new runtime dependency, and no test framework beyond the two above.
