defmodule Exoforge.Std.Ws do
  @moduledoc """
  Standard real-time ingress and egress plugin for Exoforge.
  Provides the :ws service and manages the Bandit WebSocket server in its supervision tree.

  Game clients use it as the low-latency path for actions and live events, and it stays an extension so the gateway can be replaced without changing client code.

  ### How it works
  - `children/0` starts Bandit with `Exoforge.Std.Ws.Router` on the port from `Exoforge.Endpoints.ws_port/0`.
  - The router answers `/health`, serves a landing page at `/`, and upgrades `/ws` to `Exoforge.Std.Ws.SocketHandler` with a 60 second idle timeout.
  - A socket authenticates with a token query parameter on upgrade or a later auth frame; both verify through `:auth`, and a bad token closes the connection with code 4001.
  - Frames are JSON: ping, pong, action, auth, subscribe and unsubscribe; actions go through `Exoforge.Std.Transport`.
  - Subscribed sockets receive event frames from the event bus, carrying topic, payload, origin and the request id.
  - The module implements the `Exoforge.Contracts.Transport` behaviour with id `:ws` and type `:realtime`, routing outbound pushes through the event bus.

  ### Depends on
  `:auth`.
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
  defaction broadcast(payload), scope: Exoforge.Auth.Roles.studio() do
    topic = Map.get(payload, :topic) || Map.get(payload, "topic")
    event = Map.get(payload, :event) || Map.get(payload, "event")
    data = Map.get(payload, :payload) || Map.get(payload, "payload", %{})

    Exoforge.EventDispatcher.broadcast(event, data, topic: topic)
    {:ok, %{status: "ok"}}
  end

  @impl true
  defaction connection_count(), scope: Exoforge.Auth.Roles.studio() do
    {:ok, %{count: 0}}
  end
end
