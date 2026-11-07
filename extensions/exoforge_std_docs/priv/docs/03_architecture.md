# Exoforge Architecture & Native Process Runtime

Tree-Shaking, Native Compilation, and OTP Supervision.

---

## Architectural Doctrine

> **The Rule**: Everything above the kernel is an extension.  
> **The Exception**: The kernel itself is not an extension.

The kernel is strictly limited to:
- `ExtensionRegistry`: In-memory ETS catalog of service manifests and resources.
- `ActionDispatcher`: Authorization scope checks and service action routing.
- `EventDispatcher`: Real-time pub/sub bus with pattern matching and Registry fanout.
- `WorkerRegistry`: Named singleton process locator.
- `ExtensionSupervisor` & `ExtensionBootstrapper`: Topological DAG ordering and process lifecycle.

---

## Tree-Shaking & Native Compilation Architecture

When publishing a native C# extension, Exoforge leverages **.NET IL Trimming & Ahead-Of-Time (AOT) tree-shaking**. All unused base class library (BCL) methods and reflection overhead are stripped at compile time.

- **Zero Reflection at Runtime**: Contracts, actions, and parameter types are analyzed and serialized into a lightweight `manifest.json` at build time.
- **Minimal Memory Footprint**: Stripped extension binaries load in milliseconds with predictable memory usage under Erlang/OTP supervision.
- **Binary Isolation**: Each extension operates in an isolated worker OS process without polluting cluster dependencies.

---

## Extension Wire Protocol

Communication between the Erlang/OTP host and the native .NET process takes place over stdio using newline-delimited JSON frames:

| Frame Type | Direction | Carries |
|---|---|---|
| `hello` | host → extension | `protocol`, `host`, `capabilities` |
| `hello` | extension → host | `protocol`, `extension`, `capabilities` |
| `action` / `action_result` | host → extension / back | `id`, `action`, `payload` / `status`, `data` or `error` |
| `event` | host → extension | `event`, `payload` |
| `host_call` / `host_call_result` | extension → host / back | `id`, `op`, `args` / `result` |
| `host_log` | extension → host | `level`, `message` |

Handshake protocol is `1`, with capability negotiation and automatic supervised process recovery.
