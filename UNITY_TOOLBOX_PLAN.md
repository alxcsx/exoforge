# Exoforge Unity & C# Toolbox Hardening Plan

> **Status**: **Completed & Landed** (Commit `ede9f54` and subsequent releases).  
> **Scope**: Self-contained packaging (`Exoforge.Plugin.SDK` & `com.exoforge.sdk`), dynamic `.NET 9+` TFM resolution with `netstandard2.1` SDK/stub compatibility, pre-packed `System.Text.Json` dependencies, Unity `.asmdef` compilation graph optimization, in-use stub preservation during contract sync, clear runtime `service_not_found` errors across WS/HTTP/IPC, and `ExoCodeGenerator` identifier/model collision hardening. All 6 tasks landed, passing unit and integration test suites.

---

## Guardrails (Historical)

> [!NOTE]
> 1. **All SDK libraries on `netstandard2.1`**: `<TargetFramework>netstandard2.1</TargetFramework>` preserved across `Exoforge.Client`, `Exoforge.Management`, `Exoforge.Plugin.SDK`, and `Exoforge.Plugin.Generator`.
> 2. **Pre-packed assemblies**: Staged `System.Text.Json.dll`, `System.Text.Encodings.Web.dll`, and `Microsoft.Bcl.AsyncInterfaces.dll` into `Runtime/Plugins` without duplicate BCL collisions.
> 3. **Verification**: Verified with targeted test suites (`Exoforge.Management.Tests`, `Exoforge.Client.Tests`, `Exoforge.Plugin.SDK.Tests`, `Exoforge.Plugin.Generator.Tests`, core mix tests, and `just sample-check`).

---

## Task 1: Self-Contained Packaging & Pre-Packed Dependencies (Completed)

### Delivered
- `Exoforge.Plugin.SDK` (`just pack-sdk`) and Unity SDK (`just pack-unity` / `just build-unity-sdk`) bundled independently without external NuGet dependencies.
- Embedded `Exoforge.Plugin.SDK.<version>.nupkg` inside `sdk/unity/Exoforge.SDK/Editor/Plugins/NuGet~/` during `build-unity-sdk` so any Unity project has the extension SDK offline.
- Auto-resolves embedded `NuGet~` feed in `ExoScaffolder` and `ExoDeployer` when outside the monorepo.
- Pre-packed `System.Text.Json.dll`, `System.Text.Encodings.Web.dll`, and `Microsoft.Bcl.AsyncInterfaces.dll` into `sdk/unity/Exoforge.SDK/Runtime/Plugins/` and updated `package.json`.

---

## Task 2: Dynamic `.NET 9+` TFM Detection & Cross-Machine Build Resilience (Completed)

### Delivered
- Scaffolded extensions target the **latest installed .NET SDK with a minimum of `net9.0`** (e.g., `net9.0` if .NET 9 is installed, `net10.0` if .NET 10 is installed).
- If an extension targets a different TFM than the installed .NET host, `ExoDeployer.PublishNative` detects the mismatch and passes `-p:TargetFramework=<installedTfm>` so builds succeed without editing `.csproj`.

---

## Task 3: First-Import Guard in `ExoforgeControlCenter` (Completed)

### Delivered
- Guarded `AutoCheckClientBindings` from executing on initial package import before workspace initialization (`Exoforge/exoforge.json`).
- Added first-install setup modal guiding users through initialization.

---

## Task 4: Unity Compilation Graph Optimization & `.asmdef` Isolation (Completed)

### Delivered
- Automatically generates and updates `Exoforge.Generated.asmdef` alongside `ExoforgeServices.g.cs` inside Unity `Assets/` trees.
- Configured with `"noEngineReferences": true`, `"autoReferenced": true`, and `"overrideReferences": false`.
- Isolated `Exoforge.Generated` and `Exoforge.SDK` to compile cleanly in parallel via Bee build graph without triggering cascade recompilations of `Assembly-CSharp`.

---

## Task 5: Preserve In-Use Stubs & Clear Runtime "Service Not Found" Errors (Completed)

### Delivered
1. **Never break compilation when syncing against a remote server that lacks a service used in local code**:
   - Embeds compact `// @exoforge-contract: <json>` metadata per generated service at the bottom of `ExoforgeServices.g.cs` and `PluginServices.g.cs`.
   - On `GenerateToFile` or `GeneratePluginStubsToFile`, recovers previously embedded `ServiceContractModel` entries from the existing `.g.cs` file on disk.
   - For each previously generated service missing from the remote contract export, scans non-generated `.cs` files to check if that service is referenced in code.
   - Retains the service contract stub in `.g.cs` when in use or when remote export is empty.
2. **Actionable runtime error on invoking missing services**:
   - Normalized `{:error, :service_not_found}` and `{:error, {:action_not_found, _}}` in WebSocket (`socket_handler.ex`) and HTTP (`router.ex`).
   - In `ExoClient.cs` (`SendActionWsAsync` and `SendActionHttpAsync`) and `HostBridge.cs` (`CallAction<TResponse>`), throws `ExoActionException` / `InvalidOperationException` with clear diagnostics.

---

## Task 6: Harden `ExoCodeGenerator` Against Identifier & Model Collisions (Completed)

### Delivered
- Sanitizes wire identifiers in `ToPascalCase`, `ToCamelCase`, and `SanitizeFieldName` (handles leading digits, colons, slashes, dots, whitespace).
- Prevents CS0542 (member names matching enclosing class name) via `SafePropertyName`.
- Prevents duplicate property names (CS0102) via incremental property naming.
- Disambiguates cross-service model collisions when two services define return records with identical short names but different fields.
