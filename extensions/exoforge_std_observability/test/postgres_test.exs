defmodule Exoforge.Std.Observability.PostgresTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database
  alias Exoforge.Std.Database.Adapters.Postgres
  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.Std.Database.TestDB
  alias Exoforge.Std.Observability
  alias Exoforge.Std.Observability.Events

  @moduletag :postgres

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(Exoforge.Std.Database.PoolRegistry) do
      start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Database.PoolRegistry})
    end

    unless Process.whereis(Exoforge.Std.Database.PoolSupervisor) do
      start_supervised!({DynamicSupervisor, name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one})
    end

    if pid = Process.whereis(DbManager) do
      stop_supervised!(DbManager)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end

    start_supervised!(DbManager)
    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)

    Exoforge.ExtensionCase.register_extension(Observability,
      id: :exoforge_std_observability,
      provides: [Exoforge.Std.Services.Observability],
      dependencies: [Exoforge.Std.Services.Database]
    )

    if :ets.info(:exo_observability_events_schema) != :undefined do
      :ets.delete(:exo_observability_events_schema)
    end

    Database.reset!(:observability)
    Database.execute(:observability, "SELECT 1", [])

    on_exit(fn ->
      if :ets.info(:exo_observability_events_schema) != :undefined do
        :ets.delete(:exo_observability_events_schema)
      end

      _ = Postgres.reset(:observability, TestDB.config())
    end)

    :ok
  end

  test "F33(c): schema creation on fresh Postgres succeeds without duplicate-column ALTER errors" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        unless Process.whereis(Events) do
          start_supervised!(Events)
        end

        Events.flush!()
      end)

    refute log =~ "already exists"
    assert :ets.info(:exo_observability_events_schema) != :undefined
  end

  test "F33(a): millisecond timestamps persist in events without int4 overflow" do
    unless Process.whereis(Events) do
      start_supervised!(Events)
    end

    item = Events.record("action:pg.test", %{ok: true}, %{origin: "p1", rid: "r_pg_1"})
    Events.flush!()

    assert {:ok, %{rows: rows}} =
             Database.execute(:observability, "SELECT at, timestamp FROM events WHERE rid = $1", ["r_pg_1"])

    at = item.at
    ts = at * 1000
    assert [%{"at" => ^at, "timestamp" => ^ts}] = rows
  end

  test "F33(b): rollup upsert qualifies table column n without ambiguous-column error" do
    unless Process.whereis(Events) do
      start_supervised!(Events)
    end

    ms = 1_795_010_740_821
    Events.record("action:pg.rollup", %{ok: true}, %{origin: "p1", rid: "r_pg_r1", at: ms})
    Events.record("action:pg.rollup", %{ok: true}, %{origin: "p1", rid: "r_pg_r2", at: ms})
    Events.flush!()

    assert {:ok, %{rows: rows}} =
             Database.execute(
               :observability,
               "SELECT n FROM event_rollups WHERE event = $1 AND origin = $2",
               ["action:pg.rollup", "p1"]
             )

    assert [%{"n" => n}] = rows
    assert n >= 2
  end
end
