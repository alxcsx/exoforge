defmodule Exoforge.EntityTest do
  use ExUnit.Case, async: false
  alias Exoforge.Entities
  alias Exoforge.Entity.MemoryStore

  # -- Test Entity Definitions --

  defmodule TestGuild do
    use Exoforge.Entity, persist: :memory, timeout: 100

    @impl true
    def on_create(_id, opts) do
      {:ok, %{name: opts[:name] || "Default Guild", level: 1, members: [], gold: 0}}
    end

    @impl true
    def handle_call({:add_member, member}, _from, state) do
      new_state = %{state | members: [member | state.members]}
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:add_gold, amount}, _from, state) do
      new_state = %{state | gold: state.gold + amount}
      {:reply, new_state.gold, new_state}
    end

    @impl true
    def handle_call(:get_guild, _from, state) do
      {:reply, state, state}
    end

    @impl true
    def handle_cast({:set_level, level}, state) do
      {:noreply, %{state | level: level}}
    end
  end

  defmodule RunawayEntity do
    # Low 100KB heap limit to trigger memory cap
    use Exoforge.Entity, persist: :memory, max_heap_size: 100 * 1024

    @impl true
    def on_create(_id, _opts) do
      {:ok, %{items: []}}
    end

    @impl true
    def handle_call(:consume_memory, _from, state) do
      # Generate a huge list exceeding 100KB
      big_list = Enum.to_list(1..100_000)
      {:reply, :ok, %{state | items: big_list}}
    end
  end

  setup do
    MemoryStore.clear()

    if !Process.whereis(Entities.registry_name()) do
      start_supervised!(Entities.registry_spec())
    end

    if !Process.whereis(Entities.supervisor_name()) do
      start_supervised!(Entities.supervisor_spec())
    end

    :ok
  end

  describe "Stateful Entity Lifecycle & Dispatch" do
    test "activates new entity, executes on_create, and handles calls" do
      # 1. First call activates entity and executes on_create
      {:ok, guild} = Entities.call(:guilds, TestGuild, "g_101", :get_guild, 5000)
      assert guild.level == 1
      assert guild.members == []
      assert guild.gold == 0

      # 2. Modify state via call
      assert :ok == Entities.call(:guilds, TestGuild, "g_101", {:add_member, "Alice"})
      {:ok, updated} = Entities.call(:guilds, TestGuild, "g_101", :get_guild)
      assert updated.members == ["Alice"]

      # 3. Modify state via cast
      assert :ok == Entities.cast(:guilds, TestGuild, "g_101", {:set_level, 5})
      # Give cast a moment to process
      :timer.sleep(10)
      {:ok, leveled} = Entities.call(:guilds, TestGuild, "g_101", :get_guild)
      assert leveled.level == 5
    end

    test "persists state across actor termination and rehydration" do
      # Activate and deposit gold
      {:ok, 500} = Entities.call(:guilds, TestGuild, "g_202", {:add_gold, 500})
      {:ok, pid1} = Entities.whereis(:guilds, TestGuild, "g_202")
      assert is_pid(pid1)

      # Gracefully stop entity (flushes state to store)
      assert :ok == Entities.stop(:guilds, TestGuild, "g_202")
      assert {:error, :not_found} == Entities.whereis(:guilds, TestGuild, "g_202")

      # Re-invoke entity -> starts new actor and hydrates from store without calling on_create
      {:ok, guild} = Entities.call(:guilds, TestGuild, "g_202", :get_guild)
      assert guild.gold == 500

      {:ok, pid2} = Entities.whereis(:guilds, TestGuild, "g_202")
      assert is_pid(pid2)
      assert pid1 != pid2
    end

    test "passivates idle actor automatically after timeout" do
      # Entity has 100ms timeout configured
      {:ok, 100} = Entities.call(:guilds, TestGuild, "g_passivate", {:add_gold, 100})
      assert {:ok, _pid} = Entities.whereis(:guilds, TestGuild, "g_passivate")

      # Wait for passivation timeout (100ms + margin)
      :timer.sleep(150)

      # Actor should have passivated and exited
      assert {:error, :not_found} == Entities.whereis(:guilds, TestGuild, "g_passivate")

      # But state was preserved in store!
      {:ok, guild} = Entities.call(:guilds, TestGuild, "g_passivate", :get_guild)
      assert guild.gold == 100
    end

    test "handles concurrent start races safely" do
      # Spawn 10 concurrent callers attempting to start the same entity simultaneously
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Entities.call(:guilds, TestGuild, "g_race", {:add_gold, 10})
          end)
        end

      results = Task.await_many(tasks)
      # All tasks should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Only 1 actor PID should exist
      {:ok, pid} = Entities.whereis(:guilds, TestGuild, "g_race")
      assert is_pid(pid)

      # All 10 gold deposits (10 * 10 = 100) are accounted for
      {:ok, guild} = Entities.call(:guilds, TestGuild, "g_race", :get_guild)
      assert guild.gold == 100
    end

    test "enforces max_heap_size memory protection" do
      # Spawning a runaway actor that allocates beyond its heap limit kills the process safely
      # without bringing down the supervisor or node
      Process.flag(:trap_exit, true)

      res = Entities.call(:test, RunawayEntity, "runaway_1", :consume_memory)
      assert match?({:error, {:entity_call_failed, _}}, res)

      # Allow asynchronous exit signal to unregister from Registry
      :timer.sleep(25)

      # Supervisor and other entities remain completely unaffected
      assert {:error, :not_found} == Entities.whereis(:test, RunawayEntity, "runaway_1")
      assert {:ok, _} = Entities.call(:guilds, TestGuild, "healthy_1", :get_guild)
    end

    test "list_active returns metadata of all running entity actors" do
      {:ok, _} = Entities.call(:guilds, TestGuild, "guild_active_1", {:add_gold, 50})
      {:ok, _} = Entities.call(:guilds, TestGuild, "guild_active_2", {:add_gold, 100})

      active = Entities.list_active()
      assert length(active) >= 2

      item1 = Enum.find(active, &(&1.id == "guild_active_1"))
      assert item1 != nil
      assert item1.plugin == :guilds
      assert item1.type == TestGuild
      assert is_binary(item1.pid)
      assert is_number(item1.memory_kb)

      # Clean up test entities
      Entities.stop(:guilds, TestGuild, "guild_active_1")
      Entities.stop(:guilds, TestGuild, "guild_active_2")
    end
  end
end
