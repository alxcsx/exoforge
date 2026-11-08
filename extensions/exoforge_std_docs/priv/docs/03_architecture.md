# Exoforge Architecture & Native Process Runtime

Microkernel Design, Native C# OS Workers, and Actor Concurrency Supervision.

---

## 1. Core Philosophy: The Microkernel Architecture

Exoforge is designed around a single, straightforward principle: **a minimal, immutable microkernel with pluggable extensions**.

Instead of a monolithic game backend where every feature is tightly coupled, Exoforge strictly separates the system into two distinct realms:

### 1. The Kernel (`core/`)
The kernel is the foundational engine of Exoforge. You never need to modify, rebuild, or customize it. It provides four core primitives:
- **`ActionDispatcher`**: Verifies caller security permissions (`:guest`, `:player`, `:server`, `:studio`) and routes requests to the correct service provider in memory.
- **`EventDispatcher`**: Real-time pub/sub bus broadcasting events cluster-wide over Erlang process groups (`:pg`) with a verified **0.07 ms fanout SLA** (measured across 50 concurrent subscribers).
- **`ExtensionRegistry`**: Zero-latency in-memory ETS catalog of service manifests, actions, and schema metadata.
- **`ExtensionSupervisor`**: Starts extensions in topological dependency order, isolates worker failures, and automatically recovers crashed processes.

### 2. Pluggable Extensions (`extensions/` & Game Projects)
Everything built on top of the kernel is a pluggable extension. Extensions communicate exclusively through declared contracts (`ActionDispatcher.dispatch`), never through direct code imports or hardcoded dependencies.
- **Network Gateways**: The WebSocket gateway (`:ws` on port 4000) and HTTP REST gateway (`:http` on port 4001) are extensions. Swapping or adding new transports (e.g., gRPC, TCP, WebTransport) requires no kernel changes.
- **Platform Services**: Authentication (`:auth`), player profiles (`:player_data`), scheduled tasks (`:cron`), usage metering (`:metering`), and asset storage (`:file_bucket`).
- **Your Game Code**: First-party game servers (e.g. leaderboards, matchmaking, inventory, combat) written in native C# and executed in isolated OS worker processes.
- **Storage**: Multi-engine persistence (`:database`) supporting PostgreSQL and SQLite, providing each extension with its own strictly isolated database schema.

### Simple Rule of Thumb
- **Is it game logic, storage, or transport?** → It belongs in an **Extension**.
- **Does starting the cluster depend on it?** → It belongs in the **Kernel**.

---

## 2. End-to-End System Architecture

Here is how data flows from a player's screen in Unity to the database and back:

```
[ Unity Game Client ] (ExoforgeSDK)
         │
         │  1. WebSocket (:4000) or REST (:4001) JSON framing
         ▼
[ Transport Gateways (:ws / :http) ]
         │  • Verifies session authentication token
         │  • Stays stateless; strips spoofed client fields
         │  • Forcibly stamps verified player_id / scopes
         │
         │  2. In-Memory Function Call
         ▼
[ ActionDispatcher (Kernel Core) ]
         │  • Checks caller permissions against action scope contract
         │  • Resolves provider entry point in zero-latency ETS
         │
         │  3. Extension Wire Protocol (stdio IPC)
         ▼
[ Native C# Game Worker (.NET OS Process) ]
         │  • Deserializes JSON into strongly-typed C# records
         │  • Runs game logic with zero System.Reflection overhead
         │  • Calls host capabilities via static Exo holder:
         │      ├── Exo.Database.Put / Exo.Database.Query
         │      └── Exo.Events.Publish
         │
         │  4. Result returned over stdio frame
         ▼
[ Framed Response Sent Back to Unity Client ]
```

---

## 3. Extension Wire Protocol (Host Supervisor ↔ Worker IPC)

A critical architectural distinction is understanding what the extension wire protocol is and is not.

### What It IS and What It IS NOT

- **IT IS**: Host-to-Worker Process IPC (inter-process communication) over standard I/O (`stdin`/`stdout`). It is the wire contract between the cluster host supervisor (Elixir BEAM) and the native C# worker process (`.NET`).
- **IT IS NOT Client-to-Server**: Game clients (Unity, Unreal, Godot) **never** speak this protocol. Clients communicate with the cluster over WebSocket (`:ws` on port 4000) or REST (`:http` on port 4001) using public JSON framing handled by the Transport Gateway.
- **IT IS NOT Extension-to-Extension**: Extensions calling other services do **not** use stdio frames or raw JSON. They call generated, strongly-typed stubs (e.g., `PlayerData.GetProfileAsync(id)`), which route through the in-memory `ActionDispatcher` with zero network overhead.

### Wire Frame Types & What Triggers Them

The wire protocol is version `1`, newline-delimited JSON. Every frame carries a `"type"` property:

| Frame `type` | Direction | What Triggers This Frame | Carries |
|---|---|---|---|
| `hello` | Host ➔ Worker | Host spawns the native OS process. Initiates capability handshake. | `protocol: 1`, `host: "exoforge"`, `capabilities: ["action_result", "host_call", "host_log"]` |
| `hello` | Worker ➔ Host | Worker starts and answers within 5-second timeout, declaring what it can receive. | `protocol: 1`, `extension: "<name>"`, `capabilities: ["action", "event"]` |
| `action` | Host ➔ Worker | A player calls an action, or a background cron triggers a scheduled task. | `id: "req_..."`, `action: "method_name"`, `payload: { ... }` |
| `action_result` | Worker ➔ Host | The C# action method finishes execution (or throws an unhandled exception). | `id: "req_..."`, `status: "ok" \| "error"`, `data: { ... }` or `error: "..."` |
| `event` | Host ➔ Worker | An event that this extension subscribed to is published on the cluster event bus. | `event: "topic.name"`, `payload: { ... }` |
| `host_call` | Worker ➔ Host | Extension invokes host capabilities: `Exo.Database.Put`, `Exo.Database.Query`, or `Exo.Events.Publish`. | `id: "call_..."`, `op: "db_put" \| "db_query" \| "publish_event"`, `args: { ... }` |
| `host_call_result` | Host ➔ Worker | The host completes the requested database operation or event publication. | `id: "call_..."`, `result: { ... }` |
| `host_log` | Worker ➔ Host | Extension outputs logs via `Exo.Log.Info` or `Console.WriteLine`. | `level: "info" \| "warn" \| "error"`, `message: "..."` |

### Handshake & Fault Isolation Guarantees
1. **5-Second Handshake**: If an extension does not answer `hello` with valid capabilities within 5 seconds, the host refuses the extension with a clear log reason instead of retrying indefinitely.
2. **Crash Recovery**: If an OS worker process crashes (e.g., segfault or uncaught exception), the Erlang/Elixir `ExtensionSupervisor` catches the exit signal, clears pending in-flight requests with a 503 error, and re-spawns a clean worker process without bringing down the cluster.

---

## 4. Tree-Shaking & Native Compilation Architecture

Game extensions in Exoforge are native C# compiled to a **framework-dependent single file**:

- **Zero Reflection at Runtime**: The `Exoforge.Plugin.Generator` Roslyn source generator runs during `dotnet publish` or `exo extension build`. It emits the dispatch table (`ExoforgeDispatch`) and entry point (`ExoforgeEntryPoint`), so the runtime invokes actions via direct static delegates without `System.Reflection`.
- **Ahead-Of-Time (AOT) IL Trimming**: All unused Base Class Library (BCL) classes and metadata are stripped out. The compiled binary is only a few hundred kilobytes.
- **Pure C# Records**: Data contracts are typed C# records with parameter names matching action arguments. The SDK owns JSON serialization, and generated stubs preserve end-to-end typing from server to client.
- **Multi-Engine Isolated Storage**: Extensions access the database through `Exo.Database`, which automatically scopes queries and KV storage to the extension's private schema (`ext_<extension_name>`), preventing cross-service data corruption.
