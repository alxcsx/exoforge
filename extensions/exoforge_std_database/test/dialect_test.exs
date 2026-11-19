defmodule Exoforge.Std.Database.DialectTest do
  @moduledoc """
  The SQL layer against a driver that is not PostgreSQL (ADR 005).

  A recording stand-in for `lldb` speaks a different dialect: `?` placeholders, backtick quoting, no
  `ON CONFLICT` (an upsert is a delete then an insert) and no `::jsonb` casts. If the database layer had
  slipped PostgreSQL's habits into its SQL, the statements asserted here would show it.
  """
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database.{Dialect, Store}

  defmodule FakeLldb do
    use Exoforge.Extension, provides: [:lldb]

    @manifest %{category: "Storage", system: true, title: "Fake driver", icon: "🧪", dashboard_view: nil}

    def start, do: Agent.start_link(fn -> %{calls: [], introspect: %{}, fail_at: nil} end, name: __MODULE__)
    def stop, do: if(Process.whereis(__MODULE__), do: Agent.stop(__MODULE__))
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))
    def script(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
    def table(name, response), do: Agent.update(__MODULE__, &put_in(&1.introspect[name], response))

    defp record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})

    @impl true
    defaction dialect(), scope: :global do
      {:ok,
       %{
         name: "fake",
         placeholder: "question",
         identifier_quote: "`",
         upsert: "delete_insert",
         json_cast: "",
         transactional_ddl: false,
         types: %{"text" => "TEXT", "json" => "TEXT", "timestamp" => "DATETIME", "timestamp_naive" => "DATETIME"}
       }}
    end

    @impl true
    defaction introspect(payload) do
      table = payload[:table]
      record({:introspect, table})

      {:ok, Agent.get(__MODULE__, & &1.introspect[table]) || %{exists: false, columns: [], primary_key: []}}
    end

    @impl true
    defaction exec(payload) do
      record({:exec, payload[:operation], payload[:arguments]})
      {:ok, %{rows: [], num_rows: 1}}
    end

    @impl true
    defaction transaction(payload) do
      statements = payload[:statements]
      record({:transaction, statements})

      case Agent.get(__MODULE__, & &1.fail_at) do
        nil -> {:ok, %{results: Enum.map(statements, fn _ -> %{rows: [], num_rows: 1} end), num_rows: length(statements)}}
        index -> {:error, %{index: index, reason: {:fake, :boom}, message: "boom"}}
      end
    end
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    {:ok, _} = FakeLldb.start()

    Exoforge.ExtensionCase.register_extension(FakeLldb,
      id: :exoforge_std_lldb,
      provides: [Exoforge.Std.Services.Lldb]
    )

    Dialect.reset()

    # The dialect is remembered process-wide: forget the fake one so the next test asks the real driver.
    on_exit(fn -> Dialect.reset() end)
    :ok
  end

  defp transactions, do: for({:transaction, statements} <- FakeLldb.calls(), do: statements)

  test "the dialect comes from the driver layer, and quoting and placeholders follow it" do
    assert Dialect.quote_ident("scores") == "`scores`"
    assert Dialect.placeholder(1) == "?"
    assert Dialect.placeholder(2) == "?"
    assert Dialect.json_placeholder(2) == "?"
    assert Dialect.type(:json) == "TEXT"
    assert_raise ArgumentError, fn -> Dialect.quote_ident("Scores; DROP") end
  end

  test "a document put creates the table in the engine's types and upserts as delete then insert" do
    assert {:ok, %{num_rows: 1}} = Store.run(:player, %{action: :put, table: "scores", id: "p1", data: %{"score" => 10}})

    assert [
             [
               {create, []},
               {delete, ["p1"]},
               {insert, ["p1", json]}
             ]
           ] = transactions()

    assert create ==
             "CREATE TABLE IF NOT EXISTS `scores` (id TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)"

    assert delete == "DELETE FROM `scores` WHERE `id` = ?"
    assert insert == "INSERT INTO `scores` (`id`, `data`, `updated_at`) VALUES (?, ?, CURRENT_TIMESTAMP)"
    assert Jason.decode!(json) == %{"score" => 10}
  end

  test "nothing of PostgreSQL's syntax appears in what the database layer writes" do
    Store.run(:player, %{action: :put, table: "scores", id: "p1", data: %{"score" => 10}})
    Store.run(:player, %{action: :get, table: "scores", id: "p1"})
    Store.run(:player, %{action: :delete, table: "scores", id: "p1"})
    Store.run(:player, %{action: :all, table: "scores"})

    sql =
      FakeLldb.calls()
      |> Enum.flat_map(fn
        {:exec, sql, _} -> [sql]
        {:transaction, statements} -> Enum.map(statements, &elem(&1, 0))
        _ -> []
      end)

    assert sql != []

    for statement <- sql do
      refute statement =~ ~r/\$\d/, "numbered placeholder in: #{statement}"
      refute statement =~ "::", "cast in: #{statement}"
      refute statement =~ "ON CONFLICT", "upsert clause in: #{statement}"
      refute statement =~ "EXCLUDED", "EXCLUDED in: #{statement}"
      refute statement =~ ~s("), "double-quoted identifier in: #{statement}"
    end
  end

  test "a typed put coerces to the column's logical type and upserts as delete then insert" do
    FakeLldb.table("wallets", %{
      exists: true,
      columns: [
        %{name: "player_id", type: "text", tz: false, nullable: false},
        %{name: "coins", type: "int32", tz: false, nullable: true}
      ],
      primary_key: ["player_id"]
    })

    assert {:ok, %{rows: [%{"id" => "p1"}], num_rows: 1}} =
             Store.run(:player, %{action: :put, table: "wallets", id: "p1", data: %{"coins" => "42"}})

    assert [
             [
               {"DELETE FROM `wallets` WHERE `player_id` = ?", ["p1"]},
               {"INSERT INTO `wallets` (`player_id`, `coins`) VALUES (?, ?)", ["p1", 42]}
             ]
           ] = transactions()

    assert {:error, {:invalid_value, "coins", "int32"}} =
             Store.run(:player, %{action: :put, table: "wallets", id: "p2", data: %{"coins" => "lots"}})
  end

  test "a typed read is a plain select with the engine's placeholder" do
    FakeLldb.table("wallets", %{
      exists: true,
      columns: [
        %{name: "player_id", type: "text", tz: false, nullable: false},
        %{name: "coins", type: "int32", tz: false, nullable: true}
      ],
      primary_key: ["player_id"]
    })

    Store.run(:player, %{action: :get, table: "wallets", id: "p1"})

    assert {:exec, "SELECT * FROM `wallets` WHERE `player_id` = ?", ["p1"]} in FakeLldb.calls()
  end

  test "a batch is one transaction, and a failure names the operation, not the statement" do
    FakeLldb.script(:fail_at, 3)

    operations = [
      %{action: "execute", sql: "UPDATE counters SET n = n + 1", args: []},
      %{action: "put", table: "scores", key: "a", value: %{"s" => 1}},
      %{action: "put", table: "scores", key: "b", value: %{"s" => 2}}
    ]

    # op 0 = 1 statement (index 0); op 1 = create + delete + insert (1..3); op 2 starts at 4
    assert {:error, %{index: 1, reason: {:fake, :boom}}} = Store.run(:player, %{action: :batch, operations: operations})

    assert [statements] = transactions()
    assert length(statements) == 1 + 3 + 3
    assert {"UPDATE counters SET n = n + 1", []} = hd(statements)
  end
end
