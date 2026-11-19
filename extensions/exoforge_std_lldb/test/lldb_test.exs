defmodule Exoforge.Std.LldbTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Manager

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(Manager) do
      start_supervised!(Manager)
    end

    Exoforge.ExtensionCase.register_extension(Lldb, id: :exoforge_std_lldb, provides: [Exoforge.Std.Services.Lldb])

    # Cleaned up front: by the time on_exit callbacks run the Manager is already stopped.
    Manager.reset(:lldb_contract)
    :ok
  end

  describe "connection config and health" do
    test "connection_config returns unique isolated details per namespace" do
      {:ok, auth_config} = Manager.connection_config(:auth)
      assert auth_config.database == "exoforge_auth"
      assert auth_config.schema == "plugin_auth"
      assert String.contains?(auth_config.url, "exoforge_auth")

      {:ok, player_config} = Manager.connection_config(:player_data)
      assert player_config.database == "exoforge_player_data"
      assert player_config.schema == "plugin_player_data"
      assert auth_config.url != player_config.url
    end

    test "health_check returns ok status" do
      assert {:ok, %{status: "ok"}} = Manager.health_check()
    end
  end

  describe "the lldb service contract" do
    test "provision_namespace, exec, table_columns and drop_namespace work through the service" do
      ns = :lldb_contract

      assert {:ok, _} = ActionDispatcher.dispatch_internal(:lldb, :provision_namespace, %{namespace: ns})

      assert {:ok, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation: "CREATE TABLE widgets (id text, name text)"
               })

      assert {:ok, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation: "INSERT INTO widgets (id, name) VALUES ($1, $2)",
                 arguments: ["w1", "gear"]
               })

      assert {:ok, %{rows: [%{"name" => "gear"}]}} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation: "SELECT name FROM widgets WHERE id = $1",
                 arguments: ["w1"]
               })

      assert {:ok, %{columns: columns}} =
               ActionDispatcher.dispatch_internal(:lldb, :table_columns, %{namespace: ns, table: "widgets"})

      assert Enum.sort(columns) == ["id", "name"]

      assert :ok = ActionDispatcher.dispatch_internal(:lldb, :drop_namespace, %{namespace: ns}) |> normalize()

      assert {:error, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{namespace: ns, operation: "SELECT * FROM widgets"})
    end

    test "transaction is atomic and names the failing statement" do
      ns = :lldb_contract
      exec = fn sql, args -> ActionDispatcher.dispatch_internal(:lldb, :exec, %{namespace: ns, operation: sql, arguments: args}) end

      assert {:ok, _} = exec.("CREATE TABLE ledger (id text PRIMARY KEY, coins integer NOT NULL CHECK (coins >= 0))", [])

      assert {:ok, %{num_rows: 2, results: [_, _]}} =
               ActionDispatcher.dispatch_internal(:lldb, :transaction, %{
                 namespace: ns,
                 statements: [
                   {"INSERT INTO ledger (id, coins) VALUES ($1, $2)", ["a", 10]},
                   {"INSERT INTO ledger (id, coins) VALUES ($1, $2)", ["b", 20]}
                 ]
               })

      # the second statement violates the CHECK: nothing of this transaction is kept
      assert {:error, %{index: 1, message: message}} =
               ActionDispatcher.dispatch_internal(:lldb, :transaction, %{
                 namespace: ns,
                 statements: [
                   {"INSERT INTO ledger (id, coins) VALUES ($1, $2)", ["c", 30]},
                   {"INSERT INTO ledger (id, coins) VALUES ($1, $2)", ["d", -1]}
                 ]
               })

      assert message =~ "ledger"
      assert {:ok, %{rows: [%{"n" => 2}]}} = exec.("SELECT count(*)::int AS n FROM ledger", [])

      assert {:ok, %{results: [], num_rows: 0}} =
               ActionDispatcher.dispatch_internal(:lldb, :transaction, %{namespace: ns, statements: []})
    end

    test "introspect describes a table with logical types, nullability and the primary key" do
      ns = :lldb_contract

      assert {:ok, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation:
                   "CREATE TABLE shapes (id uuid PRIMARY KEY, label text NOT NULL, sides smallint, area numeric, ratio double precision, " <>
                     "born timestamptz, seen timestamp, solid boolean, blob bytea, meta jsonb, count bigint, n integer, f real)"
               })

      assert {:ok, %{exists: true, columns: columns, primary_key: ["id"]}} =
               ActionDispatcher.dispatch_internal(:lldb, :introspect, %{namespace: ns, table: "shapes"})

      type = fn name -> Enum.find(columns, &(&1.name == name)) end

      assert %{type: "uuid", nullable: false} = type.("id")
      assert %{type: "text", nullable: false} = type.("label")
      assert %{type: "int16", nullable: true} = type.("sides")
      assert %{type: "decimal"} = type.("area")
      assert %{type: "float64"} = type.("ratio")
      assert %{type: "timestamp", tz: true} = type.("born")
      assert %{type: "timestamp", tz: false} = type.("seen")
      assert %{type: "bool"} = type.("solid")
      assert %{type: "bytes"} = type.("blob")
      assert %{type: "json"} = type.("meta")
      assert %{type: "int64"} = type.("count")
      assert %{type: "int32"} = type.("n")
      assert %{type: "float32"} = type.("f")

      assert {:ok, %{exists: false, columns: [], primary_key: []}} =
               ActionDispatcher.dispatch_internal(:lldb, :introspect, %{namespace: ns, table: "no_such_table"})
    end

    test "dialect tells the SQL layer how to write for this engine" do
      assert {:ok, %{name: "postgres", placeholder: "numbered", upsert: "on_conflict", identifier_quote: "\"", types: types}} =
               ActionDispatcher.dispatch_internal(:lldb, :dialect, %{})

      assert %{"text" => "text", "json" => "jsonb"} = types
    end

    test "the contract names no engine: namespace, not schema or role" do
      contract = Exoforge.Std.Services.Lldb.__service_metadata__()
      text = inspect(contract) |> String.downcase()

      for word <- ["postgres", "schema", "role", "search_path", "jsonb"] do
        refute text =~ word, "the lldb contract must not mention #{word}"
      end
    end
  end

  defp normalize({:ok, _}), do: :ok
  defp normalize(other), do: other
end
