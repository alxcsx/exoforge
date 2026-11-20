# Versioning: game versions, extension versions, row stamps (spec v1)

Status: approved architecture, nothing built. Supersedes the per-resource `Version`/`MinVersion` of db-t6-spec.md
(the declarative ALTER migrations shipped in 2452ee7 stay; only the version *source* changes, see S3).

## Rules
1. One process per extension, always the latest version. No side-by-side copies.
2. Data version = extension version. A row's `_v` is the extension version whose shape the row has.
   Code at version N reads any row with `_v <= N` and migrates it up on touch (steps without a migration are identity).
   A client built against an older version that meets a row stamped newer gets `client_outdated`. Never back.
3. Old clients are served by the same code: action revisions (`[ExoAction(Until = "2.0")]`), deleted when no supported game version needs them.
4. Same scheme for per-player rows, configs, globals and singletons.

## Versioning extension (`exoforge_std_versioning`, provides `versioning`, no dependencies)
- Game version: `{version, status, locks: %{extension_id => ext_version}, created_at}`.
- Status: `dev` (pre-prod) -> `live` (current) -> `outdated` (in migration, still served) -> `blocked` (`upgrade_required`).
- Policy: at most 3 non-blocked game versions (one each of dev, live, outdated). Promoting a new one moves the oldest
  `outdated` to `blocked` automatically. The limit is config (`max_active_versions`, default 3).
- Actions: `register(version, locks)`, `promote(version)`, `block(version)`, `list`, `resolve(version)` -> `{status, locks}`.
- Studio: badges per extension version listing the game versions that lock it.

## Client version plumbing (revised: no kernel or protocol change)
- Ingress already builds `_auth` (`player_id`, `scopes`) for each call and the SDK already reads it. The game version rides there too.
- S2a (done, wt/ver2): SDK reads `_auth.game_version` into `IPluginContext.CallerGameVersion`. SDK 0.1.59.
- S2b (revised again after reading auth: stateless, no token/table change): the client sends its game version on the connection,
  WS in the `auth` frame (`game_version`), HTTP in the `x-exoforge-game-version` header. The transport (`Exoforge.Std.Transport`)
  resolves it through `versioning.resolve` with a short ETS/process cache (30 s), only when the `versioning` service is registered
  (no versioning extension = no check, no field). Unknown or `blocked` -> `{error, upgrade_required}` with `status` in the body;
  otherwise `_auth.game_version` is set for every call. A missing header/field means no game version (old clients keep working).
  It is compatibility information, not a security boundary: a client that lies only breaks itself.
- Game version -> extension version happens in the SDK (`versioning.resolve` through `Exo.Services`, cached per game version), so the
  dispatcher and the wire frames stay untouched.

## Contract gate (database layer)
Refuse a deploy that drops/renames a column, or removes an action revision, while any non-blocked game version locks an
extension version that still needs it, or any row has `_v` below the new minimum. Message names the game version and the count.

## Slices
- S1 versioning extension (registry, statuses, 3-version policy, resolve) + tests for status moves and the policy.
- S2 session + dispatcher + frame `client_version`; `upgrade_required`.
- S3 `_v` = extension version in the database layer, lazy migration in the SDK, contract gate; replace per-resource `Version`
  (`[ExoMigration]` From/To become extension versions). Needs an SDK version bump.
- S4 Studio badges, `migrate_batch` sweeper action, action revisions.

Tests stay narrow (status moves, policy, stamp comparison, gate); end-to-end runs belong to CI.
- S5 opt-out (see below). Runs after S4; needs an SDK version bump.

## Opting out: `SchemaVersioningMode` (S5)
- Per resource (per table): `[ExoResource("items", SchemaVersioningMode = SchemaVersioningMode.Manual)]`; enum `Auto` (default) | `Manual`.
  Emitted in the manifest on the resource as `"schema_versioning_mode": "auto" | "manual"`; absent means auto.
- `Auto`: everything above (reconciler, ALTER migrations, `_v` stamps, lazy migration, contract gate, sweeper).
- `Manual`: Exoforge never alters that table and adds no `_v`. The studio owns migrations as plain SQL files
  (`migrations/0007_name.sql`), applied in order by `exo db migrate` with the same lock timeout and the `_exo_migrations` ledger.
  At deploy the live table is compared with the manifest (drift check): a mismatch fails that extension alone, nothing is changed,
  and the message says what differs. A manual table is not part of the contract gate; the studio owns that safety (say so in the docs).
- Mixed extensions are fine: auto and manual resources side by side. A swapped-out or removed versioning extension affects only auto resources.
- Maintenance mode (transports answer `service_unavailable` with a retry hint during a studio's migration) is NOT in S5; add it when asked.
- Tests: manifest emits the flag; manual table is not altered and a drifted one fails alone; auto resources beside it still reconcile.

## Std extensions: hand-rolled migrations (S5a, independent of S1-S4)
Std extensions are `Manual`: they ship with the server image, so their schema follows the server release, not game versions.
Today each one runs inline `CREATE TABLE IF NOT EXISTS` (auth, player_data, metering, observability, file_bucket, http cors),
which never alters an existing table, so the `db-audit.md` fixes cannot reach a real deployment.
- Runner in `exoforge_std_lldb` (it owns DDL and the `_exo_migrations` ledger): an extension gives an ordered list of
  `{version, name, sql}`; the runner applies the ones not in the ledger, in one transaction each, under `lock_timeout` and the advisory lock, and records them.
  Exposed as an lldb action (e.g. `run_migrations`: `namespace`, `migrations`).
- Migration 1 of each std extension is its current table, verbatim. Later numbers carry audit fixes (not part of S5a).
- Convert one extension first (metering: smallest) as the template; others follow in separate commits.
- Tests: ledger skips applied versions; a failing migration rolls back and later ones do not run; order is by version.

## S3 contracts (server / C# / client run in parallel against these)
**Stamp encoding.** Extension version "MAJOR.MINOR.PATCH" (minor, patch < 1000) -> bigint `major*1_000_000 + minor*1_000 + patch`.
Elixir: `Exoforge.VersionStamp.encode/1` in core (`"2.1.0" -> 2001000`; invalid/nil -> 0). C# mirror in the SDK (`ExoVersion.Encode`). A missing `_v` means 0 (older than everything).

**Row stamp `_v`.** Every typed table of an *auto* resource gets an implicit `_v bigint NOT NULL DEFAULT 0` column (safe add, never in the manifest
column list). Writes through the database layer set `_v` to the encoded manifest version of the calling extension (ExtensionRegistry). Typed reads return `"_v"` in the row map.
`put` accepts optional `if_v` (an encoded stamp): the upsert only updates when the stored `_v` equals it; zero rows written -> `{:error, :stale}`.

**Manifest migrations (replaces per-resource Version and From/To ints).** Resource `"version"` is removed. Top-level
`"migrations": [{"resource": "counters", "to": "1.2.0", "decl": "V12.cs:7", "ops": [...]}]`. A migration applies when the table's ledger version
(encoded ext version of the last deploy, 0 if none) < encode(to) <= encode(manifest version of the extension being deployed); in ascending `to` order, no
contiguity needed. Ops: `rename`, `convert`, `fill`, `drop`, `set_not_null` (as shipped in T6). The reconciler ledger `version` column now holds the encoded ext version.
An unsafe change with no migration whose `to` is in (live, manifest] is refused (message: add `[ExoMigration(typeof(T), To = "<manifest version>")]` in its own file).

**Retired columns.** A live column absent from the manifest is no longer an unsafe drop: it is *retired* (no SQL; `NOT NULL` is lifted with `DROP NOT NULL` so new writes work). Only an explicit
`drop` op physically drops it, and that is gated (below).

**Contract gate (resource_store/lldb, Elixir).** A `drop` op (or any op that destroys data) is refused while `SELECT count(*) FROM t WHERE _v < encode(op migration "to")` > 0
(message: N rows still below version X; the sweeper or time will clear them) or, when the `versioning` service is registered, while a non-blocked game version locks this extension below `to`.

**Lazy row migration (C# SDK).** `[ExoRowMigration(typeof(T), To = "2.0.0")] static T Up(JsonElement oldRow)` (any static class). The generator emits a registry.
`Exo.Database.Get<T>/All<T>/First<T>/Query<T>` read `_v`; for a row with `_v` < encode(To) of any row migration of T, apply the pending ones in `To` order, then write the row back with `put` + `if_v`
(lost race -> re-read, no error). Rows already current are untouched. The extension's own version stamps the write-back (host does it).

**Client.** `ExoClientOptions.GameVersion` (string?; Unity default `Application.version`), sent as WS `auth` frame field `game_version` and HTTP header `x-exoforge-game-version`; WS close 4001 / HTTP 426 / `upgrade_required` raises `ExoUpgradeRequiredException` and an `OnUpgradeRequired` event. No version bump in feature branches: the orchestrator bumps the SDK version once at merge.

