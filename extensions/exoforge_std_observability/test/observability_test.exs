defmodule Exoforge.Std.ObservabilityTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.Std.Observability
  alias Exoforge.Std.Observability.Analytics
  alias Exoforge.Std.Observability.Events

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)

    Exoforge.ExtensionCase.register_extension(Observability,
      id: :exoforge_std_observability,
      provides: [Exoforge.Std.Services.Observability],
      dependencies: [Exoforge.Std.Services.Database]
    )

    unless Process.whereis(Events) do
      start_supervised!(Events)
    end

    Events.clear()
    Exoforge.ActionTrace.enable()
    Exoforge.ActionTrace.clear()
    Exoforge.ErrorGroups.clear()

    on_exit(fn ->
      Exoforge.ActionTrace.clear()
      Exoforge.ErrorGroups.clear()
    end)

    :ok
  end

  test "recent_events serves the ring through the contract" do
    Events.record("action:auth.login", %{player_id: "p1"}, %{origin: "p1", rid: "r_store"})

    assert {:ok, %{events: events}} =
             ActionDispatcher.dispatch_internal(:observability, :recent_events, %{limit: 10})

    assert Enum.any?(events, &(&1.event == "action:auth.login"))

    # The store's own subscription records broadcasts too (the mailbox flush makes it deterministic).
    Exoforge.EventDispatcher.broadcast(:some_event, %{a: 1}, topic: "test")
    _ = :sys.get_state(Events)

    assert {:ok, %{events: events}} =
             ActionDispatcher.dispatch_internal(:observability, :recent_events, %{limit: 10})

    assert Enum.any?(events, &(&1.event == "some_event"))
  end

  test "error_groups serves grouped failures through the contract" do
    assert {:error, :service_not_found} =
             ActionDispatcher.dispatch(:ghost_service, :do_thing, %{"x" => 1})

    assert {:ok, %{groups: [group], count: 1}} =
             ActionDispatcher.dispatch_internal(:observability, :error_groups, %{limit: 5})

    assert group.service == "ghost_service"
    assert group.action == "do_thing"
    assert group.rid =~ ~r/^r_/
    assert group.request == %{"x" => 1}
  end

  test "timeline joins the action, its log line, its event and its failure on the request id" do
    rid = "r_timeline_1"
    parent = %{origin: "alice", rid: rid, depth: 0, capture: :off}

    previous = Exoforge.RequestContext.enter(parent)

    Exoforge.ActionTrace.record(
      :player_data,
      :get_player,
      "alice",
      %{"id" => "p1"},
      {:error, :not_found},
      4
    )

    :ok = Exoforge.ExtensionLogs.append(:exoforge_std_player_data, 2, "player not found")
    Exoforge.RequestContext.restore(previous)

    Events.record("action:player_data.get_player", %{id: "p1"}, %{origin: "alice", rid: rid})

    Exoforge.ErrorGroups.record(
      :player_data,
      :get_player,
      "alice",
      rid,
      %{"id" => "p1"},
      :not_found
    )

    nodes = Analytics.timeline(%{rid: rid})

    kinds = Enum.map(nodes, & &1.kind)
    assert :action in kinds
    assert :event in kinds
    assert :log in kinds
    assert :error in kinds

    action = Enum.find(nodes, &(&1.kind == :action))
    assert action.label == "player_data.get_player"
    assert action.status == "error: :not_found"
    assert action.depth == 0
    assert action.rid == rid

    log = Enum.find(nodes, &(&1.kind == :log))
    assert log.message =~ "player not found"

    # Oldest first.
    assert Enum.map(nodes, & &1.at) == Enum.sort(Enum.map(nodes, & &1.at))
  end

  test "timeline is served through the contract and can be cleared" do
    rid = "r_timeline_2"

    previous =
      Exoforge.RequestContext.enter(%{origin: "bob", rid: rid, depth: 0, capture: :off})

    Exoforge.ActionTrace.record(:auth, :login, "bob", %{}, {:ok, %{}}, 1)
    Exoforge.RequestContext.restore(previous)

    assert {:ok, %{nodes: [node], count: 1}} =
             ActionDispatcher.dispatch_internal(:observability, :timeline, %{rid: rid})

    assert node.kind == :action
    assert node.label == "auth.login"

    assert {:ok, %{status: "cleared"}} =
             ActionDispatcher.dispatch_internal(:observability, :clear_events, %{})

    assert {:ok, %{events: []}} =
             ActionDispatcher.dispatch_internal(:observability, :recent_events, %{limit: 10})
  end

  test "a player timeline filters the retained samples by caller" do
    for caller <- ["alice", "bob"] do
      previous =
        Exoforge.RequestContext.enter(%{
          origin: caller,
          rid: "r_#{caller}",
          depth: 0,
          capture: :off
        })

      Exoforge.ActionTrace.record(:player_data, :get_player, caller, %{}, {:ok, %{}}, 1)
      Exoforge.RequestContext.restore(previous)
    end

    nodes = Analytics.timeline(%{player: "alice"})

    assert nodes != []
    assert Enum.all?(nodes, &(&1.caller == "alice"))
  end
end
