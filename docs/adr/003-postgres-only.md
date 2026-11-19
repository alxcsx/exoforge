# ADR 003: Official `exoforge_std_database` Is PostgreSQL-Only

- **Status**: Accepted
- **Date**: 2026-11-19
- **Context**: Removing embedded SQLite from the official database extension while keeping `database` swappable.

---

## 1. Context & Problem Statement

Offline embedded SQLite with fewer guarantees than production proved nothing about production behaviour, while PostgreSQL runs offline locally in a container (`just db-up`).

---

## 2. Decision Outcomes

- **Official Extension Is Postgres-Only**: Remove the SQLite adapter, `exqlite`, SQLite fallback config, and throwaway `EXOFORGE_DATA_DIR` SQLite test files from `exoforge_std_database` (keeping the `Exoforge.Std.Database.Adapter` behaviour seam for test doubles).
- **Swappable Contract & `dialect`**: The `database` contract stays swappable, and the optional `dialect` field in host `hello` (`Exo.Database.Dialect`) stays so swapped-in extensions identify their engine (the official extension reports `postgres`).
- **Local Dev & Tests**: Docker or Podman is required to run a backend locally (contributors, local server, and Elixir tests via `just db-up`/`just db-down` with throwaway Postgres DBs); Unity game developers connect to a dev or preprod cluster.

### Swapped-In Database Ownership
Whoever swaps the `database` extension owns cross-extension joins and every isolation and security guarantee. `db_read` grants and per-extension Postgres-role isolation are provided and tested only by the official Postgres extension; a replacement must implement `db_read` itself or refuse `db_read` at boot.

---

## 3. Consequences & Accepted Cost

- **Positive**: Dev, CI, and production share identical Postgres semantics (per-extension LOGIN roles, transactions, `JSONB`, `db_read` grants) under the official extension while keeping the `database` contract swappable.
- **Accepted Cost**: Running a local backend requires Docker or Podman, and third-party database replacements own their isolation and `db_read` enforcement.
- **Where Postgres-specific parts live**: see [ADR 005](005-database-layers.md); everything above `lldb` stays engine-agnostic.
