defmodule Exoforge.Std.Database.Adapters.PostgresTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database
  alias Exoforge.Std.Database.Adapters.Postgres
  alias Exoforge.Std.Database.Manager
  alias Exoforge.Std.Database.TestDB

  defp pg_config, do: TestDB.config()

  describe "F31: default pool_size" do
    test "defaults to a small pool_size (2) and remains overridable via config" do
      {:ok, default_cfg} = Postgres.connection_config(:wallet, %{})
      assert default_cfg.pool_size == 2

      {:ok, custom_cfg} = Postgres.connection_config(:wallet, %{pool_size: 6})
      assert custom_cfg.pool_size == 6
    end
  end

  describe "F32: KV operations on resource-migrated tables" do
    @tag :postgres
    test "put, get, all, and delete work on a schema-migrated table without a data column" do
      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_res_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())

      on_exit(fn ->
        _ = Postgres.reset(plugin, pg_config())
      end)

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE wallet_balances (player_id text PRIMARY KEY, coins integer NOT NULL)",
                 [],
                 pg_config()
               )

      assert {:ok, %{num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "wallet_balances", id: "p1", data: %{"coins" => 50}},
                 [],
                 pg_config()
               )

      assert {:ok, %{rows: [%{"player_id" => "p1", "coins" => 50}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 [],
                 pg_config()
               )

      assert {:ok, %{rows: [%{"player_id" => "p1", "coins" => 50}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :all, table: "wallet_balances"},
                 [],
                 pg_config()
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :delete, table: "wallet_balances", id: "p1"},
                 [],
                 pg_config()
               )

      assert {:ok, %{rows: [], num_rows: 0}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 [],
                 pg_config()
               )
    end

    @tag :postgres
    test "a legacy document table accepts typed-column rows once its data column is relaxed" do
      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_legacy_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())
      on_exit(fn -> _ = Postgres.reset(plugin, pg_config()) end)

      # The document table the KV path creates on first write, then a resource that gains typed columns.
      assert {:ok, _} = Postgres.execute(plugin, %{action: :put, table: "itens", id: "old", data: %{"x" => 1}}, [], pg_config())
      assert {:ok, _} = Postgres.execute(plugin, "ALTER TABLE itens ADD COLUMN preco integer, ADD COLUMN tags text", [], pg_config())

      assert {:error, _} = Postgres.execute(plugin, "INSERT INTO itens (id, preco) VALUES ($1, $2)", ["new", 5], pg_config())

      assert {:ok, _} = Postgres.execute(plugin, "ALTER TABLE itens ALTER COLUMN data DROP NOT NULL", [], pg_config())
      assert {:ok, _} = Postgres.execute(plugin, "INSERT INTO itens (id, preco, tags) VALUES ($1, $2, $3)", ["new", 5, ~s(["a","b"])], pg_config())

      assert {:ok, %{rows: [%{"id" => "new", "preco" => 5, "tags" => ~s(["a","b"])}]}} =
               Postgres.execute(plugin, "SELECT id, preco, tags FROM itens WHERE id = $1", ["new"], pg_config())
    end

    @tag :postgres
    test "undeclared KV tables still use (id, data, updated_at)" do
      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_doc_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())

      on_exit(fn ->
        _ = Postgres.reset(plugin, pg_config())
      end)

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "sessions", id: "s1", data: %{"token" => "abc"}},
                 [],
                 pg_config()
               )

      assert {:ok, %{rows: [%{"id" => "s1", "token" => "abc"}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "sessions", id: "s1"},
                 [],
                 pg_config()
               )
    end
  end

  describe "F34 & F35: coercion by declared Postgres column type" do
    setup do
      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_coerce_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())

      on_exit(fn ->
        _ = Postgres.reset(plugin, pg_config())
      end)

      {:ok, plugin: plugin}
    end

    @tag :postgres
    test "F34: string id and string integer values coerce for integer PK and columns", %{plugin: plugin} do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE daily_reward_table (day integer PRIMARY KEY, coins integer NOT NULL, label text)",
                 [],
                 pg_config()
               )

      assert {:ok, %{num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "daily_reward_table", id: "1", data: %{"coins" => "100", "label" => "Day 1"}},
                 [],
                 pg_config()
               )

      assert {:ok, %{rows: [%{"day" => 1, "coins" => 100, "label" => "Day 1"}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "daily_reward_table", id: "1"},
                 [],
                 pg_config()
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :delete, table: "daily_reward_table", id: "1"},
                 [],
                 pg_config()
               )
    end

    @tag :postgres
    test "F35: ISO-8601 timestamp strings coerce on put and round-trip as ISO-8601 strings", %{plugin: plugin} do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE wallet_balances (player_id text PRIMARY KEY, coins integer NOT NULL, active boolean NOT NULL, updated_at timestamp without time zone NOT NULL)",
                 [],
                 pg_config()
               )

      assert {:ok, %{num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{
                   action: :put,
                   table: "wallet_balances",
                   id: "p1",
                   data: %{
                     "coins" => 50,
                     "active" => "true",
                     "updated_at" => "2026-11-18T14:40:28.756442Z"
                   }
                 },
                 [],
                 pg_config()
               )

      assert {:ok, %{rows: [row], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 [],
                 pg_config()
               )

      assert row["player_id"] == "p1"
      assert row["coins"] == 50
      assert row["active"] == true
      assert is_binary(row["updated_at"])
      assert String.starts_with?(row["updated_at"], "2026-11-18T14:40:28")
    end

    @tag :postgres
    test "uncoercible value returns {:error, {:invalid_value, column, type}}", %{plugin: plugin} do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE typed_items (id integer PRIMARY KEY, coins integer NOT NULL)",
                 [],
                 pg_config()
               )

      assert {:error, {:invalid_value, "coins", "integer"}} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "typed_items", id: "1", data: %{"coins" => "not_an_int"}},
                 [],
                 pg_config()
               )
    end
  end

  describe "cross-extension tables" do
    @tag :postgres
    test "a missing relation explains that tables are private to each extension" do
      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_missing_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())
      on_exit(fn -> _ = Postgres.reset(plugin, pg_config()) end)

      assert {:error, {:postgres_error, message}} =
               Postgres.execute(plugin, "SELECT * FROM other_extension_table", [], pg_config())

      assert message =~ "does not exist"
      assert message =~ "get_many"
      assert message =~ "typed stub"
    end
  end

  describe "throwaway test database & Manager isolation" do
    @tag :postgres
    test "uses a throwaway exoforge_test_* database and isolates plugin schemas via Manager" do
      cfg = pg_config()
      assert cfg.database != "exoforge_prod"
      assert String.starts_with?(cfg.database, "exoforge_test_")

      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      unless Process.whereis(Manager) do
        start_supervised!({Manager, [driver: :postgres] ++ Map.to_list(cfg)})
      end

      plugin_a = :"pg_mgr_a_#{System.unique_integer([:positive])}"
      plugin_b = :"pg_mgr_b_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        _ = Postgres.reset(plugin_a, cfg)
        _ = Postgres.reset(plugin_b, cfg)
      end)

      assert {:ok, conn_cfg} = Database.get_connection_config(plugin_a)
      assert conn_cfg.driver == :postgres
      assert conn_cfg.schema == "plugin_#{Database.clean_id(plugin_a)}"

      assert {:ok, %{rows: [%{"db" => current_db, "schema" => current_schema}]}} =
               Database.execute(plugin_a, "SELECT current_database() AS db, current_schema() AS schema")

      assert current_db == cfg.database
      assert current_schema == "plugin_#{Database.clean_id(plugin_a)}"

      assert {:ok, _} = Database.execute(plugin_a, "CREATE TABLE items (id text PRIMARY KEY, owner text NOT NULL)")
      assert {:ok, _} = Database.execute(plugin_a, "INSERT INTO items (id, owner) VALUES ($1, $2)", ["i1", "alpha"])

      assert {:error, {:postgres_error, msg}} = Database.execute(plugin_b, "SELECT * FROM items")
      assert msg =~ "does not exist"

      assert {:ok, _} = Database.execute(plugin_b, "CREATE TABLE items (id text PRIMARY KEY, owner text NOT NULL)")
      assert {:ok, _} = Database.execute(plugin_b, "INSERT INTO items (id, owner) VALUES ($1, $2)", ["i1", "beta"])

      assert {:ok, %{rows: [%{"id" => "i1", "owner" => "alpha"}]}} =
               Database.execute(plugin_a, "SELECT id, owner FROM items")

      assert {:ok, %{rows: [%{"id" => "i1", "owner" => "beta"}]}} =
               Database.execute(plugin_b, "SELECT id, owner FROM items")
    end
  end

  describe "D3: batched atomic writes (db_batch) with Postgrex.transaction rollback" do
    setup do
      unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_batch_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())

      on_exit(fn ->
        _ = Postgres.reset(plugin, pg_config())
      end)

      {:ok, plugin: plugin}
    end

    @tag :postgres
    test "commits all execute, put, and delete operations atomically in order when all succeed", %{plugin: plugin} do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE accounts (id text PRIMARY KEY, coins integer NOT NULL CHECK (coins >= 0))",
                 [],
                 pg_config()
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "sessions", id: "stale", data: %{"token" => "old"}},
                 [],
                 pg_config()
               )

      operations = [
        %{action: "put", table: "accounts", key: "p1", value: %{"coins" => 100}},
        %{action: "put", table: "accounts", key: "p2", value: %{"coins" => 50}},
        %{action: "execute", sql: "UPDATE accounts SET coins = coins - $1 WHERE id = $2", args: [30, "p1"]},
        %{action: "execute", sql: "UPDATE accounts SET coins = coins + $1 WHERE id = $2", args: [30, "p2"]},
        %{action: "put", table: "sessions", key: "active", value: %{"token" => "fresh"}},
        %{action: "delete", table: "sessions", key: "stale"}
      ]

      assert {:ok, %{num_rows: 6}} =
               Postgres.execute(plugin, %{action: :batch, operations: operations}, [], pg_config())

      assert {:ok, %{rows: [%{"id" => "p1", "coins" => 70}]}} =
               Postgres.execute(plugin, %{action: :get, table: "accounts", id: "p1"}, [], pg_config())

      assert {:ok, %{rows: [%{"id" => "p2", "coins" => 80}]}} =
               Postgres.execute(plugin, %{action: :get, table: "accounts", id: "p2"}, [], pg_config())

      assert {:ok, %{rows: [%{"id" => "active", "token" => "fresh"}]}} =
               Postgres.execute(plugin, %{action: :get, table: "sessions", id: "active"}, [], pg_config())

      assert {:ok, %{rows: []}} =
               Postgres.execute(plugin, %{action: :get, table: "sessions", id: "stale"}, [], pg_config())
    end

    @tag :postgres
    test "rolls back every preceding SQL and KV write in the batch on failure and names the failing index", %{
      plugin: plugin
    } do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE accounts (id text PRIMARY KEY, coins integer NOT NULL CHECK (coins >= 0))",
                 [],
                 pg_config()
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "accounts", id: "p1", data: %{"coins" => 100}},
                 [],
                 pg_config()
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "accounts", id: "p2", data: %{"coins" => 50}},
                 [],
                 pg_config()
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "sessions", id: "keep_me", data: %{"token" => "still_here"}},
                 [],
                 pg_config()
               )

      # Index 0..2 succeed inside the transaction; index 3 violates CHECK (coins >= 0).
      operations = [
        %{action: "execute", sql: "UPDATE accounts SET coins = coins + $1 WHERE id = $2", args: [30, "p2"]},
        %{action: "put", table: "sessions", key: "rolled_back", value: %{"token" => "transient"}},
        %{action: "delete", table: "sessions", key: "keep_me"},
        %{action: "execute", sql: "UPDATE accounts SET coins = coins - $1 WHERE id = $2", args: [500, "p1"]}
      ]

      assert {:error, %{index: 3, reason: {:postgres_error, msg}, message: message}} =
               Postgres.execute(plugin, %{action: :batch, operations: operations}, [], pg_config())

      assert is_binary(msg)
      assert is_binary(message)

      # Index 0 was rolled back: p2 still has 50 coins, p1 still has 100 coins.
      assert {:ok, %{rows: [%{"id" => "p2", "coins" => 50}]}} =
               Postgres.execute(plugin, %{action: :get, table: "accounts", id: "p2"}, [], pg_config())

      assert {:ok, %{rows: [%{"id" => "p1", "coins" => 100}]}} =
               Postgres.execute(plugin, %{action: :get, table: "accounts", id: "p1"}, [], pg_config())

      # Index 1 was rolled back: "rolled_back" session was not persisted.
      assert {:ok, %{rows: []}} =
               Postgres.execute(plugin, %{action: :get, table: "sessions", id: "rolled_back"}, [], pg_config())

      # Index 2 was rolled back: "keep_me" session was not deleted.
      assert {:ok, %{rows: [%{"id" => "keep_me", "token" => "still_here"}]}} =
               Postgres.execute(plugin, %{action: :get, table: "sessions", id: "keep_me"}, [], pg_config())
    end

    @tag :postgres
    test "rolls back preceding writes when a resource KV put fails coercion at a later index", %{plugin: plugin} do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE accounts (id text PRIMARY KEY, coins integer NOT NULL)",
                 [],
                 pg_config()
               )

      operations = [
        %{action: "put", table: "accounts", key: "p1", value: %{"coins" => 100}},
        %{action: "put", table: "accounts", key: "p2", value: %{"coins" => "not_an_int"}}
      ]

      assert {:error, %{index: 1, reason: {:invalid_value, "coins", "integer"}}} =
               Postgres.execute(plugin, %{action: :batch, operations: operations}, [], pg_config())

      assert {:ok, %{rows: []}} =
               Postgres.execute(plugin, %{action: :all, table: "accounts"}, [], pg_config())
    end
  end
end
