# Exoforge Unity & C# Toolbox Hardening Plan

> **Target Executor**: Autonomous coding agent  
> **Scope**: Self-contained packaging (`Exoforge.Plugin.SDK` & `com.exoforge.sdk`), dynamic `.NET 9+` TFM resolution with `netstandard2.1` SDK/stub compatibility, pre-packed `System.Text.Json` dependencies, Unity `.asmdef` compilation graph optimization, in-use stub preservation during contract sync, clear runtime `service_not_found` errors across WS/HTTP/IPC, and `ExoCodeGenerator` identifier/model collision hardening.

---

## Guardrails for the Executing Agent (Read First)

> [!IMPORTANT]
> 1. **Keep all SDK libraries on `netstandard2.1`**: Do **NOT** change `<TargetFramework>netstandard2.1</TargetFramework>` in `Exoforge.Client.csproj`, `Exoforge.Management.csproj`, `Exoforge.Plugin.SDK.csproj`, or `Exoforge.Plugin.Generator.csproj`. Unity requires `netstandard2.1`.
> 2. **Do NOT stage `System.Memory.dll`, `System.Buffers.dll`, or `System.Runtime.CompilerServices.Unsafe.dll` into Unity**: Unity 2022.3+ and Unity 6 already include these in their built-in `netstandard2.1` profile. Copying them into `Runtime/Plugins` will cause duplicate assembly errors in Unity. Only stage `System.Text.Json.dll`, `System.Text.Encodings.Web.dll`, and `Microsoft.Bcl.AsyncInterfaces.dll`.
> 3. **Do NOT run slow E2E or container recipes locally**: Verify changes using targeted unit tests (`dotnet test sdk/csharp/Exoforge.Management.Tests`, `dotnet test sdk/csharp/Exoforge.Client.Tests --filter "FullyQualifiedName!~VerticalSliceIntegrationTests"`, `dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests --filter "Category!=SlowIntegration"`, `mix test` in `core`, `plugins/exoforge_std_ws`, `plugins/exoforge_std_http`, and `just sample-check`).

---

## Task 1: Self-Contained Packaging & Pre-Packed Dependencies (Items 1.A & 1.C)

### Goal
- Allow `Exoforge.Plugin.SDK` (`just pack-sdk`) and the Unity SDK (`just pack-unity` / `just build-unity-sdk`) to be bundled individually without uploading to NuGet.org.
- Embed `Exoforge.Plugin.SDK.<version>.nupkg` inside `sdk/unity/Exoforge.SDK/Editor/Plugins/NuGet~/` during `build-unity-sdk` so any Unity project has the extension SDK offline.
- Auto-resolve the embedded `NuGet~` feed in `ExoScaffolder` and `ExoDeployer` when outside the monorepo.
- Pre-pack `System.Text.Json.dll`, `System.Text.Encodings.Web.dll`, and `Microsoft.Bcl.AsyncInterfaces.dll` into `sdk/unity/Exoforge.SDK/Runtime/Plugins/` and update `package.json`.

---

## Task 2: Dynamic `.NET 9+` TFM Detection & Cross-Machine Build Resilience (Item 1.B)

### Goal
- Scaffolded extensions target the **latest installed .NET SDK with a minimum of `net9.0`** (e.g., `net9.0` if .NET 9 is installed, `net10.0` if .NET 10 is installed).
- If an extension on disk targets `net10.0` on a machine that only has `.NET 9` installed (or `net9.0` on a machine that only has `.NET 10` installed), `ExoDeployer.PublishNative` detects the mismatch and passes `-p:TargetFramework=<installedTfm>` so builds succeed without editing `.csproj`.

---

## Task 3: First-Import Guard in `ExoforgeControlCenter` (Item 1.D)

### Goal
- Prevent `AutoCheckClientBindings` from running on first package import before the user has initialized an Exoforge workspace (`Exoforge/exoforge.json`).

---

## Task 4: Unity Compilation Graph Optimization & `.asmdef` Isolation (Item 2.E)

### Goal
Optimize Unity compilation speed and assembly isolation:
- `Exoforge.Generated.asmdef` is automatically created/updated in the same directory as `ExoforgeServices.g.cs` whenever `ExoCodeGenerator.GenerateToFile` runs inside a Unity `Assets/` tree.
- `Exoforge.Generated.asmdef` uses `"noEngineReferences": true`, `"autoReferenced": true`, and `"overrideReferences": false` (it only depends on `System.*` and precompiled `Exoforge.Client.dll`).
- `Exoforge.Generated` and `Exoforge.SDK` have no dependency on each other, compiling in parallel via Unity's Bee build graph without triggering re-compilations of each other or `Assembly-CSharp`.

---

## Task 5: Preserve In-Use Stubs & Clear Runtime "Service Not Found" Errors (Items 3.F & 3.G)

### Goal
1. **Never break compilation when syncing against a remote server that lacks a service used in local code**:
   - Embed compact `// @exoforge-contract: <json>` metadata per generated service at the bottom of `ExoforgeServices.g.cs` and `PluginServices.g.cs`.
   - When `GenerateToFile` or `GeneratePluginStubsToFile` is called, recover previously embedded `ServiceContractModel` entries from the existing `.g.cs` file on disk.
   - For each previously generated service that is missing from the new contract export, scan non-generated `.cs` files to check if that service is referenced in code.
   - If referenced in code (or if the new export is completely empty), retain the service contract so its client stub remains in `.g.cs`.
2. **Throw a clear runtime error if a kept stub is called when the service is not on the remote server**:
   - Normalize `{:error, :service_not_found}` and `{:error, {:action_not_found, _}}` in both WebSocket (`socket_handler.ex`) and HTTP (`router.ex`).
   - In `ExoClient.cs` (`SendActionWsAsync` and `SendActionHttpAsync`) and `HostBridge.cs` (`CallAction<TResponse>`), detect `service_not_found` / `action_not_found` and throw an `ExoActionException` / `InvalidOperationException` with a clear, actionable diagnostic message.

---

## Task 6: Harden `ExoCodeGenerator` Against Identifier & Model Collisions (Item 3.H)

### Goal
Prevent malformed or colliding contract definitions from generating uncompilable C# in `ExoforgeServices.g.cs` or `PluginServices.g.cs`:
- Sanitize wire identifiers in `ToPascalCase`, `ToCamelCase`, and `SanitizeFieldName` (handles leading digits, colons, slashes, dots, whitespace).
- Prevent CS0542 (member names matching enclosing class name) via `SafePropertyName`.
- Prevent duplicate property names (CS0102) via incremental property naming.
- Disambiguate cross-service model collisions when two services define return records with identical short names but different fields.
