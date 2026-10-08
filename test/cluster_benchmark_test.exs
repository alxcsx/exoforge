defmodule Exoforge.ClusterBenchmarkTest do
  use ExUnit.Case, async: false

  setup_all do
    # Ensure :exo_cluster_pg is running
    case :pg.start_link(:exo_cluster_pg) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  # The entity benchmark that used to live here went with the entity runtime. What is left is the half
  # that measures something the platform still does: fanout to subscribers over `:pg`, which is the
  # path a live board or a chat room actually uses.
  describe "Cluster Event Fanout Benchmark" do
    test "fans one event out to 50 subscribers" do
      subscriber_count = 50
      test_pid = self()

      _subscribers =
        for i <- 1..subscriber_count do
          spawn_link(fn ->
            {:ok, _} = Exoforge.EventDispatcher.subscribe(:benchmark_ping, topic: "bench:events")
            send(test_pid, {:ready, i})

            receive do
              {:exo_event, :benchmark_ping, _payload, _ctx} -> send(test_pid, {:received, i})
            end
          end)
        end

      # Wait for all subscribers to register
      for _ <- 1..subscriber_count do
        assert_receive {:ready, _}, 1000
      end

      {fanout_us, _} =
        :timer.tc(fn ->
          Exoforge.EventDispatcher.broadcast(:benchmark_ping, %{ts: System.os_time()},
            topic: "bench:events"
          )

          for _ <- 1..subscriber_count do
            assert_receive {:received, _}, 1000
          end
        end)

      fanout_ms = fanout_us / 1000

      assert fanout_ms < 50.0, "Event fanout to 50 subscribers must be < 50ms"

      IO.puts("""

      ===============================================================
                    EXOFORGE CLUSTER BENCHMARK SCORECARD
      ===============================================================
       Concurrent Event Subscribers: #{subscriber_count}
      ---------------------------------------------------------------
       Cluster Event 50x Fanout:     #{Float.round(fanout_ms, 2)} ms
      ---------------------------------------------------------------
       Status:                       PASSED (Production SLA Met)
      ===============================================================
      """)
    end
  end
end
