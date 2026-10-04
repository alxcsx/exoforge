defmodule Exoforge.PluginRegistryTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry

  setup do
    start_supervised!(PluginRegistry)
    :ok
  end

  test "register and fetch round-trip" do
    manifest = %Manifest{
      id: :fixture,
      name: "fixture",
      version: "0.1.0",
      entry_point: Exoforge.Fixture.Plugin,
      provides: [Exoforge.Fixture.Service]
    }

    assert :ok = PluginRegistry.register(manifest)
    assert PluginRegistry.fetch_manifest(:fixture) == manifest
    assert PluginRegistry.fetch_service(Exoforge.Fixture.Service) == manifest
    assert PluginRegistry.fetch_service(:fixture_service) == manifest
    assert PluginRegistry.fetch_service("fixture_service") == manifest
    assert PluginRegistry.fetch_by_module(Exoforge.Fixture.Plugin) == manifest
    assert PluginRegistry.fetch_by_module(Exoforge.Fixture.Unknown) == nil
  end

  test "clean_service_name strips Elixir.Exoforge and Std.Services prefixes" do
    assert PluginRegistry.clean_service_name(:"Elixir.Exoforge.Std.Services.Combat") == "combat"
    assert PluginRegistry.clean_service_name("Elixir.Exoforge.Std.Services.PlayerData") == "player_data"
    assert PluginRegistry.clean_service_name("Exoforge.Std.Services.Database") == "database"
    assert PluginRegistry.clean_service_name("Std.Services.Economy") == "economy"
    assert PluginRegistry.clean_service_name("Elixir.Exoforge.Services.Guilds") == "guilds"
    assert PluginRegistry.clean_service_name("Elixir.Exoforge.Matchmaking") == "matchmaking"
    assert PluginRegistry.clean_service_name(:combat) == "combat"
    assert PluginRegistry.clean_service_name("lldb") == "lldb"
  end

  test "dashboard_extensions resolves dashboard_view and has_dashboard_view flag" do
    manifest = %Manifest{
      id: :auth_plugin,
      name: "Auth Plugin",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [:auth],
      dashboard_view: %{
        id: :auth,
        title: "Users & Auth",
        icon: "🛡️",
        module: Exoforge.Std.Auth.DashboardView
      }
    }

    assert :ok = PluginRegistry.register(manifest)
    summaries = PluginRegistry.dashboard_extensions()
    auth_summary = Enum.find(summaries, &(&1.id == :auth_plugin))

    assert auth_summary != nil
    assert auth_summary.has_dashboard_view == true
    assert auth_summary.dashboard_view.title == "Users & Auth"
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

  test "normalize_action_params keeps unknown types as strings without creating atoms" do
    unknown = "custom_type_#{System.unique_integer([:positive])}"

    [param] = PluginRegistry.normalize_action_params(%{"thing" => unknown})
    assert param.type == unknown
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end
end
