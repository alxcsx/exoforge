# M46 handoff to omp — you now own ALL remaining tracks

The agy/teamwork side is out of quota. Ignore earlier `apply_patch` / `run_command --` / `git commit` / `git push`
messages from agy: they were malformed and you were right to refuse them. Nothing was committed (HEAD = 84288e1).
The Track F ownership restriction is lifted: you own every file below.

Plan: `docs/plans/m46-sdk-dx-hardening.md` (read it first for each track's intent).

## Current state (uncommitted in the working tree)
- Tracks A, B, C, F: done and previously verified (Management.Tests 51/51).
- Tracks D and E plus Wave 2 remediation: implemented by the teamwork workers but NOT confirmed green.
  Files: core/lib/action_dispatcher.ex, native_extension_runner.ex, extension_registry.ex, http/router.ex,
  ws/socket_handler.ex, sqlite.ex, extension_manager.ex, PluginHost.cs, PluginContext.cs, Exceptions.cs and their tests.
  The last open review finding: sqlite.ex `table_source/1` must accept atom sources (`{:table, :scores}`) as well as
  strings, and extension_registry.ex `fetch_resource/1` must match sanitized list/map shapes when `name != table`.
  Add coverage in database_test.exs.
- Track G: not started (any earlier G patch from agy was NOT applied; good).

## What to do, in order
1. **Finish D/E.** Verify the two edge cases above, fix them if missing, run the affected unit tests.
2. **Track G.**
   - C#: `AllowPlayerRead` on `ExoResourceAttribute`, emitted into manifest.json by the generator.
   - Elixir resources: list/get become player-callable, enforced inside the action. Allow `:internal`, allow callers
     that satisfy `studio`, and allow anyone when the resource has `allow_player_read`. Writes stay `studio`.
     (This is the design you proposed. Do not use `scope == :player` equality.)
   - `[ExoSeed]` / `OnExtensionStart` lifecycle hook per the plan. If it needs a new wire frame, update both
     `ExtensionProtocol` and the SDK, plus `extension_protocol_test.exs` and `HandshakeTests.cs`.
     If this becomes large, ship AllowPlayerRead first and report the seed hook as remaining.
3. **Track H.**
   - Fast unit tests only, no live E2E: `mix test` (core + affected extensions) and `dotnet test` for
     Plugin.SDK.Tests, Plugin.Generator.Tests, Management.Tests. If vstest hangs, run each project separately.
   - Bump to 0.1.40 wherever 0.1.39 is the Unity SDK / exo CLI version (package.json, ExoforgePackageVersion.cs,
     CLI csproj). Check how commit 84288e1 did it.
   - Update test counts in AGENTS.md and plan.md with the real numbers. Move the plan to `docs/archive/`.
4. **Commit as you go**, one commit per track. Stage explicit paths only (no `git add .`).
   Do NOT stage `.agents/`, `skills-lock.json` or `sdk/unity/Exoforge.SDK/Editor/Cli~/` unless they are clearly meant
   to ship. Commit only when that track's tests are green. Push to origin/projetao_mvp after every green commit
   (the user has approved pushing). Never push a red tree.

## Reporting
After each track: `hc send agy "AGY_REPORT: <track> done, <tests passed/failed>, <commit sha>"`.
If you get blocked: `hc send agy "AGY_REPORT: BLOCKED <track>: <reason>"`.
When all tracks are done, write `.agents/TEAMWORK_DONE.json` = `{"status":"complete","artifact":"docs/archive/m46-sdk-dx-hardening.md"}`.
