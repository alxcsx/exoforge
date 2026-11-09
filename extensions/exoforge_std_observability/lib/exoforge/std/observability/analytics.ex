defmodule Exoforge.Std.Observability.Analytics do
  @moduledoc """
  Joins one request back together from the kernel's bounded diagnostics and the event history.

  A timeline is a view, not a new store: the trace keeps the recent samples per action (and, when
  a request is captured, its queries and host calls), the event store keeps the last events, the
  log buffer keeps the lines, and the error groups keep the failures. All of it is joined on the
  request id (or the caller, for a player's recent activity), ordered by time, and indented by the
  dispatch depth the trace recorded.
  """

  alias Exoforge.Std.Observability.Events

  @default_limit 200
  @recent_sample_limit 2_000

  @doc """
  Nodes for one request (`:rid`) or one caller's recent activity (`:player`), oldest first.

  `:since_ms` drops anything older; `:limit` caps the result.
  """
  def timeline(opts) do
    rid = opts[:rid]
    player = opts[:player]
    since = opts[:since_ms] || 0
    limit = opts[:limit] || @default_limit

    cond do
      is_binary(rid) and rid != "" ->
        (trace_nodes(rid, since) ++
           event_nodes(rid, since) ++ log_nodes(rid, since) ++ error_nodes(rid, since))
        |> sort_and_cap(limit)

      is_binary(player) and player != "" ->
        (caller_trace_nodes(player, since) ++
           origin_event_nodes(player, since) ++ caller_error_nodes(player, since))
        |> sort_and_cap(limit)

      true ->
        []
    end
  end

  ## ---- nodes ----

  defp trace_nodes(rid, since) do
    Exoforge.ActionTrace.for_rid(rid)
    |> Enum.filter(&(&1.at >= since))
    |> Enum.map(&trace_node/1)
  end

  defp caller_trace_nodes(player, since) do
    player = to_string(player)

    Exoforge.ActionTrace.recent_samples(@recent_sample_limit)
    |> Enum.filter(&(to_string(&1.caller) == player and &1.at >= since))
    |> Enum.map(&trace_node/1)
  end

  defp trace_node(sample) do
    %{
      kind: Map.get(sample, :kind) || :action,
      at: sample.at,
      depth: Map.get(sample, :depth) || 0,
      label: sample.key,
      rid: sample.rid,
      caller: sample.caller,
      status: sample.status,
      duration_ms: sample.duration_ms,
      internal: Map.get(sample, :internal, false),
      request: sample.request,
      response: sample.response
    }
  end

  defp event_nodes(rid, since) do
    Events.for_rid(rid)
    |> Enum.filter(&(div(&1.timestamp, 1000) >= since))
    |> Enum.map(&event_node/1)
  end

  defp origin_event_nodes(player, since) do
    player = to_string(player)

    # Hot table first, archive when the range reaches back; the store caps the search.
    Events.query(%{player: player, since_ms: since}, 100).events
    |> Enum.map(&event_node/1)
  end

  defp event_node(event) do
    context = Map.get(event, :context) || %{}

    %{
      kind: :event,
      at: div(event.timestamp, 1000),
      label: event.event,
      origin: context[:origin] || context["origin"],
      rid: context[:rid] || context["rid"],
      payload: event.payload
    }
  end

  defp log_nodes(rid, since) do
    Exoforge.ExtensionLogs.entries_for_rid(rid)
    |> Enum.filter(&(&1.at >= since))
    |> Enum.map(fn entry ->
      %{kind: :log, at: entry.at, label: entry.level_name, message: entry.message}
    end)
  end

  defp error_nodes(rid, since) do
    Exoforge.ErrorGroups.list(%{rid: rid})
    |> Enum.filter(&(&1.last_seen >= since))
    |> Enum.map(&error_node/1)
  end

  defp caller_error_nodes(player, since) do
    Exoforge.ErrorGroups.list(%{caller: player})
    |> Enum.filter(&(&1.last_seen >= since))
    |> Enum.map(&error_node/1)
  end

  defp error_node(group) do
    %{
      kind: :error,
      at: group.last_seen,
      label: "#{group.service}.#{group.action}",
      reason: group.reason,
      count: group.count
    }
  end

  defp sort_and_cap(nodes, limit) do
    nodes
    |> Enum.sort_by(&{&1.at, kind_rank(&1.kind)})
    |> Enum.take(limit)
  end

  # Actions open the story; the rest of the node kinds follow within the same millisecond.
  defp kind_rank(:action), do: 0
  defp kind_rank(:query), do: 1
  defp kind_rank(:host_call), do: 2
  defp kind_rank(:error), do: 3
  defp kind_rank(:log), do: 4
  defp kind_rank(_event), do: 5
end
