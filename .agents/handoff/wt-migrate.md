# wt/migrate: resource names that differ only by case, and a migrate scoped to one extension
(worktree /Users/alexcs/projects/exoforge-wt/migrate). Read wt-common.md first.
Bug (user, Postgres): redeploying `loja_itens` failed `{:migration_failed, {:postgres_error, "column \"id\" specified
more than once"}}`. Root cause: its manifest came from a generator before ca3d00a, which emitted
`[ExoResource("itens", PrimaryKey = nameof(Id))]` as "primary_key": "Id" while the column is "id".
resources.ex column_defs (~L162) drops the pk column with a CASE-SENSITIVE compare, so it writes
`Id text PRIMARY KEY, id text, ...`; SQL folds names, Postgres and SQLite both refuse it. Also: migrate runs over
EVERY resource in the cluster (extension_manager.ex ~L566 passes %{}), so any broken resource elsewhere blocks an
unrelated push and unregisters it; the error names no table.
Want:
1. Server (extensions/exoforge_std_resources): normalize resource primary_key and column names to lowercase before
   building SQL (column_defs, reconcile_columns/existing_columns, repair_primary_key, default/choices clauses), so an
   already-built manifest like loja_itens' deploys unchanged. Before any DDL, refuse two columns equal ignoring case
   (and a primary_key naming no column, other than the implicit id) with
   {:invalid_resource, %{extension, table, column, reason}}.
2. extension_manager: migrate only the pushed extension's resources (plugin_id/target); a migration error names
   extension and table; a failed migration of a REdeploy must leave the previously running version registered.
3. Generator (sdk/csharp/Exoforge.Plugin.Generator): build-time diagnostic (next free EXO id, Error) when two
   properties of a resource map to the same column name ignoring case, or PrimaryKey names no column, or a column name
   (explicit [ExoColumn("...")]/Name) is not a valid lowercase snake identifier - with the property names in the
   message. Lowercase explicit names. ToSnakeCase treats runs of capitals as one word (ID -> id, HTTPCode ->
   http_code, PlayerID -> player_id); list in the commit message which existing names change because of it.
Tests: resources_test with the exact loja_itens manifest shape ("primary_key": "Id", column "id") migrates and a
redeploy succeeds; duplicate-ignoring-case refused with the named error; extension_manager test that a broken
resource in extension A does not block pushing B; Generator.Tests for each diagnostic and the ToSnakeCase cases.
The user's original source (must build clean, no diagnostic): .agents/handoff/loja_itens.cs
