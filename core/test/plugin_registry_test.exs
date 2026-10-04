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

end
