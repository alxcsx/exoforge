defmodule Exoforge.Std.Ws do
  @moduledoc """
  Standard real-time ingress and egress plugin for Exoforge.
  Provides the :ws service and manages the Bandit WebSocket server in its supervision tree.
  """
  use Exoforge.Plugin, provides: [:ws]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Auth],
    category: "Ingress",
    system: true,
    dashboard_view: nil
  }

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
