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
- [x] **2.3 Reconnect in `ExoTransport.ConnectAsync`.** *(The original description overstated this:
      the receive loop checks its cancellation token first, so a cancelled token already blocked
      re-entry and a second `ReceiveAsync` on the new socket was not reachable.)* What was real:
      `_webSocket?.Dispose()` disposed the old socket while its loop could still be inside
      `ReceiveAsync`, whose `ObjectDisposedException` surfaced as a **spurious `OnDisconnected` after a
      successful reconnect**; and both the loop and the teardown path could notify, so one connection
      could report two disconnects. Fixed by draining the previous connection before swapping, passing
      the socket and token to the loop so it never reads a field a later connect can replace, and
      reporting at most one disconnect per connection.
      *Guarded by:* `TransportTests` — reconnect then assert every frame arrives and one disconnect is
      reported. These are guards, not proofs: the window is too narrow to reproduce deterministically
      from outside, so the guarantee is structural (the loop no longer reads the field).
- [x] **2.4 A stale display name survives reconnecting to another account.** `SaveSession` now clears
      the name when the player id changes — a reconnect as the same player keeps it, a different
      account cannot inherit it. *Proven by:* two `SessionLifecycleTests` cases.

### DX

- [x] **3.1 The HTTP port is invented, not configured.** The derivation is gone; `HttpBaseUri` comes
      from the workspace environment (`ExoDeployer` sets it) or from whoever constructs the client.
      *Proven by:* two `TransportTests` — a connect leaves it null, and a configured one is kept.
- [x] **3.2 Stop swallowing errors.** The `catch { }` around the HTTP-base derivation went with 3.1.
      In the Control Center, a failed disconnect during teardown now logs, and a failed telemetry
      fetch reports in the status bar — it used to leave the window showing stale telemetry and a
      stale service catalog with nothing to say why. (My review had listed a third site in
      `ExoforgeBehaviourEditor`; there is none.)
- [x] **3.3 Make timeouts configurable.** `ExoClient.DefaultTimeout` replaces the three magic
      numbers, overridable per call; `ExoTransport.CloseTimeout` bounds the close handshake, which
      had none — `DisconnectAsync` awaited `CloseAsync` forever if the peer never replied, which is
      what hung the test suite until the stub was made to reply.
      *Proven by:* `TransportTests.The_default_timeout_is_configurable`.
- [x] **3.4 Reconnect with backoff.** `ExoforgeBehaviour` retries with exponential backoff
      (`ExoBackoff`, capped at 30s by default), starting from a **failed first connect** as well as
      from a drop — a backend that is not up yet is the common case at boot, and was the motivating
      one. A background task, not something driven from `Update()`, because disconnect notifications
      go through the dispatcher and a behaviour that stops pumping would never reconnect.
      *Proven by:* `BackoffTests` (the doubling and the cap, Unity-free) and a play-mode test that a
      failed connect announces its first retry — a log line only the retry loop emits.
      Two notes from building the tests:
      `OnDisconnected` is delivered *through the dispatcher*, so once `Update()` stops being called
      (behaviour disabled or destroyed) disconnect notifications stop too — a reconnect timer must not
      depend on the pump. And `ConnectAsync` logs a failed attempt with `Debug.LogError`, so a retry
      loop would put a red error in the console per attempt; that should become a warning.
- [x] **3.5 `ExoTokenStore` wrote to disk four times per `SaveSession`.** Setters now write without
      flushing; `SaveSession` and `Clear` flush once. `ExoDeviceId.Reset()` flushes too, which was the
      one write that did not.
- [x] **3.6 Scopes are stored comma-joined.** *(Not a defect: `ExoTokenStore.Scopes` is never read —
      not by the SDK, not by the sample. The string is write-only, so nothing splits it and no scope
      can be corrupted by a comma. Left as-is rather than changing a public property's format for a
      consumer that does not exist. If one appears, that is when to fix the encoding.)*

### API shape

- [x] **4.1 One way to get a client.** *(Partly a correction: `ExoforgeBehaviour.Client` has
      legitimate users — the editor window and the play-mode tests — so making it internal would
      break them for little gain.)* The real defect was the inconsistency: `ExoforgeSDK.Client`
      returned a client whenever one had been *constructed*, and a failed connect constructs one
      before failing, so it handed back a dead client and the caller failed later somewhere
      confusing. It now requires `IsConnected`, and says so.
- [x] **4.2 Encapsulate transport state.** `AuthToken` is `private set` — it was public and only ever
      written inside `ExoClient`. *(The other two were already fine: `HttpClient` is get-only, and
      `HttpBaseUri` is legitimately settable because it is configuration — which 3.1 made explicit.)*
- [x] **4.3 The loose `SendActionAsync` overload.** *(Not a defect: there is no separate loose
      overload — `payload` is `object?` on the two that exist, which is inherent to a wire-level
      client. The generated service clients are the typed path and are what callers should use; the
      editor's own calls pass `null` for a no-payload action.)*

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
