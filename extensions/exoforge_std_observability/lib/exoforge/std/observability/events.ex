defmodule Exoforge.Std.Observability.Events do
  @moduledoc """
  The cluster-wide event history: a ring in ETS for the live tail, and the persisted store the
  Studio and the other surfaces read through `observability.recent_events`.

  One subscriber for the whole node, on the global event bus. Events are deduplicated inside a
  short window (the same broadcast can be delivered through more than one subscription) and
  written asynchronously to this extension's isolated database; a write failure never blocks the
  stream. Retention, roll-ups and the cold archive build on this table (M42).
  """
  use GenServer

  @table :exo_observability_events
  @max_events 50
  @db_table "events"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    init_table()
    ensure_schema()
    warmup_from_db()

    try do
      Exoforge.EventDispatcher.subscribe(:all, topic: :global)
    rescue
      _ -> :ok
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, state) do
    unless duplicate?(event_key, payload) do
      record(event_key, payload, context)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp duplicate?(event_key, payload) do
    key_str = to_string(event_key)
    recent = list(5)
    now_us = System.system_time(:microsecond)

    Enum.any?(recent, fn e ->
      to_string(e[:event]) == key_str and
        e[:payload] == payload and
        now_us - Map.get(e, :timestamp, 0) < 1_500_000
    end)
  end

  def init_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :ordered_set])
        rescue
          _ -> @table
        end

      _ ->
        @table
    end
  end

  @doc "Records one event into the ring and persists it asynchronously."
  def record(event_key, payload, context \\ %{}) do
    init_table()
    id = "ev_#{System.unique_integer([:positive])}"
    time = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")

    item = %{
      id: id,
      event: to_string(event_key),
      payload: payload,
      context: context,
      time: time,
      timestamp: System.system_time(:microsecond)
    }

    try do
      :ets.insert(@table, {-item.timestamp, item})
      trim()
    rescue
      _ -> :ok
    end

    persist_async(item)

    item
  end

  @doc "The most recent events, newest first."
  def list(limit \\ 50) do
    init_table()

    try do
      case :ets.tab2list(@table) do
        [] ->
          warmup_from_db()

          case :ets.tab2list(@table) do
            [] -> []
            list -> sort_and_take(list, limit)
          end

        list ->
          sort_and_take(list, limit)
      end
    rescue
      _ -> []
    end
  end

  @doc "The stored events of one request, oldest first."
  def for_rid(rid) when is_binary(rid) and rid != "" do
    list(@max_events)
    |> Enum.filter(fn event ->
      context = Map.get(event, :context) || %{}
      to_string(context[:rid] || context["rid"] || "") == rid
    end)
    |> Enum.reverse()
  end

  def for_rid(_), do: []

  @doc "Drops the ring and the persisted history (a Studio/admin reset)."
  def clear do
    init_table()

    try do
      :ets.delete_all_objects(@table)
    rescue
      _ -> :ok
    end

    Task.start(fn ->
      try do
        Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
          plugin: :observability,
          operation: "DELETE FROM #{@db_table}"
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  defp sort_and_take(list, limit) do
    list
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 1))
  end

  defp trim do
    if :ets.info(@table, :size) > @max_events do
      keys = :ets.select_reverse(@table, [{{:"$1", :_}, [], [:"$1"]}], 10)

      case keys do
        {drop_keys, _} -> Enum.each(drop_keys, &:ets.delete(@table, &1))
        _ -> :ok
      end
    end
  rescue
    _ -> :ok
  end

  defp persist_async(item) do
    Task.start(fn ->
      try do
        ensure_schema()

        payload_str =
          case Jason.encode(item.payload) do
            {:ok, bin} -> bin
            _ -> inspect(item.payload)
          end

        context_str =
          case Jason.encode(item.context) do
            {:ok, bin} -> bin
            _ -> "{}"
          end

        Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
          plugin: :observability,
          operation: """
          INSERT INTO #{@db_table} (id, event, payload, context, time, timestamp)
          VALUES ($1, $2, $3, $4, $5, $6)
          """,
          arguments: [item.id, item.event, payload_str, context_str, item.time, item.timestamp]
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)
  end

  defp ensure_schema do
    case :ets.info(:exo_observability_events_schema) do
      :undefined ->
        case do_create_schema() do
          :ok ->
            try do
              :ets.new(:exo_observability_events_schema, [:named_table, :public, :set])
            rescue
              _ -> :ok
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp do_create_schema do
    try do
      case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
             plugin: :observability,
             operation: """
             CREATE TABLE IF NOT EXISTS #{@db_table} (
               id text PRIMARY KEY,
               event text,
               payload text,
               context text,
               time text,
               timestamp integer
             )
             """
           }) do
        {:ok, _} -> :ok
        :ok -> :ok
        _ -> :retry
      end
    rescue
      _ -> :retry
    catch
      _, _ -> :retry
    end
  end

  defp warmup_from_db do
    ensure_schema()

    try do
      case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
             plugin: :observability,
             operation:
               "SELECT id, event, payload, context, time, timestamp FROM #{@db_table} " <>
                 "ORDER BY timestamp DESC LIMIT #{@max_events}"
           }) do
        {:ok, %{rows: rows}} when is_list(rows) ->
          Enum.each(rows, fn row ->
            case parse_db_row(row) do
              nil -> :ok
              item -> :ets.insert_new(@table, {-item.timestamp, item})
            end
          end)

        _ ->
          :ok
      end
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp parse_db_row(row) do
    try do
      payload =
        case row["payload"] do
          nil ->
            %{}

          bin when is_binary(bin) ->
            case Jason.decode(bin) do
              {:ok, decoded} -> decoded
              _ -> bin
            end

          other ->
            other
        end

      context =
        case row["context"] do
          nil ->
            %{}

          bin when is_binary(bin) ->
            case Jason.decode(bin) do
              {:ok, decoded} -> decoded
              _ -> %{}
            end

          other ->
            other
        end

      %{
        id: to_string(row["id"]),
        event: to_string(row["event"]),
        payload: payload,
        context: context,
        time: to_string(row["time"]),
        timestamp: String.to_integer(to_string(row["timestamp"] || "0"))
      }
    rescue
      _ -> nil
    end
  end
end
