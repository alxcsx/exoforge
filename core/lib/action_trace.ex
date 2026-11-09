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
  @max_samples 500
  @preview_bytes 512
  @preview_items 20
  @mask "•••"
  @sensitive ~w(password password_hash token secret authorization api_key)

  @doc "Starts recording. Idempotent; called by an observer (the Studio), not by the kernel."
  def enable do
    unless enabled?() do
      :persistent_term.put({__MODULE__, :enabled}, true)
      init_tables()
    end

    :ok
  end

  @doc "True once an observer has asked for traces."
  def enabled?, do: :persistent_term.get({__MODULE__, :enabled}, false)

  @doc """
  Records one invocation. Never raises into the caller: a trace is diagnostics, not a dependency.
  """
  def record(service, action, caller, payload, result, duration_ms) do
    if enabled?() do
      init_tables()

      now = System.system_time(:millisecond)
      minute = div(now, 60_000) * 60_000
      key = "#{service}.#{action}"
      caller = to_string(caller || "client")
      status = status(result)

      incr({minute, key, caller, :count})
      if status != "ok", do: incr({minute, key, caller, :error})

      :ets.insert(@samples, {
        System.unique_integer([:monotonic]),
        %{
          at: now,
          key: key,
          caller: caller,
          status: status,
          duration_ms: duration_ms,
          request: preview(payload),
          response: preview_result(result)
        }
      })

      trim_samples()
      prune(minute)
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  @doc """
  The window: `%{window_ms, buckets: [{minute, key, caller, :count | :error, n}], samples: [sample]}`.

  Buckets are oldest-first by minute; samples are newest-first.
  """
  def snapshot(minutes \\ @window_minutes) do
    init_tables()
    now = System.system_time(:millisecond)
    oldest = (div(now, 60_000) - minutes + 1) * 60_000

    buckets =
      @buckets
      |> :ets.tab2list()
      |> Enum.filter(fn {{minute, _key, _caller, _kind}, _n} -> minute >= oldest end)
      |> Enum.map(fn {{minute, key, caller, kind}, n} -> {minute, key, caller, kind, n} end)

    samples =
      @samples
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(& &1.at, :desc)

    %{window_ms: minutes * 60_000, now: now, buckets: buckets, samples: samples}
  end

  @doc "One request/response preview, capped and masked. Public so tests can pin the contract."
  def preview(value), do: preview(value, 0)

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

  defp trim_samples do
    if :ets.info(@samples, :size) > @max_samples do
      case :ets.first(@samples) do
        :"$end_of_table" -> :ok
        oldest -> :ets.delete(@samples, oldest)
      end
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

  defp preview_result({:ok, value}), do: preview(value)
  defp preview_result(:ok), do: nil
  defp preview_result({:error, reason}), do: preview(reason)
  defp preview_result(other), do: preview(other)

  defp preview(_value, depth) when depth > 3, do: "…"

  defp preview(value, _depth) when is_binary(value) do
    if byte_size(value) > @preview_bytes do
      binary_part(value, 0, @preview_bytes) <> "… (#{byte_size(value)} bytes)"
    else
      value
    end
  end

  defp preview(%{__struct__: _} = value, depth), do: value |> Map.from_struct() |> preview(depth)

  defp preview(value, depth) when is_map(value) do
    value
    |> Enum.take(@preview_items)
    |> Map.new(fn {k, v} ->
      if sensitive?(k), do: {k, @mask}, else: {k, preview(v, depth + 1)}
    end)
  end

  defp preview(value, depth) when is_list(value) do
    Enum.map(Enum.take(value, @preview_items), &preview(&1, depth + 1))
  end

  defp preview(value, _depth) when is_tuple(value), do: value |> inspect() |> truncate()

  defp preview(value, _depth) when is_atom(value) or is_number(value) or is_nil(value), do: value

  defp preview(value, _depth), do: value |> inspect() |> truncate()

  defp truncate(string) do
    if byte_size(string) > @preview_bytes, do: binary_part(string, 0, @preview_bytes) <> "…", else: string
  end

  defp sensitive?(key) do
    down = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive, &String.contains?(down, &1))
  end
end
