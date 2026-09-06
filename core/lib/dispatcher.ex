defmodule Exoforge.Dispatcher do
  @registry Exoforge.EventRegistry

  def subscribe(event_key, opts \\ []) do
    topic = Keyword.get(opts, :topic, :global)
    Registry.register(@registry, {event_key, topic}, opts)
  end

  def unsubscribe(event_key, opts \\ []) do
    topic = Keyword.get(opts, :topic, :global)
    Registry.unregister(@registry, {event_key, topic})
  end

  def broadcast(event_key, payload, opts \\ []) do
    topic = Keyword.get(opts, :topic, :global)

    context = %{
      source: Keyword.get(opts, :source),
      topic: topic,
      scope: Keyword.get(opts, :scope, :server)
    }

    do_dispatch(event_key, topic, payload, context)

    if topic != :global do
      do_dispatch(event_key, :global, payload, context)
    end
  end

  defp do_dispatch(event_key, topic, payload, context) do
    Registry.dispatch(@registry, {event_key, topic}, fn entries ->
      for {pid, _opts} <- entries do
        send(pid, {:exo_event, event_key, payload, context})
      end
    end)
  end
end
