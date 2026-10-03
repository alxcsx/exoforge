defmodule Exoforge.EventDispatcherTest do
  use ExUnit.Case, async: false
  alias Exoforge.EventDispatcher

  setup do
    start_supervised!({Registry, keys: :duplicate, name: EventDispatcher.registry_name()})
    :ok
  end

  test "subscribes with wildcard '*' topic and receives events from any topic" do
    EventDispatcher.subscribe(:all, topic: "*")

    EventDispatcher.broadcast("combat:damage_dealt", %{damage: 25}, topic: "combat")
    assert_receive {:exo_event, "combat:damage_dealt", %{damage: 25}, context}
    assert context.topic == "combat"

    EventDispatcher.broadcast("player:leveled_up", %{level: 10})
    assert_receive {:exo_event, "player:leveled_up", %{level: 10}, _}
  end

  test "unsubscribes with wildcard '*' topic cleanly" do
    EventDispatcher.subscribe(:all, topic: "*")
    EventDispatcher.unsubscribe(:all, topic: "*")

    EventDispatcher.broadcast("test:event", %{val: 1})
    refute_receive {:exo_event, "test:event", _, _}, 50
  end
end
