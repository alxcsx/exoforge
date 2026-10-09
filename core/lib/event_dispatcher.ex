defmodule Exoforge.EventDispatcher do
  @registry __MODULE__.Registry

  def registry_name, do: @registry

  def child_spec(_opts \\ []) do
    %{
      id: @registry,
      start: {Registry, :start_link, [[keys: :duplicate, name: @registry]]}
    }
  end

  def subscribe(event_key, opts \\ []) do
    topic = normalize_topic(Keyword.get(opts, :topic, :global))
    res = Registry.register(@registry, {event_key, topic}, opts)

    if Process.whereis(:exo_cluster_pg) do
      try do
        :pg.join(:exo_cluster_pg, {event_key, topic}, self())
      catch
        _, _ -> :ok
      end
    end

    res
  end

  def unsubscribe(event_key, opts \\ []) do
    topic = normalize_topic(Keyword.get(opts, :topic, :global))
    res = Registry.unregister(@registry, {event_key, topic})

    if Process.whereis(:exo_cluster_pg) do
      try do
        :pg.leave(:exo_cluster_pg, {event_key, topic}, self())
      catch
        _, _ -> :ok
      end
    end

    res
  end

  def broadcast(event_key, payload, opts \\ []) do
    topic = normalize_topic(Keyword.get(opts, :topic, :global))

    context = %{
      source: Keyword.get(opts, :source),
      topic: to_string(topic),
      scope: Keyword.get(opts, :scope, :server),
      event: event_key
    }

    # One pid, one message (M33 Fix 13): overlapping subscriptions - an event and `:all`, a topic
    # and the global one, or the same key registered twice - are one recipient.
    recipients = MapSet.new()

    recipients =
      for {reg_key, t} <- targets(event_key, topic),
          {pid, _opts} <- Registry.lookup(@registry, {reg_key, t}),
          into: recipients do
        pid
      end

    recipients =
      if Process.whereis(:exo_cluster_pg) do
        try do
          for {reg_key, t} <- targets(event_key, topic),
              pid <- :pg.get_members(:exo_cluster_pg, {reg_key, t}),
              node(pid) != node(),
              into: recipients do
            pid
          end
        catch
          _, _ -> recipients
        end
      else
        recipients
      end

    for pid <- recipients do
      send(pid, {:exo_event, event_key, payload, context})
    end

    :ok
  end

  defp normalize_topic(t) when t in [:global, "global", :*, "*", "all", :all], do: :global
  defp normalize_topic(t), do: t

  # The key pairs a broadcast is delivered under. A subscriber to the exact event, to `:all`, and
  # to the topic's global fallback each receive it.
  defp targets(event_key, topic) do
    base = [{event_key, topic}, {:all, topic}]
    if topic == :global, do: base, else: base ++ [{event_key, :global}, {:all, :global}]
  end
end
