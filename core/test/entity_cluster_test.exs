defmodule Exoforge.EntityClusterTest do
  use ExUnit.Case, async: false
  alias Exoforge.Entities
  alias Exoforge.Entities.Adapters.Horde, as: HordeAdapter

  defmodule ClusteredGuild do
    use Exoforge.Entity, persist: :memory

    @impl true
    def on_create(id, _opts) do
      {:ok, %{id: id, gold: 0, members: []}}
    end

    @impl true
    def handle_call({:deposit, amount}, _from, state) do
      new_state = %{state | gold: state.gold + amount}
      {:reply, {:ok, new_state.gold}, new_state}
    end

    @impl true
    def handle_call(:get, _from, state) do
      {:reply, {:ok, state}, state}
    end
  end

  setup_all do
    # Configure unique Horde registry and supervisor names for test isolation
    Application.put_env(:exoforge, :horde_registry, TestHordeRegistry)
    Application.put_env(:exoforge, :horde_supervisor, TestHordeSupervisor)
    Application.put_env(:exoforge, :entity_adapter, HordeAdapter)

    # Ensure :exo_cluster_pg is started for tests
    case :pg.start_link(:exo_cluster_pg) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Ensure EventDispatcher registry is started
    if !Process.whereis(Exoforge.EventDispatcher.registry_name()) do
      start_supervised!(Exoforge.EventDispatcher)
    end

    # Ensure Horde components are started
    reg_spec = HordeAdapter.registry_spec(members: :auto)
    sup_spec = HordeAdapter.supervisor_spec(members: :auto)

    start_supervised!(reg_spec)
    start_supervised!(sup_spec)

    on_exit(fn ->
      Application.delete_env(:exoforge, :horde_registry)
      Application.delete_env(:exoforge, :horde_supervisor)
      Application.delete_env(:exoforge, :entity_adapter)
    end)

    :ok
  end

  describe "Distributed Horde Adapter" do
    test "implements Adapter callbacks with delta-CRDT Horde" do
      # 1. Start child on Horde supervisor
      spec = %{
        id: {:guilds, ClusteredGuild, "horde_g1"},
        start: {ClusteredGuild, :start_link, [{:guilds, ClusteredGuild, "horde_g1", []}]},
        restart: :temporary
      }

      {:ok, pid} = HordeAdapter.start_child(spec)
      assert is_pid(pid)

      # 2. Lookup via Horde registry
      assert {:ok, ^pid} = HordeAdapter.whereis(:guilds, ClusteredGuild, "horde_g1")

      # 3. Call entity
      assert {:ok, 100} = GenServer.call(pid, {:__exo_call__, {:deposit, 100}})
      assert {:ok, %{gold: 100}} = GenServer.call(pid, {:__exo_call__, :get})

      # 4. Count
      assert HordeAdapter.count() >= 1

      # 5. Terminate child
      assert :ok = HordeAdapter.terminate_child(pid)
      refute Process.alive?(pid)
    end

    test "HordeAdapter set_members and members helpers" do
      nodes = [Node.self()]
      assert :ok = HordeAdapter.set_members(nodes)
      members = HordeAdapter.members()
      assert is_list(members)
    end

    test "Entities manager transparently routes calls through Horde adapter when configured" do
      # Call via high-level Entities manager
      assert {:ok, 50} = Entities.call(:guilds, ClusteredGuild, "cluster_g2", {:deposit, 50})
      assert {:ok, 75} = Entities.call(:guilds, ClusteredGuild, "cluster_g2", {:deposit, 25})
      assert {:ok, %{gold: 75}} = Entities.call(:guilds, ClusteredGuild, "cluster_g2", :get)

      # Count includes cluster entity
      assert Entities.count() >= 1

      # Stop entity
      assert :ok = Entities.stop(:guilds, ClusteredGuild, "cluster_g2")
      assert {:error, :not_found} = Entities.whereis(:guilds, ClusteredGuild, "cluster_g2")
    end
  end

  describe "Cluster Event Dispatching via :pg" do
    test "broadcasts events to :pg group subscribers" do
      # Subscribe calling process to cluster events
      {:ok, _} = Exoforge.EventDispatcher.subscribe(:raid_started, topic: "guild:alpha")

      # Broadcast event from another process
      spawn_link(fn ->
        Exoforge.EventDispatcher.broadcast(:raid_started, %{boss: "Dragon"}, topic: "guild:alpha")
      end)

      # Verify calling process receives event frame
      assert_receive {:exo_event, :raid_started, %{boss: "Dragon"}, context}, 1000
      assert context.topic == "guild:alpha"
      assert context.event == :raid_started

      :ok = Exoforge.EventDispatcher.unsubscribe(:raid_started, topic: "guild:alpha")
    end
  end
end
