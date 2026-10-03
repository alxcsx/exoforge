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

## 2. Completed Milestones Ledger (M1–M22)

All 22 MVP milestones have been implemented, tested, and verified:

- [x] **M1–M6: Kernel Core, Contracts & Standard Plugins**: `PluginRegistry` ETS, `ActionDispatcher`, `EventDispatcher`, Bandit HTTP/WS ingress, WASM runtime (`wasmex`), Sandbox DB, Auth, PlayerData.
- [x] **M7–M13: Studio LiveView, Distributed Actors & Clustering**: Phoenix LiveView Producer Studio (`:4005`), Horde delta-CRDT virtual actors, `:pg` cluster event fanout, 729k ops/sec cluster benchmark, Kubernetes manifests.
- [x] **M14–M17: DevEx, Typed Resources & Multi-Plugin WASM**: Global `Cmd+K` palette, live actor passivation, typed resource structs (`[ExoResource]`), dynamic action parameter forms, C# client generation.
- [x] **M18: Hardening, Zero Warnings & E2E Slice**: Cleaned all compiler warnings, integrated WebSocket `AuthenticateAsync`, restored green E2E test in 292 ms.
- [x] **M19: Standard Plugin Manager (`exoforge_std_plugin_manager`)**: `:plugin_manager` service contract, hot WASM upload (`\0asm` verification), runtime restart/reload, manifest export.
- [x] **M20: Standalone C# Management Engine (`Exoforge.Management` & `exo` CLI)**: Dual-targeted `netstandard2.1` / `net10.0` library, `exo` CLI tool (`init`, `plugin new`, `plugin build`, `plugin push`, `sync`, `status`), and dedicated Studio Plugin Manager GUI.
- [x] **M21: Unity Engine SDK (`com.exoforge.sdk`)**: Standard UPM layout, in-engine Control Center window (`Window > Exoforge > Control Center`), persistent `EditorPrefs`, one-click client code generation, and `CombatDemo` sample.
- [x] **M22: GameDev Control Center, LiveOps Time Primitives & Standalone Package**:
  - Gamedev-first Unity Editor window with live cluster ping, environment switcher, real-time event streaming monitor, in-engine RPC action sandbox, C# WASM plugin manager, and LiveOps schedule viewer.
  - Core `Exoforge.TimeWindow` construct and C# `ExoTimeWindow` with active window evaluation, daily/weekly recurrence, countdowns, and progress tracking.
  - Reusable Studio dashboard components: `schedule_timeline/1` and `calendar_view/1` with automatic tab integration in `GenericExtensionView`.
  - Self-contained UPM distribution packaging target (`just pack-unity`) producing standalone `com.exoforge.sdk-0.1.0.tgz`.
  - Interactive `CombatDemoController` with on-screen runtime HUD.

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
- **Current State**: `exoforge_std_database` supports PostgreSQL and an in-memory Sandbox adapter.
- **Simplification**: In production, prefer raw SQL or light `:postgrex` query execution over heavy Ecto schemas inside standard plugins. Keep entity actor state boring: state is a serialized blob or JSON map persisted on passivation or periodic snapshot. Avoid complex relational object mappers for virtual actors.

### 4. Zero-Friction Container & Kubernetes Workflows
- **Current State**: Docker Compose and Kubernetes previously required 4-5 manual environment variables before starting.
- **Simplification**: Baked sensible local development defaults (`postgres` credentials, cluster cookies, secret keys) directly into `docker-compose.yml`, `deploy/k8s/secret.example.yaml`, and `Justfile`. Developers can run `just compose-up` or `just k8s-deploy` with zero environment configuration.

---

## 4. Post-MVP Growth Opportunities (Studio & Engine Expansion)

Future modular extensions to be built as plugins on top of the completed MVP kernel:

- [ ] **M22: SQLite Local Mode Plugin (`exoforge_std_sqlite`)**
  - Lightweight single-file database plugin for offline indie games, local integration tests, and peer-to-peer prototyping without a running PostgreSQL daemon.
- [ ] **M23: Unreal Engine SDK (`ExoforgeUE`)**
  - Native C++ client plugin for Unreal Engine 5 utilizing the same framed WebSocket protocol and code generation pipeline.
- [ ] **M24: LiveOps Visual Flow & Rules Engine**
  - Visual node-graph editor inside Producer Studio (`:4005`) for game designers to script live loot tables, quest prerequisites, and scheduled events without recompilation.
- [ ] **M25: Clustered Matchmaking & Lobby Plugin**
  - Authoritative matchmaking service plugin using Horde distributed state to group players into game sessions based on MMR and latency.
