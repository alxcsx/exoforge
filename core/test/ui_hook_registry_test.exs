defmodule Exoforge.UIHookRegistryTest do
  use ExUnit.Case, async: false

  alias Exoforge.UIHookRegistry
  alias Exoforge.DrawerRegistry
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  setup do
    unless Process.whereis(PluginRegistry), do: start_supervised!(PluginRegistry)
    PluginRegistry.initialize_ets()
    :ok
  end

  test "manifest ui_hooks are discovered live, sorted, and cleaned up on unregister" do
    manifest = %Manifest{
      id: :my_extension,
      name: "My Extension",
      version: "0.1.0",
      entry_point: MyExtModule,
      provides: [:my_service],
      dashboard_view: %{id: :my_view, title: "My View", icon: "✨"},
      ui_hooks: %{
        settings: [
          %{id: :my_settings, title: "My Settings", icon: "🛠️", order: 50},
          %{id: :early_settings, title: "Early", icon: "⏱️", order: 5}
        ],
        player_inspect: [
          %{id: :my_player_hook, title: "Player Badge", icon: "🎖️", order: 25}
        ]
      }
    }

    assert :ok = PluginRegistry.register(manifest)

    settings = UIHookRegistry.list_hooks(:settings)
    assert Enum.map(settings, & &1.id) == [:early_settings, :my_settings]
    assert Enum.all?(settings, &(&1.plugin_id == :my_extension))

    player = UIHookRegistry.list_hooks(:player_inspect)
    assert Enum.any?(player, &(&1.id == :my_player_hook and &1.title == "Player Badge"))

    assert :ok = PluginRegistry.unregister(:my_extension)
    refute Enum.any?(UIHookRegistry.list_hooks(:settings), &(&1.id == :my_settings))
    refute Enum.any?(UIHookRegistry.list_hooks(:player_inspect), &(&1.id == :my_player_hook))
  end

  test "DrawerRegistry lists declared tabs and resolves binary names without creating atoms" do
    defmodule TestInventoryService do
      import Exoforge.Contracts.Service

      defservice inventory_dash do
        resource :dash_items do
          primary_key(:item_id)
          column(:item_id, :string, label: "Item ID")
          drawer([:overview, :attributes, :transactions])
        end
      end
    end

    manifest = %Manifest{
      id: :inventory_dash_plugin,
      name: "inventory_dash_plugin",
      version: "1.0.0",
      entry_point: nil,
      provides: [TestInventoryService.InventoryDash]
    }

    assert :ok = PluginRegistry.register(manifest)

    tabs = DrawerRegistry.list_tabs(:dash_items)
    assert Enum.map(tabs, & &1.id) == [:overview, :attributes, :transactions]

    # A binary name resolves to the same tabs.
    assert DrawerRegistry.list_tabs("dash_items") == tabs

    # An unknown binary returns [] and does NOT create an atom.
    unknown = "no_such_resource_#{System.unique_integer([:positive])}"
    assert DrawerRegistry.list_tabs(unknown) == []
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end
end
