# Exoforge Architecture & Plan (`plan.md`)

> **Status**: Kernel, 9 standard plugins, C# Client SDK, C# Plugin SDK, C# Management Engine (`exo`
> CLI), Unity SDK (`com.exoforge.sdk`), Producer Studio, clustering and Kubernetes manifests are
> **complete** — **240 Elixir + 72 C# = 312 tests passing**, plus a live E2E vertical slice.
> **Benchmark**: 0.07 ms fanout to 50 event subscribers over `:pg`.

Completed work is not kept here. It is in `git log`, which is the record that does not drift; this
file is the invariants and what is next. Milestone identifiers (**M1**…**M30**) are historical and are
referenced from `Agents.MD`, `DX.md` and commit messages, so they stay in the table below and nowhere
else.

---

## 1. Ground Truth & Invariants

**The Rule**: everything above the kernel is a plugin.
**The Exception**: the kernel is not — `PluginRegistry`, `ActionDispatcher`, `EventDispatcher`,
`WorkerRegistry`, `PluginSupervisor`, `PluginBootstrapper`.

- **Service atoms, never module names.** Plugins depend on `:database`, `:auth`, `:player_data`.
  Swapping PostgreSQL for SQLite changes no consumer.
- **Pure C# outside Mix.** Game developers have no Elixir toolchain. Workspace init, scaffolding,
  codegen and deploy are pure C# (`netstandard2.1`).
- **The Unity package is the unit of distribution.** It ships into projects with no Exoforge checkout
  anywhere near them, so it must work exactly as it is shipped.
- **No engine SDK owns engine-agnostic code.** The C# client and the plugin tooling belong to the
  dotnet side; each engine ships them as a compiled assembly. Adding an engine adds a bucket that
  ships those libraries, not one that reimplements them.
- **A project names no other project's path.** Where a build input comes from is a property of the
  environment, decided by the hooks in `Directory.Build.targets`, not by a reference in a `.csproj`.

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
| **M26** | `Exoforge.Plugin.Generator` — a Roslyn source generator replaces the out-of-process `ManifestGen` tool. The manifest, the entry point, the action/event dispatch table and the contract interfaces come from the plugin's own compile, so native and WASM builds share one pipeline, the host no longer reflects over a generated plugin's methods, and a C# plugin declares services on a class or on a contract interface in its own assembly |
| **M27** | Self-Contained Unity Package — no symlink leaves the package, no path is resolved by walking out of it, and nothing in package code names this repository's layout |
| **M28** | SDK Runtime Hardening — four correctness bugs and six DX problems on the game-facing path, each with a test that fails when the fix is reverted |
| **M29** | Engine-Agnostic C# Core — the C# client and plugin tooling moved out of the Unity package, which now contains only Unity-specific code and ships the libraries as binaries |
| **M30** | Duplication and Build-Step Cleanup — one code generator, one manifest path, no second implementation of anything |
| **M31** | Dev Hooks and the Plugin Feed — `Directory.Build.targets` supplies a plugin's SDK, generator and manifest plumbing from a single opt-in, the Unity package stages its own libraries by building, and `Exoforge.Plugin.SDK` packs into a feed a plugin outside this repository builds against |

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

## 4. Next

Nothing outstanding.

Two things were on this list and are settled:

- **Publishing `Exoforge.Plugin.SDK` to a public feed** — decided against. `just pack-sdk` fills the
  local feed, a plugin built outside this repository resolves from it, and `just clean-room-sdk`
  proves the consumer path from a pristine export of `HEAD`. A published feed buys nothing until
  someone without a checkout needs one.
- **Generating client stubs without a cluster** — done, and it took the manifest format with it. The
  manifest is JSON now, written by the plugin's own generator and by the Elixir compiler, and read by
  both the server and the C# tooling. It used to be an Elixir map literal that the server evaluated,
  which meant the only copy of a plugin's contracts could be read by one language — and the tooling
  that generates client stubs from them has no Elixir. Stub generation lays each built plugin's
  manifest over the cluster export, so a plugin that is built but not deployed has stubs, and one
  being edited generates stubs for what it is now rather than for what was last deployed.

What that leaves: a service that is neither built locally nor deployed has no contract, so stubs for
it cannot be generated. The command says which services are missing and writes nothing, rather than
replacing working stubs with a file that has fewer of them.

## 5. Out of Scope for the MVP

Not planned. Recorded so they stop reappearing as "next":

- **Unreal Engine SDK (`ExoforgeUE`)** — a second engine client. M29/M30 already did the work that
  would make this cheap (engine SDKs ship the dotnetSDK binaries), but nothing needs it yet.
- **Clustered matchmaking / lobby** — Horde-backed matchmaking by MMR and latency.
- **Non-standard plugin runtimes** — anything beyond native (AOT), WASM reactor and Elixir. The
  three runtimes cover first-party, sandboxed third-party and system plugins.

---

## 6. Naming

Three buckets, one rule: **no engine SDK owns engine-agnostic code.**

| Bucket | Is | Holds |
| :--- | :--- | :--- |
| **Exo** | language-agnostic deploy & management | the CLI. Deploys C#, Elixir and WASM alike; carries no build logic of its own |
| **dotnetSDK** | C#-specific | plugin authoring (`Exoforge.Plugin.SDK`), manifest gen, build and codegen tooling, the C# client |
| **unitySDK** | Unity-specific | the UPM package: Unity runtime wrappers, editor tooling, and the dotnetSDK assemblies as binaries |

Adding an engine means adding a fourth bucket that ships the same two libraries — not a fourth
implementation of them.
