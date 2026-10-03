defmodule Exoforge.ResourceTest do
  use ExUnit.Case, async: true
  import Exoforge.Contracts.Service

  defmodule SampleHero do
    use Exoforge.Resource,
      primary_key: :hero_id,
      drawer: [:overview, :inventory]

    column(:hero_id, :string, sortable: true)
    column(:name, :string, label: "Hero Name", filterable: true)
    column(:level, :integer, default: 1, sortable: true)
    column(:status, :string, default: "active", badge: true)
  end

  defservice rpg_service do
    defresource Weapon, primary_key: :weapon_id do
      column(:weapon_id, :string, sortable: true)
      column(:title, :string, label: "Weapon Name")
      column(:power, :integer, default: 10)
      drawer([:overview, :attributes])
      actions([:equip, :unequip])
    end

    resource(SampleHero, actions: [:inspect_hero])
  end

  test "standalone Exoforge.Resource defines struct and metadata" do
    hero = SampleHero.new(%{"hero_id" => "h1", "name" => "Arthur", "level" => 10})
    assert hero.hero_id == "h1"
    assert hero.name == "Arthur"
    assert hero.level == 10
    assert hero.status == "active"

    map = SampleHero.to_map(hero)
    assert map == %{hero_id: "h1", name: "Arthur", level: 10, status: "active"}

    meta = SampleHero.__resource_metadata__()
    assert meta.name == :sample_hero
    assert meta.primary_key == :hero_id
    assert meta.drawer == [:overview, :inventory]
    assert length(meta.columns) == 4
  end

  test "defresource inside defservice generates nested module struct and service metadata" do
    alias Exoforge.ResourceTest.RpgService.Weapon

    weapon = Weapon.new(%{weapon_id: "w_sword", title: "Excalibur", power: 99})
    assert weapon.weapon_id == "w_sword"
    assert weapon.title == "Excalibur"
    assert weapon.power == 99

    meta = Exoforge.ResourceTest.RpgService.__service_metadata__()
    assert length(meta.resources) == 2

    weapon_meta = Enum.find(meta.resources, &(&1.name == :weapon))
    assert weapon_meta.primary_key == :weapon_id
    assert weapon_meta.actions == [:equip, :unequip]
    assert weapon_meta.drawer == [:overview, :attributes]

    hero_meta = Enum.find(meta.resources, &(&1.name == :sample_hero))
    assert hero_meta.primary_key == :hero_id
    assert hero_meta.actions == [:inspect_hero]
  end
end
