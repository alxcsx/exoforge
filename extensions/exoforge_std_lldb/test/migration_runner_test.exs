defmodule Exoforge.Std.Lldb.MigrationRunnerTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Adapters.Postgres
  alias Exoforge.Std.Lldb.MigrationRunner
  alias Exoforge.Std.Lldb.TestDB

  setup do
    cfg = TestDB.config()
    plugin = :"s5a_#{System.unique_integer([:positive])}"
    assert {:ok, _} = Postgres.ensure_database(plugin, cfg)
    schema = "plugin_#{Lldb.clean_id(plugin)}"

    conn =
      start_supervised!(
        {Postgrex,
         hostname: cfg.host,
         port: cfg.port,
         username: cfg.username,
         password: cfg.password,
         database: cfg.database,
         parameters: [search_path: ~s("#{schema}", public)]},
        id: :migration_runner_conn
      )

    on_exit(fn -> Postgres.reset(plugin, cfg) end)
    {:ok, conn: conn, schema: schema}
  end

  test "ledger skips applied versions", %{conn: conn, schema: schema} do
    migrations = [%{version: 1, name: "create counters", sql: ["CREATE TABLE counters (value integer)", "INSERT INTO counters VALUES (1)"]}]

    assert {:ok, %{applied: [1], skipped: []}} = MigrationRunner.run(conn, schema, migrations)
    assert {:ok, %{applied: [], skipped: [1]}} = MigrationRunner.run(conn, schema, migrations)
    assert %Postgrex.Result{rows: [[1]]} = Postgrex.query!(conn, "SELECT count(*) FROM counters", [])
  end

  test "a failing migration rolls back and stops", %{conn: conn, schema: schema} do
    migrations = [
      %{version: 1, name: "broken", sql: ["CREATE TABLE rolled_back (value integer)", "SELECT missing FROM no_such_table"]},
      %{version: 2, name: "later", sql: ["CREATE TABLE never_runs (value integer)"]}
    ]

    assert {:error, {:migration_failed, %{version: 1, name: "broken", reason: %Postgrex.Error{}}}} =
             MigrationRunner.run(conn, schema, migrations)

    for table <- ["rolled_back", "never_runs"] do
      assert %Postgrex.Result{rows: [[nil]]} =
               Postgrex.query!(conn, "SELECT to_regclass($1)", ["#{schema}.#{table}"])
    end

    assert %Postgrex.Result{rows: [[0]]} =
             Postgrex.query!(conn, ~s|SELECT count(*) FROM "#{schema}"."_exo_migrations"|, [])
  end

  test "migrations run by ascending version", %{conn: conn, schema: schema} do
    migrations = [
      %{version: 2, name: "insert", sql: ["INSERT INTO ordered VALUES (2)"]},
      %{version: 1, name: "create", sql: ["CREATE TABLE ordered (value integer)"]}
    ]

    assert {:ok, %{applied: [1, 2]}} = MigrationRunner.run(conn, schema, migrations)
    assert %Postgrex.Result{rows: [[2]]} = Postgrex.query!(conn, "SELECT value FROM ordered", [])
  end
end
