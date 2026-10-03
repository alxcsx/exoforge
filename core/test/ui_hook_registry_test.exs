defmodule Exoforge.UIHookRegistryTest do
  use ExUnit.Case, async: false

  alias Exoforge.UIHookRegistry
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  setup do
    PluginRegistry.initialize_ets()
    UIHookRegistry.initialize_ets()
    :ok
  end

  test "registers, sorts, and unregisters UI hooks directly" do
    assert :ok =
             UIHookRegistry.register_hook(:settings, :database, %{
               title: "Database Engine",
               icon: "🗄️",
               order: 20
             })

    assert :ok =
             UIHookRegistry.register_hook(:settings, :metadata, %{
               title: "Metadata",
               icon: "⚙️",
               order: 5
             })

    assert :ok =
             UIHookRegistry.register_hook(:settings, :auth, %{
               title: "Auth & Security",
               icon: "🔐",
               order: 10
             })

    hooks = UIHookRegistry.list_hooks(:settings)
    assert length(hooks) == 3
    assert Enum.map(hooks, & &1.id) == [:metadata, :auth, :database]

    assert :ok = UIHookRegistry.unregister_hook(:settings, :auth)
    remaining = UIHookRegistry.list_hooks(:settings)
    assert Enum.map(remaining, & &1.id) == [:metadata, :database]
  end

  test "plugins do not have UI by default (has_dashboard_view is false when dashboard_view is nil)" do
    headless_manifest = %Manifest{
      id: :headless_service,
      name: "Headless Service",
      version: "1.0.0",
      entry_point: HeadlessModule,
      provides: [:headless],
      services: [
        %{
          name: :headless,
          actions: [%{name: :ping, mode: :sync}],
          resources: [],
          events: []
        }
      ],
      dashboard_view: nil
    }

    assert :ok = PluginRegistry.register(headless_manifest)

    extensions = PluginRegistry.dashboard_extensions()
    summary = Enum.find(extensions, &(&1.id == :headless_service))

    assert summary != nil
    assert summary.has_dashboard_view == false
    assert summary.has_visual_controls == false
    assert summary.has_custom_view == false
  end

  test "manifest settings_tab and ui_hooks are auto-registered and cleaned up on unregister" do
    manifest = %Manifest{
      id: :my_extension,
      name: "My Extension",
      version: "0.1.0",
      entry_point: MyExtModule,
      provides: [:my_service],
      dashboard_view: %{id: :my_view, title: "My View", icon: "✨"},
      settings_tab: %{id: :my_settings, title: "My Settings", icon: "🛠️", order: 50},
      ui_hooks: %{
        player_inspect: [
          %{id: :my_player_hook, title: "Player Badge", icon: "🎖️", order: 25}
        ]
      }
    }

    assert :ok = PluginRegistry.register(manifest)

    # Verify dashboard view is active
    summary = Enum.find(PluginRegistry.dashboard_extensions(), &(&1.id == :my_extension))
    assert summary.has_dashboard_view == true

    # Verify settings hook was registered
    settings_hooks = UIHookRegistry.list_hooks(:settings)
    assert Enum.any?(settings_hooks, &(&1.id == :my_settings and &1.icon == "🛠️"))

    # Verify player_inspect tab hook was registered
    player_hooks = UIHookRegistry.list_hooks(:player_inspect)
    assert Enum.any?(player_hooks, &(&1.id == :my_player_hook and &1.title == "Player Badge"))

    # Unregister plugin
    assert :ok = PluginRegistry.unregister(:my_extension)

    # Verify hooks cleaned up
    refute Enum.any?(UIHookRegistry.list_hooks(:settings), &(&1.id == :my_settings))
    refute Enum.any?(UIHookRegistry.list_hooks(:player_inspect), &(&1.id == :my_player_hook))
  end
end
