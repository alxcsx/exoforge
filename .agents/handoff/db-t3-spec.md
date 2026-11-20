# T3: typed storage for declared resources, wired into boot

Decisions (user): in dev every Postgres instance and existing table is resettable; production never resets silently and asks for a migration for unsafe changes.
So T5 (jsonb to typed conversion) is dropped. A schema reconcile failure fails only that extension (B1 must land first).

## Rules
- A resource is TYPED only if every one of its manifest columns has `storage` (commit d0ca30a). Anything else (std Elixir extensions today,
  undeclared `Database.Put` tables) keeps the `(id, data jsonb, updated_at)` envelope, untouched.
- `schema_change_mode` is decided PER ENVIRONMENT, never silently `:reset` in production. Resolution order: explicit setting wins (env var
  `EXOFORGE_SCHEMA_CHANGE_MODE=reset|refuse` or extension config `schema_change_mode`); otherwise `:reset` when the environment is :dev or :test and `:refuse`
  for everything else. The environment is `Mix.env()` under mix, else `Application.get_env(:exoforge, :env, :prod)` (the bootstrapper's `current_env/0`
  logic; extract it to one place), so a release defaults to `:prod` and therefore `:refuse`.
  - `:reset` (dev/test only by default): a table whose plan has unsafe ops (including `:convert_envelope`, drop/rename, narrowing, NOT NULL without
    default) is DROPPED and recreated, with ONE warning log line naming the table, the ops and the number of rows dropped, plus a ledger row; safe ops apply in place.
  - `:refuse` (production default): unsafe ops return `{:error, {:unsafe_schema_change, ops}}`; the extension fails to boot (B1, status `:boot_failed`,
    stage `:schema`). The message must say WHERE: for each unsafe op, `table.column`, the op, the reason and, when the manifest carries it, the C# declaration
    site (`Models/Item.cs:42`); for a database column missing from the code, "column 'x' exists in the database but not in your code". It ends with the migration
    hint: "add an [ExoMigration] (T6) or set EXOFORGE_SCHEMA_CHANGE_MODE=reset to rebuild this table" and prints a migration stub once T6 exists.
  - To make the location available, T1 gets a small follow-up in this task: the generator emits per column `decl` = project-relative `file:line` of the property
    (Roslyn location; never an absolute path; omitted when unavailable). Does not enter `schema_hash`.
- Feature flag `typed_resources` (default false): until T4 makes Resources/Studio CRUD work on typed tables, main must keep working. Tests enable it;
  T4 flips the default and DELETES the flag (user: remember to delete it). The flag must be named exactly `typed_resources` so `git grep typed_resources` proves it is gone.

## Wiring
- After D5 provisioning in `ensure_database`, read the plugin's manifest resources (use the manifest seam D5 added for `db_read`), run
  `Schema.reconcile` for the typed ones in one pass, write ledger rows, and cache `{schema, table} => columns` (ETS/persistent_term) so storage ops know
  which tables are typed. Failure returns an error that fails only that extension.
- Typed `put/get/all/delete` in the Postgres adapter for cached typed tables (the host calls `db_put/db_get/db_all/db_delete` and `db_batch` are unchanged,
  and so is the C# SDK):
  - put: `INSERT ... ON CONFLICT (pk) DO UPDATE SET <all non-pk columns>`; the JSON value's keys map to column names (verify the C# JSON naming equals
    the manifest names, snake_case); a missing key is NULL or the column default; an unknown key is ignored (C# `Put<T>` never sends one).
  - Coercion per storage: text, integer family and numeric from JSON numbers (and numeric strings), boolean, uuid, timestamptz from ISO-8601,
    bytea from base64, jsonb as is, enum text checked by the CHECK constraint. A value that cannot be coerced returns a structured error naming the column.
  - get/all: row to JSON map with the same encodings back; numeric must come back as a JSON NUMBER without float rounding (Jason encodes Decimal as a
    string by default, which the C# side cannot read as decimal: use a number fragment); timestamptz as ISO-8601 UTC; bytea as base64.
  - delete by pk. `db_batch`: typed put/delete inside the same transaction; `execute` stays raw SQL.
- Raw `Database.Query<T>` is unchanged and now sees real columns.

## Tests (real Postgres via TestDB; fail before)
Round trip for every storage type including nullable, decimal that floats cannot hold exactly, uuid, timestamptz with offset, bytea, nested jsonb, enum;
upsert replaces; delete; all ordered by pk; batch atomic rollback with typed ops; envelope resources untouched when flag off or a column lacks storage;
mode resolution (dev, test, prod, release default, explicit override); `:reset` drops and recreates an unsafe-changed table with one warning and keeps safe changes in place; `:refuse` returns an error that names table.column, op, reason and the `decl` location, and the extension fails alone (B1); the generator emits `decl` (generator test); `database.plan_schema` agrees with what boot applies; a cross-extension JOIN on real columns through `db_read` (D5) returns rows.

## Accept
database extension tests green with the temp Postgres; the full extension sweep green with the flag at its default (nothing changes for std extensions);
core tests green.
