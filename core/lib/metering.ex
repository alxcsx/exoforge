defmodule Exoforge.Metering do
  @moduledoc """
  Per-plugin usage counters: what was called, how long it took, how many bytes it moved.

  Process-per-plugin is what makes this cheap and honest. The runner owns the plugin's stdio port,
  so it sees every action result, event and host call without asking the plugin to count itself, and
  the OS can account for the plugin process's CPU and memory from outside the BEAM. The counters
  live in ETS and are stamped with the instance's `title_id` and `studio_id`, the shape a rollup
  needs: usage belongs to a plugin, a plugin to a title, a title to a studio, and the sum is a
  `GROUP BY`. One studio and one title today, so both ids are constant - the shape is what matters
  now (see plan.md, M32).

  Shape, never content: plugin and action names, counts, durations, byte sizes. Never payloads,
  never player or user identifiers. That is what makes "on by default" defensible.
  """

  @table :exo_metering

  @doc "Records one action call, with the wall time and wire bytes the runner observed."
  def record_invocation(plugin_id, action, duration_us, status, bytes_in, bytes_out) do
    id = to_string(plugin_id)
    action = to_string(action)

    incr({:action, id, action, :invocations}, 1)
    if status != :ok, do: incr({:action, id, action, :errors}, 1)
    incr({:action, id, action, :wall_us}, duration_us)
    incr({:action, id, action, :bytes_in}, bytes_in)
    incr({:action, id, action, :bytes_out}, bytes_out)
    :ok
  end

  @doc "Records one event forwarded to the plugin."
  def record_event(plugin_id, event) do
    id = to_string(plugin_id)
    event = to_string(event)

    incr({:plugin, id, :events}, 1)
    incr({:event, id, event, :count}, 1)
    :ok
  end

  @doc "Records one host call the plugin made into the cluster."
  def record_host_call(plugin_id, op) do
    id = to_string(plugin_id)
    op = to_string(op)

    incr({:plugin, id, :host_calls}, 1)
    incr({:host_call, id, op, :count}, 1)
    :ok
  end

  @doc """
  Records a runner start. The first is the plugin's uptime origin; every one after it is a restart,
  which is the number that says a plugin is crash-looping.
  """
  def record_start(plugin_id) do
    id = to_string(plugin_id)
    starts = incr({:plugin, id, :starts}, 1)
    :ets.insert(ensure_table(), {{:plugin, id, :started_at}, System.system_time(:millisecond)})
    starts
  end

  @doc "Usage for one plugin, or for every plugin when `plugin_id` is nil."
  def snapshot(plugin_id \\ nil) do
    wanted = if plugin_id, do: to_string(plugin_id)
    now = System.system_time(:millisecond)

    plugins =
      ensure_table()
      |> :ets.tab2list()
      |> Enum.filter(fn {key, _value} -> is_nil(wanted) or elem(key, 1) == wanted end)
      |> Enum.group_by(fn {key, _value} -> elem(key, 1) end)
      |> Enum.map(fn {id, rows} -> plugin_usage(id, rows, now) end)
      |> Enum.sort_by(& &1.plugin_id)

    %{
      title_id: title_id(),
      studio_id: studio_id(),
      generated_at: now,
      plugins: plugins
    }
  end

  @doc "The tenant this instance belongs to: one Title today, with the studio as the billing account."
  def title_id, do: Keyword.get(instance(), :title_id, "local")

  @doc "The studio the title rolls up to."
  def studio_id, do: Keyword.get(instance(), :studio_id, "local")

  # -- internals --

  defp instance, do: Application.get_env(:exoforge, :instance, [])

  @doc """
  Samples the plugin's OS process: cumulative CPU and the high-water RSS mark.

  Linux reads these from `/proc`: `utime + stime` in clock ticks, `VmHWM` in kB. `VmHWM` is a peak
  for the process's lifetime, so the stored value is a max across restarts; CPU is cumulative per
  pid, so the stored value accumulates deltas. On anything without `/proc` this is a no-op.
  """
  def sample_os(plugin_id, os_pid) when is_integer(os_pid) do
    with {:ok, ticks} <- read_cpu_ticks(os_pid),
         {:ok, peak_kb} <- read_peak_rss_kb(os_pid) do
      id = to_string(plugin_id)
      # USER_HZ is 100 on every Linux this runs on; the division keeps the unit honest anyway.
      # ponytail: fixed USER_HZ, read sysconf if a platform ever disagrees.
      add_cpu(id, os_pid, div(ticks * 1000, 100))
      keep_peak_rss(id, peak_kb)
      :ok
    else
      _ -> :ok
    end
  end

  def sample_os(_plugin_id, _os_pid), do: :ok

  defp add_cpu(id, os_pid, cpu_ms) do
    table = ensure_table()

    delta =
      case :ets.lookup(table, {:plugin, id, :cpu_last}) do
        [{{:plugin, ^id, :cpu_last}, {^os_pid, previous_ms}}] when cpu_ms >= previous_ms ->
          cpu_ms - previous_ms

        # A pid we have not seen is a process that just started, and its counter starts at zero.
        _ ->
          cpu_ms
      end

    :ets.insert(table, {{:plugin, id, :cpu_last}, {os_pid, cpu_ms}})
    incr({:plugin, id, :cpu_ms}, delta)
  end

  defp keep_peak_rss(id, peak_kb) do
    table = ensure_table()
    previous = current_peak_rss(table, id)
    if peak_kb > previous, do: :ets.insert(table, {{:plugin, id, :peak_rss_kb}, peak_kb})
    :ok
  end

  defp current_peak_rss(table, id) do
    case :ets.lookup(table, {:plugin, id, :peak_rss_kb}) do
      [{{:plugin, ^id, :peak_rss_kb}, kb}] -> kb
      _ -> 0
    end
  end

  defp read_cpu_ticks(os_pid) do
    with {:ok, stat} <- File.read("/proc/#{os_pid}/stat") do
      # The comm field is parenthesised and may contain spaces, so fields are counted from after
      # the last `)`: index 11 is utime and 12 is stime when the first token is `state`.
      fields = stat |> String.split(")") |> List.last() |> String.split()

      with [utime, stime] <- Enum.slice(fields, 11, 2),
           {u, ""} <- Integer.parse(utime),
           {s, ""} <- Integer.parse(stime) do
        {:ok, u + s}
      else
        _ -> :error
      end
    end
  end

  defp read_peak_rss_kb(os_pid) do
    with {:ok, status} <- File.read("/proc/#{os_pid}/status") do
      case Regex.run(~r/^VmHWM:\s+(\d+)\s+kB/m, status) do
        [_, kb] -> {:ok, String.to_integer(kb)}
        _ -> :error
      end
    end
  end

  defp plugin_usage(id, rows, now) do
    plugin = for {{:plugin, ^id, field}, value} <- rows, into: %{}, do: {field, value}
    started_at = Map.get(plugin, :started_at)
    starts = Map.get(plugin, :starts, 0)

    actions =
      rows
      |> Enum.filter(&match?({{:action, ^id, _action, _field}, _value}, &1))
      |> Enum.group_by(
        fn {{:action, _id, action, _field}, _value} -> action end,
        fn {key, value} -> {elem(key, 3), value} end
      )
      |> Enum.map(fn {action, fields} -> action_usage(action, Map.new(fields)) end)
      |> Enum.sort_by(& &1.action)

    events = for {{:event, ^id, event, :count}, count} <- rows, do: %{event: event, count: count}

    host_calls =
      for {{:host_call, ^id, op, :count}, count} <- rows, do: %{op: op, count: count}

    %{
      plugin_id: id,
      plugin: %{
        starts: starts,
        restarts: max(starts - 1, 0),
        started_at: started_at,
        uptime_ms: if(started_at, do: now - started_at, else: nil),
        cpu_ms: Map.get(plugin, :cpu_ms, 0),
        peak_rss_kb: Map.get(plugin, :peak_rss_kb, 0),
        events: Map.get(plugin, :events, 0),
        host_calls: Map.get(plugin, :host_calls, 0)
      },
      actions: actions,
      events: Enum.sort_by(events, & &1.event),
      host_calls: Enum.sort_by(host_calls, & &1.op)
    }
  end

  defp action_usage(action, fields) do
    invocations = Map.get(fields, :invocations, 0)
    wall_us = Map.get(fields, :wall_us, 0)

    %{
      action: action,
      invocations: invocations,
      errors: Map.get(fields, :errors, 0),
      wall_us: wall_us,
      avg_wall_us: if(invocations > 0, do: div(wall_us, invocations), else: 0),
      bytes_in: Map.get(fields, :bytes_in, 0),
      bytes_out: Map.get(fields, :bytes_out, 0)
    }
  end

  defp incr(key, amount) do
    :ets.update_counter(ensure_table(), key, {2, amount}, {key, 0})
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> Exoforge.TableOwner.ensure_started()
      _ -> @table
    end

    init_table()
  end

  @doc "Creates the table if it does not exist. Called by `Exoforge.TableOwner`, its owner."
  def init_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:set, :named_table, :public, write_concurrency: true])
      _ -> @table
    end
  end
end
