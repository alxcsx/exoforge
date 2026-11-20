# D5 spike: Postgres roles for db_read (PG 16.16, run by claude, non-superuser pool user with CREATEROLE only)

## Verdict
The ADR-002 design as written (one pool user + `SET LOCAL ROLE ext_x` per query) is NOT a security boundary.
Use a LOGIN role per extension and connect each extension's existing pool as that role. No SET ROLE at all.

## What broke the written design
- Inside `SET LOCAL ROLE ext_store`, `SET ROLE ext_other`, `SET ROLE <pool user>` and `RESET ROLE` all work: role checks use the
  SESSION user. `Database.Query` takes free SQL, so any extension could become another extension or the pool user.
- Pool user must also hold SET on every ext role, so it is a master key that the extension's SQL can reach.
- PG16: a CREATEROLE user gets ADMIN on roles it creates but NOT the SET option; `GRANT ext_x TO pool WITH SET TRUE, INHERIT FALSE` is needed.
- Cost of the wrapper (BEGIN; SET LOCAL ROLE; SET LOCAL search_path; query; COMMIT), pgbench 4 clients: 0.148 ms vs 0.041 ms plain (3.6x,
  ~27k vs ~98k tps); in Postgrex it is also 5 round trips unless pipelined. Login roles cost nothing per query.

## Design that passed every test (script: db-d5-spike.sql)
Admin pool (CREATEROLE, not superuser; owns the database) provisions per extension X, idempotently on every boot:
1. `CREATE ROLE ext_X LOGIN PASSWORD <derived>`; `GRANT ext_X TO admin WITH SET TRUE, INHERIT FALSE`.
2. `CREATE SCHEMA plugin_X AUTHORIZATION ext_X` (admin needs SET on ext_X); `REVOKE CREATE ON DATABASE db FROM PUBLIC`.
3. Grants for a declared reader R of owner O are executed AS the owner: `SET ROLE ext_O; GRANT USAGE ON SCHEMA plugin_O TO ext_R;
   GRANT SELECT ON ALL TABLES IN SCHEMA plugin_O TO ext_R; ALTER DEFAULT PRIVILEGES FOR ROLE ext_O IN SCHEMA plugin_O GRANT SELECT ON TABLES TO ext_R; RESET ROLE`.
   Doing it as the admin fails once the schema is owned by ext_O (admin does not inherit it).
4. The extension's pool (today: search_path startup param, postgres.ex:82,602) connects as `ext_X` with its password; keep the search_path param.
Password: derive per extension with HMAC(server secret, ext id); never stored in the manifest. No password in logs.

## Verified as ext_store, connected directly (no SET ROLE)
- Own schema read/write ok. JOIN onto declared items table returns rows. Future tables in items are readable (default privileges).
- INSERT/DELETE on items: `permission denied for table`; DROP: `must be owner`. Undeclared schema: `permission denied for schema`.
- `SET ROLE ext_other` / `SET ROLE <admin>` denied; `RESET ROLE` leaves ext_store. CREATE in public, CREATE SCHEMA: denied.
- `pg_read_file`, `COPY ... PROGRAM`: denied. information_schema shows only own + granted tables; pg_roles lists ext_* names (minor).

## Teardown / revocation (verified)
- Reconcile revokes every boot: as owner `SET ROLE ext_O; REVOKE ALL ON ALL TABLES IN SCHEMA plugin_O FROM ext_R; REVOKE USAGE ON SCHEMA ...;
  ALTER DEFAULT PRIVILEGES ... REVOKE SELECT ON TABLES FROM ext_R` for readers no longer declared.
- Removing X: revoke X's reads as each grantor first, then `SET ROLE ext_X; DROP OWNED BY ext_X; RESET ROLE; DROP ROLE ext_X`.
  `DROP OWNED` alone does NOT revoke grants made by other owners (warning "no privileges could be revoked"), and the role then cannot be dropped.
- Roles are cluster-wide: leftovers from other databases block DROP ROLE ("N objects in database y"); use one role namespace per database (prefix with the db name) in tests.

## Risks
- Needs CREATEROLE for the admin user. Managed Postgres without it (some clouds only allow it via a special role): fall back to schema-qualified grants
  with one login per extension created out of band, or refuse `db_read` at boot with a clear error.
- Free SQL can still `SET search_path`, `pg_sleep`, hog connections: set `statement_timeout` and `idle_in_transaction_session_timeout` as ALTER ROLE ext_X SET ... .
- Each extension pool now needs its own credentials: migration for existing deployments (existing schemas owned by the admin: ALTER SCHEMA/TABLE OWNER TO ext_X must run
  tables-first, then the schema, as a role that can SET ext_X).
- Test isolation: TestDB throwaway databases need role names prefixed per database, since roles are global.
