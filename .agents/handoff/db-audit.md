# Database connection and std-table audit (replaces T9)

Decision (user): std extensions stay LOW-LEVEL (hand-written SQL, no ORM) for performance and control; review the connection path and
make their tables optimized and SQL-compliant instead.

## Connection path: measured on a throwaway Postgres 16 (ops/s)
| case | before | after |
|---|---|---|
| SELECT 1, 1 caller | 8,900 | 9,200 |
| SELECT 1, 16 callers, one extension | 9,500 | 17,500 |
| SELECT 1, 16 callers, four extensions | 9,600 | 29,500 |
| 10 ms query, 16 callers | 82 (fully serial) | 168 (capped by the 2-connection pool) |
| key-value put (document table) | 390 | 3,650 |
| key-value get | 441 | 7,639 |

Findings and state:
1. FIXED: every query of every extension ran inside ONE GenServer (`Lldb.Manager`). A slow query anywhere queued all other extensions
   (auth included), and the 5 s call timeout coupled them. Now only provisioning goes through it; queries run in the caller.
2. FIXED: a document `put` paid `CREATE TABLE IF NOT EXISTS` + a transaction + the upsert (4 round trips); typed tables paid 2 catalog queries
   per call. The database layer now remembers table kinds for 5 s (`KindCache`), forgets them on DDL, and writes a known table in one statement.
3. OPEN, decide: default pool size is 2 per extension. One extension can run only two queries at once (the 168 above). The role connection limit
   is pool+2, and with ~16 extensions a default of 5 is ~80 connections against Postgres' default `max_connections` of 100. Options: raise the default
   to 4, make it per-extension (manifest/config), or both. Needs your call on the connection budget.
4. OPEN: without a pool supervisor (tests only) each call opens its own connection; in production the extension always starts the pools.
   Make the unmanaged fallback an error instead of silently slow?
5. OPEN: two ActionDispatcher hops per query (database -> lldb) plus introspection on a cache miss. Not measured separately; the 9k ops/s
   single-caller figure bounds it. Worth a direct in-VM path for std extensions only if profiling shows it matters.

## Std tables: what is not SQL-compliant or not optimized
| extension | table | problems |
|---|---|---|
| auth | tokens, players, accounts | no primary key, every column nullable text; lookups by token id / email / player id have no index (every authenticated request scans `tokens`); no UNIQUE on email; `scopes` is a text blob; DDL and ensure_column also run from request paths |
| player_data | players, player_kv | no primary key; `(player_id, key)` index is not unique (duplicate keys possible); profile/state JSON kept in `text` |
| metering | usage_actions, usage_plugins | no key; `integer` (32-bit) for epoch seconds (2038), `wall_us` (overflows at ~35 min of microseconds), `bytes_in/out`, `uptime_ms` |
| observability | events, rollups, archive | `day text` instead of `date`; `payload`/`context` JSON in `text`; `time text` AND `timestamp bigint` AND `at bigint` for the same instant; `bytes integer` overflows at 2 GB |
| file_bucket | visibility | fine (primary key present) |
| http | cors settings | fine (primary key present) |

Proposed fix, one extension at a time, each with a test and an upgrade from the legacy table (a missing primary key is an unsafe change under `refuse`;
under the "existing data is resettable" decision a reset is acceptable until the format settles):
1. auth: PK on tokens(token_id) and accounts(id)/players(id), UNIQUE accounts(email), indexes on the lookup columns, NOT NULL where true, bigint timestamps; stop running DDL on request paths.
2. player_data: PK players(player_id), PK player_kv(player_id, key), jsonb for profile/state.
3. metering: bigint everywhere that counts or timestamps; composite PK per period.
4. observability: date/timestamptz/jsonb, one instant column, bigint sizes.
