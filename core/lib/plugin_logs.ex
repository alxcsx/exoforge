defmodule Exoforge.PluginLogs do
  # Declared before the moduledoc so the number can be stated in one place.
  @max_per_second 100

  @moduledoc """
  Bounded, in-memory record of the most recent log lines each plugin emitted.

  Plugin output used to go only to the server's `Logger`, which meant a game developer working in
  Unity had no way to watch their own plugin run — no log line, no swallowed exception, no sign of a
  plugin that booted and immediately died. The runners append here as well, and
  `plugin_manager.logs` serves the buffer to the CLI and the Studio.

  Deliberately not a log store: lines live in ETS, are capped per plugin, and are lost on restart.
  It answers "what did my plugin just do?", not "what happened last Tuesday".

  Past #{@max_per_second} lines in a second the plugin's lines are dropped before either the
  buffer or the server log sees them, so a plugin that logs in a tight loop cannot flood the
  operator's log or burn the VM feeding it. Dropping is silent: a flood guard that reports every
  dropped line is no guard at all.
  """

  @table :exo_plugin_logs
  @rate_table :exo_plugin_log_rate
  @max_lines 200

  @type level :: 0 | 1 | 2 | 3
  @type entry :: %{at: integer(), level: level(), level_name: String.t(), message: String.t()}

  @doc "The per-plugin ceiling on lines per second; `append/3` refuses the rest of the second past it."
  def rate_limit, do: @max_per_second

  @doc """
  Records one line for a plugin. Older lines are dropped past #{@max_lines} per plugin, and a plugin
  is held to #{@max_per_second} lines per second: past that nothing is recorded and `:rate_limited`
  is returned, so the line never reaches the server log either.

  The fourth argument is the clock the rate window is measured against, defaulting to the monotonic
  time. It exists so a test can cross a window without sleeping.
  """
  def append(plugin_id, level, message, now_ms \\ System.monotonic_time(:millisecond))

  def append(plugin_id, level, message, now_ms) when is_binary(message) do
    table = ensure_table()
    id = to_string(plugin_id)

    if allowed?(id, now_ms) do
      if :ets.select_count(table, [{{id, :_, :_, :_}, [], [true]}]) >= @max_lines do
        drop_oldest(table, id)
      end

      :ets.insert(table, {id, System.system_time(:millisecond), normalize_level(level), message})
      :ok
    else
      :rate_limited
    end
  end

  def append(_plugin_id, _level, _message, _now_ms), do: :ok

  @doc "Recent lines for a plugin, newest last. `limit` caps how many are returned."
  def list(plugin_id, limit \\ 100) do
    table = ensure_table()
    id = to_string(plugin_id)

    table
    |> :ets.lookup(id)
    |> Enum.map(fn {_id, at, level, message} ->
      %{at: at, level: level, level_name: level_name(level), message: message}
    end)
    |> Enum.sort_by(& &1.at)
    |> Enum.take(-max(limit, 1))
  end

  @doc "Drops every recorded line for a plugin (called when it is removed)."
  def clear(plugin_id) do
    id = to_string(plugin_id)
    :ets.delete(ensure_table(), id)
    :ets.delete(ensure_rate_table(), id)
    :ok
  end

  @doc "How many lines are currently held for a plugin."
  def count(plugin_id) do
    :ets.select_count(ensure_table(), [{{to_string(plugin_id), :_, :_, :_}, [], [true]}])
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined ->
        # `duplicate_bag`: several lines can share a millisecond, and we must keep them all.
        :ets.new(@table, [:duplicate_bag, :named_table, :public, read_concurrency: true])

      _ ->
        @table
    end
  end

  defp ensure_rate_table do
    case :ets.info(@rate_table) do
      :undefined ->
        :ets.new(@rate_table, [:set, :named_table, :public, write_concurrency: true])

      _ ->
        @rate_table
    end
  end

  # One counter per plugin per second window, so a flood is bounded without a timer that would
  # have to be cleaned up. The table holds at most one entry per plugin: the next line in a new
  # window overwrites it.
  defp allowed?(id, now_ms) do
    table = ensure_rate_table()
    window = div(now_ms, 1000)

    case :ets.lookup(table, id) do
      [{^id, ^window, count}] when count >= @max_per_second ->
        false

      [{^id, ^window, count}] ->
        :ets.insert(table, {id, window, count + 1})
        true

      _ ->
        :ets.insert(table, {id, window, 1})
        true
    end
  end

  defp drop_oldest(table, id) do
    case table |> :ets.lookup(id) |> Enum.min_by(fn {_id, at, _level, _msg} -> at end, fn -> nil end) do
      nil -> :ok
      oldest -> :ets.delete_object(table, oldest)
    end
  end

  # Levels mirror the C# HostBridge: 0 debug, 1 info, 2 warning, 3 error.
  defp normalize_level(level) when level in 0..3, do: level
  defp normalize_level(_), do: 1

  defp level_name(0), do: "debug"
  defp level_name(1), do: "info"
  defp level_name(2), do: "warning"
  defp level_name(3), do: "error"
  defp level_name(_), do: "info"
end
