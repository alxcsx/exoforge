defmodule Exoforge.ActionTrace do
  @moduledoc """
  Bounded, in-memory trace of recent action invocations, for the Studio's action console.

  Opt-in: nothing is recorded until an observer calls `enable/0` (the Studio does when it mounts),
  and nothing is ever written to the database. Each sample carries a *preview* of the request and
  of the response — size-capped and with credential-shaped fields masked — so the console can show
  what was sent and what came back without the event bus, or the instance's storage, ever carrying
  a payload.

  Alongside the samples, calls are counted per minute, per action and per caller. That is what turns
  "total invocations" into a rate over time, and what lets the console answer *who* called.

  This is deliberately not `Exoforge.Metering`: metering promises shape without content, on by
  default, and is the thing usage rollups are built from. This is a bounded debug window that only
  exists once someone asks for it.
  """

  @samples :exo_action_trace
  @buckets :exo_action_trace_buckets

  @window_minutes 30
  # Per action, and in total. One noisy action must not evict another's errors - that is exactly
  # how a row could report errors the unfold could not show.
  @per_action 30
  @max_samples 2_000

  @doc "Starts recording. Idempotent; called by an observer (the Studio), not by the kernel."
  def enable do
    unless enabled?() do
      :persistent_term.put({__MODULE__, :enabled}, true)
      init_tables()
    end

    :ok
  end

  defp enabled?, do: :persistent_term.get({__MODULE__, :enabled}, false)

  @doc """
  Records one invocation. Never raises into the caller: a trace is diagnostics, not a dependency.
  """
  def record(service, action, caller, payload, result, duration_ms, internal? \\ false, kind \\ :action) do
    if enabled?() do
      init_tables()

      now = System.system_time(:millisecond)
      minute = div(now, 60_000) * 60_000
      key = "#{service}.#{action}"
      caller = to_string(caller || "client")
      status = status(result)

      incr({minute, key, caller, :count})
      if status != "ok", do: incr({minute, key, caller, :error})

      sample = %{
        at: now,
        key: key,
        kind: kind,
        rid: Exoforge.RequestContext.rid(),
        depth: Exoforge.RequestContext.depth() || 0,
        caller: caller,
        status: status,
        duration_ms: duration_ms,
        internal: internal?,
        request: Exoforge.PayloadPreview.preview(payload),
        response: preview_result(result)
      }

      seq = System.unique_integer([:monotonic])
      :ets.insert(@samples, {seq, sample})
      remember({{:queue, key}, @per_action}, seq)
      remember({:queue_all, @max_samples}, seq)

      # A failure is kept twice: once in the action's recent samples, once in its error bucket. Each
      # queue then owns the rows it evicts, so a burst of successes cannot erase the failures the
      # error view exists to show.
      if status != "ok" do
        error_seq = System.unique_integer([:monotonic])
        :ets.insert(@samples, {error_seq, sample})
        remember({{:queue, key, :error}, @per_action}, error_seq)
      end

      prune(minute)
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  @doc """
  The window: `%{buckets: [{minute, key, caller, :count | :error, n}]}`.

  Buckets are oldest-first by minute. Samples are fetched per action by `samples/2`, because they
  are paginated and a caller rarely wants every action's at once.
  """
  def snapshot do
    init_tables()
    oldest = (div(System.system_time(:millisecond), 60_000) - @window_minutes + 1) * 60_000

    buckets =
      @buckets
      |> :ets.tab2list()
      |> Enum.filter(fn {{minute, _key, _caller, _kind}, _n} -> minute >= oldest end)
      |> Enum.map(fn {{minute, key, caller, kind}, n} -> {minute, key, caller, kind, n} end)

    %{buckets: buckets}
  end

  @doc """
  One page of retained samples for an action, newest first.

  `:errors_only` keeps failures, `:caller` narrows to one origin, `:rid` to one request, and
  `:page` / `:per_page` page the result. `total` is what is still retained - the ring drops old
  samples, so it can be smaller than the bucket counters.
  """
  def samples(key, opts \\ []) do
    init_tables()

    per_page = max(Keyword.get(opts, :per_page, 8), 1)
    errors_only? = Keyword.get(opts, :errors_only, false) == true
    caller = Keyword.get(opts, :caller, "")
    rid = Keyword.get(opts, :rid, "")

    retained =
      key
      |> retained_seqs(errors_only?)
      |> Enum.map(&fetch(&1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn sample -> caller in ["", nil] or sample.caller == to_string(caller) end)
      |> Enum.filter(fn sample -> rid in ["", nil] or sample.rid == to_string(rid) end)
      |> Enum.reverse()

    total = length(retained)
    pages = max(ceil(total / per_page), 1)
    page = Keyword.get(opts, :page, 1) |> max(1) |> min(pages)

    %{
      samples: Enum.slice(retained, (page - 1) * per_page, per_page),
      total: total,
      page: page,
      pages: pages
    }
  end

  @doc "Drops every sample and counter (a reset; tests and a Studio reset use it)."
  def clear do
    init_tables()
    :ets.delete_all_objects(@samples)
    :ets.delete_all_objects(@buckets)
    :ok
  end

  @doc "The newest retained samples across every action, newest first."
  def recent_samples(limit \\ 100) do
    init_tables()

    @samples
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {seq, sample} when is_integer(seq) -> [sample]
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.sort_by(& &1.at, :desc)
    |> Enum.take(max(limit, 1))
  end

  @doc """
  The retained samples of one request, oldest first.

  A scan of the sample table (bounded by `#{@max_samples}` rows): a debugger asking for one request
  is not a hot path.
  """
  def for_rid(rid) do
    init_tables()
    rid = to_string(rid)

    @samples
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {seq, sample} when is_integer(seq) -> [sample]
      _ -> []
    end)
    |> Enum.filter(&(&1.rid == rid))
    |> Enum.sort_by(& &1.at)
    # A failure is stored twice (sample + error bucket); one timeline row is enough.
    |> Enum.uniq()
  end

  ## ---- internals ----

  defp init_tables do
    ensure_table(@samples, [:ordered_set, :public, :named_table, read_concurrency: true])
    ensure_table(@buckets, [:set, :public, :named_table, write_concurrency: true])
  end

  defp ensure_table(name, opts) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, opts)
        rescue
          _ -> name
        end

      _ ->
        name
    end
  end

  defp incr(key), do: :ets.update_counter(@buckets, key, 1, {key, 0})

  # A bounded queue of sequence numbers per bucket; evicting drops the row it owns. Rows are not
  # shared between queues, so a dropped sequence number is never another bucket's row.
  defp remember({bucket, cap}, seq) do
    queue =
      case :ets.lookup(@samples, bucket) do
        [{^bucket, queue}] -> :queue.in(seq, queue)
        [] -> :queue.from_list([seq])
      end

    queue = trim_queue(bucket, queue, cap)
    :ets.insert(@samples, {bucket, queue})
    :ok
  end

  defp trim_queue(_bucket, queue, cap) do
    if :queue.len(queue) > cap do
      {{:value, dropped}, rest} = :queue.out(queue)
      :ets.delete(@samples, dropped)
      trim_queue(nil, rest, cap)
    else
      queue
    end
  end

  defp retained_seqs(key, errors_only?) do
    bucket = if errors_only?, do: {:queue, key, :error}, else: {:queue, key}

    case :ets.lookup(@samples, bucket) do
      [{^bucket, queue}] -> :queue.to_list(queue)
      [] -> []
    end
  end

  defp fetch(seq) do
    case :ets.lookup(@samples, seq) do
      [{^seq, sample}] -> sample
      [] -> nil
    end
  end

  # Pruned once per minute, not per call: minute buckets are the unit, so anything older than the
  # window is already invisible to `snapshot/1`.
  defp prune(minute) do
    if :persistent_term.get({__MODULE__, :last_prune}, 0) != minute do
      :persistent_term.put({__MODULE__, :last_prune}, minute)
      cutoff = minute - @window_minutes * 60_000

      :ets.select_delete(@buckets, [
        {{{:"$1", :_, :_, :_}, :_}, [{:<, :"$1", cutoff}], [true]}
      ])
    end

    :ok
  end

  defp status({:error, reason}), do: "error: #{inspect(reason)}"
  defp status(_), do: "ok"

  defp preview_result({:ok, value}), do: Exoforge.PayloadPreview.preview(value)
  defp preview_result(:ok), do: nil
  defp preview_result({:error, reason}), do: Exoforge.PayloadPreview.preview(reason)
  defp preview_result(other), do: Exoforge.PayloadPreview.preview(other)
end
