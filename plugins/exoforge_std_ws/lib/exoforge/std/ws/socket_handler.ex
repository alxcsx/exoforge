defmodule Exoforge.Std.Ws.SocketHandler do
  @moduledoc """
  WebSocket connection handler for Exoforge game clients.
  Implements the WebSock behavior to process incoming framed JSON protocol messages.
  """
  @behaviour WebSock

  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher

  @impl true
  def init(_opts) do
    state = %{
      subscriptions: MapSet.new()
    }

    {:ok, state}
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
      {:ok, %{"type" => "ping"}} ->
        reply(%{type: "pong"}, state)

      {:ok, %{"type" => "action"} = req} ->
        handle_action(req, state)

      {:ok, %{"type" => "auth", "token" => token}} ->
        handle_auth(token, state)

      {:ok, %{"type" => "subscribe", "topic" => topic}} when is_binary(topic) ->
        EventDispatcher.subscribe(:all, topic: topic)
        new_state = %{state | subscriptions: MapSet.put(state.subscriptions, topic)}
        reply(%{type: "subscribed", topic: topic}, new_state)

      {:ok, %{"type" => "unsubscribe", "topic" => topic}} when is_binary(topic) ->
        EventDispatcher.unsubscribe(:all, topic: topic)
        new_state = %{state | subscriptions: MapSet.delete(state.subscriptions, topic)}
        reply(%{type: "unsubscribed", topic: topic}, new_state)

      {:ok, unhandled} ->
        reply(
          %{
            type: "error",
            error: %{code: "unhandled_message", message: "Unhandled message type", payload: unhandled}
          },
          state
        )

      {:error, decode_err} ->
        reply(
          %{
            type: "error",
            error: %{code: "invalid_json", message: Exception.message(decode_err)}
          },
          state
        )
    end
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, state) do
    event_name = format_event_name(event_key)

    frame = %{
      type: "event",
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
        reply(%{type: "auth_result", status: "ok", player_id: player_id, scopes: scopes}, new_state)

      {:error, reason} ->
        reply(%{type: "auth_result", status: "error", error: reason}, state)
    end
  end

  defp handle_action(req, state) do
    req_id = Map.get(req, "id")
    service_str = Map.get(req, "service", "")
    action_str = Map.get(req, "action", "")
    raw_payload =
      case Map.get(req, "payload") do
        p when is_map(p) -> Map.delete(p, "_auth") |> Map.delete(:_auth)
        other -> other
      end

    {payload, caller_scopes} =
      case Map.get(state, :auth) do
        nil ->
          {raw_payload, []}

        auth ->
          p =
            if is_map(raw_payload) do
              raw_payload
              |> Map.put_new("player_id", auth.player_id)
              |> Map.put_new("_auth", auth)
            else
              raw_payload
            end

          {p, auth.scopes || []}
      end

    service = parse_service(service_str)
    action = parse_action(action_str)

    case ActionDispatcher.dispatch(service, action, payload, caller_scopes: caller_scopes) do
      {:ok, data} ->
        reply(
          %{
            type: "action_result",
            id: req_id,
            status: "ok",
            data: data
          },
          state
        )

      :ok ->
        reply(
          %{
            type: "action_result",
            id: req_id,
            status: "ok",
            data: %{}
          },
          state
        )

      {:error, reason} when reason in [:unauthorized, :forbidden_scope] ->
        reply(
          %{
            type: "action_result",
            id: req_id,
            status: "error",
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
            type: "action_result",
            id: req_id,
            status: "error",
            error: %{
              code: "action_failed",
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
    if String.contains?(str, ".") do
      parts = String.split(str, ".") |> Enum.map(&Macro.camelize/1)
      try do
        Module.concat(parts)
      rescue
        _ -> String.to_atom(str)
      end
    else
      try do
        String.to_existing_atom(str)
      rescue
        ArgumentError -> String.to_atom(str)
      end
    end
  end

  defp parse_service(other), do: other

  defp parse_action(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> String.to_atom(str)
    end
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
