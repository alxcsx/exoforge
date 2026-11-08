# Exoforge Architecture & Native Process Runtime

Tree-Shaking, Native Process Compilation, and Actor Concurrency Supervision.

---

## 1. Architectural Doctrine: The Rule & The Litmus Test

> **The Rule**: Everything above the kernel is an extension.  
> **The Exception**: The kernel itself is not an extension.

The Exoforge kernel is strictly limited to four foundational primitives:
- `ExtensionRegistry`: In-memory ETS catalog of service manifests, routes, and resource schemas.
- `ActionDispatcher`: Authorization scope verification (`:guest`, `:player`, `:server`, `:studio`) and service action routing.
- `EventDispatcher`: Real-time pub/sub bus with pattern matching and `:pg` distributed Erlang process groups (verified **0.07 ms SLA** to 50 subscribers).
- `WorkerRegistry` & `ExtensionSupervisor`: Topological DAG ordering, process lifecycle, and actor supervision.

Everything else—including the WebSocket gateway (`:ws`), HTTP REST gateway (`:http`), authentication (`:auth`), player profiles (`:player_data`), scheduling (`:cron`), and all game features—is a pluggable extension.

### The 4-Question Litmus Test: "Should this be an extension?"
1. **Can two implementations be swapped?** (REST ↔ gRPC ↔ WebSocket, Postgres ↔ SQLite) → **Extension**.
2. **Does something need to depend on it by contract?** → **Extension**.
3. **Would bootstrapping itself depend on it?** → **Kernel**.
4. **Is it only consumed by one domain extension?** → Keep it **Internal** to that extension.

---

## 2. Extension Wire Protocol (Host Supervisor ↔ Native Process IPC)

A common point of confusion is understanding what the extension wire protocol actually is.

### What It IS and What It IS NOT

- **IT IS**: Host-to-Worker Process IPC (inter-process communication) over standard I/O (`stdin`/`stdout`). It is the wire contract between the cluster host supervisor (Elixir BEAM) and the native C# worker process (`.NET`).
- **IT IS NOT Client-to-Server**: Game clients (Unity, Unreal, Godot) **never** speak this protocol. Clients communicate with the cluster over WebSocket (`:ws` on port 4000) or REST (`:http` on port 4001) using the public JSON framing handled by the Transport Gateway.
- **IT IS NOT Extension-to-Extension**: Extensions calling other services do **not** use stdio frames or raw JSON. They call generated, strongly-typed stubs (e.g., `PlayerData.GetProfileAsync(id)`), which route through the in-memory `ActionDispatcher` with zero network overhead.

### Protocol Boundary Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Game Client (Unity)                     │
└──────────────────────────────┬──────────────────────────────┘
                               │ WebSocket (:4000) / HTTP (:4001)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 Transport Gateway (:ws / :http)             │
│            • Authenticates session token                    │
│            • Stamps verified player_id / user_id            │
└──────────────────────────────┬──────────────────────────────┘
                               │ In-Memory Dispatch
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 ActionDispatcher (Kernel)                   │
│            • Verifies action authorization scope            │
│            • Resolves service provider in ETS               │
└──────────────────────────────┬──────────────────────────────┘
                               │
            ╔══════════════════╧══════════════════╗
            ║    EXTENSION WIRE PROTOCOL (IPC)    ║
            ║    Newline-delimited JSON on stdio  ║
            ╚══════════════════╤══════════════════╝
                               ▼
┌─────────────────────────────────────────────────────────────┐
│           Native C# Extension (.NET OS Process)             │
│            • Supervised worker process                      │
│            • Tree-shaken, zero reflection                   │
│            • Calls host capabilities via Exo.Database       │
└─────────────────────────────────────────────────────────────┘
```

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

## 3. Tree-Shaking & Native Compilation Architecture

Game extensions in Exoforge are native C# compiled to a **framework-dependent single file**:

- **Zero Reflection at Runtime**: The `Exoforge.Plugin.Generator` Roslyn source generator runs during `dotnet publish` or `exo extension build`. It emits the dispatch table (`ExoforgeDispatch`) and entry point (`ExoforgeEntryPoint`), so the runtime invokes actions via direct static delegates without `System.Reflection`.
- **Ahead-Of-Time (AOT) IL Trimming**: All unused Base Class Library (BCL) classes and metadata are stripped out. The compiled binary is only a few hundred kilobytes.
- **Pure C# Records**: Data contracts are typed C# records with parameter names matching action arguments. The SDK owns JSON serialization, and generated stubs preserve end-to-end typing from server to client.
