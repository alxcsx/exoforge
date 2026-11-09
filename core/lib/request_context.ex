defmodule Exoforge.RequestContext do
  @moduledoc """
  The request a dispatch belongs to: who started it, its id, its depth, and whether it is captured.

  It lives in the process dictionary, entered by `ActionDispatcher.dispatch/4` for the duration of
  the action and restored afterwards, so a long-lived process (a LiveView, a socket handler, a
  GenServer) never leaks one request into the next. A nested dispatch (an action calling another
  service) inherits the id and the origin and goes one level deeper.

  Events, log lines and trace samples carry `rid`, and ingress echoes it to the client. That is the
  join key: one id answers "what happened in this request" across every surface.
  """

  @key :exoforge_request
  @rid_format ~r/^[A-Za-z0-9_-]{1,64}$/

  @doc "A fresh request id: `r_` and twelve url-safe characters."
  def new_rid, do: "r_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  @doc "A request id from an untrusted source: kept if well-formed, replaced otherwise."
  def sanitize_rid(value) when is_binary(value) do
    if Regex.match?(@rid_format, value), do: value, else: new_rid()
  end

  def sanitize_rid(_), do: new_rid()

  @doc "The context of the action running in this process, or nil."
  def current, do: Process.get(@key)

  def origin, do: with(%{origin: origin} <- current(), do: origin)
  def rid, do: with(%{rid: rid} <- current(), do: rid)
  def depth, do: with(%{depth: depth} <- current(), do: depth)
  def capture, do: with(%{capture: capture} <- current(), do: capture)
  def capturing?, do: capture() not in [nil, :off]

  @doc """
  Enters a context for the current process and returns the previous one; `restore/1` pops it.
  """
  def enter(nil), do: Process.delete(@key)
  def enter(%{} = context), do: Process.put(@key, context)

  def restore(nil), do: Process.delete(@key)
  def restore(previous), do: Process.put(@key, previous)
end
