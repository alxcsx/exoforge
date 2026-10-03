defmodule Exoforge.Std.Ws.SocketHandler do
  @moduledoc """
  WebSocket connection handler for Exoforge game clients.
  Implements the WebSock behavior to process incoming framed JSON protocol messages.
  """
  @behaviour WebSock

  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher

  # Wire protocol vocabulary, defined once.
  @type_key "type"
  @token_key "token"
  @topic_key "topic"
  @id_key "id"
  @service_key "service"
  @action_key "action"
  @payload_key "payload"
  @status_ok "ok"
  @status_error "error"

  @frame_ping "ping"
  @frame_pong "pong"
  @frame_action "action"
  @frame_auth "auth"
  @frame_subscribe "subscribe"
  @frame_unsubscribe "unsubscribe"
  @frame_subscribed "subscribed"
  @frame_unsubscribed "unsubscribed"
  @frame_event "event"
  @frame_error "error"
  @frame_action_result "action_result"
  @frame_auth_result "auth_result"

  @code_unauthenticated "unauthenticated"
  @code_unhandled_message "unhandled_message"
  @code_invalid_json "invalid_json"
  @code_action_failed "action_failed"

  @impl true
  def init(opts) do
    state = %{
      subscriptions: MapSet.new()
    }

    # A token supplied on the /ws upgrade (?token=...) authenticates the socket
    # up front; otherwise the client sends a {type: "auth", token} frame.
    case Keyword.get(opts, :token) do
      token when is_binary(token) and token != "" ->
        case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}) do
          {:ok, auth} -> {:ok, Map.put(state, :auth, auth)}
          _ -> {:ok, state}
        end

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def handle_in({text, opts}, state) when is_list(opts) do
    case Keyword.get(opts, :opcode) do
      :text -> process_text(text, state)
      _ -> {:ok, state}
    end
  end

  def handle_in({text, :text}, state) do
    process_text(text, state)
  end

  def handle_in({_data, _type}, state) do
    {:ok, state}
  end

  defp process_text(text, state) do
    case Jason.decode(text) do
      {:ok, %{@type_key => @frame_ping}} ->
        reply(%{type: @frame_pong}, state)

      {:ok, %{@type_key => @frame_action} = req} ->
        handle_action(req, state)

      {:ok, %{@type_key => @frame_auth, @token_key => token}} ->
        handle_auth(token, state)

      {:ok, %{@type_key => @frame_subscribe, @topic_key => topic}} when is_binary(topic) ->
        if Map.get(state, :auth) do
          EventDispatcher.subscribe(:all, topic: topic)
          new_state = %{state | subscriptions: MapSet.put(state.subscriptions, topic)}
          reply(%{type: @frame_subscribed, topic: topic}, new_state)
        else
          reply(
            %{
              type: @frame_error,
              error: %{code: @code_unauthenticated, message: "Authenticate before subscribing."}
            },
            state
          )
        end

      {:ok, %{@type_key => @frame_unsubscribe, @topic_key => topic}} when is_binary(topic) ->
        EventDispatcher.unsubscribe(:all, topic: topic)
        new_state = %{state | subscriptions: MapSet.delete(state.subscriptions, topic)}
        reply(%{type: @frame_unsubscribed, topic: topic}, new_state)

      {:ok, unhandled} ->
        reply(
          %{
            type: @frame_error,
            error: %{
              code: @code_unhandled_message,
              message: "Unhandled message type",
              payload: unhandled
            }
          },
          state
        )

      {:error, decode_err} ->
        reply(
          %{
            type: @frame_error,
            error: %{code: @code_invalid_json, message: Exception.message(decode_err)}
          },
          state
        )
    end
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, state) do
    event_name = format_event_name(event_key)

    frame = %{
      type: @frame_event,
      event: event_name,
      topic: context.topic,
      payload: payload
    }

    {:push, {:text, Jason.encode!(frame)}, state}
  end

  def handle_info(_other, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    for topic <- state.subscriptions do
      EventDispatcher.unsubscribe(:all, topic: topic)
    end

    :ok
  end

  # ---- Private Helpers ----

  defp handle_auth(token, state) do
    case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}) do
      {:ok, %{player_id: player_id, scopes: scopes} = auth_info} ->
        new_state = Map.put(state, :auth, auth_info)

        reply(
          %{type: @frame_auth_result, status: @status_ok, player_id: player_id, scopes: scopes},
          new_state
        )

      {:error, reason} ->
        reply(%{type: @frame_auth_result, status: @status_error, error: reason}, state)
    end
  end

  defp handle_action(req, state) do
    case Map.get(state, :auth) do
      nil -> unauthenticated_action(req, state)
      auth -> do_handle_action(req, auth, state)
    end
  end

  defp unauthenticated_action(req, state) do
    reply(
      %{
        type: @frame_action_result,
        id: Map.get(req, @id_key),
        status: @status_error,
        error: %{
          code: @code_unauthenticated,
          message: "Authenticate first with a {type: \"auth\", token} frame."
        }
      },
      state
    )
  end

  defp do_handle_action(req, auth, state) do
    req_id = Map.get(req, @id_key)
    service_str = Map.get(req, @service_key, "")
    action_str = Map.get(req, @action_key, "")

    raw_payload =
      case Map.get(req, @payload_key) do
        p when is_map(p) -> Map.delete(p, "_auth") |> Map.delete(:_auth)
        other -> other
      end

    payload =
      if is_map(raw_payload) do
        raw_payload
        |> Map.put_new("player_id", auth.player_id)
        |> Map.put_new("_auth", auth)
      else
        raw_payload
      end

    caller_scopes = auth.scopes || []

    service = parse_service(service_str)
    action = parse_action(action_str)

    case ActionDispatcher.dispatch(service, action, payload, caller_scopes: caller_scopes) do
      {:ok, data} ->
        reply(
          %{
            type: @frame_action_result,
            id: req_id,
            status: @status_ok,
            data: data
          },
          state
        )

      :ok ->
        reply(
          %{
            type: @frame_action_result,
            id: req_id,
            status: @status_ok,
            data: %{}
          },
          state
        )

      {:error, reason} when reason in [:unauthorized, :forbidden_scope] ->
        reply(
          %{
            type: @frame_action_result,
            id: req_id,
            status: @status_error,
            error: %{
              code: to_string(reason),
              message: "Scope authorization failed"
            }
          },
          state
        )

      {:error, reason} ->
        reply(
          %{
            type: @frame_action_result,
            id: req_id,
            status: @status_error,
            error: %{
              code: @code_action_failed,
              message: inspect(reason)
            }
          },
          state
        )
    end
  end

  defp reply(data, state) do
    json = Jason.encode!(data)
    {:push, {:text, json}, state}
  end

  defp parse_service(str) when is_binary(str) do
    existing_atom(str)
  end

  defp parse_service(other), do: other

  defp parse_action(str) when is_binary(str) do
    existing_atom(str)
  end

  defp parse_action(other), do: other

  defp existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp format_event_name(key) when is_atom(key) do
    str = Atom.to_string(key)

    if String.starts_with?(str, "Elixir.") do
      key
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    else
      str
    end
  end

  defp format_event_name(other), do: to_string(other)
end
