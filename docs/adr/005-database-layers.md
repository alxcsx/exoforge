# ADR 005: Database Layers — `lldb` (driver), `database` (SQL helper), `resource_store` (ORM)

- **Status**: Accepted
- **Date**: 2026-11-19
- **Context**: `lldb`, `database`, and `resource_store` were three names with unclear roles.

---

## 1. Context & Problem Statement

The database stack exposed `lldb`, `database`, and `resource_store` with overlapping responsibilities and no declared ownership. Anything above the driver could name PostgreSQL, schema, or roles, leaking the engine into engine-agnostic contracts.

---

## 2. Decision Outcomes

### Decision 1: Layered Ownership

| Layer | Extension | Owns | Engine-agnostic service contract | Implementation |
|---|---|---|---|---|
| `lldb` | `exoforge_std_lldb` | one engine: pools, isolated namespaces per extension, roles/grants, transactions, DDL rendering, catalog introspection, dialect, type mapping, health | `dialect`, `quote_identifier`, `render_type(logical)`, `exec(namespace, sql, params)`, `transaction`, `provision_namespace`/`drop_namespace`, `grant_read`/`revoke_read`, `introspect(namespace)`, `health_check`, `connection_config`, event `connection_lost` | official: PostgreSQL (schema per extension, login roles, `pg_catalog`, advisory locks, `jsonb`) |
| `database` | `exoforge_std_database` | SQL helper over `lldb`: put/get/all/delete, query/execute with binding, batch, row<->JSON mapping, SQL building via `lldb` dialect helpers | unchanged for clients/SDK (`execute`, `table_columns`, `health_check`); internal `register_table(descriptor)` | SQL-generic: no `pg_catalog`, no roles, no `search_path` |
| `resource_store` | `exoforge_std_resources` | ORM: manifest resources to table descriptors, schema reconcile (plan/apply, safe/unsafe, ledgers), `[ExoMigration]`, `schema_change_mode`, quarantine, attribute helpers | `resource_store` + a provisioning step run before an extension starts | engine-agnostic: logical types via `database`/`lldb` |

Dependencies: `resource_store` -> `database` -> `lldb`.

### Decision 2: Nothing Above `lldb` Names PostgreSQL

Words that stay below `lldb`'s contract: `schema`, `role`, `search_path`, `pg_*`, `jsonb`. The contract says "namespace". A swapped-in `lldb` implements or refuses.

### Decision 3: Logical Types for Manifest `storage`

`text`, `int16`, `int32`, `int64`, `float32`, `float64`, `decimal`, `bool`, `uuid`, `timestamp`, `bytes`, `json` (enum = text + choices). `lldb` renders them (Postgres: `smallint`, `integer`, `bigint`, `real`, `double precision`, `numeric`, `boolean`, `uuid`, `timestamptz`, `bytea`, `jsonb`).

### Decision 4: Provisioning Step

Before an extension starts the kernel calls `resource_store.provision(manifest)`: `lldb` provisions the namespace and grants, `resource_store` reconciles declared resources, then registers table descriptors with `database`. Failure is a B1 boot failure with `stage: :storage`.

### Decision 5: Deploy-Site Schema Change Strategy

Set at the deploy site: env var `EXOFORGE_SCHEMA_CHANGE_MODE=reset|refuse` or config. Default when unset: `refuse`. `just dev`, the dev compose file, and the test helper set `reset` explicitly. No `Mix.env`/environment sniffing. `refuse` failures name table.column, op, reason, and the C# decl.

### Decision 6: Test-Double `lldb`

An in-repo test double `lldb` with a different dialect (quote style, no upsert) that `database`/`resource_store` tests also run against, keeping the SQL layer honest.

---

## 3. Consequences & Accepted Cost

- **Positive**: clean engine boundary; `database`/`resource_store` stay SQL-generic and swappable.
- **Accepted Cost**: one extra service hop per query (`database` -> `lldb`); excluded from metering, expect microseconds.
- **Risk**: a SQL-generic layer over one real engine can drift into Postgres-only assumptions; mitigated by the test double.
- **Risk**: L2 is a large move (~3,000 lines); do pure moves first, behaviour changes after.
