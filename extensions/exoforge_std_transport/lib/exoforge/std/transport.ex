defmodule Exoforge.Std.Transport do
  @moduledoc """
  Standard transport abstraction layer for Exoforge ingress gateways.
  Provides the :transport service contract and canonical RPC/event framing helpers.
  """
  use Exoforge.Extension, provides: [:transport]

  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry

  @game_version_cache :exoforge_game_version_cache
  @game_version_cache_ttl 30_000

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

  @doc "Checks an optional client game version when the versioning service is installed."
  @spec check(nil | binary()) :: {:ok, nil | %{version: binary(), status: term()}} | {:error, :upgrade_required}
  def check(nil), do: {:ok, nil}

  def check(version) when is_binary(version) do
    if ExtensionRegistry.fetch_service(:versioning) do
      resolve_game_version(version)
    else
      {:ok, nil}
    end
  end

  def check(_), do: {:ok, nil}

  defp resolve_game_version(version) do
    now = System.monotonic_time(:millisecond)

    case cache_lookup(version, now) do
      nil ->
        result =
          case ActionDispatcher.dispatch_internal(:versioning, :resolve, %{version: version}) do
            {:ok, response} -> version_result(version, response)
            _ -> {:error, :upgrade_required}
          end

        cache_put(version, result, now)
        result

      result ->
        result
    end
  end

  defp version_result(version, response) when is_map(response) do
    status = Map.get(response, :status) || Map.get(response, "status")

    if status in [:blocked, "blocked", nil],
      do: {:error, :upgrade_required},
      else: {:ok, %{version: version, status: status}}
  end

  defp version_result(_version, _response), do: {:error, :upgrade_required}

  defp cache_lookup(version, now) do
    ensure_game_version_cache()

    case :ets.lookup(@game_version_cache, version) do
      [{^version, expires_at, result}] when expires_at > now -> result
      [{^version, _, _}] -> :ets.delete(@game_version_cache, version)
      [] -> nil
    end
  end

  defp cache_put(version, result, now) do
    ensure_game_version_cache()
    :ets.insert(@game_version_cache, {version, now + @game_version_cache_ttl, result})
    :ok
  end

  defp ensure_game_version_cache do
    if :ets.whereis(@game_version_cache) == :undefined do
      try do
        :ets.new(@game_version_cache, [:named_table, :public, read_concurrency: true])
      rescue
        ArgumentError -> @game_version_cache
      end
    else
      @game_version_cache
    end
  end

  @doc """
  Checks whether an action is allowed for unauthenticated callers (e.g. auth login, register, anonymous).
  """
  @spec public_action?(atom() | binary(), binary() | atom()) :: boolean()
  def public_action?(service, action) do
    s = to_string(service)
    a = to_string(action)

    s == "auth" and a in ["login", "register", "authenticate", "create_player", "anonymous", "refresh"]
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

  def format_action_result(id, :error, reason) do
    frame = %{
      "type" => "action_result",
      "status" => "error",
      "error" => action_error(reason)
    }

    if id, do: Map.put(frame, "id", id), else: frame
  end

  @doc """
  The one error shape every ingress puts on the wire:

      {"status": "error", "error": {"code": ..., "message": ..., "details": {...}}, "rid": ...}

  `details` is always a map, so a client can read it without checking for absence. Whatever a
  reason carries beyond its code and message lands there - a scope refusal names the required and
  caller scopes, a missing action names itself, and a native extension may report its own.

  A native extension reports `%{"code" => ..., "message" => ...}`, which the runner hands over as
  `{code, message}`; a `defaction` may return the same tuple; a plain atom is its own code. None of
  them may reach a client as an `inspect/1` string, and none may be silently dropped.
  """
  @spec action_error(term()) :: %{binary() => term()}
  def action_error(%{"code" => code} = error) when is_atom(code) or is_binary(code) do
    error_shape(code, Map.get(error, "message"), Map.get(error, "details"))
  end

  def action_error(%{code: code} = error) when is_atom(code) or is_binary(code) do
    error_shape(code, Map.get(error, :message), Map.get(error, :details))
  end

  def action_error({:action_not_found, action}) when is_atom(action) or is_binary(action) do
    %{
      "code" => "action_not_found",
      "message" => "Action '#{action}' was not found on the remote server.",
      "details" => %{"action" => to_string(action)}
    }
  end

  def action_error({:forbidden_scope, %{required: required} = details}) do
    scopes = Map.get(details, :caller_scopes) || Map.get(details, "caller_scopes") || []

    %{
      "code" => "forbidden_scope",
      "message" => "Scope authorization failed",
      "details" =>
        %{
          "required_scope" => to_string(required),
          "caller_scopes" => Enum.map(scopes, &to_string/1)
        }
        |> put_reason(Map.get(details, :reason) || Map.get(details, "reason"))
    }
  end

  def action_error(:forbidden_scope) do
    %{
      "code" => "forbidden_scope",
      "message" => "Scope authorization failed",
      "details" => %{}
    }
  end

  def action_error({code, message}) when is_atom(code) or is_binary(code) do
    error_shape(code, message, nil)
  end

  def action_error(code) when is_atom(code) do
    error_shape(code, nil, nil)
  end

  def action_error(message) when is_binary(message) do
    %{"code" => "action_failed", "message" => message, "details" => %{}}
  end

  def action_error(other) do
    %{"code" => "action_failed", "message" => inspect(other), "details" => %{}}
  end

  @doc """
  Wraps [action_error/1] in the envelope `{"status": "error", "error": ..., "rid": ...}`.

  The rid is present when the request had one; every ingress uses this instead of assembling the
  same three keys itself.
  """
  @spec error_body(term(), binary() | nil) :: map()
  def error_body(reason, rid \\ nil) do
    body = %{"status" => "error", "error" => action_error(reason)}

    if is_binary(rid) and rid != "", do: Map.put(body, "rid", rid), else: body
  end

  @doc """
  The HTTP status an action failure answers with. The wire shape is one; the status codes were
  already distinct, so they stay.
  """
  @spec http_status(term()) :: non_neg_integer()
  def http_status(:service_not_found), do: 404
  def http_status(:upgrade_required), do: 426
  def http_status({:action_not_found, _}), do: 404
  def http_status(:unauthorized), do: 401
  def http_status(:forbidden_scope), do: 403
  def http_status({:forbidden_scope, _}), do: 403
  def http_status(_reason), do: 400

  @doc """
  True for a caller whose reply may carry this request's extension logs.

  Logs hold extension stack traces and host paths, so they are staff-only; a player, guest or
  webhook gets the failure code and message, never the internals behind them.
  """
  @spec staff_scopes?(term()) :: boolean()
  def staff_scopes?(scopes) do
    Exoforge.Auth.Roles.has?(scopes, :admin) or Exoforge.Auth.Roles.has?(scopes, :studio)
  end

  @doc """
  Adds `logs` to a reply only for a staff caller. The rid is added by the transport, always.
  """
  @spec with_logs(map(), binary(), term()) :: map()
  def with_logs(reply, rid, scopes) when is_map(reply) do
    if staff_scopes?(scopes) do
      Map.put(reply, :logs, Exoforge.ExtensionLogs.for_rid(rid))
    else
      reply
    end
  end

  # ---- Private Helpers ----

  defp error_shape(code, message, details) do
    %{
      "code" => to_string(code),
      "message" => error_message(message, code),
      "details" => if(is_map(details), do: details, else: %{})
    }
  end

  defp error_message(message, _code) when is_binary(message), do: message
  defp error_message(nil, code), do: to_string(code)
  defp error_message(message, _code), do: inspect(message)

  # A trusted game server (`service`) acts for players, so it names its target like staff does.
  defp staff_scope?(auth) when is_map(auth) do
    scopes = Map.get(auth, :scopes) || Map.get(auth, "scopes") || []
    Enum.any?(scopes, &(&1 in [:admin, "admin", :studio, "studio", :service, "service"]))
  end

  defp staff_scope?(_), do: false

  # ---- Actions ----

  @impl true
  defaction status(), scope: :global do
    {:ok, %{status: "online", layer: "exoforge_std_transport"}}
  end

  # Why the scope was not enough, when the action's own check knows (the dispatcher's does not: the
  # declared scope is the whole reason).
  defp put_reason(details, nil), do: details
  defp put_reason(details, reason), do: Map.put(details, "reason", to_string(reason))

end
