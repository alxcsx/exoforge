# Native Process Runtime & Wire Protocol

Technical reference for .NET OS process isolation, stdio wire frames, and ahead-of-time tree-shaking.

---

## 1. Extension Wire Protocol (Host Supervisor ↔ Worker IPC)

Communication between the host cluster supervisor (Elixir BEAM) and the native C# worker process (`.NET`) takes place over standard I/O (`stdin`/`stdout`) using newline-delimited JSON frames:

- **Host-to-Worker Process IPC Only**: Game clients (Unity) never speak this protocol; clients communicate over WebSocket (`:ws`) or REST (`:http`).
- **Zero Reflection Overhead**: Roslyn-generated entry points dispatch actions directly to static method delegates.

### Wire Frame Types & Triggers

| Frame `type` | Direction | What Triggers This Frame | Carries |
|---|---|---|---|
| `hello` | Host ➔ Worker | Host spawns the native OS process. Initiates capability handshake. | `protocol: 1`, `host: "exoforge"`, `capabilities: ["action_result", "host_call", "host_log"]` |
| `hello` | Worker ➔ Host | Worker starts and answers within 5-second timeout, declaring what it can receive. | `protocol: 1`, `extension: "<name>"`, `capabilities: ["action", "event"]` |
| `action` | Host ➔ Worker | A player calls an action, or a background cron triggers a scheduled task. | `id: "req_..."`, `action: "method_name"`, `payload: { ... }` |
| `action_result` | Worker ➔ Host | The C# action method finishes execution (or throws an unhandled exception). | `id: "req_..."`, `status: "ok" \| "error"`, `data: { ... }` or `error: "..."` |
| `event` | Host ➔ Worker | An event that this extension subscribed to is published on the cluster event bus. | `event: "topic.name"`, `payload: { ... }` |
| `host_call` | Worker ➔ Host | Extension invokes host capabilities: `Exo.Database.Put`, `Exo.Database.Query`, or `Exo.Events.EmitAsync`. | `id: "call_..."`, `op: "db_put" \| "db_query" \| "publish_event"`, `args: { ... }` |
| `host_call_result` | Host ➔ Worker | The host completes the requested database operation or event publication. | `id: "call_..."`, `result: { ... }` |
| `host_log` | Worker ➔ Host | Extension outputs logs via `Exo.Logger.Info` or `Console.WriteLine`. | `level: "info" \| "warn" \| "error"`, `message: "..."` |

### Handshake & Fault Isolation Guarantees
1. **5-Second Handshake**: If an extension does not answer `hello` with valid capabilities within 5 seconds, the host refuses the extension with a clear log reason.
2. **Crash Recovery**: If an OS worker process crashes, the `ExtensionSupervisor` catches the exit signal, clears pending in-flight requests with a 503 error, and re-spawns a clean worker process without bringing down the cluster.

---

## 2. Tree-Shaking & Native Compilation Architecture

Game extensions in Exoforge are native C# compiled to a **framework-dependent single file**:

- **Zero Reflection at Runtime**: The `Exoforge.Plugin.Generator` Roslyn source generator runs during compilation. It emits the dispatch table (`ExoforgeDispatch`) and entry point (`ExoforgeEntryPoint`), so the runtime invokes actions via direct static delegates without `System.Reflection`.
- **Ahead-Of-Time (AOT) IL Trimming**: All unused Base Class Library (BCL) classes and metadata are stripped out. The compiled binary is only a few hundred kilobytes.
- **Pure C# Records**: Data contracts are typed C# records with parameter names matching action arguments. The SDK owns JSON serialization, and generated stubs preserve end-to-end typing from server to client.
- **Multi-Engine Isolated Storage**: Extensions access the database through `Exo.Database`, which automatically scopes queries and KV storage to the extension's private schema (`ext_<extension_name>`), preventing cross-service data corruption.

---

## 3. Extension Discovery & Production Volume Isolation

Exoforge boots by scanning configured paths for `manifest.json` files and constructing a topological dependency graph:

- **Multi-Path Scanning**: `EXTENSIONS_PATH` (or `:scan_path` in application config) can be configured with multiple paths. The runtime accepts Elixir lists, comma-separated, semicolon-separated, or JSON array strings (e.g., `EXTENSIONS_PATH="/app/builtin_extensions,/app/uploaded_extensions"`).
- **Static vs. Mutable Volume Separation**: In containerized production deployments (Docker / Kubernetes), pre-compiled standard extensions are baked into `/app/builtin_extensions` inside the immutable image. A persistent volume is mounted strictly over `/app/uploaded_extensions` (`UPLOADED_EXTENSIONS_PATH`). This ensures that image updates deploy new built-in extensions without overwriting or obscuring custom user extensions.
- **Deduplication & Semver Precedence**: When an extension ID appears in multiple scanned directories, `ManifestLoader` resolves the collision by keeping the higher semantic version. If versions are identical, the later/uploaded directory takes precedence so that hot patches override built-ins seamlessly. Built-in files are protected against accidental file deletion.
