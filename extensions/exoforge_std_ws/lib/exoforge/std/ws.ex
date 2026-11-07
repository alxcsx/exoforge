defmodule Exoforge.Std.Ws do
  @moduledoc """
  Standard real-time ingress and egress plugin for Exoforge.
  Provides the :ws service and manages the Bandit WebSocket server in its supervision tree.
  """
  use Exoforge.Extension, provides: [:ws]
  @behaviour Exoforge.Contracts.Transport

  @manifest %{
    dependencies: [Exoforge.Std.Services.Auth],
    title: "WebSocket Gateway",
    icon: "⚡",
    category: "Network",
    system: true,
    dashboard_view: nil
  }

  @impl Exoforge.Contracts.Transport
  def transport_id, do: :ws

  @impl Exoforge.Contracts.Transport
  def transport_type, do: :realtime

  @impl Exoforge.Contracts.Transport
  def dispatch_action(service, action, payload, context) do
    Exoforge.Std.Transport.dispatch(service, action, payload, context)
  end

  @impl Exoforge.Contracts.Transport
  def push_event(_conn_id, topic, event, payload) do
    Exoforge.EventDispatcher.broadcast(event, payload, topic: topic)
    :ok
  end

  def children do
    port = Exoforge.Endpoints.ws_port()

    [
      {Bandit, plug: Exoforge.Std.Ws.Router, port: port, scheme: :http}
    ]
  end

  @impl true
  defaction broadcast(payload) do
    topic = Map.get(payload, :topic) || Map.get(payload, "topic")
    event = Map.get(payload, :event) || Map.get(payload, "event")
    data = Map.get(payload, :payload) || Map.get(payload, "payload", %{})

    Exoforge.EventDispatcher.broadcast(event, data, topic: topic)
    {:ok, %{status: "ok"}}
  end

  @impl true
  defaction connection_count() do
    {:ok, %{count: 0}}
  end
end
