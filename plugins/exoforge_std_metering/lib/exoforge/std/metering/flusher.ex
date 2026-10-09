defmodule Exoforge.Std.Metering.Flusher do
  @moduledoc """
  Moves the kernel's counters into the metering database on a timer.

  `Exoforge.Metering` holds cumulative totals for the life of the node; the database holds deltas,
  an append-only row group per period per plugin. A flush writes `current - last`, so a flush that
  runs twice writes nothing the second time, and one that runs late writes one larger group rather
  than losing an update. A graceful stop flushes; a crash loses at most `@interval_ms` of counters.
  """
  use GenServer
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.Metering

  # A minute keeps the write rate trivial while making a hard crash lose at most a minute. `VmHWM`
  # is a high-water mark, so a memory spike between flushes is not lost to the interval.
  @interval_ms 60_000
  @name __MODULE__

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: @name)

  @doc "Flushes now, so a query can rely on the table being current."
  def flush, do: GenServer.call(@name, :flush, 15_000)

  @impl true
  def init(_opts) do
    state = %{last: empty_memory(), period_start: System.system_time(:second), timer: schedule()}
    {:ok, state}
  end

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, :ok, flush_state(state)}

  @impl true
  def handle_info(:flush, state) do
    {:noreply, %{flush_state(state) | timer: schedule()}}
  end

  @impl true
  def terminate(_reason, state) do
    # A graceful stop is the last chance to persist this period; a crash is not.
    _ = flush_state(state)
    :ok
  end

  defp schedule, do: Process.send_after(self(), :flush, @interval_ms)

  defp flush_state(state) do
    now = System.system_time(:second)
    snapshot = Metering.snapshot()
    title_id = Metering.title_id()
    studio_id = Metering.studio_id()

    action_rows =
      action_deltas(snapshot.plugins, state.last.actions, title_id, studio_id, state.period_start, now)

    plugin_rows =
      plugin_deltas(snapshot.plugins, state.last.plugins, title_id, studio_id, state.period_start, now)

    persist(action_rows, plugin_rows)

    %{state | last: current_memory(snapshot.plugins), period_start: now}
  end

  # -- deltas --

  defp action_deltas(plugins, last, title_id, studio_id, period_start, period_end) do
    for plugin <- plugins,
        action <- plugin.actions,
        previous = Map.get(last, {plugin.plugin_id, action.action}, %{}) do
      row = %{
        invocations: action.invocations - Map.get(previous, :invocations, 0),
        errors: action.errors - Map.get(previous, :errors, 0),
        wall_us: action.wall_us - Map.get(previous, :wall_us, 0),
        bytes_in: action.bytes_in - Map.get(previous, :bytes_in, 0),
        bytes_out: action.bytes_out - Map.get(previous, :bytes_out, 0)
      }

      if Enum.any?(Map.values(row), &(&1 != 0)) do
        [
          title_id,
          studio_id,
          plugin.plugin_id,
          action.action,
          period_start,
          period_end,
          row.invocations,
          row.errors,
          row.wall_us,
          row.bytes_in,
          row.bytes_out
        ]
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp plugin_deltas(plugins, last, title_id, studio_id, period_start, period_end) do
    Enum.map(plugins, fn plugin ->
      id = plugin.plugin_id
      previous = Map.get(last, id, %{})
      uptime_ms = plugin.plugin.uptime_ms || 0

      # Always a row: uptime is a gauge for the period, so an idle plugin still says it was up.
      [
        title_id,
        studio_id,
        id,
        period_start,
        period_end,
        plugin.plugin.events - Map.get(previous, :events, 0),
        plugin.plugin.host_calls - Map.get(previous, :host_calls, 0),
        plugin.plugin.starts - Map.get(previous, :starts, 0),
        plugin.plugin.cpu_ms - Map.get(previous, :cpu_ms, 0),
        plugin.plugin.peak_rss_kb,
        uptime_ms
      ]
    end)
  end

  defp current_memory(plugins) do
    Enum.reduce(plugins, empty_memory(), fn plugin, acc ->
      acc =
        put_in(acc.plugins[plugin.plugin_id], %{
          events: plugin.plugin.events,
          host_calls: plugin.plugin.host_calls,
          starts: plugin.plugin.starts,
          cpu_ms: plugin.plugin.cpu_ms,
          peak_rss_kb: plugin.plugin.peak_rss_kb
        })

      Enum.reduce(plugin.actions, acc, fn action, acc ->
        put_in(acc.actions[{plugin.plugin_id, action.action}], %{
          invocations: action.invocations,
          errors: action.errors,
          wall_us: action.wall_us,
          bytes_in: action.bytes_in,
          bytes_out: action.bytes_out
        })
      end)
    end)
  end

  defp empty_memory, do: %{actions: %{}, plugins: %{}}

  # -- persistence --

  @insert_actions """
  INSERT INTO usage_actions
    (title_id, studio_id, plugin_id, action, period_start, period_end,
     invocations, errors, wall_us, bytes_in, bytes_out)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
  """

  @insert_plugins """
  INSERT INTO usage_plugins
    (title_id, studio_id, plugin_id, period_start, period_end,
     events, host_calls, starts, cpu_ms, peak_rss_kb, uptime_ms)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
  """

  defp persist(action_rows, plugin_rows) do
    Enum.each(action_rows, &insert(@insert_actions, &1))
    Enum.each(plugin_rows, &insert(@insert_plugins, &1))
  end

  defp insert(sql, args) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :metering,
           operation: sql,
           arguments: args
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("[Metering] flush failed: #{inspect(reason)}")
    end
  end
end
