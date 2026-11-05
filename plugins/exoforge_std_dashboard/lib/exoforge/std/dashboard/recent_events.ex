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
    item = record(event_key, payload, context)

    try do
      Phoenix.PubSub.broadcast(Exoforge.Std.Dashboard.PubSub, @pubsub_topic, {:studio_event, item})
    rescue
      _ -> :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
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

    item
  end

  @doc "Returns the most recent events ordered newest first."
  def list(limit \\ 50) do
    init_table()

    try do
      case :ets.tab2list(@table) do
        [] -> []
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
end
