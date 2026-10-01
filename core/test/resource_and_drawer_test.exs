defmodule Exoforge.ResourceAndDrawerTest do
  use ExUnit.Case, async: false

  alias Exoforge.PluginRegistry
  alias Exoforge.DrawerRegistry
  alias Exoforge.Domain.Manifest

  defmodule ResourceTestService do
    import Exoforge.Contracts.Service

    defservice inventory do
      @doc "Player inventory items"
      resource :items do
        @doc "Game items and equipment"
        primary_key :item_id
        column :item_id, :string, label: "Item ID", sortable: true
        column :name, :string, label: "Item Name", filterable: true
        column :quantity, :integer, label: "Quantity", sortable: true
        column :rarity, :string, label: "Rarity", badge: true
        drawer [:overview, :attributes, :transactions]
        actions [:get_item, :equip_item]
      end

      action :get_item do
        params(item_id: :string)
        returns(item: :map)
      end
    end
  end

  setup do
    start_supervised!(PluginRegistry)
    start_supervised!(DrawerRegistry)
    :ok
  end

  test "contract metadata extracts resource and columns properly" do
    meta = ResourceTestService.Inventory.__service_metadata__()
    assert meta.name == :inventory
    assert length(meta.resources) == 1

    [res] = meta.resources
    assert res.name == :items
    assert res.primary_key == :item_id
    assert res.drawer == [:overview, :attributes, :transactions]
    assert res.actions == [:get_item, :equip_item]
    assert length(res.columns) == 4

    [id_col, name_col, _qty_col, rarity_col] = res.columns
    assert id_col.name == :item_id
    assert id_col.type == :string
    assert id_col.sortable == true

    assert name_col.name == :name
    assert name_col.label == "Item Name"
    assert name_col.filterable == true

    assert rarity_col.badge == true
  end

  test "PluginRegistry discovers resources across plugins" do
    manifest = %Manifest{
      id: :inventory_plugin,
      name: "inventory_plugin",
      version: "1.0.0",
      entry_point: nil,
      provides: [ResourceTestService.Inventory]
    }

    assert :ok = PluginRegistry.register(manifest)

    resources = PluginRegistry.all_resources()
    assert length(resources) >= 1
    assert Enum.any?(resources, fn r -> r.resource.name == :items and r.plugin_id == :inventory_plugin end)

    assert {:ok, found} = PluginRegistry.fetch_resource(:items)
    assert found.plugin_id == :inventory_plugin
    assert found.resource.primary_key == :item_id

    assert {:error, :not_found} = PluginRegistry.fetch_resource(:non_existent)
  end

  test "DrawerRegistry manages inspector tabs" do
    manifest = %Manifest{
      id: :inventory_plugin,
      name: "inventory_plugin",
      version: "1.0.0",
      entry_point: nil,
      provides: [ResourceTestService.Inventory]
    }

    assert :ok = PluginRegistry.register(manifest)

    # list_tabs should include declared tabs [:overview, :attributes, :transactions]
    tabs = DrawerRegistry.list_tabs(:items)
    assert length(tabs) == 3
    tab_ids = Enum.map(tabs, & &1.id)
    assert tab_ids == [:overview, :attributes, :transactions]

    # Register an extension-contributed tab: :moderation
    DrawerRegistry.register_tab(:items, :moderation, %{label: "Item Logs", order: 50})

    updated_tabs = DrawerRegistry.list_tabs(:items)
    assert length(updated_tabs) == 4
    assert Enum.any?(updated_tabs, fn t -> t.id == :moderation and t.label == "Item Logs" end)

    # Unregister tab
    DrawerRegistry.unregister_tab(:items, :moderation)
    assert length(DrawerRegistry.list_tabs(:items)) == 3
  end

  test "standard services contain declared resources" do
    player_data_meta = Exoforge.Std.Services.PlayerData.__service_metadata__()
    assert length(player_data_meta.resources) == 1
    [players_res] = player_data_meta.resources
    assert players_res.name == :players
    assert players_res.primary_key == :player_id

    combat_meta = Exoforge.Std.Services.Combat.__service_metadata__()
    assert length(combat_meta.resources) == 1
    [combatants_res] = combat_meta.resources
    assert combatants_res.name == :combatants
    assert combatants_res.primary_key == :entity_id
  end
end
