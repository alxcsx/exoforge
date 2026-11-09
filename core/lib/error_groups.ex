defmodule Exoforge.ErrorGroups do
  @moduledoc """
  Failures grouped by what broke, instead of counted per action.

  A fingerprint is `{service, action, inspect(reason)}` capped at a readable length. Each group keeps
  how often it happened, when it was first and last seen, the callers it touched, and one masked
  preview of the request that failed, with its `rid` — enough to open the timeline on the failure
  instead of guessing from "7 errors".

  In memory and bounded: this is diagnosis, not storage. A deployment that never fails pays one
  empty ETS table.
  """

  @table :exo_error_groups
  @max_groups 200
  @max_callers 10
  @reason_chars 200

  @doc """
  Records one failure. Never raises into the dispatcher: an error group is diagnostics.
  """
  def record(service, action, caller, rid, request, reason) do
    init_table()

    now = System.system_time(:millisecond)
    service = to_string(service)
    action = to_string(action)
    reason_text = reason_text(reason)
    request = Exoforge.PayloadPreview.preview(request)
    key = {service, action, reason_text}

    group =
      case :ets.lookup(@table, key) do
        [{^key, group}] -> update(group, now, caller, rid, request)
        [] -> new_group(service, action, reason_text, now, caller, rid, request)
      end

    :ets.insert(@table, {key, group})
    evict()
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  @doc """
  Groups newest-first. `filters` accepts a map or keyword list with `:service`, `:action`,
  `:caller` and `:rid`; blank or missing filters do not narrow.
  """
  def list(filters \\ %{}, limit \\ 50) do
    init_table()
    filters = normalize_filters(filters)

    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_key, group} -> group end)
    |> Enum.filter(fn group ->
      matches?(filters[:service], group.service) and
        matches?(filters[:action], group.action) and
        matches?(filters[:rid], group.rid) and
        caller_matches?(filters[:caller], group.callers)
    end)
    |> Enum.sort_by(& &1.touched, :desc)
    |> Enum.take(max(limit, 1))
  end

  @doc "How many groups are held, bounded by the table's cap."
  def count do
    init_table()
    :ets.info(@table, :size)
  end

  @doc "Drops every group (tests, and a Studio reset)."
  def clear do
    init_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  ## ---- internals ----

  defp new_group(service, action, reason, now, caller, rid, request) do
    %{
      service: service,
      action: action,
      reason: reason,
      count: 1,
      first_seen: now,
      last_seen: now,
      touched: System.unique_integer([:monotonic]),
      rid: rid,
      caller: caller,
      request: request,
      callers: [caller] |> Enum.reject(&is_nil/1)
    }
  end

  defp update(group, now, caller, rid, request) do
    %{
      group
      | count: group.count + 1,
        last_seen: now,
        touched: System.unique_integer([:monotonic]),
        rid: rid || group.rid,
        caller: caller || group.caller,
        request: if(request in [nil, %{}], do: group.request, else: request),
        callers: add_caller(group.callers, caller)
    }
  end

  defp add_caller(callers, nil), do: callers
  defp add_caller(callers, ""), do: callers

  defp add_caller(callers, caller) do
    caller = to_string(caller)

    cond do
      caller in callers -> callers
      length(callers) >= @max_callers -> [caller | Enum.take(callers, @max_callers - 1)]
      true -> [caller | callers]
    end
  end

  defp reason_text(reason) do
    reason |> inspect() |> String.slice(0, @reason_chars)
  end

  defp matches?(nil, _actual), do: true
  defp matches?("", _actual), do: true
  defp matches?(expected, actual), do: to_string(expected) == to_string(actual)

  defp caller_matches?(nil, _callers), do: true
  defp caller_matches?("", _callers), do: true

  defp caller_matches?(caller, callers) do
    to_string(caller) in Enum.map(callers, &to_string/1)
  end

  defp normalize_filters(filters) when is_map(filters) do
    Map.new([:service, :action, :caller, :rid], fn key ->
      {key, Map.get(filters, key) || Map.get(filters, to_string(key))}
    end)
  end

  defp normalize_filters(filters) when is_list(filters) do
    Map.new([:service, :action, :caller, :rid], fn key -> {key, Keyword.get(filters, key)} end)
  end

  defp normalize_filters(_), do: %{}

  # One insertion can push the table one past the cap; drop the least recently seen group.
  defp evict do
    if :ets.info(@table, :size) > @max_groups do
      case @table |> :ets.tab2list() |> Enum.min_by(fn {_key, group} -> group.touched end, fn -> nil end) do
        nil -> :ok
        {key, _group} -> :ets.delete(@table, key)
      end
    end
  end

  defp init_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          _ -> @table
        end

      _ ->
        @table
    end
  end
end
