# T9 as planned does not exist; what is really there

Plan said: "convert the std Elixir extensions' declared resources to typed resources". Checked on 2026-11-19:

- No std extension declares resources with the Elixir DSL (`resource :x do` appears only in resources.ex's moduledoc and in tests).
- Seven extensions hand-write their own tables and their own "add the missing column" migrations:
  auth (tokens, players, accounts), player_data (players, player_kv), file_bucket (visibility), observability (events store, rollups, archive),
  metering (usage_actions, usage_plugins), http (cors settings), plus resources.ex's own DSL-column table maker.
- Their tables mostly have NO primary key and every column is nullable text (`id text, player_id text, scopes text`), use composite indexes
  (`ON player_kv (player_id, key)`), a bigint timestamp, and per-extension ensure_column code. Their data-access code relies on that shape.

So converting them is a storage redesign of seven extensions: choose keys and types, rewrite the queries that assume no key,
give each a legacy-table upgrade story (a missing primary key is an unsafe change under `refuse`), and extend the reconciler with
composite keys, composite indexes and default expressions. It changes nothing a game developer or player sees.

## Recommendation
Do not parallelise it now. If wanted later, in this order: (1) reconciler support for composite PK/index and default expressions,
(2) a shared helper so an extension declares its tables in one place and calls `lldb.apply_schema` at init (mode handling lives in
resources.ex today: move it to core), (3) pilot on http/cors (it already has `key text PRIMARY KEY`), (4) then one extension per worker,
each with an "upgrade from the legacy table" test. Each is independent after (1)-(3), so that part parallelises well.
