defmodule Exoforge.Contracts.Transport do
  @moduledoc """
  Contract behaviour for ingress and egress network transports (WebSocket, HTTP REST, gRPC, etc.).
  Standardizes connection lifecycle, action dispatch normalization, and realtime event push.
  """

  @type transport_id :: atom()
  @type connection_id :: binary()
  @type session_info :: %{
          player_id: binary() | nil,
          scopes: list(binary())
        }

  @doc "Returns the unique transport identifier (e.g. :ws, :http, :grpc)."
  @callback transport_id() :: transport_id()

  @doc "Returns the delivery mode of the transport (:realtime, :stateless, :datagram)."
  @callback transport_type() :: :realtime | :stateless | :datagram

  @doc "Dispatches an action frame to the ActionDispatcher with normalized auth context."
  @callback dispatch_action(
              service :: atom(),
              action :: atom() | binary(),
              payload :: map(),
              context :: map()
            ) :: {:ok, term()} | {:error, term()}

  @doc "Pushes an event payload to a connected client or topic."
  @callback push_event(
              connection_id :: connection_id(),
              topic :: binary(),
              event :: binary(),
              payload :: map()
            ) :: :ok | {:error, term()}

  @optional_callbacks [push_event: 4]
end
