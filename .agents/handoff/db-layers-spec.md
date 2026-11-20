# Database layers: lldb (driver), database (SQL helper), resource_store (ORM)  [ADR 005 draft, for review]

Decision (user): each layer is more than a thin wrapper. Nothing above lldb names PostgreSQL; the official lldb implementation is the only place that does.

| Layer | Extension | Owns | Service contract (engine-agnostic) | Implementation |
|---|---|---|---|---|
| lldb | `exoforge_std_lldb` (new) | everything about ONE engine: connections and pools, isolated namespaces per extension, roles/grants, transactions, DDL rendering, catalog introspection, dialect, type mapping, health | `dialect` (name + capabilities such as transactional_ddl, upsert, returning, advisory_lock), `quote_identifier`, `render_type(logical)`, `exec(namespace, sql, params)`, `transaction(namespace, ops)`, `provision_namespace` / `drop_namespace`, `grant_read` / `revoke_read`, `introspect(namespace)` (normalized tables, columns, keys, indexes, checks), `health_check`, `connection_config`, event `connection_lost` | official: PostgreSQL (schema per extension, login roles, pg_catalog, advisory locks, jsonb). A swapped-in lldb implements or refuses the same contract |
| database | `exoforge_std_database` | SQL-level helper over lldb: put/get/all/delete, query/execute with binding, batch, row<->JSON mapping for a table descriptor, SQL building using lldb's dialect helpers | UNCHANGED for clients and the C# SDK (`execute`, `table_columns`, `health_check`); internal `register_table(descriptor)` | SQL-generic: no pg_catalog, no roles, no `search_path`; anything dialect-specific (upsert, placeholders, returning) comes from lldb |
| resource_store | `exoforge_std_resources` | the ORM: manifest resources to table descriptors, schema reconcile (plan/apply, safe/unsafe, ledgers), `[ExoMigration]`, schema_change_mode, quarantine, attribute helpers (types, keys, indexes, FKs), Studio CRUD | `resource_store` + a provisioning step run before an extension starts | engine-agnostic: speaks logical types through database/lldb |

Dependencies: resource_store -> database -> lldb. Words that stay below lldb's contract: schema, role, search_path, pg_*, jsonb. The contract says "namespace".

## Logical types (manifest `storage`)
text, int16, int32, int64, float32, float64, decimal, bool, uuid, timestamp, bytes, json (enum = text + choices). T1 emitted PostgreSQL names (jsonb, timestamptz,
"double precision"), which leaks the engine into the manifest: L1 changes it now, while nothing consumes it. lldb renders them (Postgres: smallint, integer, bigint,
real, double precision, numeric, boolean, uuid, timestamptz, bytea, jsonb).

## Provisioning step
Before an extension starts the kernel calls `resource_store.provision(manifest)`: lldb provisions the namespace and grants (D5 logic), resource_store reconciles
declared resources (T2 logic), then registers table descriptors with `database`. Failure is a B1 boot failure with `stage: :storage`.

## Schema change strategy (replaces environment detection)
Set at the deploy site: env var `EXOFORGE_SCHEMA_CHANGE_MODE=reset|refuse` or config, the same way compose/devops set other settings. Default when unset: `refuse`.
`just dev`, the dev compose file and the test helper set `reset` explicitly. No `Mix.env`/environment sniffing. `refuse` failures say where (table.column, op, reason, C# decl).

## Tasks (each: worktree, one commit, tests; the refactors change NO behaviour and every suite stays green)
- L0 ADR 005 from this file + AGENTS.md section 2 table update (docs).
- L1 generator emits logical `storage`; update T1 tests, Agents.MD, manifest docs; Plugin.SDK/Generator suites (C# only).
- L2 extract `exoforge_std_lldb`: move adapters/postgres.ex, manager pools, provisioning, roles/grants (D5), TestDB; grow the lldb contract in core/lib/std/services.ex;
  `database` becomes the SQL layer calling lldb through the service (no module-name calls); database contract for clients unchanged; dependency order lldb, database, rest.
  ~3,000 lines move. Acceptance: the full extension sweep, core, and `just test-sdk` unchanged.
- L3 move the schema reconciler and ledgers (T2) into resource_store using `lldb.introspect` and `render_type`; `plan_schema` moves with it; resources.ex stops calling the Database module by name.
- L4 revised T3: provisioning step, table descriptors, typed CRUD in `database` via dialect helpers, schema_change_mode as above, `typed_resources` flag (deleted in T4).
- Then T4 (Studio CRUD on typed tables, flip default, delete the flag), T6 (C# migrations), T9 (convert std Elixir extensions).

## Risks
- One extra service hop per query (database -> lldb). Excluded from metering already; measure before and after L2, expect microseconds.
- A SQL-generic layer over one real engine can drift into assumptions only Postgres satisfies. Mitigation: an in-repo test double lldb with a different dialect (quote style, no upsert) that the database/resource_store tests also run against.
- L2 is a large move; do it as pure moves first, behaviour changes after.

## Status (updated)
- L0 (ADR 005), L1 (logical storage types in the generator), L2.1 (extract exoforge_std_lldb), L2.2 (key-value, typed rows and batch move into the
  database layer; lldb gains transaction/introspect/dialect), L2.3 (test-double lldb with a different dialect): DONE and pushed.
- L3 (revised, deliberate): the reconciler STAYS in the driver layer. Its planner and its DDL are interleaved and both are engine-aware (widening
  rules, ALTER syntax), so splitting them would have meant rewriting ~700 lines for little. lldb now exposes `apply_schema` and `reset_table`
  next to `plan_schema`, accepts logical `storage` types (mapped through the dialect's type map), and the end-to-end path
  (logical manifest columns -> apply_schema -> typed Store put/get/all/delete) is tested. resource_store owns the POLICY around it.
- Next: L4 = resource_store orchestration: the provisioning step before an extension starts, EXOFORGE_SCHEMA_CHANGE_MODE reset|refuse
  (reset = reset_table for unsafe tables, refuse = fail that extension with where-it-is messages), failures via B1 stage :storage; then T4, T6, T9.
- Unity sample regeneration is handed off: .agents/handoff/unity-sample-regen.md
