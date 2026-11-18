defmodule Exoforge.Std.Ws.SocketHandler do
  @moduledoc """
  WebSocket connection handler for Exoforge game clients.
  Implements the WebSock behavior to process incoming framed JSON protocol messages.
  """
  @behaviour WebSock
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.Std.Transport

  # Wire protocol vocabulary, defined once.
  @type_key "type"
  @token_key "token"
  @topic_key "topic"
  @id_key "id"
  @rid_key "rid"
  @service_key "service"
  @action_key "action"
  @payload_key "payload"
  @status_ok "ok"

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

  @impl true
  def init(opts) do
    state = %{
      subscriptions: MapSet.new()
    }

    # A token supplied on the /ws upgrade (?token=...) authenticates the socket
    # up front; an invalid or expired token is refused (never treated as anonymous).
    # Without a token, the socket stays anonymous and awaits a {type: "auth", token} frame.
    rid = Exoforge.RequestContext.sanitize_rid(Keyword.get(opts, :rid))

    case Keyword.get(opts, :token) do
      token when is_binary(token) and token != "" ->
        case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}, rid: rid) do
          {:ok, auth} ->
            Logger.info("[WS] Client connected & authenticated as #{auth.player_id}")
            {:ok, Map.put(state, :auth, auth)}

          {:error, reason} ->
            error = Transport.action_error(reason)
            code = error["code"] || "invalid_token"
            Logger.warning("[WS] Connection refused (?token=): #{code}: #{error["message"]}")

            frame =
              Map.merge(
                %{type: @frame_auth_result},
                Transport.error_body(reason, rid)
              )

            {:stop, :normal, {4001, code}, [{:text, encode_json(frame)}], state}
        end

      _ ->
        Logger.info("[WS] Client connected (awaiting auth frame)")
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

      {:ok, %{@type_key => @frame_auth, @token_key => token} = req} ->
        handle_auth(token, req, state)

      {:ok, %{@type_key => @frame_subscribe, @topic_key => topic} = req} when is_binary(topic) ->
        if Map.get(state, :auth) do
          EventDispatcher.subscribe(:all, topic: topic)
          new_state = %{state | subscriptions: MapSet.put(state.subscriptions, topic)}
          player = state.auth.player_id
          Logger.info("[WS] Player #{player} subscribed to topic: #{topic}")
          reply(%{type: @frame_subscribed, topic: topic}, new_state)
        else
          Logger.warning("[WS] Subscribe rejected: socket unauthenticated")
          rid = Exoforge.RequestContext.sanitize_rid(Map.get(req, @rid_key))

          reply(
            Map.merge(
              %{type: @frame_error},
              Transport.error_body({@code_unauthenticated, "Authenticate before subscribing."}, rid)
            ),
            state
          )
        end

      {:ok, %{@type_key => @frame_unsubscribe, @topic_key => topic}} when is_binary(topic) ->
        EventDispatcher.unsubscribe(:all, topic: topic)
        new_state = %{state | subscriptions: MapSet.delete(state.subscriptions, topic)}
        player = if state[:auth], do: state.auth.player_id, else: "anonymous"
        Logger.info("[WS] #{player} unsubscribed from topic: #{topic}")
        reply(%{type: @frame_unsubscribed, topic: topic}, new_state)

      {:ok, unhandled} ->
        reply(
          %{
            type: @frame_error,
            error: %{
              code: @code_unhandled_message,
              message: "Unhandled message type",
              details: %{payload: unhandled}
            }
          },
          state
        )

      {:error, decode_err} ->
        reply(
          %{
            type: @frame_error,
            error: %{
              code: @code_invalid_json,
              message: Exception.message(decode_err),
              details: %{}
            }
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
      topic: to_string(context.topic),
      payload: payload,
      # Who triggered it, when the event happened inside an action. Optional on the wire: older
      # clients ignore it, and clients that show it can answer "who did this".
      origin: Map.get(context, :origin),
      # The request that raised it - the id the Studio timeline joins. Absent outside any request.
      rid: Map.get(context, :rid)
    }

    {:push, {:text, Jason.encode!(frame)}, state}
  end

  # WebSockAdapter's idle timeout, from the `timeout:` option on the upgrade. Returning {:ok, state}
  # here - which is what the catch-all below did - just resets the timer, so an abandoned client held
  # a process until TCP noticed, which can be hours. A client that connects at login and never uses
  # the socket is the common case, so this is the one that matters.
  @impl true
  def handle_info(:timeout, state) do
    Logger.info("[WS] Closing idle connection")
    {:stop, :normal, {1000, "idle timeout"}, state}
  end

  def handle_info(_other, state) do
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    for topic <- state.subscriptions do
      EventDispatcher.unsubscribe(:all, topic: topic)
    end

    client = if state[:auth], do: state.auth.player_id, else: "anonymous"
    Logger.info("[WS] Client disconnected (#{client}): #{inspect(reason)}")

    :ok
  end

  # ---- Private Helpers ----

  defp handle_auth(token, req, state) do
    rid = Exoforge.RequestContext.sanitize_rid(Map.get(req, @rid_key))

    case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}, rid: rid) do
      {:ok, %{player_id: player_id, scopes: scopes} = auth_info} ->
        Logger.info("[WS] Authenticated player: #{player_id} (scopes: #{inspect(scopes)})")
        new_state = Map.put(state, :auth, auth_info)

        reply(
          %{type: @frame_auth_result, status: @status_ok, player_id: player_id, scopes: scopes, rid: rid},
          new_state
        )

      {:error, reason} ->
        error = Transport.action_error(reason)
        Logger.warning("[WS] Authentication failed: #{error["code"]}: #{error["message"]}")

        reply(
          Map.merge(
            %{type: @frame_auth_result},
            Transport.error_body(reason, rid)
          ),
          state
        )
    end
  end

  defp handle_action(req, state) do
    service = Map.get(req, @service_key, "")
    action = Map.get(req, @action_key, "")

    # One request id per action frame: the client may propose one (its own correlation id), the
    # server sanitises or replaces it, and every result frame echoes it.
    rid = Exoforge.RequestContext.sanitize_rid(Map.get(req, @rid_key))

    case Map.get(state, :auth) do
      nil ->
        if Exoforge.Std.Transport.public_action?(service, action) do
          do_handle_action(req, %{player_id: nil, scopes: []}, state, rid)
        else
          unauthenticated_action(req, state, rid)
        end

      auth ->
        do_handle_action(req, auth, state, rid)
    end
  end

  defp unauthenticated_action(req, state, rid) do
    reply(
      Map.merge(
        %{type: @frame_action_result, id: Map.get(req, @id_key)},
        Transport.error_body(
          {@code_unauthenticated, "Authenticate first with a {type: \"auth\", token} frame."},
          rid
        )
      ),
      state
    )
  end

  defp do_handle_action(req, auth, state, rid) do
    req_id = Map.get(req, @id_key)
    service_str = Map.get(req, @service_key, "")
    action_str = Map.get(req, @action_key, "")

    raw_payload = Map.get(req, @payload_key)

    payload =
      if is_map(raw_payload) do
        raw_payload
        |> Exoforge.Std.Transport.sanitize_payload(auth)
        |> Map.put("_auth", auth)
      else
        raw_payload
      end

    caller_scopes = auth.scopes || []

    service = parse_service(service_str)
    action = parse_action(action_str)

    t0 = System.monotonic_time(:microsecond)

    res =
      ActionDispatcher.dispatch(service, action, payload,
        caller_scopes: caller_scopes,
        caller: auth.player_id,
        rid: rid
      )

    latency_us = System.monotonic_time(:microsecond) - t0

    # Logs name extension internals and host paths, so only a staff caller's frame carries them.
    push = fn body -> reply(Transport.with_logs(body, rid, caller_scopes), state) end

    case res do
      {:ok, data} ->
        Logger.info(
          "[WS:Action] #{service}.#{action} by #{auth.player_id} -> OK (#{latency_us}µs)"
        )

        push.(%{
          type: @frame_action_result,
          id: req_id,
          rid: rid,
          status: @status_ok,
          data: data
        })

      :ok ->
        Logger.info(
          "[WS:Action] #{service}.#{action} by #{auth.player_id} -> OK (#{latency_us}µs)"
        )

        push.(%{
          type: @frame_action_result,
          id: req_id,
          rid: rid,
          status: @status_ok,
          data: %{}
        })

      {:error, reason} ->
        error = Transport.action_error(reason)

        Logger.warning(
          "[WS:Action] #{service}.#{action} by #{auth.player_id} -> error: #{error["code"]}: #{error["message"]} (#{latency_us}µs)"
        )

        push.(
          Map.merge(
            %{type: @frame_action_result, id: req_id},
            Transport.error_body(reason, rid)
          )
        )
    end
  end

  defp reply(data, state) do
    {:push, {:text, encode_json(data)}, state}
  end

  defp encode_json(data) do
    case Jason.encode(data) do
      {:ok, json} ->
        json

      {:error, _} ->
        data |> Exoforge.ExtensionRegistry.sanitize_for_json() |> Jason.encode!()
    end
  end

  defp parse_service(str) when is_binary(str) do
    Exoforge.Atoms.existing(str, str)
  end

  defp parse_service(other), do: other

  defp parse_action(str) when is_binary(str) do
    Exoforge.Atoms.existing(str, str)
  end

  defp parse_action(other), do: other

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
