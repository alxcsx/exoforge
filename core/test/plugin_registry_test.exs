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
    assert PluginRegistry.fetch_by_module(Exoforge.Fixture.Plugin) == manifest
    assert PluginRegistry.fetch_by_module(Exoforge.Fixture.Unknown) == nil
  end
end
