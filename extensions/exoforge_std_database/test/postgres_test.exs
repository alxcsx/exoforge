defmodule Exoforge.Std.Database.Adapters.PostgresTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database.Adapters.Postgres

  @pg_config %{
    host: "127.0.0.1",
    port: 5432,
    username: "postgres",
    password: "postgres",
    database: "exoforge_prod"
  }

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
      assert {:ok, _} = Postgres.ensure_database(plugin, @pg_config)

      on_exit(fn ->
        _ = Postgres.reset(plugin, @pg_config)
      end)

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE wallet_balances (player_id text PRIMARY KEY, coins integer NOT NULL)",
                 [],
                 @pg_config
               )

      assert {:ok, %{num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "wallet_balances", id: "p1", data: %{"coins" => 50}},
                 [],
                 @pg_config
               )

      assert {:ok, %{rows: [%{"player_id" => "p1", "coins" => 50}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 [],
                 @pg_config
               )

      assert {:ok, %{rows: [%{"player_id" => "p1", "coins" => 50}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :all, table: "wallet_balances"},
                 [],
                 @pg_config
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :delete, table: "wallet_balances", id: "p1"},
                 [],
                 @pg_config
               )

      assert {:ok, %{rows: [], num_rows: 0}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 [],
                 @pg_config
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
      assert {:ok, _} = Postgres.ensure_database(plugin, @pg_config)
      on_exit(fn -> _ = Postgres.reset(plugin, @pg_config) end)

      # The document table the KV path creates on first write, then a resource that gains typed columns.
      assert {:ok, _} = Postgres.execute(plugin, %{action: :put, table: "itens", id: "old", data: %{"x" => 1}}, [], @pg_config)
      assert {:ok, _} = Postgres.execute(plugin, "ALTER TABLE itens ADD COLUMN preco integer, ADD COLUMN tags text", [], @pg_config)

      assert {:error, _} = Postgres.execute(plugin, "INSERT INTO itens (id, preco) VALUES ($1, $2)", ["new", 5], @pg_config)

      assert {:ok, _} = Postgres.execute(plugin, "ALTER TABLE itens ALTER COLUMN data DROP NOT NULL", [], @pg_config)
      assert {:ok, _} = Postgres.execute(plugin, "INSERT INTO itens (id, preco, tags) VALUES ($1, $2, $3)", ["new", 5, ~s(["a","b"])], @pg_config)

      assert {:ok, %{rows: [%{"id" => "new", "preco" => 5, "tags" => ~s(["a","b"])}]}} =
               Postgres.execute(plugin, "SELECT id, preco, tags FROM itens WHERE id = $1", ["new"], @pg_config)
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
      assert {:ok, _} = Postgres.ensure_database(plugin, @pg_config)

      on_exit(fn ->
        _ = Postgres.reset(plugin, @pg_config)
      end)

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "sessions", id: "s1", data: %{"token" => "abc"}},
                 [],
                 @pg_config
               )

      assert {:ok, %{rows: [%{"id" => "s1", "token" => "abc"}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "sessions", id: "s1"},
                 [],
                 @pg_config
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
      assert {:ok, _} = Postgres.ensure_database(plugin, @pg_config)

      on_exit(fn ->
        _ = Postgres.reset(plugin, @pg_config)
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
                 @pg_config
               )

      assert {:ok, %{num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "daily_reward_table", id: "1", data: %{"coins" => "100", "label" => "Day 1"}},
                 [],
                 @pg_config
               )

      assert {:ok, %{rows: [%{"day" => 1, "coins" => 100, "label" => "Day 1"}], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "daily_reward_table", id: "1"},
                 [],
                 @pg_config
               )

      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 %{action: :delete, table: "daily_reward_table", id: "1"},
                 [],
                 @pg_config
               )
    end

    @tag :postgres
    test "F35: ISO-8601 timestamp strings coerce on put and round-trip as ISO-8601 strings", %{plugin: plugin} do
      assert {:ok, _} =
               Postgres.execute(
                 plugin,
                 "CREATE TABLE wallet_balances (player_id text PRIMARY KEY, coins integer NOT NULL, active boolean NOT NULL, updated_at timestamp without time zone NOT NULL)",
                 [],
                 @pg_config
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
                 @pg_config
               )

      assert {:ok, %{rows: [row], num_rows: 1}} =
               Postgres.execute(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 [],
                 @pg_config
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
                 @pg_config
               )

      assert {:error, {:invalid_value, "coins", "integer"}} =
               Postgres.execute(
                 plugin,
                 %{action: :put, table: "typed_items", id: "1", data: %{"coins" => "not_an_int"}},
                 [],
                 @pg_config
               )
    end
  end
end
