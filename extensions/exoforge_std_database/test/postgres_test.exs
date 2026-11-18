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
end
