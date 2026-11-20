# Next steps (written 2026-11-18, exoforge at dcd1cb6, SDK 0.1.50)

Start here in a new session. Findings so far: `.agents/SAMPLES_FINDINGS.md` (F1–F30),
`.agents/samples-findings/phase2.md`, `phase3.md`. Arcade samples: `/Users/alexcs/projects/exoforge-arcade`
(public: github.com/alxcsx/exoforge-arcade, branch main, single squashed commit f0c9785; pre-squash history backup was in the Claude scratchpad only).

## State
- Everything merged and pushed to `projetao_mvp`. No worktrees, no wt/* branches.
- No backend, omp worker or agy running for exoforge.
- After pulling: `mise exec -- mix deps.compile --force`.
- `Exoforge/exoforge.json` (admin session) is now gitignored in the arcade (template: `exoforge.example.json`); never commit it or `Exoforge/mock-game-server.token`. The repo is PUBLIC.
  The arcade's working-tree diff (scenes, `.contracts_cache.json`) is SetUpAll churn; leave it.

## Standing rules from the user
- No workarounds in samples: let them crash where the platform needs a change, and fix the platform.
- Players never get raw file read/upload; always behind server-side logic (file_bucket private + signed_url).
- Dev/service credentials are ordinary users the admin creates (CLI or Studio).
- Orchestration: omp first (Beam free when DeepSeek quota is out), agy `/teamwork` on Gemini second,
  Claude Haiku reviewer / Copilot Fusion (auto model only) last for risky diffs. Worktree per task under
  `/Users/alexcs/projects/exoforge-wt/<task>`, branch `wt/<task>`, merge `--no-ff`.
- omp needs env passed: `env ${=ENVV} PATH="$PATH" omp --model opencode-go/beam-free`
  (ENVV = XDG_*, ZDOTDIR, PI_CODING_AGENT_DIR, DOTNET_ROOT, MIX_HOME, HEX_HOME).
- Beam claims "done" without tests/commits: require pasted test output and a commit hash.

## Next, in order

### 1. DONE — F30 flaky Plugin.SDK test hang (root cause: DeploymentGuardTests build-server pipes; merged)
One run of `sdk/csharp/Exoforge.Plugin.SDK.Tests` hung 10 min; 7 reruns passed.
Suspect: the host-call reader thread blocking on a real stdin.
- Loop: `dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests --blame-hang-timeout 60s` until it dumps.
- Done when: root cause named from the dump, fix + a test that hangs without it, 20 clean loops.

### 2. DONE — typed Query<T> bool mapping (already fixed in 69ae5dd; regression tests merged)
EF/Dapper convert by the target property type. Make typed `Query<T>` map 0/1 (SQLite) and
true/false (Postgres) to `bool` properties.
- Done when: a test per adapter (SQLite, Postgres) round-trips a bool column through `Query<T>`.

### 3. DONE — arcade on Postgres, all green after F31-F35 (merged); 11 local commits unpushed
The arcade only ran on SQLite; the loja_itens bug was a Postgres DDL error.
- Backend with Postgres (`just compose-up` or a local PG + `EXOFORGE_DATA_DIR` temp dir), redeploy all
  arcade extensions, run `tools/smoke.sh`, the 7 test projects, and SetUpAll in Unity.
- Each failure becomes an F-number in SAMPLES_FINDINGS.md with a repro, then a platform fix.

### 4. New sample covering untested surfaces (agy plans, omp builds)
One game exercising:
- `cron`: a scheduled task inside a game extension.
- `file_bucket`: private bucket + extension-issued `signed_url` (Addressables path).
- Token lifetime: a session running past the ~1h access token (shortened TTL in test env), refresh,
  reuse-revokes-family.
- Multi-instance: two MPPM clones playing each other (F28 profiles end to end).
Write findings the same way; fix platform, not the sample.

### Known, documented, not bugs
- Brief downtime during redeploy (one instance by design; rollback on failure).
- F26 moot.
