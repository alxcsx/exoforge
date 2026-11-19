# ADR 004: Typed Resource Schemas (Real Columns, Not id/data JSONB)

- **Status**: Accepted
- **Date**: 2026-11-19
- **Context**: Declared resources used an `id/data jsonb` envelope, which blocked real columns, joins and indexes.

---

## 1. Context & Problem Statement

Declared resources were stored as `(id text, data jsonb, updated_at)` rows: every property lived inside one JSON blob. That blocked real columns, joins, indexes, typed FKs, and per-column filtering/sorting in the Studio. D7 (expression indexes on jsonb) is superseded; D5 (login roles + db_read) is independent.

---

## 2. Decision Outcomes

### Decision 1: Typed Tables for Declared Resources
- Manifest `resources[].columns` ⇒ a typed table `schema.table`, one column per record property.
- Undeclared `Database.Put/Get` tables keep the `(id text, data jsonb, updated_at)` envelope: nothing breaks.
- **No extra jsonb**: C# `Put<T>` writes only T's properties, so unknown fields cannot exist; reads of older rows get column defaults.

### Decision 2: Type Mapping (Generator Emits `storage`)
`string→text`, `int→integer`, `long→bigint`, `short→smallint`, `bool→boolean`, `double→double precision`, `float→real`, `decimal→numeric`, `Guid→uuid`, `DateTime/DateTimeOffset→timestamptz`, `byte[]→bytea`, `enum→text + CHECK`, `List/Dictionary/nested record→jsonb`. Nullable from `Nullable`. The server never guesses.

### Decision 3: Declarative Migration
- On every boot, diff manifest vs `information_schema`, record `schema_hash` per table in `_exo_schema`.
- Auto-applied (safe): `CREATE TABLE`, `ADD COLUMN` (nullable, or `NOT NULL` with default), `CREATE INDEX IF NOT EXISTS`, widen a type.
- Refused with a clear error unless an explicit migration exists: `DROP`/`RENAME` column, narrowing/incompatible type, `NOT NULL` without default on a non-empty table. `database.plan_schema` returns the plan without applying (dry run). Advisory lock around apply.
- One-time conversion: add typed columns, backfill from `data`, keep `data` renamed `_legacy_data` until a later release drops it.

### Decision 4: FK Rules
- Real `REFERENCES` only inside one extension; cross-schema stays soft with a plain index (no jsonb expression indexes).

---

## 3. Consequences & Accepted Cost

- **Positive**: real columns, joins, indexes, typed FKs and Studio column ops for declared resources; envelope retained for undeclared tables.
- **Accepted Cost**: manifest becomes a schema contract; unsafe changes need an explicit migration (escape hatch).
- **Escape hatch**: `[ExoMigration]` methods run through `db_batch` with a ledger; `exo db plan/apply` CLI.

### Why Ecto Is Not Used
Ecto migrations are versioned Elixir modules; ours are generated declaratively from a C# manifest and authors write C#. Ecto does not diff. DDL here is a few idempotent statements over validated identifiers.