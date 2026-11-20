# Database handling improvement: plan

Supersedes the "no cross-extension SQL" call in fb-xext-design.md (S1's hint stays valid for undeclared access).
Why the reversal is safe: access is explicit (`db_read`), SELECT-only, enforced by Postgres roles, and FKs stay soft.
Cost accepted: a producer's table layout becomes a contract for its declared readers. Record this in docs/adr/002.

## Tracks (each task = one worktree wt/<id>, one commit, tests that fail before)

| id | task | touches | depends |
|---|---|---|---|
| D0 | ADR 002: db_read grants, soft FKs, why RPC hydration is no longer the only path | docs/adr/002-*.md, AGENTS.md sec. 2 | - |
| D1 | `Exo.Database.QuerySql<T>(FormattableString)` / `ExecuteSql`: interpolations become $1..$n; never string-concatenated | Plugin.SDK (Interfaces, DatabaseExtensions), SDK tests | - |
| D2 | Dialect: host `hello` carries `dialect` (postgres/sqlite), optional field so protocol 1 stays compatible; `Exo.Database.Dialect` | extension_protocol.ex + test, native_extension_runner.ex, HostBridge.cs, HandshakeTests.cs | - |
| D3 | `Exo.Database.Transaction(Action<ITransaction>)` / `ExecuteBatch`: new `host_call` op `db_batch`, one stdio round trip, atomic on both adapters | native_extension_runner.ex, adapters/{postgres,sqlite}.ex, HostBridge.cs, Plugin.SDK | - |
| D4 | Manifest `db_read: [...]`; `[DbRead<T>]` and `[ExoForeignKey<T>("id")]` inference in the generator; db_read also registered as a dependency (bootstrap order) | Plugin.Generator, manifest compiler, ExtensionBootstrapper test | D0 |
| D5 | Postgres roles: `ext_<id>` per extension, reconcile `db_read` grants on boot, every Query in a txn with `SET LOCAL ROLE` + `SET LOCAL search_path`; foreign writes rejected by Postgres | adapters/postgres.ex, database tests (tag :postgres) | D3, D4 |
| D6 | SQLite parity: read-only `ATTACH DATABASE ... AS <schema>` for declared db_read | adapters/sqlite.ex, offline test | D4 |
| D7 | Cross-schema FKs are soft (indexed, no REFERENCES) so uninstall/migration cannot deadlock | postgres.ex DDL, resources | D4 |
| D8 | Docs/skills (Agents.MD, Agents~ skills), sample using db_read, one SDK version bump | docs | all |

Order: D0, D1, D2 in parallel-safe sequence, then D3, D4, then D5/D6/D7, D8 last.

## Risks to check first (D5)
- The pool's DB user must be allowed CREATE ROLE and to SET ROLE to each `ext_<id>` (membership grant); managed Postgres may forbid CREATEROLE. Spike this before building D5; fall back to schema-qualified SELECT grants on the shared user with a query allow-list if it does.
- Pools are per extension today (search_path startup param, postgres.ex:602); SET LOCAL needs a txn per Query: measure the latency cost.
- Roles and grants must be idempotent on every boot and removed with the extension.

## Routing (budgets as of now: agy Gemini group ok, agy Claude group and paid omp out ~3d, copilot 200 credits)
- Gemini on agy: D1, D2, D4 (C#/generator, well-bounded), D0, D8.
- Elixir + Postgres work (D3, D5, D6, D7) and the D5 spike: paid omp when it resets; until then Gemini only for D3's C# half.
- Review: copilot reads D5 (security-sensitive) and D3 diffs; different family than the writer.
- Claude: specs, acceptance, merge. Merge in order onto projetao_mvp, push when each wave is green.

## Amendment (decision: Postgres only)
SQLite is removed, not demoted: an offline adapter with fewer guarantees than production proves nothing. Postgres runs
offline in a container. Consequences:
- D6 (SQLite ATTACH) is deleted. D2 (dialect) is reverted: one dialect needs no advertisement. D3/D5/D7 may use Postgres features freely.
- ADR 002 Decision 3 is rewritten: no SQLite; docs/adr/003 records "Postgres is the only database adapter".

| id | task | touches | depends |
|---|---|---|---|
| P1 | Postgres for dev and tests: compose service, `just db-up/db-down`, `just dev` and `just test` bring it up, test helper creates a throwaway database per run (replaces the EXOFORGE_DATA_DIR throwaway-sqlite pattern), CI service container, setup check that Docker/Podman is present | Justfile, compose file, database/test_helper, .github workflows, Unity ExoforgeDotnetValidator-style check | - |
| P2 | Remove the SQLite adapter, its config, deps, tests and docs; Postgres becomes the default and only adapter; keep the adapter behaviour seam | extensions/exoforge_std_database, Agents.MD, docs | P1 |
| P3 | Revert D2 (dialect in hello + Exo.Database.Dialect) | core/lib/drivers/runtime, SDK, tests, Agents.MD | - |
| P4 | ADR 003 (Postgres only) + ADR 002 Decision 3 rewrite + AGENTS.md litmus test no longer cites SQLite | docs | - |
Order: P1, P3, P4 in parallel; P2 after P1; then D3, D5 (spike first), D7, D8.
Risk: Unity developers need Docker/Podman; P1 adds the setup check and a clear message.

Clarification (user): Unity developers never run the project offline; they use a dev/preprod environment (local server or a
separate cluster). Docker/Podman is needed only to run a backend (contributors, a local server). So P1 must NOT add a
Docker check to the Unity editor tooling or Studio setup wizard; keep only the `just`/compose side and the CI service container.

Correction (user): the dialect field STAYS, so someone can swap the database extension for another engine. Only the official
`exoforge_std_database` is Postgres-only. So P3 (revert D2) is CANCELLED; D2 stays merged. The official extension reports
`postgres`. P4's ADR 003 must say: the official database extension is Postgres only; the `database` contract stays swappable
and the dialect field is how a swapped-in extension identifies itself. The litmus-test example in AGENTS.md may keep
mentioning swappable databases, but must not claim SQLite ships.

Note (user): whoever swaps the database extension owns the consequences. ADR 003 must state it: db_read grants, cross-extension
joins and every isolation/security guarantee are provided and tested only by the official Postgres extension; a replacement
must implement or refuse `db_read` itself (refusing at boot is acceptable) and takes responsibility for its isolation.
