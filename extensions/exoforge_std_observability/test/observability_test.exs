defmodule Exoforge.Std.ObservabilityTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.Std.Observability
  alias Exoforge.Std.Observability.Analytics
  alias Exoforge.Std.Observability.Events

  # A service with a visible side effect, so replay can be observed rather than inferred.
  defmodule CounterService do
    import Exoforge.Contracts.Service

    defservice counter do
      action :bump do
        params(by: [type: :integer, optional: true])
        returns(total: :integer)
      end
    end
  end

  defmodule CounterPlugin do
    use Exoforge.Extension, provides: [Exoforge.Std.ObservabilityTest.CounterService.Counter]

    @impl true
    defaction bump(payload) do
      by = Map.get(payload, "by") || Map.get(payload, :by) || 1
      total = :ets.update_counter(:obs_counter, :n, {2, by}, {:n, 0})
      {:ok, %{total: total}}
    end
  end

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

    Exoforge.ExtensionCase.register_extension(CounterPlugin,
      id: :counter_plugin,
      provides: [CounterService.Counter]
    )

    if :ets.info(:obs_counter) == :undefined do
      :ets.new(:obs_counter, [:named_table, :public, :set])
    end

    :ets.insert(:obs_counter, {:n, 0})
    Exoforge.DebugCapture.stop_all()

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

  test "events persist with day, origin, rid and status, and roll up by hour" do
    Events.record(
      "action:auth.login",
      %{status: "ok"},
      %{origin: "alice", rid: "r_persist", topic: "global"}
    )

    Events.flush!()

    %{events: [event], total: 1} = Events.page(%{rid: "r_persist"})
    assert event.event == "action:auth.login"
    assert event.origin == "alice"
    assert event.status == "ok"
    assert event.day == Date.utc_today() |> Date.to_iso8601()
    assert event.rid == "r_persist"

    [row | _] =
      Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :observability,
        operation: "SELECT n FROM event_rollups WHERE day = $1 AND event = $2 AND origin = $3",
        arguments: [event.day, "action:auth.login", "alice"]
      })
      |> elem(1)
      |> Map.get(:rows)

    assert row["n"] == 1
  end

  test "a capture keeps the full request, and replay dispatches it again for the same caller" do
    assert {:ok, %{capture: %{kind: "player", value: "alice"}}} =
             ActionDispatcher.dispatch_internal(:observability, :capture, %{
               kind: "player",
               value: "alice",
               seconds: 60
             })

    assert {:ok, %{total: 1}} =
             ActionDispatcher.dispatch(CounterService.Counter, :bump, %{"by" => 1},
               caller: "alice",
               caller_scopes: [:player],
               rid: "r_replay_src"
             )

    assert {:ok, %{captures: [%{kind: "player", value: "alice", remaining_s: _}]}} =
             ActionDispatcher.dispatch_internal(:observability, :captures, %{})

    [sample] = Enum.filter(Exoforge.ActionTrace.recent_samples(20), &(&1.rid == "r_replay_src"))
    assert %{payload: %{"by" => 1}} = Exoforge.ActionTrace.deep_sample(sample.id)

    assert {:ok,
            %{source_rid: "r_replay_src", rid: new_rid, status: %{status: "ok", data: result}}} =
             ActionDispatcher.dispatch_internal(:observability, :replay, %{id: sample.id})

    assert result == %{total: 2}
    assert new_rid =~ ~r/^r_/

    # The replay is a real request: a new rid, the same caller, traced.
    assert Enum.any?(
             Exoforge.ActionTrace.recent_samples(20),
             &(&1.rid == new_rid and &1.caller == "alice")
           )

    assert {:ok, %{status: "stopped"}} =
             ActionDispatcher.dispatch_internal(:observability, :stop_capture, %{
               kind: "player",
               value: "alice"
             })

    assert {:ok, %{captures: []}} =
             ActionDispatcher.dispatch_internal(:observability, :captures, %{})
  end

  test "replay refuses a sample that was not captured" do
    assert {:error, :not_captured} =
             ActionDispatcher.dispatch_internal(:observability, :replay, %{id: 1})
  end

  test "health reports 30-minute rates, percentiles and an attention list" do
    assert {:error, :service_not_found} =
             ActionDispatcher.dispatch(:ghost_slow, :do_thing, %{}, caller: "alice")

    assert {:ok, %{rows: rows, attention: attention}} =
             ActionDispatcher.dispatch_internal(:observability, :health, %{limit: 10})

    row = Enum.find(rows, &(&1.action == "do_thing"))
    assert row
    assert row.calls_30m >= 1
    assert row.errors_30m >= 1
    assert row.error_rate > 0
    assert is_float(row.p50_ms)
    assert row.p95_ms >= row.p50_ms

    assert Enum.any?(attention, &(&1.kind == "error" and &1.label =~ "ghost_slow"))
  end

  test "retention archives an old day to gzip, then drops the rows, and the archive answers queries" do
    dir = Path.join(System.tmp_dir!(), "exo-archive-#{System.unique_integer([:positive])}")
    System.put_env("EXOFORGE_EVENT_ARCHIVE_DIR", dir)

    on_exit(fn ->
      System.delete_env("EXOFORGE_EVENT_ARCHIVE_DIR")
      File.rm_rf(dir)
    end)

    old_day = Date.utc_today() |> Date.add(-60) |> Date.to_iso8601()

    old_at =
      DateTime.new!(Date.from_iso8601!(old_day), ~T[12:00:00], "Etc/UTC")
      |> DateTime.to_unix(:millisecond)

    assert {:ok, _} =
             ActionDispatcher.dispatch_internal(:database, :execute, %{
               plugin: :observability,
               operation:
                 "INSERT INTO events (id, at, day, event, origin, rid, status, payload, context, time, timestamp) " <>
                   "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
               arguments: [
                 "ev_archived",
                 old_at,
                 old_day,
                 "action:player_data.get_player",
                 "alice",
                 "r_archived",
                 "error: :not_found",
                 ~s({"player_id":"alice"}),
                 ~s({"origin":"alice","rid":"r_archived"}),
                 "12:00:00",
                 old_at * 1000
               ]
             })

    assert [^old_day] = Events.maintain()

    path = Path.join(dir, "events-#{old_day}.ndjson.gz")
    assert File.exists?(path)

    [line | _] = File.stream!(path, [:compressed, :utf8], :line) |> Enum.take(1)
    archived = Jason.decode!(line)
    assert archived["rid"] == "r_archived"
    assert archived["day"] == old_day

    # The hot table no longer has it; the archive catalog does.
    assert Events.page(%{rid: "r_archived"}).events == []

    assert [%{"day" => ^old_day}] =
             ActionDispatcher.dispatch_internal(:database, :execute, %{
               plugin: :observability,
               operation: "SELECT day FROM event_archives WHERE day = $1",
               arguments: [old_day]
             })
             |> elem(1)
             |> Map.get(:rows)

    # An old request id is still findable, and the timeline includes its archived event.
    assert [%{rid: "r_archived"}] = Events.for_rid("r_archived")
    assert Enum.any?(Analytics.timeline(%{rid: "r_archived"}), &(&1.kind == :event))
  end

  test "log lines survive the memory buffer and are found by request id in the table" do
    rid = "r_log_db"

    previous =
      Exoforge.RequestContext.enter(%{origin: "alice", rid: rid, depth: 0, capture: :off})

    :ok = Exoforge.ExtensionLogs.append(:db_log_plugin, 1, "persisted line")
    Exoforge.RequestContext.restore(previous)

    # Persistence is asynchronous.
    :timer.sleep(200)
    :ets.delete_all_objects(:exo_extension_logs)

    entries = Exoforge.ExtensionLogs.entries_for_rid(rid)
    assert Enum.any?(entries, &(&1.message == "persisted line"))
  end

  test "purge_origin drops one caller's hot events" do
    Events.record("action:auth.login", %{}, %{origin: "alice", rid: "r_purge"})
    Events.record("action:auth.login", %{}, %{origin: "bob", rid: "r_keep"})
    Events.flush!()

    Events.purge_origin("alice")

    assert Events.page(%{rid: "r_purge"}).events == []
    assert [_] = Events.page(%{rid: "r_keep"}).events
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
