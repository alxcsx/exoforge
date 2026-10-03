# Exoforge Operating Manual (`AGENTS.md`)

> **Branch**: `projetao_mvp`  
> **Status**: Monorepo Core, 7 Standard Plugins, C# Client & Plugin SDKs, C# Management Engine (`exo` CLI), Unity SDK (`com.exoforge.sdk`), LiveView Producer Studio, and Stateful Distributed Entity Runtime are **COMPLETE** (**164 tests passing + live E2E slice**).  
> **Verified SLAs**: 729k stateful actor ops/sec, 1.4 µs latency, 0.07 ms 50x event fanout.

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
               │
database ──────┴──▶ dashboard (:4005)
plugin_manager ───▶ (independent root)
```

| Plugin | Port / Role | Provides | Depends on | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `exoforge_std_database` | Storage | `database`, `lldb` | — | Per-plugin schema isolation with Postgres and Sandbox adapters. |
| `exoforge_std_auth` | Identity | `auth` | `database` | Token issuance, session verification, scope validation. |
| `exoforge_std_player_data` | Profiles | `player_data` | `database`, `auth` | Canonical player profile persistence and lifecycle events. |
| `exoforge_std_http` | REST (:4001) | `http` | `auth` | Dynamic OpenAPI routes derived from service contracts. |
| `exoforge_std_ws` | Realtime (:4000) | `ws` | `auth` | Low-latency binary/JSON framing for actions and event pub/sub. |
| `exoforge_std_dashboard` | Studio (:4005) | `dashboard_view` | `database` | LiveView Producer Studio, Actor Inspector, and Plugin Manager GUI. |
| `exoforge_std_plugin_manager`| Lifecycle | `plugin_manager` | — | Hot WASM upload, system restart/reload, and manifest export. |

---

## 3. Ponytail Engineering Principles (Points to Simplify & Polish)

1. **Stdlib & OTP First**: Reach for Erlang/Elixir built-ins (`:ets`, `:pg`, `Registry`, `DynamicSupervisor`) before adding third-party dependencies.
2. **Zero Module Coupling**: Plugins depend on **service atoms** (`:database`, `:auth`, `:player_data`), NEVER on another plugin's Elixir module name. Use `ActionDispatcher.dispatch(service, action, payload)`.
3. **Pure C# Outside Mix**: External game developers and Unity designers do not have Elixir or Mix installed. All client tooling, scaffolding (`ExoScaffolder`), and code generation (`ExoCodeGenerator`) must remain pure C# (`netstandard2.1`).
4. **Minimal WASM Boundary**: Keep the WASM host boundary strictly to JSON payloads and a single `emit_event` host bridge. Avoid complex multi-function FFI layers.
5. **Virtual Actors over Distributed Locks**: Use Horde process registries and `:pg` groups. Do not introduce external distributed lock managers (no Redis locks, no ZooKeeper).
6. **Deletion Over Addition**: The best code is code you never had to write. Remove dead code, redundant wrappers, and unneeded abstractions ruthlessly.

---

## 4. Commands Quick Reference

| Command | Action |
| :--- | :--- |
| `just test` | Run entire test suite (Core, Plugins, System, C# SDKs — 164 tests) |
| `just test-e2e` | Run live end-to-end vertical slice (WebSocket + WASM + Event loop) |
| `just dev` | Start backend development server (ports 4000, 4001, 4005) |
| `just build-wasm` | Compile C# WASM plugins in `plugins_csharp/` |
| `just test-sdk` | Run C# test suite (`Exoforge.Client`, `Plugin.SDK`, `Management`) |
| `just compose-up` | Run full production stack with PostgreSQL via Docker Compose |
| `just compose-down` | Stop and tear down Compose stack |
| `just k8s-deploy` | Deploy cluster to Kubernetes via Kustomize (with sensible defaults) |
| `just benchmark` | Run stateful entity cluster performance benchmark |

---

## 5. Agent & Contributor Guidelines

1. **Read before editing**: Inspect existing contracts and tests before adding new abstractions.
2. **Verify every change**: Always run `just test` or the relevant unit suite (`just test-core`, `just test-plugins`, `just test-sdk`).
3. **Honor the Rule**: Everything above the kernel is a plugin.
4. **Shortest working diff wins**: Do not create speculative configuration, wrapper classes with one implementation, or premature abstractions.
