# ADR 002: Cross-Extension Database Read Grants

- **Status**: Accepted
- **Date**: 2026-11-19
- **Context**: Opt-in read-only cross-extension SQL grants across isolated extension schemas.

---

## 1. Context & Problem Statement

Exoforge previously enforced a strict "no cross-extension SQL" rule: each extension queried only its own schema, and RPC batch hydration (`get_many` via generated typed stubs) was the only cross-extension read path.

While RPC hydration preserves action-level authorization and loose coupling, join-heavy reads and lookups can avoid extra RPC round-trips when granted direct read-only access. This ADR supersedes the strict prohibition with explicit `db_read` grants; undeclared cross-extension access remains denied with the existing missing-table RPC/stub hint.

---

## 2. Decision Outcomes

### Decision 1: Explicit `db_read` Grants
- **Manifest declaration**: Extensions declare read-only targets in `manifest.json` via `db_read: [...]`.
- **C# generation**: The generator populates `db_read` from `[DbRead<T>]` or cross-extension `[ExoForeignKey<T>("col")]`.
- **Bootstrap ordering**: Each declared `db_read` target is also registered as a dependency so target schemas exist before consumers start.

### Decision 2: Postgres Enforcement
- Each extension receives a per-extension database role `ext_<id>` owning its schema.
- At boot, the database extension reconciles `USAGE` and `SELECT` grants for declared `db_read` targets.
- Queries execute inside a transaction with `SET LOCAL ROLE` and `SET LOCAL search_path`, so Postgres rejects writes to foreign schemas and any undeclared reads.

### Decision 3: Official Extension Ownership & Swapped-In Databases
- Cross-extension `db_read` grants are enforced by PostgreSQL roles only in the official `exoforge_std_database` extension (see [ADR 003](003-postgres-only.md)).
- A swapped-in `database` extension owns its isolation guarantees and must implement `db_read` itself or refuse `db_read` at boot.

### Decision 4: Soft Cross-Schema Foreign Keys
- Cross-schema foreign keys are indexed columns with no SQL `REFERENCES` constraint.
- Omitting cross-schema constraints ensures extension uninstall, schema drop, or independent migrations cannot deadlock.

---

## 3. Consequences & Accepted Cost

- **Positive**: Enables direct cross-extension joins and reads with database-enforced read-only isolation in PostgreSQL under the official extension.
- **Accepted Cost**: A producer's table and column layout becomes part of its contract for declared `db_read` readers (breaking schema changes affect declared consumers just like breaking action contracts).
- **Opt-In & Least Privilege**: Read grants are strictly `SELECT`-only and opt-in; undeclared cross-extension SQL remains denied with the missing-table RPC/stub hint.
- **RPC Default Preserved**: RPC hydration (`get_many` + stubs) remains the default when action-level authorization or decoupling is preferred.
