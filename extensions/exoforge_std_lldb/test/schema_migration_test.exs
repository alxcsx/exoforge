defmodule Exoforge.Std.Lldb.SchemaMigrationTest do
  @moduledoc """
  A change that is not safe on its own is applied as plain ALTERs when a migration leads to the extension version being
  deployed; otherwise it is refused and the table is left alone. Versions are stamps (`Exoforge.VersionStamp`):
  1.0.0 is 1_000_000, 1.1.0 is 1_001_000, 1.2.0 is 1_002_000.
  """
  use ExUnit.Case, async: false

  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Adapters.Postgres
  alias Exoforge.Std.Lldb.Manager
  alias Exoforge.Std.Lldb.Schema
  alias Exoforge.Std.Lldb.TestDB

  defp pg_config, do: TestDB.config()

  setup do
    unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
      start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
    end

    unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
      start_supervised!(
        {DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one}
      )
    end

    unless Process.whereis(Exoforge.ExtensionRegistry) do
      start_supervised!(Exoforge.ExtensionRegistry)
    end

    Exoforge.ExtensionRegistry.initialize_ets()

    cfg = pg_config()

    unless Process.whereis(Manager) do
      start_supervised!({Manager, [driver: :postgres] ++ Map.to_list(cfg)})
    end

    plugin = :"t2_schema_#{System.unique_integer([:positive])}"
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
        id: :test_conn
      )

    on_exit(fn ->
      _ = Postgres.reset(plugin, cfg)
    end)

    {:ok, plugin: plugin, schema: schema, conn: conn, cfg: cfg}
  end


  @v100 1_000_000
  @v110 1_001_000
  @v120 1_002_000

  defp col(name, storage, opts \\ []) do
    Map.merge(
      %{name: name, storage: storage, nullable: true, primary_key: false, unique: false, indexed: false, default: nil, choices: nil},
      Map.new(opts)
    )
  end

  defp resource(columns, hash) do
    %{name: "items", source: %{table: "items"}, schema_hash: hash, columns: [col("id", "text", nullable: false, primary_key: true) | columns]}
  end

  defp migration(to, ops), do: %{resource: "items", to: to, ops: ops}

  defp reconcile(conn, schema, resource, migrations, version), do: Schema.reconcile(conn, schema, [resource], migrations, version)

  defp rows(conn, schema) do
    %Postgrex.Result{columns: columns, rows: rows} = Postgrex.query!(conn, ~s|SELECT * FROM "#{schema}".items ORDER BY id|, [])
    Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)
  end

  defp ledger_version(conn, schema) do
    %Postgrex.Result{rows: [[version]]} =
      Postgrex.query!(conn, ~s|SELECT "version" FROM "#{schema}"."_exo_schema" WHERE table_name = 'items' ORDER BY applied_at DESC LIMIT 1|, [])

    version
  end

  defp column_type(conn, schema, column) do
    %Postgrex.Result{rows: rows} =
      Postgrex.query!(conn, "SELECT data_type FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'items' AND column_name = $2", [schema, column])

    case rows do
      [[type]] -> type
      [] -> nil
    end
  end

  defp seed_v1(conn, schema) do
    assert {:ok, _} = reconcile(conn, schema, resource([col("nm", "text"), col("qty", "text")], "h1"), [], @v100)
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, nm, qty) VALUES ('a', 'sword', '5'), ('b', 'shield', '7')|, [])
  end

  defp v2_renamed, do: resource([col("name", "text"), col("qty", "text")], "h2")
  defp rename_nm, do: migration("1.1.0", [%{op: "rename", from: "nm", to: "name"}])

  test "a new table carries the row stamp, at 0 until something writes it", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    assert column_type(conn, schema, "_v") == "bigint"
    assert [%{"_v" => 0}, %{"_v" => 0}] = rows(conn, schema)
    assert ledger_version(conn, schema) == @v100
  end

  test "a rename with a migration keeps the data and records the extension version", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)

    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v2_renamed(), [rename_nm()], @v110)

    assert [%{"id" => "a", "name" => "sword", "qty" => "5"}, %{"id" => "b", "name" => "shield"}] = rows(conn, schema)
    assert ledger_version(conn, schema) == @v110

    # and now it is simply at its version: nothing more to do
    assert {:ok, %{applied: 0}} = reconcile(conn, schema, v2_renamed(), [rename_nm()], @v110)
  end

  test "string keys work as well as atom keys, as a manifest read from JSON has them", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)

    json_migration = %{"resource" => "items", "to" => "1.1.0", "ops" => [%{"op" => "rename", "from" => "nm", "to" => "name"}]}
    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v2_renamed(), [json_migration], @v110)
  end

  test "an unsafe change with no migration is refused and nothing changes", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)

    # a required column existing rows cannot fill: not safe on its own
    required_name = resource([col("name", "text", nullable: false), col("qty", "text")], "h2")

    assert {:error, {:migration_missing, %{table: "items", resource: "items", live: @v100, manifest: @v110, changes: changes}}} =
             reconcile(conn, schema, required_name, [], @v110)

    assert Enum.any?(changes, &(&1.column == "name"))
    assert [%{"nm" => "sword"} | _] = rows(conn, schema)
    assert ledger_version(conn, schema) == @v100
  end

  test "an unsafe change without a new extension version is refused, naming the versions", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    same_version = resource([col("nm", "text"), col("qty", "integer")], "h1b")

    assert {:error, {:unsafe_schema_change, ops}} = reconcile(conn, schema, same_version, [], @v100)
    assert [%{column: "qty", live_version: @v100, manifest_version: @v100} | _] = ops
    assert column_type(conn, schema, "qty") == "text"
  end

  test "a renamed column with no migration is just a new column beside the retired one: nothing is lost", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)

    assert {:ok, _} = reconcile(conn, schema, v2_renamed(), [], @v110)
    assert [%{"nm" => "sword", "name" => nil} | _] = rows(conn, schema)
  end

  test "a migration is not needed for a column that is no longer declared: it is retired, not dropped", %{conn: conn, schema: schema} do
    assert {:ok, _} = reconcile(conn, schema, resource([col("nm", "text", nullable: false)], "h1"), [], @v100)
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, nm) VALUES ('a', 'sword')|, [])

    # the next version no longer declares nm
    assert {:ok, _} = reconcile(conn, schema, resource([], "h2"), [], @v110)

    # old rows keep their data, and a new row can be written without the retired column
    assert [%{"nm" => "sword"}] = rows(conn, schema)
    assert {:ok, _} = Postgrex.query(conn, ~s|INSERT INTO "#{schema}".items (id) VALUES ('b')|, [])
  end

  test "convert changes a column's type in place, USING the cast, and keeps the values", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource([col("nm", "text"), col("qty", "int32")], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2, [migration("1.1.0", [%{op: "convert", column: "qty", to: "int32"}])], @v110)

    assert column_type(conn, schema, "qty") == "integer"
    assert [%{"qty" => 5}, %{"qty" => 7}] = rows(conn, schema)
  end

  test "a conversion the data cannot take rolls the whole migration back", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, nm, qty) VALUES ('c', 'bow', 'many')|, [])
    v2 = resource([col("name", "text"), col("qty", "int32")], "h2")

    ops = [%{op: "rename", from: "nm", to: "name"}, %{op: "convert", column: "qty", to: "int32"}]
    assert {:error, %Postgrex.Error{}} = reconcile(conn, schema, v2, [migration("1.1.0", ops)], @v110)

    # the rename that ran before the failing step is undone too
    assert column_type(conn, schema, "nm") == "text"
    assert column_type(conn, schema, "name") == nil
    assert column_type(conn, schema, "qty") == "text"
    assert ledger_version(conn, schema) == @v100
  end

  test "fill adds a required column that existing rows get a value for", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource([col("nm", "text"), col("qty", "text"), col("rarity", "text", nullable: false)], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2, [migration("1.1.0", [%{op: "fill", column: "rarity", value: "common"}])], @v110)

    assert [%{"rarity" => "common"}, %{"rarity" => "common"}] = rows(conn, schema)

    # the manifest declares no default, so new rows must say what they are
    assert {:error, %Postgrex.Error{}} = Postgrex.query(conn, ~s|INSERT INTO "#{schema}".items (id, nm, qty) VALUES ('z', 'x', '1')|, [])
  end

  test "set_not_null fills the gaps first", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, qty) VALUES ('c', '1')|, [])
    v2 = resource([col("nm", "text", nullable: false), col("qty", "text")], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2, [migration("1.1.0", [%{op: "set_not_null", column: "nm", value: "unnamed"}])], @v110)
    assert [%{"nm" => "sword"}, %{"nm" => "shield"}, %{"nm" => "unnamed"}] = rows(conn, schema)
  end

  test "drop is refused while a row is still stamped below the migration's version", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource([col("nm", "text")], "h2")
    drop_qty = migration("1.1.0", [%{op: "drop", column: "qty"}])

    # both rows have _v 0: nobody has brought them up to 1.1.0
    assert {:error, {:rows_below_version, %{table: "items", rows: 2, to: "1.1.0"}}} = reconcile(conn, schema, v2, [drop_qty], @v110)
    assert column_type(conn, schema, "qty") == "text"
    assert ledger_version(conn, schema) == @v100

    # once they are current, the column can go
    Postgrex.query!(conn, ~s|UPDATE "#{schema}".items SET _v = #{@v110}|, [])
    assert {:ok, _} = reconcile(conn, schema, v2, [drop_qty], @v110)
    assert column_type(conn, schema, "qty") == nil
    assert [%{"nm" => "sword"}, %{"nm" => "shield"}] = rows(conn, schema)
  end

  test "several migrations to versions up to the deploy run in order in one go", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v3 = resource([col("name", "text"), col("quantity", "int32")], "h3")

    chain = [
      migration("1.2.0", [%{op: "rename", from: "qty", to: "quantity"}, %{op: "convert", column: "quantity", to: "int32"}]),
      rename_nm()
    ]

    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v3, chain, @v120)
    assert [%{"name" => "sword", "quantity" => 5} | _] = rows(conn, schema)
    assert ledger_version(conn, schema) == @v120
  end

  test "a migration to a version past the deploy's is left for the deploy that gets there", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    later = migration("1.2.0", [%{op: "rename", from: "qty", to: "quantity"}])

    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v2_renamed(), [rename_nm(), later], @v110)
    assert column_type(conn, schema, "qty") == "text"
    assert column_type(conn, schema, "quantity") == nil
    assert ledger_version(conn, schema) == @v110
  end

  test "a migration that does not lead to the declared shape is rolled back", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    # the manifest also changes qty to an integer; the migration only renames
    v2 = resource([col("name", "text"), col("qty", "int32")], "h2")

    assert {:error, {:migration_incomplete, %{table: "items", remaining: remaining}}} = reconcile(conn, schema, v2, [rename_nm()], @v110)

    assert Enum.any?(remaining, &(&1.column == "qty"))
    assert column_type(conn, schema, "nm") == "text"
    assert ledger_version(conn, schema) == @v100
  end

  test "a table newer than the deploy is refused", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    assert {:ok, _} = reconcile(conn, schema, v2_renamed(), [rename_nm()], @v110)

    older = resource([col("nm", "text"), col("qty", "text")], "h1")
    assert {:error, {:version_downgrade, %{live: @v110, manifest: @v100, table: "items"}}} = reconcile(conn, schema, older, [], @v100)
    assert column_type(conn, schema, "name") == "text"
  end

  test "a new extension version over a change that is safe needs no migration", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource([col("nm", "text"), col("qty", "text"), col("extra", "text")], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2, [], @v110)
    assert column_type(conn, schema, "extra") == "text"
    assert ledger_version(conn, schema) == @v110
  end

  test "a new extension version over an identical table is recorded", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    same_shape = resource([col("nm", "text"), col("qty", "text")], "h1")

    assert {:ok, _} = reconcile(conn, schema, same_shape, [], @v110)
    assert ledger_version(conn, schema) == @v110
  end

  test "history is not replayed over a table the ledger never knew", %{conn: conn, schema: schema} do
    # a table that exists but was never reconciled (no ledger row) is not at "version 0 of a migration history"
    Postgrex.query!(conn, ~s|CREATE TABLE "#{schema}".items (id text PRIMARY KEY, name text, qty text)|, [])
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, name) VALUES ('a', 'sword')|, [])

    assert {:ok, _} = reconcile(conn, schema, v2_renamed(), [rename_nm()], @v110)
    assert [%{"name" => "sword"}] = rows(conn, schema)
  end

  test "an ALTER that cannot get its lock fails the deploy instead of waiting behind the other queries", %{conn: conn, schema: schema, cfg: cfg} do
    seed_v1(conn, schema)
    Application.put_env(:exoforge_std_lldb, :schema_lock_timeout, "200ms")
    on_exit(fn -> Application.delete_env(:exoforge_std_lldb, :schema_lock_timeout) end)

    holder =
      Task.async(fn ->
        {:ok, other} =
          Postgrex.start_link(hostname: cfg.host, port: cfg.port, username: cfg.username, password: cfg.password, database: cfg.database)

        Postgrex.transaction(other, fn tx ->
          Postgrex.query!(tx, ~s|LOCK TABLE "#{schema}".items IN ACCESS EXCLUSIVE MODE|, [])
          Process.sleep(2_000)
        end)
      end)

    Process.sleep(300)

    {microseconds, result} = :timer.tc(fn -> reconcile(conn, schema, v2_renamed(), [rename_nm()], @v110) end)

    assert {:error, {:lock_timeout, %{timeout: "200ms"}}} = result
    assert microseconds < 1_500_000, "waited #{div(microseconds, 1000)} ms for a lock it should have given up on"

    assert {:ok, _} = Task.await(holder, 5_000)
    assert column_type(conn, schema, "nm") == "text"
  end
end
