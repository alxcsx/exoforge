# Exoforge

> **The High-Performance, Modular Game Backend Platform & LiveOps Engine.**  
> Built on Erlang/BEAM, WebAssembly (WASI), and native Unity / C# integration.

[![Build Status](https://img.shields.io/badge/tests-181%20passing-brightgreen)](Justfile)
[![E2E Vertical Slice](https://img.shields.io/badge/E2E%20Slice-verified%20live-blue)](sdk/csharp/Exoforge.Client.Tests/VerticalSliceIntegrationTests.cs)
[![Event Fanout](https://img.shields.io/badge/event%20fanout-0.07%20ms%20to%2050%20subs-purple)](test/cluster_benchmark_test.exs)
[![Unity SDK](https://img.shields.io/badge/Unity%20SDK-UPM%20Ready-black)](sdk/unity/Exoforge.SDK)

---

## What is Exoforge?

Exoforge is an open, high-density game backend and LiveOps platform. It combines the distributed actor concurrency of the Erlang/BEAM virtual machine with sandboxed WebAssembly execution to run authoritative game logic without external cache layers or heavy microservice sprawl.

### What it is for

- **Authoritative Gameplay Logic**: Run combat calculations, inventory reconciliation, loot tables, and economy logic on the server using C# compiled to WebAssembly (WASI).
- **Zero-Downtime LiveOps**: Update drop rates, rebalance gameplay numbers, and deploy new game rules dynamically without rebuilding game clients or awaiting app store approvals.
- **Stateful Plugins, Not a Framework**: A plugin *is* the actor — a supervised, long-lived process holding its own state, free to spawn a worker per matchmaking queue, game room, or chat channel. There is no grain API to learn and nothing to adopt.
- **Unified Game Services**: Provides out-of-the-box identity, isolated multi-tenant databases, real-time WebSocket pub/sub, dynamic REST APIs, and a LiveView designer studio.

---

## System Architecture

```
+--------------------------------------------------------------------------+
|                  GAME PRODUCER & DESIGNER STUDIO (:4005)                 |
|             (LiveView Dashboard, Actor Inspector, Plugin Manager)        |
+--------------------------------------------------------------------------+
|      REST INGRESS (:4001)         |        WEBSOCKET INGRESS (:4000)     |
|   (Dynamic OpenAPI Routes)        |   (Real-time JSON/Binary Protocol)   |
+-----------------------------------+--------------------------------------+
|                 SANDBOXED C# WASM PLUGINS (WASI Runtime)                  |
|          authoritative combat • inventory • liveops • matchmaking        |
+--------------------------------------------------------------------------+
|                     STANDARD EXTENSION SERVICES                          |
|         :auth  •  :player_data  •  :database  •  :plugin_manager         |
+--------------------------------------------------------------------------+
|                      EXOFORGE KERNEL (OTP Core)                          |
|   Registry  •  Dispatcher  •  Supervisor  •  Event Bus                   |
+--------------------------------------------------------------------------+
```

### Deployments

Exoforge runs as an **instance**. A developer does not run the kernel; they point their tools at one.

```
   instance  (yours, or one you are given)      developer's machine
   ───────────────────────────────────────     ──────────────────────────
   kernel  •  standard plugins                  Unity  •  com.exoforge.sdk
   database  •  LiveView Studio                 Exoforge/plugins/*   (theirs)
   :4000 ws  •  :4001 rest  •  :4005 studio            │
        ▲                                              │  build, deploy, stubs
        └───────────────  wss:// + https://  ──────────┘
```

The standard plugins are **builtin and server-side**. They are not installed on the developer's
machine and their contracts arrive over the wire; a team that wants its own can remove or replace
any of them.

Two audiences, two UIs, one instance: the **Unity editor window** is for developers, so they never
leave Unity while building a plugin, and the **LiveView Studio** is for designers and producers —
though developers use it too for visualisation and integration work.

### Architectural Doctrine

> **The Rule**: Everything above the kernel is a plugin.  
> **The Exception**: The kernel itself is not a plugin.

The kernel is minimal and deterministic, containing only:
- **`PluginRegistry`**: In-memory ETS catalog of service manifests and resources.
- **`ActionDispatcher`**: Authorization scope checks and service action routing.
- **`EventDispatcher`**: Real-time pub/sub bus with pattern matching and Registry fanout.
- **`WorkerRegistry`**: Named singleton process locator.
- **`PluginSupervisor` & `PluginBootstrapper`**: Topological DAG ordering and process lifecycle.
- **Plugin Drivers**: Native Elixir (`ElixirPluginRunner`) and WASM (`WasmPluginRunner`).

All networking, storage, authentication, and game domains exist as swappable plugins.

---

## Standard Plugins

| Plugin | Port / Role | Provides | Purpose |
| :--- | :--- | :--- | :--- |
| `exoforge_std_database` | Storage | `:database`, `:lldb` | Per-plugin schema isolation with PostgreSQL and SQLite adapters. |
| `exoforge_std_auth` | Identity | `:auth` | Session verification, bearer token issuance, and RBAC scope validation. |
| `exoforge_std_player_data` | Profiles | `:player_data` | Canonical player profile persistence, schemas, and lifecycle events. |
| `exoforge_std_http` | REST (:4001) | `:http` | Dynamic OpenAPI endpoints generated directly from service contracts. |
| `exoforge_std_ws` | Realtime (:4000) | `:ws` | Low-latency binary and JSON WebSocket framing for actions and event pub/sub. |
| `exoforge_std_dashboard` | Studio (:4005) | `:dashboard_view` | Game Producer & Designer Studio (LiveView UI, actor inspector, schedule calendars). |
| `exoforge_std_plugin_manager` | Lifecycle | `:plugin_manager` | Runtime plugin lifecycle, hot WASM binary uploads, and manifest exports. |

---

## Unity & C# Tooling

Exoforge separates game engineering from backend operations. Game developers work in standard C# without needing Erlang or Mix installed.

### 1. Unity Exoforge Studio (`com.exoforge.sdk`)

A dedicated Unity Editor extension (`Tools ▸ Exoforge ▸ Exoforge Studio`, or `Window ▸ Exoforge`) providing:
- **One-Click Scaffolding**: Generate standard, inventory, or LiveOps native C# plugins directly into `plugins/` — each with its own solution (`.slnx`) and sources under `src/`.
- **Compilation & Deployment**: Build the NativeAOT binary + manifest and upload them to the running server.
- **Live Action Sandbox**: Test actions and inspect payloads with latency metrics (`µs`).
- **Real-Time Event Stream**: Monitor backend broadcasts and filter topics inside Unity.

### 2. Standalone C# CLI (`exo`)

The **engine-agnostic** tool: the same commands a Unity developer clicks, for other engines, for
CI/CD, and for headless work. A Unity project does not need it.
```bash
exo init                     # Initialize /exoforge workspace
exo plugin new combat        # Scaffold a native C# plugin (--template standard|inventory)
exo plugin build combat      # Build the NativeAOT binary + manifest.json
exo plugin stubs combat      # Generate typed service stubs from the cluster contracts
exo plugin push combat       # Hot-load plugin onto live cluster
exo sync                     # Generate strongly-typed C# client bindings
exo status                   # Inspect cluster health and telemetry
```

### 3. C# Client SDK (`ExoClient`)

High-performance WebSocket client with automatic reconnection, typed action RPC, and main-thread event dispatching:
```csharp
using Exoforge.Client;

var client = new ExoClient();
await client.ConnectAsync(new Uri("ws://localhost:4000/ws"));
await client.AuthenticateAsync("dev:player_42");

// Subscribe to backend event broadcasts
client.Subscribe("player_damaged", (eventName, payload) => {
    Debug.Log($"Damage event received: {payload}");
});

// Invoke backend action
var result = await client.SendActionAsync<CombatResult>("combat", "attack", new {
    target_id = "enemy_99",
    damage = 45
});
```

---

## Performance Benchmarks

Benchmarked on commodity single-node hardware (Apple Silicon / Linux x86_64):

| Metric | Result | Description |
| :--- | :--- | :--- |
| **Stateful Actor Calls** | **> 420,000 ops / sec** | Clustered virtual actor RPC throughput |
| **Actor Latency** | **2.4 µs** (0.0024 ms) | In-memory distributed actor round-trip |
| **Actor Activation** | **0.024 ms / entity** | Instant on-demand actor state hydration |
| **Cluster Fanout** | **0.15 ms** | 50 concurrent subscribers per broadcast |
| **Test Suite** | **240 Elixir + 72 C# passing** | Core, the 9 standard plugins, system integration, and the C# SDKs |

---

## Quickstart

### Using Exoforge

You need an instance and the Unity package. The package is distributed as a tarball
(`dist/com.exoforge.sdk-*.tgz`) and carries everything a plugin build needs, the plugin SDK
included — nothing here requires a clone of this repository.

1. **Package Manager ▸ + ▸ Add package from tarball**, and pick the `.tgz`.
2. **Tools ▸ Exoforge ▸ Exoforge Studio**, and point it at your instance in the Settings tab.
3. **Plugins ▸ Scaffold**, then **Build & Deploy**.

The sample project ships with the package and is the reference for the whole loop.

### Working on the kernel

Prerequisites: [Elixir 1.20+ & Erlang/OTP 29+](https://elixir-lang.org) (or via `mise` / `asdf`),
the [.NET 10.0 SDK](https://dotnet.microsoft.com), and
[Just](https://github.com/casey/just).
```bash
# Run all tests (Core, Plugins, System, C# SDKs)
just test

# Run live end-to-end integration test (Client -> WS -> WASM -> Event -> Client)
just test-e2e

# Start the local development server (WS :4000, REST :4001, Studio :4005)
just dev

# Package Unity SDK UPM archive (dist/com.exoforge.sdk-*.tgz)
just pack-unity
```

### Deployment
```bash
# Docker Compose (PostgreSQL + Exoforge Backend)
just compose-up

# Standalone OTP Release
just release
just run-release

# Kubernetes (via Kustomize)
just k8s-deploy
```

---

## Repository Structure

```
├── core/                         # Exoforge OTP Kernel
│   ├── lib/                      # Dispatcher, Registry, Supervisors
│   └── test/                     # Kernel unit & benchmark tests
├── plugins/                      # Standard Elixir Plugins
│   ├── exoforge_std_auth/        # Authentication & RBAC scopes
│   ├── exoforge_std_database/    # PostgreSQL & SQLite storage adapters
│   ├── exoforge_std_player_data/ # Player profile management
│   ├── exoforge_std_http/        # REST ingress & OpenAPI reflection
│   ├── exoforge_std_ws/          # WebSocket binary/JSON ingress
│   ├── exoforge_std_dashboard/   # Phoenix LiveView Producer Studio
│   └── exoforge_std_plugin_manager/ # Runtime plugin lifecycle & upload
├── plugins_csharp/               # Sample C# WASM Plugins
│   └── combat_wasm/              # Authoritative combat logic compiled to WASM
├── sdk/
│   ├── csharp/                   # Pure C# SDKs & Tooling
│   │   ├── Exoforge.Client/      # Runtime client library (.NET Standard 2.1)
│   │   ├── Exoforge.Plugin.SDK/  # Attributes and interfaces for C# WASM plugins
│   │   ├── Exoforge.Management/  # Workspace, scaffolding, and code generation engine
│   │   └── Exoforge.CLI/         # `exo` command-line executable
│   └── unity/
│       └── Exoforge.SDK/         # Unity Package Manager (UPM) package
├── deploy/                       # Kubernetes manifests & Docker configurations
├── AGENTS.md                     # Architectural rules & manual
└── Justfile                      # Central automation recipes
```
