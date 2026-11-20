# D5 Report: Per-Extension Postgres Login Roles & `db_read` Grants (`wt/d5`)

Commit: `59a7d64 feat(database): enforce per-extension Postgres login roles and db_read grants`

## Changes
- `core/lib/domain/manifest.ex:46`, `core/lib/drivers/loaders/manifest_loader.ex:151`: Added `:db_read` to `Exoforge.Domain.Manifest` and `@atom_list_keys` in `ManifestLoader`.
- `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex:63-507,1148-1365`:
  - `role_name(plugin_id, config)`: deterministic `<= 63`-byte identifier including an 8-char SHA-256 hash of the target database name; validates all identifiers against `^[a-z0-9_]+$` and quotes via `quote_ident/1`.
  - Derives per-role password via HMAC-SHA256 from `:role_secret` / `EXOFORGE_DB_ROLE_SECRET` (falling back to the admin password); never logged.
  - `ensure_database/2`: idempotently creates/updates LOGIN role with `CONNECTION LIMIT` (`pool_size + 2` default) and `statement_timeout` (`30s`) / `idle_in_transaction_session_timeout` (`60s`), `GRANT role TO admin WITH SET TRUE, INHERIT FALSE`, `REVOKE CREATE ON DATABASE FROM PUBLIC`, `CREATE SCHEMA IF NOT EXISTS ... AUTHORIZATION role`, migrates existing admin-owned tables then schema, and reconciles `db_read` grants/revocations executed as each owner role.
  - Extension pools connect directly as their extension role with `search_path` startup parameter (no query-time `SET ROLE`).
  - `reset/2`: terminates pool/backends, revokes reads as each grantor, then `SET ROLE ext; DROP OWNED BY ext CASCADE; RESET ROLE; DROP ROLE ext`.
  - Detects missing `CREATEROLE`/`SUPERUSER`: preserves single-user fallback when `db_read` is empty and refuses `db_read` with `{:error, {:createrole_required, msg}}`.
- `extensions/exoforge_std_database/lib/exoforge/std/database/manager.ex:103-194,215`, `test_db.ex:39-68`, `test/postgres_test.exs:497-957`.

## Acceptance
- `cd extensions/exoforge_std_database && mix test`: **PASS** (`Result: 27 passed`; failed before implementation: `Result: 24/27 passed, Failed: 3 tests`)
- `cd core && mix test test/native_extension_runner_test.exs test/extension_protocol_test.exs`: **PASS** (`Result: 39 passed`)
- `cd extensions/exoforge_std_auth && mix test`: **PASS** (`Result: 51 passed`)
- `cd extensions/exoforge_std_resources && mix test`: **PASS** (`Result: 24 passed`)
- `cd extensions/exoforge_std_player_data && mix test`: **PASS** (`Result: 11 passed`)
- `git log --oneline -1 wt/d5`: `59a7d64 feat(database): enforce per-extension Postgres login roles and db_read grants`
