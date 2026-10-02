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
    topic = Keyword.get(opts, :topic, :global)
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
    topic = Keyword.get(opts, :topic, :global)
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
    topic = Keyword.get(opts, :topic, :global)

    context = %{
      source: Keyword.get(opts, :source),
      topic: topic,
      scope: Keyword.get(opts, :scope, :server),
      event: event_key
    }

    do_dispatch(event_key, topic, event_key, payload, context)
    do_dispatch(:all, topic, event_key, payload, context)

    if topic != :global do
      do_dispatch(event_key, :global, event_key, payload, context)
      do_dispatch(:all, :global, event_key, payload, context)
    end
  end

  defp do_dispatch(reg_key, topic, actual_event_key, payload, context) do
    Registry.dispatch(@registry, {reg_key, topic}, fn entries ->
      for {pid, _opts} <- entries do
        send(pid, {:exo_event, actual_event_key, payload, context})
      end
    end)

    if Process.whereis(:exo_cluster_pg) do
      try do
        for pid <- :pg.get_members(:exo_cluster_pg, {reg_key, topic}), node(pid) != node() do
          send(pid, {:exo_event, actual_event_key, payload, context})
        end
      catch
        _, _ -> :ok
      end
    end
  end
end
