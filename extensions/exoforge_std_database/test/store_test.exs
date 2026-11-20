defmodule Exoforge.Std.Database.StoreTest do
  @moduledoc """
  The key-value, typed-table and batch behaviour of the database layer, against the real driver.
  """
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database
  alias Exoforge.Std.Database.Store
  alias Exoforge.Std.Lldb.Manager

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(Manager) do
      start_supervised!(Manager)
    end

    start_supervised!(Exoforge.Std.Database.KindCache)
    Exoforge.ExtensionCase.register_database(Database)
    :ok
  end

  # A key-value command goes to the Store, SQL text to the driver layer.
  defp exec(plugin, %{} = command, _args), do: Store.run(plugin, command)
  defp exec(plugin, sql, args), do: Database.execute(plugin, sql, args)

  describe "what the database layer remembers about a table" do
    @tag :postgres
    test "changing the table with SQL is seen at once: a dropped document table is made again" do
      plugin = :"pg_cache_#{System.unique_integer([:positive])}"
      on_exit(fn -> Database.reset!(plugin) end)

      assert {:ok, _} = exec(plugin, %{action: :put, table: "notes", id: "a", data: %{"t" => 1}}, [])
      assert {:ok, %{rows: [%{"t" => 1}]}} = exec(plugin, %{action: :get, table: "notes", id: "a"}, [])

      # the table is known to exist now; dropping it through the database layer must be noticed
      assert {:ok, _} = Database.execute(plugin, "DROP TABLE notes")

      assert {:ok, _} = exec(plugin, %{action: :put, table: "notes", id: "b", data: %{"t" => 2}}, [])
      assert {:ok, %{rows: [%{"t" => 2}]}} = exec(plugin, %{action: :get, table: "notes", id: "b"}, [])
      assert {:ok, %{rows: []}} = exec(plugin, %{action: :get, table: "notes", id: "a"}, [])
    end

    @tag :postgres
    test "reset forgets what was known, so the next write starts from nothing" do
      plugin = :"pg_cache_reset_#{System.unique_integer([:positive])}"

      assert {:ok, _} = exec(plugin, %{action: :put, table: "notes", id: "a", data: %{"t" => 1}}, [])
      assert :ok = Database.reset!(plugin) |> normalize()
      assert {:ok, _} = exec(plugin, %{action: :put, table: "notes", id: "b", data: %{"t" => 2}}, [])
      assert {:ok, %{rows: [%{"t" => 2}]}} = exec(plugin, %{action: :get, table: "notes", id: "b"}, [])
      Database.reset!(plugin)
    end

    defp normalize({:ok, _}), do: :ok
    defp normalize(other), do: other
  end

  describe "typed tables made from logical manifest columns" do
    @tag :postgres
    test "a table the driver creates from logical storage types round-trips through the typed path" do
      plugin = :"pg_logical_#{System.unique_integer([:positive])}"
      on_exit(fn -> Database.reset!(plugin) end)

      resource = %{
        name: "inventory",
        source: %{table: "inventory"},
        primary_key: "sku",
        columns: [
          %{name: "sku", storage: "text", primary_key: true},
          %{name: "qty", storage: "int32", nullable: false, default: 0},
          %{name: "weight", storage: "decimal", nullable: true},
          %{name: "seen_at", storage: "timestamp", nullable: true},
          %{name: "flag", storage: "bool", nullable: true}
        ]
      }

      assert {:ok, %{applied: applied}} =
               Exoforge.ActionDispatcher.dispatch_internal(:lldb, :apply_schema, %{namespace: plugin, resources: [resource]})

      assert applied > 0

      assert {:ok, %{num_rows: 1}} =
               exec(plugin, %{
                 action: :put,
                 table: "inventory",
                 id: "gear",
                 data: %{"qty" => "7", "weight" => "1.5", "seen_at" => "2026-11-19T10:00:00Z", "flag" => "true"}
               }, [])

      assert {:ok, %{rows: [row]}} = exec(plugin, %{action: :get, table: "inventory", id: "gear"}, [])
      assert %{"sku" => "gear", "qty" => 7, "weight" => 1.5, "flag" => true} = row
      assert row["seen_at"] =~ "2026-11-19T10:00:00"

      assert {:error, {:invalid_value, "qty", "int32"}} =
               exec(plugin, %{action: :put, table: "inventory", id: "bad", data: %{"qty" => "many"}}, [])

      # the default fills what the caller leaves out
      assert {:ok, %{num_rows: 1}} = exec(plugin, %{action: :put, table: "inventory", id: "bare", data: %{}}, [])
      assert {:ok, %{rows: [%{"qty" => 0}]}} = exec(plugin, %{action: :get, table: "inventory", id: "bare"}, [])

      assert {:ok, %{rows: rows}} = exec(plugin, %{action: :all, table: "inventory"}, [])
      assert Enum.sort(Enum.map(rows, & &1["sku"])) == ["bare", "gear"]

      assert {:ok, %{num_rows: 1}} = exec(plugin, %{action: :delete, table: "inventory", id: "gear"}, [])
      assert {:ok, %{rows: []}} = exec(plugin, %{action: :get, table: "inventory", id: "gear"}, [])
    end
  end

  describe "F32: KV operations on resource-migrated tables" do
    @tag :postgres
    test "put, get, all, and delete work on a schema-migrated table without a data column" do
      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_res_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Database.execute(plugin, "SELECT 1")

      on_exit(fn ->
        _ = Database.reset!(plugin)
      end)

      assert {:ok, _} =
               exec(
                 plugin,
                 "CREATE TABLE wallet_balances (player_id text PRIMARY KEY, coins integer NOT NULL)",
                 []
               )

      assert {:ok, %{num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :put, table: "wallet_balances", id: "p1", data: %{"coins" => 50}},
                 []
               )

      assert {:ok, %{rows: [%{"player_id" => "p1", "coins" => 50}], num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 []
               )

      assert {:ok, %{rows: [%{"player_id" => "p1", "coins" => 50}], num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :all, table: "wallet_balances"},
                 []
               )

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :delete, table: "wallet_balances", id: "p1"},
                 []
               )

      assert {:ok, %{rows: [], num_rows: 0}} =
               exec(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 []
               )
    end

    @tag :postgres
    test "a legacy document table accepts typed-column rows once its data column is relaxed" do
      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_legacy_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Database.execute(plugin, "SELECT 1")
      on_exit(fn -> _ = Database.reset!(plugin) end)

      # The document table the KV path creates on first write, then a resource that gains typed columns.
      assert {:ok, _} = exec(plugin, %{action: :put, table: "itens", id: "old", data: %{"x" => 1}}, [])
      assert {:ok, _} = exec(plugin, "ALTER TABLE itens ADD COLUMN preco integer, ADD COLUMN tags text", [])

      assert {:error, _} = exec(plugin, "INSERT INTO itens (id, preco) VALUES ($1, $2)", ["new", 5])

      assert {:ok, _} = exec(plugin, "ALTER TABLE itens ALTER COLUMN data DROP NOT NULL", [])
      assert {:ok, _} = exec(plugin, "INSERT INTO itens (id, preco, tags) VALUES ($1, $2, $3)", ["new", 5, ~s(["a","b"])])

      assert {:ok, %{rows: [%{"id" => "new", "preco" => 5, "tags" => ~s(["a","b"])}]}} =
               exec(plugin, "SELECT id, preco, tags FROM itens WHERE id = $1", ["new"])
    end

    @tag :postgres
    test "undeclared KV tables still use (id, data, updated_at)" do
      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_doc_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Database.execute(plugin, "SELECT 1")

      on_exit(fn ->
        _ = Database.reset!(plugin)
      end)

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :put, table: "sessions", id: "s1", data: %{"token" => "abc"}},
                 []
               )

      assert {:ok, %{rows: [%{"id" => "s1", "token" => "abc"}], num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :get, table: "sessions", id: "s1"},
                 []
               )
    end
  end

  describe "F34 & F35: coercion by declared Postgres column type" do
    setup do
      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_kv_coerce_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Database.execute(plugin, "SELECT 1")

      on_exit(fn ->
        _ = Database.reset!(plugin)
      end)

      {:ok, plugin: plugin}
    end

    @tag :postgres
    test "F34: string id and string integer values coerce for integer PK and columns", %{plugin: plugin} do
      assert {:ok, _} =
               exec(
                 plugin,
                 "CREATE TABLE daily_reward_table (day integer PRIMARY KEY, coins integer NOT NULL, label text)",
                 []
               )

      assert {:ok, %{num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :put, table: "daily_reward_table", id: "1", data: %{"coins" => "100", "label" => "Day 1"}},
                 []
               )

      assert {:ok, %{rows: [%{"day" => 1, "coins" => 100, "label" => "Day 1"}], num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :get, table: "daily_reward_table", id: "1"},
                 []
               )

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :delete, table: "daily_reward_table", id: "1"},
                 []
               )
    end

    @tag :postgres
    test "F35: ISO-8601 timestamp strings coerce on put and round-trip as ISO-8601 strings", %{plugin: plugin} do
      assert {:ok, _} =
               exec(
                 plugin,
                 "CREATE TABLE wallet_balances (player_id text PRIMARY KEY, coins integer NOT NULL, active boolean NOT NULL, updated_at timestamp without time zone NOT NULL)",
                 []
               )

      assert {:ok, %{num_rows: 1}} =
               exec(
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
                 []
               )

      assert {:ok, %{rows: [row], num_rows: 1}} =
               exec(
                 plugin,
                 %{action: :get, table: "wallet_balances", id: "p1"},
                 []
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
               exec(
                 plugin,
                 "CREATE TABLE typed_items (id integer PRIMARY KEY, coins integer NOT NULL)",
                 []
               )

      assert {:error, {:invalid_value, "coins", "int32"}} =
               exec(
                 plugin,
                 %{action: :put, table: "typed_items", id: "1", data: %{"coins" => "not_an_int"}},
                 []
               )
    end
  end


  describe "D3: batched atomic writes (db_batch) with Postgrex.transaction rollback" do
    setup do
      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_batch_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Database.execute(plugin, "SELECT 1")

      on_exit(fn ->
        _ = Database.reset!(plugin)
      end)

      {:ok, plugin: plugin}
    end

    @tag :postgres
    test "commits all execute, put, and delete operations atomically in order when all succeed", %{plugin: plugin} do
      assert {:ok, _} =
               exec(
                 plugin,
                 "CREATE TABLE accounts (id text PRIMARY KEY, coins integer NOT NULL CHECK (coins >= 0))",
                 []
               )

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :put, table: "sessions", id: "stale", data: %{"token" => "old"}},
                 []
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
               exec(plugin, %{action: :batch, operations: operations}, [])

      assert {:ok, %{rows: [%{"id" => "p1", "coins" => 70}]}} =
               exec(plugin, %{action: :get, table: "accounts", id: "p1"}, [])

      assert {:ok, %{rows: [%{"id" => "p2", "coins" => 80}]}} =
               exec(plugin, %{action: :get, table: "accounts", id: "p2"}, [])

      assert {:ok, %{rows: [%{"id" => "active", "token" => "fresh"}]}} =
               exec(plugin, %{action: :get, table: "sessions", id: "active"}, [])

      assert {:ok, %{rows: []}} =
               exec(plugin, %{action: :get, table: "sessions", id: "stale"}, [])
    end

    @tag :postgres
    test "rolls back every preceding SQL and KV write in the batch on failure and names the failing index", %{
      plugin: plugin
    } do
      assert {:ok, _} =
               exec(
                 plugin,
                 "CREATE TABLE accounts (id text PRIMARY KEY, coins integer NOT NULL CHECK (coins >= 0))",
                 []
               )

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :put, table: "accounts", id: "p1", data: %{"coins" => 100}},
                 []
               )

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :put, table: "accounts", id: "p2", data: %{"coins" => 50}},
                 []
               )

      assert {:ok, _} =
               exec(
                 plugin,
                 %{action: :put, table: "sessions", id: "keep_me", data: %{"token" => "still_here"}},
                 []
               )

      # Index 0..2 succeed inside the transaction; index 3 violates CHECK (coins >= 0).
      operations = [
        %{action: "execute", sql: "UPDATE accounts SET coins = coins + $1 WHERE id = $2", args: [30, "p2"]},
        %{action: "put", table: "sessions", key: "rolled_back", value: %{"token" => "transient"}},
        %{action: "delete", table: "sessions", key: "keep_me"},
        %{action: "execute", sql: "UPDATE accounts SET coins = coins - $1 WHERE id = $2", args: [500, "p1"]}
      ]

      assert {:error, %{index: 3, reason: {:postgres_error, msg}, message: message}} =
               exec(plugin, %{action: :batch, operations: operations}, [])

      assert is_binary(msg)
      assert is_binary(message)

      # Index 0 was rolled back: p2 still has 50 coins, p1 still has 100 coins.
      assert {:ok, %{rows: [%{"id" => "p2", "coins" => 50}]}} =
               exec(plugin, %{action: :get, table: "accounts", id: "p2"}, [])

      assert {:ok, %{rows: [%{"id" => "p1", "coins" => 100}]}} =
               exec(plugin, %{action: :get, table: "accounts", id: "p1"}, [])

      # Index 1 was rolled back: "rolled_back" session was not persisted.
      assert {:ok, %{rows: []}} =
               exec(plugin, %{action: :get, table: "sessions", id: "rolled_back"}, [])

      # Index 2 was rolled back: "keep_me" session was not deleted.
      assert {:ok, %{rows: [%{"id" => "keep_me", "token" => "still_here"}]}} =
               exec(plugin, %{action: :get, table: "sessions", id: "keep_me"}, [])
    end

    @tag :postgres
    test "rolls back preceding writes when a resource KV put fails coercion at a later index", %{plugin: plugin} do
      assert {:ok, _} =
               exec(
                 plugin,
                 "CREATE TABLE accounts (id text PRIMARY KEY, coins integer NOT NULL)",
                 []
               )

      operations = [
        %{action: "put", table: "accounts", key: "p1", value: %{"coins" => 100}},
        %{action: "put", table: "accounts", key: "p2", value: %{"coins" => "not_an_int"}}
      ]

      assert {:error, %{index: 1, reason: {:invalid_value, "coins", "int32"}}} =
               exec(plugin, %{action: :batch, operations: operations}, [])

      assert {:ok, %{rows: []}} =
               exec(plugin, %{action: :all, table: "accounts"}, [])
    end
  end
end
