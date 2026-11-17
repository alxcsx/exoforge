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
| `hello` | Host ➔ Worker | Host spawns the native OS process. Initiates capability handshake. | `protocol: 1`, `host: "exoforge"`, `capabilities: ["action_result", "host_call", "host_log", "lifecycle_result"]` |
| `hello` | Worker ➔ Host | Worker starts and answers within 5-second timeout, declaring what it can receive. | `protocol: 1`, `plugin: "<name>"`, `capabilities: ["action", "event", "host_call_result"]` plus optional `"lifecycle"` |
| `action` | Host ➔ Worker | A player calls an action, or a background cron triggers a scheduled task. | `id: <integer>`, `action: "method_name"`, `payload: { ... }` |
| `action_result` | Worker ➔ Host | The C# action method finishes execution (or throws an unhandled exception). | `id: <integer>`, `status: "ok" \| "error"`, `data: { ... }` or `error: { "code": "...", "message": "..." }` |
| `event` | Host ➔ Worker | An event that this extension subscribed to is published on the cluster event bus. | `event: "topic.name"`, `payload: { ... }` |
| `host_call` | Worker ➔ Host | Extension invokes a host capability: `emit_event`, `call_action`, `db_put`, `db_get`, `db_all`, `db_delete`, `log`, or `clock_now`. | `id: <integer>`, `op: "<operation>"`, `args: { ... }` |
| `host_call_result` | Host ➔ Worker | The host completes the requested capability call. | `id: <integer>`, `result: <value>` or an error envelope |
| `host_log` | Worker ➔ Host | Extension outputs logs via `Exo.Logger.Info` or an unhandled exception trace. | `level: 0..3`, `message: "..."` |
| `lifecycle` | Host ➔ Worker | Sent after the handshake to an extension that declared `"lifecycle"`. | `id: <integer>` |
| `lifecycle_result` | Worker ➔ Host | The optional `OnExtensionStart()` hook finished or failed. | `id: <integer>`, `status: "ok"` or `status: "error"` with `error: { "code": "...", "message": "..." }` |

### Handshake & Fault Isolation Guarantees
1. **5-Second Handshake**: If an extension does not answer `hello` with valid capabilities within 5 seconds, the host refuses the extension with a clear log reason and stops the runner; it is not restarted in a loop.
2. **Optional Lifecycle**: An extension that declares `"lifecycle"` receives `lifecycle` after the handshake. `OnExtensionStart()` runs once per process; the host waits up to 10 seconds. A failure marks the extension crashed with `{:startup_failed, %{code: ..., message: ...}}` and stops it.
3. **Crash Recovery**: A runtime OS process exit is supervised by the extension supervisor (`:one_for_one`) and restarted without touching the rest of the cluster. Requests waiting on the dead process receive `{:error, {:extension_crashed, reason}}`, and the registry records the crash (`ExtensionRegistry.mark_crashed/2`) so Studio can show it.

---

## 2. Tree-Shaking & Native Compilation Architecture

Game extensions in Exoforge are native C# compiled to a **framework-dependent single file**:

- **Zero Reflection at Runtime**: The `Exoforge.Plugin.Generator` Roslyn source generator runs during compilation. It emits the dispatch table (`ExoforgeDispatch`) and entry point (`ExoforgeEntryPoint`), so the runtime invokes actions via direct static delegates without `System.Reflection`.
- **Framework-Dependent, Not Trimmed**: The extension carries its own IL and dependencies and takes the runtime from the host, so the published binary is a few hundred kilobytes without any trimming. `Directory.Build.targets` strips `PublishAot`, `PublishTrimmed`, `SelfContained` and `PublishSingleFile` on purpose: trimming an extension that is reflected over by the host is a class of bug worth not having, and a framework-dependent file deploys to any host image that already has .NET.
- **Pure C# Records**: Data contracts are typed C# records with parameter names matching action arguments. The SDK owns JSON serialization, and generated stubs preserve end-to-end typing from server to client.
- **Multi-Engine Isolated Storage**: Extensions access the database through `Exo.Database`, which scopes queries and KV storage to the extension's own schema — `plugin_<extension_id>`, inside a per-instance database named `exoforge_<extension_id>`. Both prefixes are configurable (`:schema_prefix`, `:db_prefix`), so an operator can separate tenants without touching extension code.

---

## 3. Extension Discovery & Production Volume Isolation

Exoforge boots by scanning configured paths for `manifest.json` files and constructing a topological dependency graph:

- **Multi-Path Scanning**: `EXTENSIONS_PATH` (or `:scan_path` in application config) can be configured with multiple paths. The runtime accepts Elixir lists, comma-separated, semicolon-separated, or JSON array strings (e.g., `EXTENSIONS_PATH="/app/builtin_extensions,/app/uploaded_extensions"`).
- **Static vs. Mutable Volume Separation**: In containerized production deployments (Docker / Kubernetes), pre-compiled standard extensions are baked into `/app/builtin_extensions` inside the immutable image. A persistent volume is mounted strictly over `/app/uploaded_extensions` (`UPLOADED_EXTENSIONS_PATH`). This ensures that image updates deploy new built-in extensions without overwriting or obscuring custom user extensions.
- **Deduplication & Semver Precedence**: When an extension ID appears in multiple scanned directories, `ManifestLoader` resolves the collision by keeping the higher semantic version. If versions are identical, the later/uploaded directory takes precedence so that hot patches override built-ins seamlessly. Built-in files are protected against accidental file deletion.
