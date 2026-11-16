# M46: SDK, CLI & Cluster DX Hardening Plan

> **Status**: Completed (Tracks A–H; `AllowPlayerRead` and `OnExtensionStart()` lifecycle hook shipped)  
> **Created**: 2026-11-16  
> **Scope**: Fixes and ergonomics improvements identified from real Unity SDK (`0.1.39`) + C# extension + cluster usage.  
> **Result**: Unity SDK `0.1.41` / CLI `0.1.40`; 436 Elixir + 132 C# unit tests green. The `OnExtensionStart()` lifecycle hook is implemented via the optional `lifecycle` frame.

---

## 1. Validation Summary (Verified Against Codebase)

| # | Reported Issue | Verdict | Verified Root Cause |
|---|---|---|---|
| 1 | Resources not auto-migrated on deploy | **Valid** | `Exoforge.Std.ExtensionManager` (`load_and_boot_extension/3` at `extensions/exoforge_std_extension_manager/lib/exoforge/std/extension_manager.ex:560-575`) and `ExtensionBootstrapper.boot_extension/1` (`core/lib/extension_bootstrapper.ex:50-52`) never call `resource_store.migrate`. `Exoforge.Std.Resources` (`extensions/exoforge_std_resources/lib/exoforge/std/resources.ex:48-52, 728-735`) only migrates on its own boot, manual `resource_store.migrate`, or lazily on `resource_store.*` calls. |
| 2 | Silent failures on `Database.Put` / `Database.All` | **Valid** | `NativeExtensionRunner` swallows errors in `run_host_call("db_all", ...)` (`core/lib/drivers/runtime/native_extension_runner.ex:546-551` → `[]`) and `db_put/4` (`:598-606` → `false`). `Sqlite` adapter (`extensions/exoforge_std_database/lib/exoforge/std/database/adapters/sqlite.ex:110-116, 194, 262-269`) turns `"no such table"` on `SELECT` into `[]` and falls back to `kv` on `kv_put`/`kv_all` when the real table is missing (unlike `Postgres`, which `CREATE TABLE IF NOT EXISTS`). |
| 3 | `forbidden_scope` lacks context | **Valid** | `ActionDispatcher.authorize_scope/2` (`core/lib/action_dispatcher.ex:448-477`) returns bare `{:error, :forbidden_scope}`. HTTP (`exoforge_std_http/lib/exoforge/std/http/router.ex:350-352`) and WS (`exoforge_std_ws/lib/exoforge/std/ws/socket_handler.ex:331-349`) do not include `required_scope` or `caller_scopes`. |
| 4 | `{:exit_before_handshake, N}` lacks stderr | **Valid** | `NativeExtensionRunner.init/1` (`core/lib/drivers/runtime/native_extension_runner.ex:155-161`) opens the Port with `[:binary, :exit_status, :use_stdio, :hide]` without capturing stderr, so `{:exit_before_handshake, status}` (`:248-265`) only reports the exit code. |
| 5 | `resource_store.*` claims `scope: "global"` in contracts | **Valid** | `core/lib/std/services.ex:672-737` omits `scope(...)` on `defservice resource_store` (defaulting to `"global"` in exported contracts), while `extensions/exoforge_std_resources/lib/exoforge/std/resources.ex:189-349` sets `scope: Exoforge.Auth.Roles.studio()` on all 8 actions. `ActionDispatcher` checks the implementation module, rejecting players with `forbidden_scope`. |
| 6 | Studio/Admin APIs mixed into Unity client stubs | **Valid** | `ExoCodeGenerator.ParseServices` (`sdk/csharp/Exoforge.Management/ExoCodeGenerator.cs:311-369`) & `Generate` (`:1231-1650`) emit all services (`Dashboard`, `ExtensionManager`, `ResourceStore`, `Cron`) and all actions into `Assets/Exoforge/Generated/ExoforgeServices.g.cs` with zero scope filtering. |
| 7 | No declarative read access on `[ExoResource]` | **Valid (Feature)** | `ExoResourceAttribute` (`sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs:187-219`) has no `AllowPlayerRead` option, and `exoforge_std_resources` enforces `studio` on `list`/`get`. |
| 8 | Inconsistent API naming in docs vs SDK | **Valid** | `CurrentPlayerId` (stale in `sdk/unity/Exoforge.SDK/README.md:38`, `sdk/unity/Exoforge.SDK/Agents~/skills/exoforge-extensions/SKILL.md:48,79`) vs `CallerPlayerId` (`IPluginContext` at `sdk/csharp/Exoforge.Plugin.SDK/Interfaces.cs:16`). Also `Exo.Database` vs `ExoServices.Database` are mixed across docs/scaffolder/samples, while `ExoServices` in Unity client code is a different facade without `.Database`. |
| 9 | Primary key casing mismatch | **Valid** | `ExoforgePluginGenerator.cs:442, 897` copies `[ExoResource(PrimaryKey = "Id")]` verbatim into `manifest.json` (`"primary_key": "Id"`), while `ColumnsFor` (`:911`) snake-cases columns (`"id"`). (`DatabaseExtensions.Put<T>(entity)` is case-insensitive in C#, but `manifest.json` is inconsistent.) |
| 10 | `int` → `long` widening in client codegen | **Valid** | `ExoCodeGenerator.MapTypeToCSharp` (`sdk/csharp/Exoforge.Management/ExoCodeGenerator.cs:1821, 1828`) maps `"integer" or "int" => "long"` and `"list_int" or "[:integer]" => "List<long>"`. |
| 11 | `exo.dll` targets `net10.0` instead of `net9.0` | **Valid** | `sdk/csharp/Exoforge.CLI/Exoforge.CLI.csproj:4` hardcodes `<TargetFramework>net10.0</TargetFramework>`, published `--no-self-contained` (`justfile:369`), producing `Editor/Cli~/exo.runtimeconfig.json` requiring `10.0.0`. Meanwhile `ExoforgeDotnetValidator.cs:18,300` and `ExoScaffolder.cs` set the floor to `net9.0`. |
| 12 | Lifecycle / Seeding Hook (`[ExoSeed]` / `OnExtensionStart`) | **Valid (Feature)** | `PluginHost.RunInstance` (`sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs:175-220`) has no startup or post-migration hook; only `[ExoCron(..., RunOnStartup = true)]` exists via `exoforge_std_cron`. |

---

## 2. Orchestrated Execution Plan (4 Waves)

### Wave 1 — Quick Wins & Unblockers (Parallelizable, Disjoint Files)

- [x] **Track A: CLI `.NET 9.0` Compatibility (`exo.dll`)**
  - **Files**: `sdk/csharp/Exoforge.CLI/Exoforge.CLI.csproj`, `justfile` (`build-unity-sdk`), `sdk/unity/Exoforge.SDK/Editor/Cli~/exo.runtimeconfig.json` (regenerated)
  - **Changes**:
    1. Change `<TargetFramework>net10.0</TargetFramework>` to `net9.0` in `Exoforge.CLI.csproj` (and add `<RollForward>Major</RollForward>` so it also runs when only .NET 10+ is installed).
    2. Rebuild via `just build-unity-sdk` and verify `Editor/Cli~/exo.runtimeconfig.json` has `"tfm": "net9.0"` and `"rollForward": "Major"`.
  - **Verify**: `dotnet sdk/unity/Exoforge.SDK/Editor/Cli~/exo.dll --help`

- [x] **Track B: Docs Naming & Generator `PrimaryKey` Casing**
  - **Files**: `sdk/unity/Exoforge.SDK/README.md`, `sdk/unity/Exoforge.SDK/Agents~/skills/exoforge-extensions/SKILL.md`, `sdk/csharp/Exoforge.Plugin.Generator/ExoforgePluginGenerator.cs`, `sdk/csharp/Exoforge.Management/ExoScaffolder.cs`
  - **Changes**:
    1. Replace `CurrentPlayerId` with `CallerPlayerId` in `README.md` and `SKILL.md`.
    2. Standardize extension docs/scaffolder examples on `Exo.Database` / `Exo.Context` (noting `ExoServices` is the Unity client facade).
    3. In `ExoforgePluginGenerator.cs` (`:442`, `:897`), normalize `PrimaryKey` with `ToSnakeCase(primaryKey)` when emitting `manifest.json` so `"primary_key"` matches snake-case `"columns"`.
  - **Verify**: `dotnet test` on `Exoforge.Plugin.Generator` / `Exoforge.Plugin.SDK` tests.

- [x] **Track C: Fix `resource_store` Contract Scope**
  - **Files**: `core/lib/std/services.ex` (`:672-737`)
  - **Changes**:
    1. Add `scope(:studio)` (matching `Exoforge.Std.Resources`) to all 8 actions in `defservice resource_store` so `.contracts_cache.json` and exported contracts accurately reflect `"studio"` instead of `"global"`.
  - **Verify**: `mix test` in `core/` (contract export tests).

---

### Wave 2 — Backend Diagnostics & Migration Safety (Elixir + SDK Bridge)

- [x] **Track D: Verbose Errors (`forbidden_scope` + `exit_before_handshake` stderr)**
  - **Files**: `core/lib/action_dispatcher.ex`, `extensions/exoforge_std_http/lib/exoforge/std/http/router.ex`, `extensions/exoforge_std_ws/lib/exoforge/std/ws/socket_handler.ex`, `core/lib/drivers/runtime/native_extension_runner.ex`
  - **Changes**:
    1. `ActionDispatcher.authorize_scope/2`: return `{:error, {:forbidden_scope, %{required: required_scope, caller_scopes: caller_scopes}}}` (or attach details in dev mode; preserve backwards-compatible error code `"forbidden_scope"` in HTTP/WS JSON while adding `required_scope` and `caller_scopes` fields in dev mode).
    2. `NativeExtensionRunner`: capture stderr (either via `:stderr_to_stdout` with a pre-handshake bounded line ring, or a wrapper/named pipe) and include the last ~20 lines of stderr + `"Run: exo extension logs <id>"` in the `Logger.error` and `{:exit_before_handshake, status, stderr_tail}` payload.
  - **Verify**: `mix test` (`action_dispatcher_test.exs`, `native_extension_runner_test.exs`, `extension_protocol_test.exs`).

- [x] **Track E: Auto-Migrate on Deploy + Strict `Database` Diagnostics**
  - **Files**: `extensions/exoforge_std_extension_manager/lib/exoforge/std/extension_manager.ex`, `core/lib/drivers/runtime/native_extension_runner.ex`, `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/sqlite.ex`, `sdk/csharp/Exoforge.Plugin.SDK/HostBridge.cs`, `sdk/csharp/Exoforge.Plugin.SDK/DatabaseExtensions.cs`
  - **Changes**:
    1. In `ExtensionManager.load_and_boot_extension/3`, if `resource_store` is registered and the manifest declares `resources`, invoke `resource_store.migrate` for that extension's resources and fail the deploy loudly if migration returns an error.
    2. In `NativeExtensionRunner` (`db_all`, `db_put`, `db_get`, `db_delete`), stop swallowing `{:error, reason}` into `[]`/`false`/`nil`; return structured `{ok: false, error: reason}` over `host_call_result`.
    3. In `Sqlite` adapter, stop masking `"no such table"` as `[]` on `SELECT` and stop silently falling back to the `kv` table when a declared resource table is missing.
    4. In `Exoforge.Plugin.SDK`, throw `ExoDatabaseException` (including table name and server error) when `host_call_result` indicates failure.
  - **Verify**: `mix test` (`exoforge_std_resources`, `exoforge_std_database`, `exoforge_std_extension_manager`) + `dotnet test` (`Exoforge.Plugin.SDK`).

---

### Wave 3 — Codegen Split, Type Fidelity & Extension Ergonomics

- [x] **Track F: Split Client vs Studio/Admin Codegen + `int` Fidelity**
  - **Files**: `sdk/csharp/Exoforge.Management/ExoCodeGenerator.cs`
  - **Changes**:
    1. Exclude system/admin services (`resource_store`, `extension_manager`, `dashboard`, `dashboard_view`, `cron`) and `studio`/`admin`-scoped actions from the default `ExoServices` Unity client facade (optionally emit them under `ExoServices.Studio` wrapped in `#if UNITY_EDITOR` or behind an `--include-studio` flag).
    2. Fix `MapTypeToCSharp`: map `"int"` / `"int32"` → `int` (keep `"int64"` → `long`), and check `"[:int]"` / `"[:integer]"` mapping so C# `int` fields stay `int` in `ExoforgeServices.g.cs`.
  - **Verify**: `dotnet test` (`Exoforge.Management` codegen tests) + regenerate `sample_unity` stubs and check `git diff`.

- [x] **Track G: `[ExoResource(AllowPlayerRead = true)]` + `[ExoSeed]` / `OnExtensionStart`**
  - **Files**: `sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs`, `sdk/csharp/Exoforge.Plugin.Generator/ExoforgePluginGenerator.cs`, `sdk/csharp/Exoforge.Plugin.Generator/ManifestEmitter.cs`, `extensions/exoforge_std_resources/lib/exoforge/std/resources.ex`, `sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs`, `core/lib/drivers/runtime/extension_protocol.ex`, `core/lib/drivers/runtime/native_extension_runner.ex`
  - **Changes**:
    1. Add `AllowPlayerRead` to `ExoResourceAttribute`, emit `"allow_player_read": true` in `manifest.json`, and allow `player`-scoped `resource_store.list` / `resource_store.get` in `exoforge_std_resources` for resources marked `allow_player_read: true`.
    2. Add `[ExoSeed]` (or `OnExtensionStart` / post-migration lifecycle hook) in `Exoforge.Plugin.SDK` + `ExtensionProtocol` so extensions can run idempotent seeding after deploy/migration.
  - **Verify**: `mix test` + `dotnet test` + new unit tests for `AllowPlayerRead` and `[ExoSeed]`.

---

### Wave 4 — Full Verification & Unity Package Sync

- [x] **Track H: End-to-End Verification**
  - Run `mix test` across `core/` and `extensions/`.
  - Run `dotnet test` across `sdk/csharp/`.
  - Run `just build-unity-sdk && just unity-sync && just sample-check`.
  - Update `AGENTS.md` / `plan.md` test counts and archive this plan to `docs/archive/` once all tracks are `[x]`.
