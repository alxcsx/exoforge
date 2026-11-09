defmodule Exoforge.Std.Dashboard.RecentEvents do
  @moduledoc """
  In-memory ring buffer of recent cluster events and action dispatches.
  Supervised background worker that stays subscribed to EventDispatcher {:all, topic: :global}
  and persists all cluster events into ETS so the Studio overview and modals always
  have the real, cluster-wide event stream even across LiveView reconnections.
  """
  use GenServer

  @table :exo_dashboard_recent_events
  @max_events 50
  @pubsub_topic "studio_events"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    init_table()
    ensure_schema()
    warmup_from_db()

    # Subscribe to all events across all topics via the global fallback in EventDispatcher
    try do
      Exoforge.EventDispatcher.subscribe(:all, topic: :global)
    rescue
      _ -> :ok
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, state) do
    if duplicate?(event_key, payload) do
      {:noreply, state}
    else
      item = record(event_key, payload, context)

      try do
        Phoenix.PubSub.broadcast(Exoforge.Std.Dashboard.PubSub, @pubsub_topic, {:studio_event, item})
      rescue
        _ -> :ok
      end

      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

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

  @doc "Records a dispatched event or action invocation into the shared buffer."
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

  @doc "Returns the most recent events ordered newest first."
  def list(limit \\ 50) do
    init_table()

    try do
      case :ets.tab2list(@table) do
        [] ->
          warmup_from_db()

          case :ets.tab2list(@table) do
            [] -> []
            list ->
              list
              |> Enum.sort_by(&elem(&1, 0))
              |> Enum.take(limit)
              |> Enum.map(&elem(&1, 1))
          end

        list ->
          list
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.take(limit)
          |> Enum.map(&elem(&1, 1))
      end
    rescue
      _ -> []
    end
  end

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
          plugin: :dashboard,
          operation: "DELETE FROM recent_events"
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)
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
          plugin: :dashboard,
          operation: """
          INSERT INTO recent_events (id, event, payload, context, time, timestamp)
          VALUES ($1, $2, $3, $4, $5, $6)
          """,
          arguments: [
            item.id,
            item.event,
            payload_str,
            context_str,
            item.time,
            item.timestamp
          ]
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)
  end

  defp ensure_schema do
    case :ets.info(:exo_recent_events_schema) do
      :undefined ->
        case do_create_schema() do
          :ok ->
            try do
              :ets.new(:exo_recent_events_schema, [:named_table, :public, :set])
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
             plugin: :dashboard,
             operation: """
             CREATE TABLE IF NOT EXISTS recent_events (
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
             plugin: :dashboard,
             operation:
               "SELECT id, event, payload, context, time, timestamp FROM recent_events ORDER BY timestamp DESC LIMIT #{@max_events}"
           }) do
        {:ok, %{rows: rows}} when is_list(rows) ->
          Enum.each(rows, fn row ->
            case parse_db_row(row) do
              nil ->
                :ok

              item ->
                :ets.insert_new(@table, {-item.timestamp, item})
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
          nil -> %{}
          bin when is_binary(bin) ->
            case Jason.decode(bin) do
              {:ok, decoded} -> decoded
              _ -> bin
            end
          other -> other
        end

      context =
        case row["context"] do
          nil -> %{}
          bin when is_binary(bin) ->
            case Jason.decode(bin) do
              {:ok, decoded} -> decoded
              _ -> %{}
            end
          other -> other
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
