defmodule Exoforge.Std.ResourcesTypedProvisionTest do
  @moduledoc """
  Resources whose columns declare a `storage` type are made and kept in line by the driver layer
  (ADR 004). The deploy decides what an unsafe change means: `reset` rebuilds the table, `refuse` fails
  the extension and says where.
  """
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry
  alias Exoforge.Std.Database
  alias Exoforge.Std.Lldb.Manager, as: DbManager
  alias Exoforge.Std.Resources

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!(DbManager)
    end

    Exoforge.ExtensionCase.register_database(Database)

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :exoforge_std_resources,
      provides: [:resource_store]
    )

    on_exit(fn -> System.delete_env("EXOFORGE_SCHEMA_CHANGE_MODE") end)
    {:ok, plugin: :"typed_#{System.unique_integer([:positive])}"}
  end

  defp inventory(qty_storage) do
    %{
      name: "inventory",
      source: {:table, "inventory"},
      primary_key: :sku,
      columns: [
        %{name: "sku", storage: "text", primary_key: true, type: "string"},
        %{name: "qty", storage: qty_storage, nullable: true, type: "integer", decl: "Inventory.cs:14"}
      ]
    }
  end

  defp declare(plugin, resource, migrations \\ [], version \\ "1.0.0") do
    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: plugin,
      name: to_string(plugin),
      version: version,
      entry_point: nil,
      provides: [plugin],
      services: [%{name: plugin, resources: [resource]}],
      migrations: migrations
    })
  end

  defp provision(plugin) do
    ActionDispatcher.dispatch_internal(:resource_store, :provision, %{extension: to_string(plugin)})
  end

  defp introspect(plugin, table) do
    {:ok, info} = ActionDispatcher.dispatch_internal(:lldb, :introspect, %{namespace: plugin, table: table})
    info
  end

  test "provision makes the table of a typed resource, with the declared column types", %{plugin: plugin} do
    on_exit(fn -> Database.reset!(plugin) end)
    declare(plugin, inventory("int32"))

    assert {:ok, %{provisioned: 1}} = provision(plugin)

    assert %{exists: true, primary_key: ["sku"], columns: columns} = introspect(plugin, "inventory")
    assert %{type: "int32"} = Enum.find(columns, &(&1.name == "qty"))

    # and the database layer reads and writes it as a typed table
    assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => "5"})
    assert {:ok, %{"sku" => "gear", "qty" => 5}} = Database.get(plugin, "inventory", "gear")
  end

  test "a resource without declared column types is left to the lazy path", %{plugin: plugin} do
    on_exit(fn -> Database.reset!(plugin) end)

    declare(plugin, %{
      name: "inventory",
      source: {:table, "inventory"},
      primary_key: :sku,
      columns: [%{name: "sku", type: "string"}, %{name: "qty", type: "integer"}]
    })

    assert {:ok, %{provisioned: 0}} = provision(plugin)
    assert %{exists: false} = introspect(plugin, "inventory")
  end

  test "provisioning again changes nothing", %{plugin: plugin} do
    on_exit(fn -> Database.reset!(plugin) end)
    declare(plugin, inventory("int32"))

    assert {:ok, %{provisioned: 1}} = provision(plugin)
    assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 1})
    assert {:ok, %{provisioned: 1}} = provision(plugin)
    assert {:ok, %{"qty" => 1}} = Database.get(plugin, "inventory", "gear")
  end

  test "refuse (the default) fails an unsafe change, says where, and keeps the data", %{plugin: plugin} do
    on_exit(fn -> Database.reset!(plugin) end)
    declare(plugin, inventory("int32"))
    assert {:ok, _} = provision(plugin)
    assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 5})

    declare(plugin, inventory("text"))

    assert {:error, {:unsafe_schema_change, %{extension: extension, table: "inventory", changes: changes, hint: hint}}} =
             provision(plugin)

    assert extension == to_string(plugin)
    assert [%{table: "inventory", column: "qty", change: _, reason: reason, decl: "Inventory.cs:14"}] = changes
    assert is_binary(reason)
    assert hint =~ "EXOFORGE_SCHEMA_CHANGE_MODE=reset"

    # nothing was touched
    assert %{columns: columns} = introspect(plugin, "inventory")
    assert %{type: "int32"} = Enum.find(columns, &(&1.name == "qty"))
    assert {:ok, %{"qty" => 5}} = Database.get(plugin, "inventory", "gear")
  end

  test "reset rebuilds the table of an unsafe change, and the rows are gone", %{plugin: plugin} do
    on_exit(fn -> Database.reset!(plugin) end)
    declare(plugin, inventory("int32"))
    assert {:ok, _} = provision(plugin)
    assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 5})

    System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "reset")
    assert Resources.schema_change_mode() == :reset

    declare(plugin, inventory("text"))
    assert {:ok, %{provisioned: 1}} = provision(plugin)

    assert %{columns: columns} = introspect(plugin, "inventory")
    assert %{type: "text"} = Enum.find(columns, &(&1.name == "qty"))
    assert {:error, :not_found} = Database.get(plugin, "inventory", "gear")
  end

  describe "Studio's generic CRUD on a typed table with an integer key" do
    setup %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin) end)

      declare(plugin, %{
        name: "counters",
        source: {:table, "counters"},
        primary_key: :counter_id,
        # the shape a native extension's manifest gives: every column also carries its Studio display fields
        columns: [
          %{name: "counter_id", storage: "int32", primary_key: true, type: "integer", label: "Counter ID", sortable: true, filterable: true, badge: false},
          %{name: "value", storage: "int32", nullable: true, type: "integer", label: "Value", sortable: true, filterable: false, badge: false},
          %{name: "status", storage: "text", nullable: true, type: "string", label: "Status", sortable: false, filterable: true, badge: true, choices: ~w(active retired)}
        ]
      })

      assert {:ok, %{provisioned: 1}} = provision(plugin)
      :ok
    end

    defp store(action, payload), do: ActionDispatcher.dispatch_internal(:resource_store, action, payload)

    test "ids arrive as strings and are read, changed and removed by the key's declared type", %{plugin: _plugin} do
      assert {:ok, _} = store(:create, %{resource: "counters", attributes: %{"counter_id" => 7, "value" => 1, "status" => "active"}})

      # what a URL or a form sends
      assert {:ok, %{row: %{"counter_id" => 7, "value" => 1}}} = store(:get, %{resource: "counters", id: "7"})

      assert {:ok, _} = store(:update, %{resource: "counters", id: "7", attributes: %{"value" => 9}})
      assert {:ok, %{row: %{"value" => 9}}} = store(:get, %{resource: "counters", id: "7"})

      assert {:ok, %{rows: [%{"counter_id" => 7}], total: 1}} = store(:list, %{resource: "counters"})

      assert {:ok, _} = store(:delete, %{resource: "counters", id: "7"})
      assert {:error, :not_found} = store(:get, %{resource: "counters", id: "7"})
    end
  end

  describe "a table the studio owns (SchemaVersioningMode.Manual)" do
    defp ledger_resource(columns) do
      %{
        name: "ledger",
        source: {:table, "ledger"},
        primary_key: :id,
        schema_versioning_mode: "manual",
        schema_hash: "m1",
        columns: [%{name: "id", storage: "text", primary_key: true, type: "string"} | columns]
      }
    end

    test "a table that matches is accepted and left alone", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin) end)
      assert {:ok, _} = Database.execute(plugin, "CREATE TABLE ledger (id text PRIMARY KEY, note text)")
      declare(plugin, ledger_resource([%{name: "note", storage: "text", nullable: true, type: "string"}]))

      assert {:ok, %{provisioned: 1}} = provision(plugin)
      assert %{columns: columns} = introspect(plugin, "ledger")
      refute Enum.any?(columns, &(&1.name == "_v"))
    end

    test "a table that drifted is refused, and reset mode does not rebuild it", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin); System.delete_env("EXOFORGE_SCHEMA_CHANGE_MODE") end)
      assert {:ok, _} = Database.execute(plugin, "CREATE TABLE ledger (id text PRIMARY KEY, note text)")
      assert {:ok, _} = Database.put(plugin, "ledger", "a", %{"note" => "kept"})
      declare(plugin, ledger_resource([%{name: "note", storage: "text", nullable: true, type: "string"}, %{name: "owner", storage: "text", nullable: false, type: "string"}]))

      System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "reset")

      assert {:error, {:unsafe_schema_change, %{table: "ledger", changes: changes, hint: hint}}} = provision(plugin)
      assert Enum.any?(changes, &(&1.column == "owner"))
      assert hint =~ "SchemaVersioningMode.Manual"
      assert hint =~ "exo db migrate"

      # the studio's rows are still there: reset mode would have dropped the table
      assert {:ok, %{"note" => "kept"}} = Database.get(plugin, "ledger", "a")
    end
  end

  describe "extension versions and migrations" do
    defp inventory(columns, hash) do
      %{
        name: "inventory",
        source: {:table, "inventory"},
        primary_key: :sku,
        schema_hash: hash,
        columns: [%{name: "sku", storage: "text", primary_key: true, type: "string"} | columns]
      }
    end

    defp qty(decl), do: %{name: "qty", storage: "int32", nullable: true, type: "integer", decl: decl}
    # required: a table that has rows cannot gain it without being told what the rows get
    defp amount(decl), do: %{name: "amount", storage: "int32", nullable: false, type: "integer", decl: decl}

    defp rename_qty,
      do: %{
        "resource" => "inventory",
        "to" => "1.1.0",
        "ops" => [%{"op" => "rename", "from" => "qty", "to" => "amount"}, %{"op" => "set_not_null", "column" => "amount", "value" => 0}]
      }

    test "a change the manifest carries a migration for is applied and the rows survive", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin) end)
      declare(plugin, inventory([qty("Inventory.cs:14")], "h1"))
      assert {:ok, _} = provision(plugin)
      assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 5})

      declare(plugin, inventory([amount("Inventory.cs:14")], "h2"), [rename_qty()], "1.1.0")

      assert {:ok, %{provisioned: 1}} = provision(plugin)
      # the table changed, the row did not: it keeps the stamp it was written under (rewriting every row at
      # deploy is the full-table write this design avoids)
      assert {:ok, %{"sku" => "gear", "amount" => 5, "_v" => 1_000_000}} = Database.get(plugin, "inventory", "gear")
    end

    test "a change without its migration is refused with the file to write", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin) end)
      declare(plugin, inventory([qty("Inventory.cs:14")], "h1"))
      assert {:ok, _} = provision(plugin)
      assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 5})

      declare(plugin, inventory([amount("Inventory.cs:14")], "h2"), [], "1.1.0")

      assert {:error, {:unsafe_schema_change, %{table: "inventory", changes: changes, hint: hint}}} = provision(plugin)

      assert Enum.any?(changes, &(&1.column == "amount" and &1.decl == "Inventory.cs:14"))
      assert hint =~ "No migration leads from version 1.0.0 to 1.1.0"
      assert hint =~ "[ExoMigration(typeof(<your inventory type>), To = \"1.1.0\")]"
      assert hint =~ "Migrations/Inventory/To1_1_0.cs"
      assert hint =~ "EXOFORGE_SCHEMA_CHANGE_MODE=reset"

      # the table is untouched
      assert {:ok, %{"qty" => 5}} = Database.get(plugin, "inventory", "gear")
    end

    test "a change that did not raise the extension version is told to", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin) end)
      declare(plugin, inventory([qty("Inventory.cs:14")], "h1"))
      assert {:ok, _} = provision(plugin)

      declare(plugin, inventory([%{name: "qty", storage: "text", nullable: true, type: "string", decl: "Inventory.cs:14"}], "h1b"))

      assert {:error, {:unsafe_schema_change, %{hint: hint}}} = provision(plugin)
      assert hint =~ "still at version 1.0.0"
      assert hint =~ "Raise the extension's version"
      assert hint =~ "To = \"<the new version>\""
    end

    test "an older build over a newer table is refused", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin) end)
      declare(plugin, inventory([qty("Inventory.cs:14")], "h1"))
      assert {:ok, _} = provision(plugin)
      declare(plugin, inventory([amount("Inventory.cs:14")], "h2"), [rename_qty()], "1.1.0")
      assert {:ok, _} = provision(plugin)

      declare(plugin, inventory([qty("Inventory.cs:14")], "h1"))

      assert {:error, {:unsafe_schema_change, %{changes: [%{change: :version, reason: reason}], hint: hint}}} = provision(plugin)
      assert reason =~ "table is at version 1.1.0 and this build is version 1.0.0"
      assert hint =~ "Deploy version 1.1.0 or later"
    end

    test "a drop is refused while rows are below its version, and reset rebuilds in development", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin); System.delete_env("EXOFORGE_SCHEMA_CHANGE_MODE") end)

      two_cols = inventory([qty("Inventory.cs:14"), %{name: "note", storage: "text", nullable: true, type: "string"}], "h1")
      declare(plugin, two_cols)
      assert {:ok, _} = provision(plugin)
      assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 5, "note" => "x"})

      # the row was written under 1.0.0; a drop that leads to 1.1.0 would lose its note
      drop_note = %{"resource" => "inventory", "to" => "1.1.0", "ops" => [%{"op" => "drop", "column" => "note"}]}
      declare(plugin, inventory([qty("Inventory.cs:14")], "h2"), [drop_note], "1.1.0")

      assert {:error, {:unsafe_schema_change, %{changes: [%{change: :drop, reason: reason}], hint: hint}}} = provision(plugin)
      assert reason =~ "1 rows are still below version 1.1.0"
      assert hint =~ "Deploy the drop once none is left"
      assert {:ok, %{"note" => "x"}} = Database.get(plugin, "inventory", "gear")

      System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "reset")
      assert {:ok, %{provisioned: 1}} = provision(plugin)
      assert {:error, :not_found} = Database.get(plugin, "inventory", "gear")
    end

    test "reset rebuilds the table when the migration is missing", %{plugin: plugin} do
      on_exit(fn -> Database.reset!(plugin); System.delete_env("EXOFORGE_SCHEMA_CHANGE_MODE") end)
      declare(plugin, inventory([qty("Inventory.cs:14")], "h1"))
      assert {:ok, _} = provision(plugin)
      assert {:ok, _} = Database.put(plugin, "inventory", "gear", %{"qty" => 5})

      System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "reset")
      declare(plugin, inventory([amount("Inventory.cs:14")], "h2"), [], "1.1.0")

      assert {:ok, %{provisioned: 1}} = provision(plugin)
      assert %{columns: columns} = introspect(plugin, "inventory")
      assert Enum.any?(columns, &(&1.name == "amount"))
      assert {:error, :not_found} = Database.get(plugin, "inventory", "gear")
    end
  end

  test "the mode is refuse unless the deploy says reset" do
    System.delete_env("EXOFORGE_SCHEMA_CHANGE_MODE")
    assert Resources.schema_change_mode() == :refuse

    System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "anything else")
    assert Resources.schema_change_mode() == :refuse

    System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "reset")
    assert Resources.schema_change_mode() == :reset
  end
end
