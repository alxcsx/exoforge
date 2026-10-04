# Exoforge Operating Manual (`AGENTS.md`)

> **Branch**: `projetao_mvp`  
> **Status**: Monorepo Core, 7 Standard Plugins, C# Client & Plugin SDKs, C# Management Engine (`exo` CLI), Unity SDK (`com.exoforge.sdk`), LiveView Producer Studio, and Stateful Distributed Entity Runtime are **COMPLETE** (**165 tests passing + live E2E slice**).  
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
| `exoforge_std_plugin_manager`| Lifecycle | `plugin_manager` | — | Hot WASM/Elixir plugin upload, reload, and manifest export. |

### Plugin Placement Rules

**System-level plugins** (generic, reusable, demonstrates SDK features):
- Elixir plugins: `plugins/exoforge_std_*/`
- C# WASM sample plugins: `plugins_csharp/` (e.g., `sample_wasm`)

**Game-specific plugins** (belong to the game project, NOT the system):
- Unity game projects: `<game>/Exoforge/plugins/`
- Example: `sdk/unity/sample_unity/Exoforge/plugins/snake_game/`
- The workspace (`exoforge.json` + `plugins/`) lives **outside** `Assets/`, so dotnet/WASM plugin
  projects can target modern .NET/C# versions without Unity importing or compiling them.
  `ExoWorkspace.PluginsDir` = `plugins`, resolved against the workspace root.
- Only Unity-consumed artifacts stay inside `Assets/`: the generated client
  (`Assets/Exoforge/Generated/`) and the runtime config (`Assets/Resources/exoforge.json`).
  `ExoWorkspace` resolves any `Assets/...` config path against the project root automatically.
- **Caveat**: the workspace is invisible to Unity's AssetDatabase, so editor tooling must reach it
  through `System.IO` (`ExoWorkspace.PluginsPath`, `ExoDeployer`), never `AssetDatabase`/`Resources`.

> **Rule**: Game-specific plugins must NOT touch `core/`, `plugins/`, or `plugins_csharp/`. They live exclusively inside the game project and are built/deployed independently. The system `just build-wasm` only builds `plugins_csharp/`; game plugins are built within their own project (e.g., Unity Editor menu or the game's own build scripts).

### Plugin Runtimes

| Runtime | Manifest `type` | Written in | Built by | Use for |
| :--- | :--- | :--- | :--- | :--- |
| **Native (AOT process)** | `:native` | C# | `exo plugin build` → `dotnet publish -p:PublishAot=true` | First-party game servers. **Default.** |
| WASM reactor | `:wasm` | C# contract + C guest | `build.sh` (needs wasi-sdk) | Sandboxed / third-party guests |
| Elixir | `:elixir` | Elixir | `mix` | System plugins |

Native plugins are plain C# — **no C, no WASI toolchain**. `exo plugin build` compiles the plugin to a
self-contained ~2 MB binary and generates `manifest.exs` from the C# attributes. The plugin's entry point is:

```csharp
public static void Main() => PluginHost.Run<MyPlugin>();
```

The host spawns the binary as an OS process (`Exoforge.Drivers.Runtime.NativePluginRunner`) and speaks
newline-delimited JSON over stdio. Host capabilities go through `HostBridge` (`EmitEvent`, `DbPut`, `Log`, …);
the runner answers those calls synchronously. Because NativeAOT trims reflection, emit **`JsonObject`** payloads
and keep `PluginHost.Run<T>()`'s `[DynamicallyAccessedMembers]` annotation intact — that is what keeps the
`[ExoAction]` methods reachable.

`ActionDispatcher` stays runtime-agnostic: every non-Elixir plugin gets a generated proxy module
(`Exoforge.Drivers.Runtime.PluginProxy`) registered as its `entry_point`.

---

## 3. Ponytail Engineering Principles (Points to Simplify & Polish)

1. **Stdlib & OTP First**: Reach for Erlang/Elixir built-ins (`:ets`, `:pg`, `Registry`, `DynamicSupervisor`) before adding third-party dependencies.
2. **Zero Module Coupling**: Plugins depend on **service atoms** (`:database`, `:auth`, `:player_data`), NEVER on another plugin's Elixir module name. Use `ActionDispatcher.dispatch(service, action, payload)`.
3. **Pure C# Outside Mix**: External game developers and Unity designers do not have Elixir or Mix installed. All client tooling, scaffolding (`ExoScaffolder`), and code generation (`ExoCodeGenerator`) must remain pure C# (`netstandard2.1`).
4. **C# for Game Code**: First-party game plugins are written in C# and compiled to a NativeAOT binary — never hand-written C, and never a WASI toolchain. Keep the host boundary to newline-delimited JSON. Reserve the WASM reactor runtime for sandboxed or third-party guests.
5. **Virtual Actors over Distributed Locks**: Use Horde process registries and `:pg` groups. Do not introduce external distributed lock managers (no Redis locks, no ZooKeeper).
6. **Deletion Over Addition**: The best code is code you never had to write. Remove dead code, redundant wrappers, and unneeded abstractions ruthlessly.

---

## 4. Commands Quick Reference

| Command | Action |
| :--- | :--- |
| `just test` | Run entire test suite (Core, Plugins, System, C# SDKs — 164 tests) |
| `just test-e2e` | Run live end-to-end vertical slice (WebSocket + WASM + Event loop) |
| `just dev` | Start backend development server (ports 4000, 4001, 4005) |
| `just build-wasm` | Compile the **system** WASM samples (`plugins_csharp/*/build.sh`) |
| `exo plugin build <name>` | Build a game plugin (NativeAOT binary + `manifest.exs`) |
| `exo plugin push <name>` | Build and deploy a plugin to a running cluster |
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
