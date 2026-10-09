defmodule Exoforge.Std.Metering do
  @moduledoc """
  Standard usage-metering plugin: persists the kernel's counters into the instance database.

  The kernel counts calls in ETS (`Exoforge.Metering`), which is the live truth but dies with the
  node. This plugin flushes the deltas since the last flush into its own isolated database as
  append-only rows, stamped with the instance's title and studio, and serves the rollup from there.
  Append-only keeps a late or repeated flush a correction rather than a lost update, and makes the
  rollup a `SUM`/`GROUP BY` - per plugin, summed to the title, summed to the studio.

  Records are shape, never content: plugin and action names, counts, durations, bytes, CPU and
  RSS. No payloads, no player identifiers.
  """

  use Exoforge.Plugin, provides: [:metering]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database],
    category: "Operations",
    # The Studio's generic extension view renders the `usage` action from this; without it the
    # plugin is invisible in the dashboard and the CLI is the only surface.
    dashboard_view: %{id: :metering, title: "Usage", icon: "📊"}
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Metering.Flusher

  def children, do: [Flusher]

  def on_init(_manifest) do
    init_schema()
    :ok
  end

  @doc "Creates the append-only usage tables in this plugin's isolated database."
  def init_schema do
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :metering,
        operation: """
        CREATE TABLE IF NOT EXISTS usage_actions (
          title_id text, studio_id text, plugin_id text, action text,
          period_start integer, period_end integer,
          invocations integer, errors integer, wall_us integer,
          bytes_in integer, bytes_out integer
        )
        """
      })

    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :metering,
        operation: """
        CREATE TABLE IF NOT EXISTS usage_plugins (
          title_id text, studio_id text, plugin_id text,
          period_start integer, period_end integer,
          events integer, host_calls integer, starts integer,
          cpu_ms integer, peak_rss_kb integer, uptime_ms integer
        )
        """
      })

    :ok
  end

  @impl true
  defaction usage(payload), scope: Exoforge.Auth.Roles.studio() do
    # The counters are live and the table is history, so flush first: the answer then covers
    # everything up to now rather than up to the last timer tick.
    Flusher.flush()

    plugin_id = Map.get(payload, :plugin_id) || Map.get(payload, "plugin_id")
    since = Map.get(payload, :since) || Map.get(payload, "since")

    actions = action_rows(plugin_id, since)
    plugins = plugin_rows(plugin_id, since)

    {:ok,
     %{
       title_id: Exoforge.Metering.title_id(),
       studio_id: Exoforge.Metering.studio_id(),
       plugins: build_plugins(actions, plugins),
       totals: totals(actions, plugins)
     }}
  end

  # -- queries --

  defp action_rows(plugin_id, since) do
    {where, args} = filters(plugin_id, since)

    select =
      "plugin_id, action, SUM(invocations) AS invocations, SUM(errors) AS errors, SUM(wall_us) AS wall_us, SUM(bytes_in) AS bytes_in, SUM(bytes_out) AS bytes_out"

    group = "GROUP BY plugin_id, action ORDER BY plugin_id, action"

    query("SELECT #{select} FROM usage_actions#{where} #{group}", args)
  end

  defp plugin_rows(plugin_id, since) do
    {where, args} = filters(plugin_id, since)

    select =
      "plugin_id, SUM(events) AS events, SUM(host_calls) AS host_calls, SUM(starts) AS starts, " <>
        "SUM(cpu_ms) AS cpu_ms, MAX(peak_rss_kb) AS peak_rss_kb, MAX(uptime_ms) AS uptime_ms"

    group = "GROUP BY plugin_id ORDER BY plugin_id"

    query("SELECT #{select} FROM usage_plugins#{where} #{group}", args)
  end

  # Both tables carry plugin_id and period_end, so one filter clause serves both queries.
  defp filters(nil, nil), do: {"", []}
  defp filters(plugin_id, nil), do: {" WHERE plugin_id = $1", [plugin_id]}
  defp filters(nil, since), do: {" WHERE period_end >= $1", [since]}

  defp filters(plugin_id, since),
    do: {" WHERE plugin_id = $1 AND period_end >= $2", [plugin_id, since]}

  defp query(sql, args) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :metering,
           operation: sql,
           arguments: args
         }) do
      {:ok, %{rows: rows}} when is_list(rows) -> rows
      _ -> []
    end
  end

  # -- rollup shape --

  defp build_plugins(actions, plugins) do
    actions_by_plugin = Enum.group_by(actions, & &1["plugin_id"])

    plugins
    |> Enum.map(fn row ->
      id = row["plugin_id"]
      starts = int(row["starts"])

      %{
        plugin_id: id,
        plugin: %{
          starts: starts,
          restarts: max(starts - 1, 0),
          events: int(row["events"]),
          host_calls: int(row["host_calls"]),
          cpu_ms: int(row["cpu_ms"]),
          peak_rss_kb: int(row["peak_rss_kb"]),
          uptime_ms: int(row["uptime_ms"])
        },
        actions: actions_for(Map.get(actions_by_plugin, id, []))
      }
    end)
  end

  defp actions_for(rows) do
    Enum.map(rows, fn row ->
      invocations = int(row["invocations"])
      wall_us = int(row["wall_us"])

      %{
        action: row["action"],
        invocations: invocations,
        errors: int(row["errors"]),
        wall_us: wall_us,
        avg_wall_us: if(invocations > 0, do: div(wall_us, invocations), else: 0),
        bytes_in: int(row["bytes_in"]),
        bytes_out: int(row["bytes_out"])
      }
    end)
  end

  defp totals(actions, plugins) do
    %{
      invocations: sum(actions, "invocations"),
      errors: sum(actions, "errors"),
      wall_us: sum(actions, "wall_us"),
      bytes_in: sum(actions, "bytes_in"),
      bytes_out: sum(actions, "bytes_out"),
      events: sum(plugins, "events"),
      host_calls: sum(plugins, "host_calls"),
      starts: sum(plugins, "starts"),
      cpu_ms: sum(plugins, "cpu_ms"),
      peak_rss_kb: Enum.reduce(plugins, 0, fn row, acc -> max(int(row["peak_rss_kb"]), acc) end)
    }
  end

  defp sum(rows, key), do: Enum.reduce(rows, 0, fn row, acc -> acc + int(row[key]) end)
  defp int(nil), do: 0
  defp int(value) when is_integer(value), do: value
  defp int(value) when is_float(value), do: trunc(value)
  defp int(_), do: 0
end
