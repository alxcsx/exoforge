defmodule Exoforge.DebugCapture do
  @moduledoc """
  On-demand capture: a rule turns deep tracing on for one player, one action, or everything, for a
  bounded time.

  A capture is a debugging session, not a setting. It expires on its own, it lives in
  `:persistent_term` (three O(1) reads on the dispatch path, no table to own), and the full request
  it keeps is held in a small in-memory ring for replay. Nothing is persisted, and an expired rule
  is simply ignored — the next `list/0` removes it.

  Captured requests are traced even when the Studio's global trace is off, and the trace stores the
  full payload (unmasked) for them: that is the point of asking for one, and the ring is bounded so
  it cannot become a store.
  """

  @prefix {__MODULE__, :rule}
  @kinds ["player", "action", "global"]
  @default_seconds 60
  @max_seconds 3_600

  @doc """
  Starts (or extends) a capture. Returns `%{kind, value, until_ms, seconds}`.

  `kind` is `"player"` (matches the request origin), `"action"` (matches `"service.action"` as
  dispatched) or `"global"` (everything).
  """
  def capture(kind, value \\ "*", seconds \\ @default_seconds) do
    kind = normalize_kind(kind)
    seconds = seconds |> to_integer(@default_seconds) |> max(1) |> min(@max_seconds)
    value = if kind == "global", do: "*", else: to_string(value)
    until_ms = System.system_time(:millisecond) + seconds * 1_000

    rule = %{kind: kind, value: value, until_ms: until_ms, seconds: seconds}
    :persistent_term.put({@prefix, kind, value}, rule)
    rule
  end

  @doc "The capture mode for one dispatch: `:deep` when a rule matches, `:off` otherwise."
  def capture_for(origin, action_key) do
    now = System.system_time(:millisecond)

    [
      rule("player", origin),
      rule("action", action_key),
      rule("global", "*")
    ]
    |> Enum.find_value(:off, fn
      %{until_ms: until_ms} when until_ms > now -> :deep
      _ -> nil
    end)
  end

  @doc "Active rules, newest expiry last; expired entries are removed."
  def list do
    now = System.system_time(:millisecond)

    :persistent_term.get()
    |> Enum.filter(fn {key, _value} ->
      match?({@prefix, _kind, _value}, key)
    end)
    |> Enum.map(fn {_key, rule} -> rule end)
    |> Enum.filter(fn rule ->
      if rule.until_ms > now do
        true
      else
        stop(rule.kind, rule.value)
        false
      end
    end)
    |> Enum.sort_by(& &1.until_ms)
    |> Enum.map(fn rule ->
      Map.put(rule, :remaining_s, max(div(rule.until_ms - now, 1_000), 0))
    end)
  end

  @doc "True when at least one capture is active."
  def active?, do: list() != []

  @doc "Stops one capture."
  def stop(kind, value) do
    kind = normalize_kind(kind)
    value = if kind == "global", do: "*", else: to_string(value)
    :persistent_term.erase({@prefix, kind, value})
    :ok
  end

  @doc "Stops every capture."
  def stop_all do
    :persistent_term.get()
    |> Enum.each(fn
      {{@prefix, _kind, _value} = key, _rule} -> :persistent_term.erase(key)
      _ -> :ok
    end)

    :ok
  end

  @doc "The kinds a capture can have."
  def kinds, do: @kinds

  defp rule(kind, value), do: :persistent_term.get({@prefix, kind, to_string(value)}, nil)

  defp normalize_kind(kind) when kind in @kinds, do: kind
  defp normalize_kind(kind) when is_atom(kind), do: normalize_kind(to_string(kind))

  defp normalize_kind(kind) when is_binary(kind) do
    kind = String.downcase(kind)
    if kind in @kinds, do: kind, else: "player"
  end

  defp normalize_kind(_kind), do: "player"

  defp to_integer(value, _default) when is_integer(value), do: value

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp to_integer(_value, default), do: default
end
