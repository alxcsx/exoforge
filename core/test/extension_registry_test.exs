defmodule Exoforge.ExtensionRegistryTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.ExtensionRegistry

  setup do
    start_supervised!(ExtensionRegistry)
    :ok
  end

  test "register and fetch round-trip" do
    manifest = %Manifest{
      id: :fixture,
      name: "fixture",
      version: "0.1.0",
      entry_point: Exoforge.Fixture.Extension,
      provides: [Exoforge.Fixture.Service]
    }

    assert :ok = ExtensionRegistry.register(manifest)
    assert ExtensionRegistry.fetch_manifest(:fixture) == manifest
    assert ExtensionRegistry.fetch_service(Exoforge.Fixture.Service) == manifest
    assert ExtensionRegistry.fetch_service(:fixture_service) == manifest
    assert ExtensionRegistry.fetch_service("fixture_service") == manifest
    assert ExtensionRegistry.fetch_by_module(Exoforge.Fixture.Extension) == manifest
    assert ExtensionRegistry.fetch_by_module(Exoforge.Fixture.Unknown) == nil
  end

  test "clean_service_name strips Elixir.Exoforge and Std.Services prefixes" do
    assert ExtensionRegistry.clean_service_name(:"Elixir.Exoforge.Std.Services.Combat") == "combat"
    assert ExtensionRegistry.clean_service_name("Elixir.Exoforge.Std.Services.PlayerData") == "player_data"
    assert ExtensionRegistry.clean_service_name("Exoforge.Std.Services.Database") == "database"
    assert ExtensionRegistry.clean_service_name("Std.Services.Economy") == "economy"
    assert ExtensionRegistry.clean_service_name("Elixir.Exoforge.Services.Guilds") == "guilds"
    assert ExtensionRegistry.clean_service_name("Elixir.Exoforge.Matchmaking") == "matchmaking"
    assert ExtensionRegistry.clean_service_name(:combat) == "combat"
    assert ExtensionRegistry.clean_service_name("lldb") == "lldb"
  end
end
