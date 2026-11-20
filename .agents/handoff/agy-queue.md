# agy queue (t7). Do these in order after your current wt/migrate Elixir-test task; Gemini Hydrogen/Flash,
# no /teamwork unless a task says so. One commit per task, only your paths. Reply after EACH task:
#   ask --reply t7 "<task id>: <=10 lines: commits, tests added (names), results, bugs found"

## Q1 - wt/migrate generator side (worktree /Users/alexcs/projects/exoforge-wt/migrate)
Beam left UNCOMMITTED, UNTESTED edits in sdk/csharp/Exoforge.Plugin.Generator/ExoforgePluginGenerator.cs and
sdk/csharp/Exoforge.Plugin.SDK/Naming.cs (ToSnakeCase runs of capitals, explicit column names lowercased, EXO005).
Review them against point 3 of .agents/handoff/wt-migrate.md, finish what is missing, and add tests in
sdk/csharp/Exoforge.Plugin.Generator.Tests: one per diagnostic case (two properties same column ignoring case;
PrimaryKey names no column; explicit column name not lowercase snake), ToSnakeCase (ID->id, PlayerID->player_id,
HTTPCode->http_code, SubmitScore->submit_score), and .agents/handoff/loja_itens.cs compiles with NO diagnostic and
emits primary_key "id". Grep sdk/unity/sample_unity + extensions_csharp for names that change; list them in the
commit message. Run Generator.Tests + Plugin.SDK.Tests (mise exec -- dotnet test ...).

## Q2 - wt/tooling: `exo unity records` (worktree /Users/alexcs/projects/exoforge-wt/tooling)
Point 1 of .agents/handoff/wt-tooling.md. Beam left UNCOMMITTED edits in sdk/csharp/Exoforge.CLI/Program.cs and
sdk/csharp/Exoforge.Management/ExoIsExternalInit.cs - review and finish. Also per-assembly presence in the Studio
(ExoforgeIsExternalInit.PresentPath) and a docs/skill line for fresh clones/CI. Management tests: --asmdef, --all,
idempotent second run. Touch only CLI/Management/Editor IsExternalInit files + their tests/docs.

## Q3 - wt/tooling: rid on every error reply (same worktree, different files)
Point 2 of .agents/handoff/wt-tooling.md: extensions/exoforge_std_http router auth plug (unauthenticated,
token_expired) and any WS auth refusal get a rid and go through Transport's shared error builder. http/ws tests
assert rid + nested shape on 401s. Touch only extensions/exoforge_std_http, exoforge_std_ws (+ transport if needed).

## Q4 - wt/tooling: Unity migrates an old project to .feed on reload (same worktree, different files)
Point 3 of .agents/handoff/wt-tooling.md: on domain reload, if Exoforge/nuget.config is not the static .feed one or
an Exoforge/extensions/**/nuget.config exists, run ExoforgeIdeProjectGenerator.EnsureWorkspaceFeed once. Put the
"needs migration?" check in Exoforge.Management so it is unit-testable; Management test for it. Touch only
ExoforgeIdeProjectGenerator.cs / Management feed code + tests.

## Q5 - wt/instances finish + review (worktree /Users/alexcs/projects/exoforge-wt/instances)
Branch is done by Beam (4 commits, ProfileTests 5/5). Review it against .agents/handoff/wt-instances.md as a
different model family (MPPM via Application.dataPath Library/VP/<id>, -exoProfile, default keeps legacy keys,
validation, no key collision between profiles). Add the missing "Testing several players on one machine" section to
the Unity skill under sdk/unity/Exoforge.SDK/Agents~ (README already has it). Fix any bug you find with a test.

## Rules for every task
- Worktree rules: /Users/alexcs/projects/exoforge/.agents/handoff/wt-common.md (no version bump, no push/merge,
  /Users/alexcs/.local/bin/mise exec -- for mix/dotnet, mix deps.get once per fresh dir).
- Every spec point needs a test you ran that fails on projetao_mvp. Commit only your own paths (git commit -- <paths>);
  Q2, Q3, Q4 share a worktree, and Q1 shares one with the wt/migrate Elixir tests.
- Final: write .agents/TEAMWORK_DONE.json {"status":"complete","artifact":"/Users/alexcs/projects/exoforge/.agents/handoff/agy-queue-report.md"}
  with one section per task (commits, tests, results, bugs found), then ask --reply t7 "TEAMWORK_DONE".
