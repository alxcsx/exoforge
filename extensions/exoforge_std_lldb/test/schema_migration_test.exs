defmodule Exoforge.Std.Lldb.SchemaMigrationTest do
  @moduledoc """
  A change that is not safe on its own is applied as plain ALTERs when the resource's version was raised and a
  migration leads to it; otherwise it is refused and the table is left alone (T6).
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


  defp col(name, storage, opts \\ []) do
    Map.merge(
      %{name: name, storage: storage, nullable: true, primary_key: false, unique: false, indexed: false, default: nil, choices: nil},
      Map.new(opts)
    )
  end

  defp resource(version, columns, hash) do
    %{name: "items", source: %{table: "items"}, version: version, schema_hash: hash, columns: [col("id", "text", nullable: false, primary_key: true) | columns]}
  end

  defp migration(from, ops), do: %{resource: "items", from: from, to: from + 1, ops: ops}

  defp reconcile(conn, schema, resource, migrations \\ []), do: Schema.reconcile(conn, schema, [resource], migrations)

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
    assert {:ok, _} = reconcile(conn, schema, resource(1, [col("nm", "text"), col("qty", "text")], "h1"))
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, nm, qty) VALUES ('a', 'sword', '5'), ('b', 'shield', '7')|, [])
  end

  test "a rename with a migration keeps the data and records the new version", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    assert ledger_version(conn, schema) == 1

    v2 = resource(2, [col("name", "text"), col("qty", "text")], "h2")

    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v2, [migration(1, [%{op: "rename", from: "nm", to: "name"}])])

    assert [%{"id" => "a", "name" => "sword", "qty" => "5"}, %{"id" => "b", "name" => "shield"}] = rows(conn, schema)
    assert ledger_version(conn, schema) == 2

    # and now it is simply at its version: nothing more to do
    assert {:ok, %{applied: 0}} = reconcile(conn, schema, v2, [migration(1, [%{op: "rename", from: "nm", to: "name"}])])
  end

  test "string keys work as well as atom keys, as a manifest read from JSON has them", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("name", "text"), col("qty", "text")], "h2")

    json_migration = %{"resource" => "items", "from" => 1, "to" => 2, "ops" => [%{"op" => "rename", "from" => "nm", "to" => "name"}]}
    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v2, [json_migration])
  end

  test "an unsafe change with no migration is refused and nothing changes", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("name", "text"), col("qty", "text")], "h2")

    assert {:error, {:migration_missing, %{table: "items", resource: "items", from: 1, to: 2, live: 1, manifest: 2, changes: changes}}} =
             reconcile(conn, schema, v2)

    assert Enum.any?(changes, &(&1.column == "nm"))
    assert [%{"nm" => "sword"} | _] = rows(conn, schema)
    assert ledger_version(conn, schema) == 1
  end

  test "an unsafe change without raising the version is refused, naming the versions", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    same_version = resource(1, [col("nm", "text"), col("qty", "integer")], "h1b")

    assert {:error, {:unsafe_schema_change, ops}} = reconcile(conn, schema, same_version)
    assert [%{column: "qty", live_version: 1, manifest_version: 1} | _] = ops
    assert column_type(conn, schema, "qty") == "text"
  end

  test "convert changes a column's type in place, USING the cast, and keeps the values", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("nm", "text"), col("qty", "int32")], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2, [migration(1, [%{op: "convert", column: "qty", to: "int32"}])])

    assert column_type(conn, schema, "qty") == "integer"
    assert [%{"qty" => 5}, %{"qty" => 7}] = rows(conn, schema)
  end

  test "a conversion the data cannot take rolls the whole migration back", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, nm, qty) VALUES ('c', 'bow', 'many')|, [])
    v2 = resource(2, [col("name", "text"), col("qty", "int32")], "h2")

    ops = [%{op: "rename", from: "nm", to: "name"}, %{op: "convert", column: "qty", to: "int32"}]
    assert {:error, %Postgrex.Error{}} = reconcile(conn, schema, v2, [migration(1, ops)])

    # the rename that ran before the failing step is undone too
    assert column_type(conn, schema, "nm") == "text"
    assert column_type(conn, schema, "name") == nil
    assert column_type(conn, schema, "qty") == "text"
    assert ledger_version(conn, schema) == 1
  end

  test "fill adds a required column that existing rows get a value for", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("nm", "text"), col("qty", "text"), col("rarity", "text", nullable: false)], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2, [migration(1, [%{op: "fill", column: "rarity", value: "common"}])])

    assert [%{"rarity" => "common"}, %{"rarity" => "common"}] = rows(conn, schema)

    # the manifest declares no default, so new rows must say what they are
    assert {:error, %Postgrex.Error{}} = Postgrex.query(conn, ~s|INSERT INTO "#{schema}".items (id, nm, qty) VALUES ('z', 'x', '1')|, [])
  end

  test "drop removes a column and set_not_null fills the gaps first", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    Postgrex.query!(conn, ~s|INSERT INTO "#{schema}".items (id, nm) VALUES ('c', 'bow')|, [])

    v2 = resource(2, [col("nm", "text", nullable: false)], "h2")
    ops = [%{op: "drop", column: "qty"}, %{op: "set_not_null", column: "nm", value: "unnamed"}]

    assert {:ok, _} = reconcile(conn, schema, v2, [migration(1, ops)])
    assert column_type(conn, schema, "qty") == nil
    assert [%{"nm" => "sword"}, %{"nm" => "shield"}, %{"nm" => "bow"}] = rows(conn, schema)
  end

  test "a chain across several versions runs in order in one go", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v3 = resource(3, [col("name", "text"), col("quantity", "int32")], "h3")

    chain = [
      migration(1, [%{op: "rename", from: "nm", to: "name"}]),
      migration(2, [%{op: "rename", from: "qty", to: "quantity"}, %{op: "convert", column: "quantity", to: "int32"}])
    ]

    assert {:ok, %{migrated: ["items"]}} = reconcile(conn, schema, v3, chain)
    assert [%{"name" => "sword", "quantity" => 5} | _] = rows(conn, schema)
    assert ledger_version(conn, schema) == 3
  end

  test "a gap in the chain names the step that is missing", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v3 = resource(3, [col("name", "text"), col("quantity", "int32")], "h3")

    assert {:error, {:migration_missing, %{from: 2, to: 3}}} =
             reconcile(conn, schema, v3, [migration(1, [%{op: "rename", from: "nm", to: "name"}])])

    assert ledger_version(conn, schema) == 1
  end

  test "a migration that does not lead to the declared shape is rolled back", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    # the manifest also changes qty to an integer; the migration only renames
    v2 = resource(2, [col("name", "text"), col("qty", "int32")], "h2")

    assert {:error, {:migration_incomplete, %{table: "items", remaining: remaining}}} =
             reconcile(conn, schema, v2, [migration(1, [%{op: "rename", from: "nm", to: "name"}])])

    assert Enum.any?(remaining, &(&1.column == "qty"))
    assert column_type(conn, schema, "nm") == "text"
    assert ledger_version(conn, schema) == 1
  end

  test "a table newer than the manifest is refused", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("name", "text"), col("qty", "text")], "h2")
    assert {:ok, _} = reconcile(conn, schema, v2, [migration(1, [%{op: "rename", from: "nm", to: "name"}])])

    older = resource(1, [col("nm", "text"), col("qty", "text")], "h1")
    assert {:error, {:version_downgrade, %{live: 2, manifest: 1, table: "items"}}} = reconcile(conn, schema, older)
    assert column_type(conn, schema, "name") == "text"
  end

  test "raising the version over a change that is safe needs no migration", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("nm", "text"), col("qty", "text"), col("extra", "text")], "h2")

    assert {:ok, _} = reconcile(conn, schema, v2)
    assert column_type(conn, schema, "extra") == "text"
    assert ledger_version(conn, schema) == 2
  end

  test "a version bump over an identical table is recorded", %{conn: conn, schema: schema} do
    seed_v1(conn, schema)
    same_shape_v2 = resource(2, [col("nm", "text"), col("qty", "text")], "h1")

    assert {:ok, _} = reconcile(conn, schema, same_shape_v2)
    assert ledger_version(conn, schema) == 2
  end

  test "an ALTER that cannot get its lock fails the deploy instead of waiting behind the other queries", %{conn: conn, schema: schema, cfg: cfg} do
    seed_v1(conn, schema)
    v2 = resource(2, [col("name", "text"), col("qty", "text")], "h2")
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

    {microseconds, result} =
      :timer.tc(fn -> reconcile(conn, schema, v2, [migration(1, [%{op: "rename", from: "nm", to: "name"}])]) end)

    assert {:error, {:lock_timeout, %{timeout: "200ms"}}} = result
    assert microseconds < 1_500_000, "waited #{div(microseconds, 1000)} ms for a lock it should have given up on"

    assert {:ok, _} = Task.await(holder, 5_000)
    assert column_type(conn, schema, "nm") == "text"
  end
end
