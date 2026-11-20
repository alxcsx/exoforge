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

  defp declare(plugin, resource) do
    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: plugin,
      name: to_string(plugin),
      version: "1.0.0",
      entry_point: nil,
      provides: [plugin],
      services: [%{name: plugin, resources: [resource]}]
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

  test "the mode is refuse unless the deploy says reset" do
    System.delete_env("EXOFORGE_SCHEMA_CHANGE_MODE")
    assert Resources.schema_change_mode() == :refuse

    System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "anything else")
    assert Resources.schema_change_mode() == :refuse

    System.put_env("EXOFORGE_SCHEMA_CHANGE_MODE", "reset")
    assert Resources.schema_change_mode() == :reset
  end
end
