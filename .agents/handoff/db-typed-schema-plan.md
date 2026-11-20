# Typed schemas from [ExoResource] (replaces the id/data-jsonb model for declared resources)

Decision (user): declared resources get real tables with real columns and a declarative, manifest-driven migration.
Supersedes D7 (expression indexes on jsonb). D5 (login roles + db_read) is independent: it is about schemas/roles, not columns.

## Shape
- Declared resource (manifest `resources[].columns`) => typed table `schema.table`, one column per record property.
  Undeclared `Database.Put/Get` tables keep the `(id text, data jsonb, updated_at)` envelope: nothing breaks.
- No `extra jsonb`: C# `Put<T>` only ever writes T's properties, so unknown fields cannot exist; reads of older rows get column defaults.
- Type mapping (generator emits `storage`, the server never guesses): string->text, int->integer, long->bigint, short->smallint,
  bool->boolean, double->double precision, float->real, decimal->numeric, Guid->uuid, DateTime/DateTimeOffset->timestamptz,
  byte[]->bytea, enum->text + CHECK (choices), List/Dictionary/nested record->jsonb. Nullable from `Nullable`.
- Migration is declarative on every boot: diff manifest vs information_schema, record `schema_hash` per table in `_exo_schema`.
  Auto-applied (safe): CREATE TABLE, ADD COLUMN (nullable, or NOT NULL with a default), CREATE INDEX IF NOT EXISTS, widen a type.
  Refused with a clear error unless an explicit migration exists: DROP/RENAME column, narrowing/incompatible type, NOT NULL without default on a
  non-empty table. `database.plan_schema` returns the plan without applying it (dry run). Advisory lock around apply.
- Existing jsonb resource tables convert once: add typed columns, backfill from `data`, keep `data` renamed `_legacy_data` until a later release drops it.
- FK: real REFERENCES only inside one extension; cross-schema stays soft with a plain index (no jsonb expression indexes needed).

## Tasks (one worktree wt/<id>, one commit, tests that fail before)
| id | task | touches | depends |
|---|---|---|---|
| T0 | ADR 004 typed schemas (this shape, the safe/unsafe table, why no extra jsonb); AGENTS.md pointer | docs | - |
| T1 | Generator: per column emit `storage` (CLR-accurate pg type), `primary_key`, `unique`, `indexed` (add ExoColumn Indexed/Unique if absent), plus per-resource `schema_hash`; manifest tests | Plugin.Generator, Plugin.SDK attrs, tests | - |
| T2 | Database ext: schema reconciler (plan + apply, ledgers `_exo_schema`, `_exo_migrations`, `_exo_rejects` created automatically, safe/unsafe classification, advisory lock, validated quoted identifiers) as a new module called after provisioning; `database.plan_schema` action | exoforge_std_database | T1 |
| T3 | Typed Put/Get/All/Delete/batch for declared tables (upsert across columns, row->JSON->record); envelope path kept for undeclared tables | postgres.ex, database.ex | T2 |
| T4 | Resources extension + Studio generic CRUD on columns (filter, sort, search, ILIKE, kv_envelope_row? removed for typed tables) | exoforge_std_resources, dashboard_views | T3 |
| T5 | One-time jsonb->typed conversion of existing tables (T2 path, `_legacy_data`) | exoforge_std_database | T3 |
| T6 | C# migrations (see Amendment): `[ExoMigration(id)]` + `IMigration` fluent API (Convert/Rename/Fill/Transform, Reject), batched and resumable through host calls, listed in the manifest; `exo db plan/apply` and `exo db migration new` (stub generator); testable via Testing.cs | Plugin.SDK, Generator, Management, native runner | T2, T3 |
| T7 | FK: REFERENCES within an extension, soft+index across schemas | T2 module | T2 |
| T8 | Docs, sample, one SDK version bump | all | all |
Order: T0 and T1 now; then T2; T3; T4/T5/T7; T6; T8. D5 (roles) runs beside this; both touch postgres.ex provisioning only at the seam (ensure_database).

## Ecto
Not adopted for migrations: Ecto migrations are versioned Elixir modules, ours are generated declaratively from a C# manifest and
authors write C#. Ecto does not diff. DDL here is a few idempotent statements over validated identifiers.

## Amendment: C# migrations and automatic versioning (user)
Game devs write migrations in plain C#, never SQL. Additive changes need none; only unsafe ones need a named migration.
```csharp
[ExoMigration("0002_price_to_decimal")]
public void Up(IMigration m) {
    m.Table<Item>().Convert("price", (string s) => decimal.Parse(s));
    m.Table<Item>().Rename("nm", "name");            // renames are never inferred: explicit
    m.Table<Item>().Fill("rarity", row => "common"); // backfill a new NOT NULL column
    m.Table<Item>().Transform(row => { /* typed access */ });
}
```
- Ledgers, created and maintained by the server per extension schema: `_exo_schema` (every applied schema_hash + time = automatic schema history),
  `_exo_migrations` (id, name, applied_at, duration, rows, checksum, status, cursor; pending = not in it, run in id order; checksum change on an applied one is flagged),
  `_exo_rejects` (table, row_id, column, original value jsonb, target type, reason, migration id, time).
- Bad values: a lambda throwing `Reject("reason")` quarantines that value (opt-in policy `OnInvalid = Quarantine`; default aborts the migration). Never quarantine whole rows
  (NOT NULL without default needs a Fill or a nullable column). Dry run reports "N values would be quarantined"; rejects are logged, emitted as an event and listed by `exo db rejects`.
- Boot order: provisioning, safe auto changes, pending migrations (data in batches, committed, cursor in the ledger so a crash resumes), final swap/constraints in one
  transaction, verify live schema == manifest (the gate: mismatch fails boot with a clear message), then [ExoSeed].
- Large tables never take a long ACCESS EXCLUSIVE lock: add-new-column, backfill in batches, swap.
- Plan output for an unsafe change names it and prints a migration stub. Build-time detection (committed schema snapshot like EF Core) is a later option.

## Status / follow-ups
- Done and pushed: T0 (ADR 004), T1 (generator storage/pk/unique/indexed/schema_hash; byte/sbyte/ushort/uint/ulong/char mapped, hash sorted by column name).
- T2 spec: .agents/tasks/db-t2.json. It builds the reconciler as an UNWIRED module (+ plan_schema dry run, ledgers) because until T3 the runtime still writes
  declared resources in the envelope; T3 wires reconcile into boot together with typed Put/Get/All/Delete/batch. Start T2 after D5 merges (shared manifest-reading seam).
- D5 (login roles, db_read grants, CONNECTION LIMIT) is running first.

## Decisions after T2 (user)
- Existing Postgres instances and tables are resettable for now; no jsonb->typed conversion (T5 dropped). `schema_change_mode` :reset now, :refuse once the format is settled.
- A broken extension is isolated: B1 (core + Studio) comes before T3. Spec files: .agents/handoff/db-b1-spec.md, db-t3-spec.md.
- T3 ships behind `typed_resources` (default false); T4 makes Resources/Studio CRUD work on typed tables, flips the default and deletes the flag.

## Decisions after B1 review (user)
- `schema_change_mode` per environment: :reset in dev/test, :refuse otherwise (release default is prod); explicit EXOFORGE_SCHEMA_CHANGE_MODE overrides. In production an unsafe change
  fails only that extension and the message points at the change (table.column, reason, C# `decl` file:line) and asks for a migration (T6).
- Blocked dependents: yes (B1). Calls to a failed/blocked extension return extension_unavailable with the reason.
- NEW T9 (after T4): convert the std Elixir extensions to typed resources: the Elixir DSL emits `storage` for declared resource columns (map the DSL types),
  then each std extension's tables (auth, player_data, file_bucket, observability, metering, http, resources/tiers) are checked and converted one at a time with their suites green.
- DELETE `typed_resources` flag in T4: acceptance `git grep -n typed_resources` returns nothing. Tracked here so it is not forgotten.
- Resources extension calls the Database module by name (Module.concat([Exoforge, Std, Database]) in resources.ex:481,580,609), which breaks the "services, never module names" rule:
  T4 moves it to dispatch on the :database service.

## Decisions after layering discussion (user) - see db-layers-spec.md
- T3 on hold. New order: B1 (running), then L0, L1, L2, L3, L4 (revised T3), T4, T6, T9.
- schema_change_mode is a deploy-site setting (EXOFORGE_SCHEMA_CHANGE_MODE, default refuse); dev recipe/compose/tests set reset. Supersedes the environment-based default in db-t3-spec.md.
- lldb = engine driver, database = SQL helper, resource_store = ORM. T1's postgres-named `storage` becomes logical types (L1).
