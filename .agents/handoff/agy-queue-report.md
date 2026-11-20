# Agy Queue Report (Q1–Q5)

## Q1 — `wt/migrate` (`/Users/alexcs/projects/exoforge-wt/migrate`)
- **Commit**: `ef19bd1` (6 files)
- **Bugs Fixed**:
  - `ExoforgePluginGenerator.cs`: `spc` was `null` at `ResourceFromType`/`ColumnsFor` call sites so `EXO005` was never emitted; wired errors through `ServiceEmit.ResourceValidationErrors` to `Report(...)`. Exempted implicit `"id"` in `PrimaryKey` check and fixed inline `[ExoResource]` on service classes to use `ColumnsFor` pk.
  - `ExoforgePluginGenerator.cs` + `DispatchEmitter.cs`: aligned `ToSnakeCase` with `ExoNaming.ToSnakeCase` (capital runs as one word) and removed duplicate in `DispatchEmitter`.
- **Tests Added**:
  - `ResourceValidationTests.cs` (6 tests): `EXO005` for duplicate column ignoring case, missing `PrimaryKey`, invalid explicit column name; implicit `id` allowed; lowercase explicit column + acronym `ToSnakeCase` (`ID`, `PlayerID`, `HTTPCode`, `SubmitScore`); `loja_itens.cs` compiles with 0 diagnostics and `"primary_key": "id"`.
  - `PluginSdkTests.cs`: added `ID`, `PlayerID`, `HTTPCode` assertions to `ExoNaming_UsesSnakeCase`.
- **Results**: `Exoforge.Plugin.Generator.Tests` 27/27 passed; `Exoforge.Plugin.SDK.Tests` 78/78 passed.
- **Sample/Extensions Impact**: No identifier renames needed in `sdk/unity/sample_unity` or `extensions_csharp`.

## Q2 — `wt/tooling` (`/Users/alexcs/projects/exoforge-wt/tooling`)
- **Commit**: `ff3282c`
- **Changes & Bugs Fixed**:
  - Completed `exo unity records [--asmdef <dir>] [--all]`, per-assembly `ExoforgeIsExternalInit.PresentPath(dir)` in Studio Settings and Setup Modal, and docs in `Agents~/AGENTS.md` + `README.md`.
  - Fixed missing `command` variable and duplicate `CliArgs.Parse` in `Program.cs`, and `using System;` + regex word-boundaries + `HasAsmdef` recursion in `ExoIsExternalInit.cs`.
- **Tests Added**: 2 new tests in `ExoIsExternalInitTests.cs`.
- **Results**: `dotnet test ... --filter ExoIsExternalInit` -> 7 passed, 0 failed.

## Q3 — `wt/tooling` (`/Users/alexcs/projects/exoforge-wt/tooling`)
- **Commit**: `79e418f` (`transport: attach rid and canonical error shape to HTTP and WS auth refusals`)
- **Changes & Bugs Fixed**:
  - `exoforge_std_http/lib/exoforge/std/http/router.ex`: added `assign_rid` plug (skipping `/health`) setting `x-exoforge-rid` + `:exoforge_rid`; routed `token_expired`, `unauthenticated`, and `forbidden` through `Transport.error_body(..., rid)`; avoided duplicate `:rid`/`"rid"` keys in `send_json`.
  - `exoforge_std_ws/lib/exoforge/std/ws/router.ex` & `socket_handler.ex`: added `assign_rid` plug and `token_expired` handling in WS HTTP router; routed `handle_auth` failures and unauthenticated `subscribe` frames through `Transport.error_body(..., rid)`.
  - Fixed missing `{:error, :token_expired}` clause in `authorize_ingress` (would raise `CaseClauseError` in HTTP) and duplicate `:rid`/`"rid"` key in `send_json`.
- **Tests Added**: 1 new + 2 updated 401 assertions in `exoforge_std_http/test/http_test.exs`; 3 new tests in `exoforge_std_ws/test/ws_test.exs`.
- **Results**: `http_test.exs` 36/36 passed; `ws_test.exs` 20/20 passed.

## Q4 — `wt/tooling` (`/Users/alexcs/projects/exoforge-wt/tooling`)
- **Commit**: `35c52c9`
- **Changes**: Added `ExoScaffolder.NeedsFeedMigration(string)` in `sdk/csharp/Exoforge.Management/ExoScaffolder.cs` and wired `NeedsWorkspaceFeedMigration()` into `ExoforgeIdeProjectGenerator` static ctor + `delayCall`.
- **Tests Added**: 5 tests in `sdk/csharp/Exoforge.Management.Tests/FeedMigrationTests.cs`.
- **Results**: `dotnet test ... --filter FeedMigration` -> 5 passed, 0 failed.

## Q5 — `wt/instances` (`/Users/alexcs/projects/exoforge-wt/instances`)
- **Commit**: `686e585`
- **Bugs Fixed & Docs**:
  - Fixed `ExoDeviceId.HardwareId` ignoring `ExoProfile.Current` via `ExoProfileResolver.DeviceSeed` (`default` unchanged, named profiles suffixed `:<profile>`).
  - Fixed missing `<summary>` tag on `LoginAnonymously` in `ExoforgeAuth.cs`.
  - Added `## 7. Testing several players on one machine` to `sdk/unity/Exoforge.SDK/Agents~/skills/exoforge-connection/SKILL.md`.
- **Results**: `dotnet test sdk/csharp/Exoforge.Client.Tests --filter Profile` -> 7 passed, 0 failed.
