# Open work (written 2026-11-18, after clearing idle helper panes)

Ordered by importance. Monorepo `projetao_mvp` has local-only commits (not pushed): 194bc43, 32fecd0,
acc15a0 (SDK 0.1.55), 5a84f90. Worktrees: exoforge-wt/{studio-split,studio-token,exo-seed} (from acc15a0).

## 1. Core platform fixes (user priority; spec in .agents/tasks/)
- studio-split  (RUNNING on agy gemini-3.8-flash, pane agy-gemini-3-8-flash-exoforge): admin/Studio services
  must not be on the gameplay ExoServices facade; separate #if UNITY_EDITOR class. Was accidentally
  interrupted once and resumed. Review its REPORT against test output before merging.
- studio-token  (not started): Studio login must write the new token to Exoforge/exoforge.json.
- exo-seed      (not started): [ExoSeed] hook after OnExtensionStart.
- Done locally, unpushed: List<T> typing + JSON columns on the KV path, RID from cluster target_rid,
  migrate relaxes legacy `data NOT NULL`, scope refusal reason, nullability + param defaults (0.1.53).
- Unverified: Unity-side edits (IsModifiedSinceBuild call sites, ExoforgeCliTools.cs) never compiled in Unity.
- Not reproduced: reporter's "resource_store.list scope global" (contract already declares player).
- Throwaway Postgres cluster running on 127.0.0.1:5432 (data dir in the Claude scratchpad `pgdata`); stop with
  `/opt/homebrew/opt/postgresql@16/bin/pg_ctl -D <scratchpad>/pgdata stop` when finished.
- `brew uninstall postgresql@16` decision pending (Argon installed it without asking).

## 2. Snowball Siege (arcade, exoforge-arcade main c6a41f0, 3d-client branch wp/3d-client c5a5280)
- WP7 result (Beam): 8 extensions deployed, generated client has WorldBoss + Achievements (commit c5a5280).
  BUG: curl spawn_boss/report_hit fail `service_not_declared`: world_boss manifest lacks a `database`
  dependency. Fix the extension (declare the dependency), redeploy, redo the curl proof. Not merged yet.
- Beam ran `pkill -f beam.smp`: that kills EVERY BEAM VM on the machine. Tell helpers to stop only their own
  backend (by pid) in future specs.
- WP5 tools/smoke/boss.sh + smoke.sh (needs live cluster, SQLite and Postgres; 40 concurrent hits, 30 accepted/10
  rejected, exactly-once payout), WP9 BossBridge.cs/MockGameServer.cs, WP10 SnowballSiegeSetup.cs + scene,
  then headless `tools/unity.sh 3d-snowball-siege ArcadeSetup.SetUpAll` and a Unity compile check.
- Docs pass: "SDK 0.1.48" -> current, test-count TODO marker, "all six samples" accuracy.
- Arcade main not pushed beyond eb17be9. Old arcade root Library/ (~1.6 GB) and generated .csproj files unremoved.

## 3. Housekeeping / questions for the user
- CLAUDE.md line about agy non-Gemini quota is stale (user corrected it).
- Stale prebuilt sdk/csharp/Exoforge.CLI/bin/.../exo.dll and Cli~/exo.dll: CI builds the package; do not build locally.
- SDK distribution idea (git release/`upm` ref built by CI): deferred by the user.

## Panes cleared (all superseded, nothing lost)
agy-exoforge (cli-wrapper, done), agy-argon (WP4 tests, quota stop; I rewrote the tests), agy-opus (plan, done),
agy-gpt-oss (WP3 stubs, quota stop; superseded), agy-sonnet (WP6, quota stop; hydrogen finished it, merged),
agy-hydrogen (WP6, done), agy-flash (WP7 first try, quota stop; Beam redid it), copilot-exoforge (README, done),
omp-beam-free-exoforge (WP7 reported above).
