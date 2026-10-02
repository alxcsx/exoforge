defmodule Exoforge.ClusterBenchmarkTest do
  use ExUnit.Case, async: false
  alias Exoforge.Entities

  defmodule BenchmarkPlayerEntity do
    use Exoforge.Entity, persist: :memory, timeout: 60_000

    @impl true
    def on_create(id, opts) do
      {:ok, %{id: id, level: opts[:level] || 1, xp: 0, items: []}}
    end

    @impl true
    def handle_call({:gain_xp, amount}, _from, state) do
      new_xp = state.xp + amount
      new_level = div(new_xp, 100) + 1
      new_state = %{state | xp: new_xp, level: new_level}
      {:reply, {:ok, new_state}, new_state}
    end

    @impl true
    def handle_call(:get_profile, _from, state) do
      {:reply, {:ok, state}, state}
    end

    @impl true
    def handle_cast({:add_item, item}, state) do
      {:noreply, %{state | items: [item | state.items]}}
    end
  end

  setup_all do
    # Ensure :exo_cluster_pg is running
    case :pg.start_link(:exo_cluster_pg) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  describe "Cluster & Entity Runtime Benchmark" do
    test "benchmarks entity activation, stateful call throughput, and latency" do
      entity_count = 100
      calls_per_entity = 10
      total_calls = entity_count * calls_per_entity

      # 1. Benchmark Activation
      {activation_time_us, _} =
        :timer.tc(fn ->
          Enum.each(1..entity_count, fn i ->
            id = "bench_p_#{i}"
            {:ok, _} = Entities.call(:benchmark, BenchmarkPlayerEntity, id, :get_profile)
          end)
        end)

      activation_time_ms = activation_time_us / 1000
      avg_activation_ms = activation_time_ms / entity_count

      # 2. Benchmark Stateful Calls (Concurrent execution)
      start_time = System.monotonic_time(:microsecond)

      tasks =
        for i <- 1..entity_count do
          Task.async(fn ->
            id = "bench_p_#{i}"

            for _ <- 1..calls_per_entity do
              {:ok, _} = Entities.call(:benchmark, BenchmarkPlayerEntity, id, {:gain_xp, 15})
            end
          end)
        end

      Task.await_many(tasks, 10_000)
      end_time = System.monotonic_time(:microsecond)

      duration_us = end_time - start_time
      duration_s = duration_us / 1_000_000
      throughput_ops_sec = total_calls / duration_s
      avg_latency_us = duration_us / total_calls

      # 3. Benchmark Cluster Event Fanout
      subscriber_count = 50
      test_pid = self()

      _subscribers =
        for i <- 1..subscriber_count do
          spawn_link(fn ->
            {:ok, _} = Exoforge.EventDispatcher.subscribe(:benchmark_ping, topic: "bench:events")
            send(test_pid, {:ready, i})

            receive do
              {:exo_event, :benchmark_ping, _payload, _ctx} ->
                send(test_pid, {:received, i})
            end
          end)
        end

      # Wait for all subscribers to register
      for _ <- 1..subscriber_count do
        assert_receive {:ready, _}, 1000
      end

      # Measure broadcast fanout time
      {fanout_us, _} =
        :timer.tc(fn ->
          Exoforge.EventDispatcher.broadcast(:benchmark_ping, %{ts: System.os_time()}, topic: "bench:events")

          for _ <- 1..subscriber_count do
            assert_receive {:received, _}, 1000
          end
        end)

      fanout_ms = fanout_us / 1000

      # 4. Verify Final State Correctness
      {:ok, sample_profile} = Entities.call(:benchmark, BenchmarkPlayerEntity, "bench_p_1", :get_profile)
      assert sample_profile.xp == calls_per_entity * 15
      assert sample_profile.level == div(sample_profile.xp, 100) + 1

      # 5. Clean up entities
      for i <- 1..entity_count do
        Entities.stop(:benchmark, BenchmarkPlayerEntity, "bench_p_#{i}")
      end

      # Assertions meeting production SLAs
      assert avg_activation_ms < 5.0, "Entity activation must be < 5ms"
      assert throughput_ops_sec > 1000, "Throughput must exceed 1,000 ops/sec"
      assert fanout_ms < 50.0, "Event fanout to 50 subscribers must be < 50ms"

      # Print Benchmark Scorecard
      IO.puts("""

      ===============================================================
                     EXOFORGE CLUSTER BENCHMARK SCORECARD
      ===============================================================
       Active Entities Benchmarked:  #{entity_count}
       Total Stateful RPC Calls:     #{total_calls}
       Concurrent Actor Tasks:       #{entity_count}
       Concurrent Event Subscribers: #{subscriber_count}
      ---------------------------------------------------------------
       Entity Activation Time:       #{Float.round(activation_time_ms, 2)} ms total (#{Float.round(avg_activation_ms, 3)} ms / entity)
       Stateful Call Throughput:     #{round(throughput_ops_sec)} ops / sec
       Avg Stateful Call Latency:    #{Float.round(avg_latency_us, 1)} µs (#{Float.round(avg_latency_us / 1000, 3)} ms)
       Cluster Event 50x Fanout:     #{Float.round(fanout_ms, 2)} ms
      ---------------------------------------------------------------
       Status:                       PASSED (All Production SLAs Met)
      ===============================================================
      """)
    end
  end
end
