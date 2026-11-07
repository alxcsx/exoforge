defmodule Exoforge.Std.Transport do
  @moduledoc """
  Standard transport abstraction layer for Exoforge ingress gateways.
  Provides the :transport service contract and canonical RPC/event framing helpers.
  """
  use Exoforge.Extension, provides: [:transport]

  alias Exoforge.ActionDispatcher

  @manifest %{
    title: "Transport Abstraction Layer",
    icon: "🔌",
    category: "Network",
    system: true,
    dashboard_view: nil
  }

  @doc """
  Normalizes an incoming transport action request into a canonical tuple.
  Returns `{:ok, service, action, payload, id}` or `{:error, reason}`.
  """
  @spec normalize_action_request(map()) ::
          {:ok, atom(), binary(), map(), any()} | {:error, binary()}
  def normalize_action_request(req) when is_map(req) do
    service_str = Map.get(req, "service") || Map.get(req, :service)
    action_str = Map.get(req, "action") || Map.get(req, :action)
    payload = Map.get(req, "payload") || Map.get(req, :payload) || %{}
    id = Map.get(req, "id") || Map.get(req, :id)

    cond do
      is_nil(service_str) or service_str == "" ->
        {:error, "Missing required 'service' field in action request"}

      is_nil(action_str) or action_str == "" ->
        {:error, "Missing required 'action' field in action request"}

      true ->
        service_atom =
          if is_atom(service_str),
            do: service_str,
            else: Exoforge.Atoms.existing(service_str, String.to_atom(service_str))

        {:ok, service_atom, to_string(action_str), payload, id}
    end
  end

  def normalize_action_request(_), do: {:error, "Action request must be a JSON object"}

  @doc """
  Checks whether an action is allowed for unauthenticated callers (e.g. auth login, register, anonymous).
  """
  @spec public_action?(atom() | binary(), binary() | atom()) :: boolean()
  def public_action?(service, action) do
    s = to_string(service)
    a = to_string(action)

    s == "auth" and a in ["login", "register", "authenticate", "create_player", "anonymous"]
  end

  @doc """
  Sanitizes an incoming payload by stripping unverified `_auth` fields and stamping
  the caller's verified `player_id` (unless the caller is staff/admin targeting another player).
  """
  @spec sanitize_payload(term(), map()) :: term()
  def sanitize_payload(payload, auth) when is_map(payload) do
    cleaned = Map.delete(payload, "_auth") |> Map.delete(:_auth)

    has_explicit_target =
      (Map.has_key?(cleaned, "player_id") and cleaned["player_id"] not in [nil, ""]) or
        (Map.has_key?(cleaned, :player_id) and cleaned[:player_id] not in [nil, ""])

    if has_explicit_target and staff_scope?(auth) do
      cleaned
    else
      player_id = Map.get(auth, :player_id) || Map.get(auth, "player_id")
      if player_id in [nil, ""], do: cleaned, else: Map.put(cleaned, "player_id", player_id)
    end
  end

  def sanitize_payload(other, _auth), do: other

  @doc """
  Dispatches an action request to the ActionDispatcher with normalized auth context.
  """
  @spec dispatch(atom(), binary() | atom(), map(), map()) ::
          {:ok, term()} | {:error, term()}
  def dispatch(service, action, payload, auth_info) do
    player_id = Map.get(auth_info, :player_id) || Map.get(auth_info, "player_id")
    scopes = Map.get(auth_info, :scopes) || Map.get(auth_info, "scopes") || []
    transport = Map.get(auth_info, :transport) || :unknown

    context = [
      caller_player_id: player_id,
      caller_scopes: scopes,
      transport: transport
    ]

    ActionDispatcher.dispatch(service, action, payload, context)
  end

  @doc """
  Formats a canonical JSON action result frame.
  """
  @spec format_action_result(any(), :ok | :error, term()) :: map()
  def format_action_result(id, :ok, data) do
    frame = %{
      "type" => "action_result",
      "status" => "ok",
      "data" => data
    }

    if id, do: Map.put(frame, "id", id), else: frame
  end

  def format_action_result(id, :error, {code, message}) when (is_atom(code) or is_binary(code)) and is_binary(message) do
    frame = %{
      "type" => "action_result",
      "status" => "error",
      "error" => %{
        "code" => to_string(code),
        "message" => message
      }
    }

    if id, do: Map.put(frame, "id", id), else: frame
  end

  def format_action_result(id, :error, reason) do
    error_payload =
      cond do
        is_map(reason) -> reason
        is_binary(reason) -> %{"code" => "action_failed", "message" => reason}
        is_atom(reason) -> %{"code" => to_string(reason), "message" => to_string(reason)}
        true -> %{"code" => "action_failed", "message" => inspect(reason)}
      end

    frame = %{
      "type" => "action_result",
      "status" => "error",
      "error" => error_payload
    }

    if id, do: Map.put(frame, "id", id), else: frame
  end

  # ---- Private Helpers ----

  defp staff_scope?(auth) when is_map(auth) do
    scopes = Map.get(auth, :scopes) || Map.get(auth, "scopes") || []
    Enum.any?(scopes, &(&1 in [:admin, "admin", :studio, "studio"]))
  end

  defp staff_scope?(_), do: false

  # ---- Actions ----

  @impl true
  defaction status() do
    {:ok, %{status: "online", layer: "exoforge_std_transport"}}
  end
end
