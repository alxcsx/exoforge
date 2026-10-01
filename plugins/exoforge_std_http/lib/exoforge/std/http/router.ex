defmodule Exoforge.Std.Http.Router do
  @moduledoc """
  Plug router for Exoforge HTTP REST ingress.
  Exposes generic REST endpoints derived from registered service contracts.
  Enforces authentication scopes where required via the :auth service.
  """
  use Plug.Router

  alias Exoforge.ActionDispatcher

  plug :match
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  plug :dispatch

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  get "/api/status" do
    send_json(conn, 200, %{status: "ok", service: "exoforge_std_http"})
  end

  get "/api/routes" do
    # Fetch registered plugins and their actions
    routes =
      try do
        :ets.tab2list(:exo_services_mem)
        |> Enum.map(fn {{svc, _ctx}, manifest} ->
          %{
            service: to_string(svc),
            plugin_id: to_string(manifest.id),
            entry_point: to_string(manifest.entry_point)
          }
        end)
        |> Enum.uniq_by(& &1.service)
      rescue
        _ -> []
      end

    send_json(conn, 200, %{routes: routes})
  end

  post "/api/:service/:action" do
    auth_header = get_req_header(conn, "authorization") |> List.first()
    raw_payload =
      case conn.body_params do
        p when is_map(p) -> Map.delete(p, "_auth") |> Map.delete(:_auth)
        other -> other
      end

    # If auth header is provided, attach identity and extract scopes
    {payload_with_auth, caller_scopes} =
      case extract_token(auth_header) do
        nil ->
          {raw_payload, []}

        token ->
          case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}) do
            {:ok, %{player_id: player_id, scopes: scopes} = auth_info} ->
              payload =
                if is_map(raw_payload) do
                  raw_payload
                  |> Map.put("player_id", player_id)
                  |> Map.put("_auth", auth_info)
                else
                  raw_payload
                end

              {payload, scopes}

            _ ->
              {raw_payload, []}
          end
      end

    case ActionDispatcher.dispatch(service, action, payload_with_auth, caller_scopes: caller_scopes) do
      {:ok, result} ->
        send_json(conn, 200, %{status: "ok", data: result})

      :ok ->
        send_json(conn, 200, %{status: "ok"})

      {:error, :service_not_found} ->
        send_json(conn, 404, %{status: "error", error: "service_not_found"})

      {:error, {:action_not_found, _}} ->
        send_json(conn, 404, %{status: "error", error: "action_not_found"})

      {:error, :unauthorized} ->
        send_json(conn, 401, %{status: "error", error: "unauthorized"})

      {:error, :forbidden_scope} ->
        send_json(conn, 403, %{status: "error", error: "forbidden_scope"})

      {:error, reason} ->
        send_json(conn, 400, %{status: "error", error: inspect(reason)})
    end
  end

  match _ do
    send_json(conn, 404, %{status: "error", error: "not_found"})
  end

  ## Helpers

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp extract_token(nil), do: nil

  defp extract_token("Bearer " <> token), do: String.trim(token)
  defp extract_token("bearer " <> token), do: String.trim(token)
  defp extract_token(token) when is_binary(token), do: String.trim(token)
end
