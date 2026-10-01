defmodule Exoforge.Std.Dashboard.ApiController do
  @moduledoc """
  JSON REST APIs and SSE event stream controller for Exoforge Studio.
  """
  use Phoenix.Controller, formats: [:json]
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.DrawerRegistry

  def health(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def overview(conn, _params) do
    data = Exoforge.Std.Dashboard.Router.build_overview_data()
    json(conn, data)
  end

  def players(conn, _params) do
    players = Exoforge.PluginRegistry.fetch_resource_rows(:players)
    json(conn, %{players: players})
  end

  def create_player(conn, params) do
    player_id =
      Map.get(params, "player_id") || "p_#{System.unique_integer([:positive])}"

    profile = Map.get(params, "profile") || %{}

    case ActionDispatcher.dispatch(:player_data, :create_player, %{
           player_id: player_id,
           profile: profile
         }) do
      {:ok, result} ->
        json(conn, %{status: "ok", player: result.player})

      _ ->
        _ =
          ActionDispatcher.dispatch(:database, :execute, %{
            plugin: :player_data,
            operation: "INSERT INTO players (id, player_id, profile, state) VALUES ($1, $2, $3, $4)",
            arguments: [player_id, player_id, Jason.encode!(profile), "active"]
          })

        json(conn, %{status: "ok", player: Map.put(profile, "player_id", player_id)})
    end
  end

  def extensions(conn, _params) do
    exts = PluginRegistry.dashboard_extensions()
    json(conn, %{extensions: exts, count: length(exts)})
  end

  def resources(conn, _params) do
    res = PluginRegistry.all_resources()
    json(conn, %{resources: res, count: length(res)})
  end

  def resource_detail(conn, %{"name" => name}) do
    case PluginRegistry.fetch_resource(name) do
      {:ok, res} ->
        json(conn, %{
          status: "ok",
          resource: res.resource,
          plugin_id: res.plugin_id,
          service: res.service
        })

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{status: "error", error: "resource_not_found"})
    end
  end

  def drawers(conn, %{"name" => name}) do
    tabs = DrawerRegistry.list_tabs(name)
    json(conn, %{status: "ok", resource: name, tabs: tabs, count: length(tabs)})
  end

  def dispatch_action(conn, params) do
    with {:ok, auth_ctx} <- verify_admin_auth(conn) do
      service = Map.get(params, "service")
      action = Map.get(params, "action")
      payload = Map.get(params, "payload") || %{}

      if is_nil(service) or is_nil(action) do
        conn
        |> put_status(400)
        |> json(%{status: "error", error: "service and action are required"})
      else
        case ActionDispatcher.dispatch(service, action, payload) do
          {:ok, result} ->
            json(conn, %{status: "ok", data: result, caller: auth_ctx.player_id})

          :ok ->
            json(conn, %{status: "ok", caller: auth_ctx.player_id})

          {:error, reason} ->
            conn
            |> put_status(400)
            |> json(%{status: "error", error: inspect(reason)})
        end
      end
    else
      {:error, :unauthenticated} ->
        conn
        |> put_status(401)
        |> json(%{status: "error", error: "Unauthorized: bearer token required"})

      {:error, :forbidden} ->
        conn
        |> put_status(403)
        |> json(%{status: "error", error: "Forbidden: admin scope required"})
    end
  end

  def events(conn, _params) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    EventDispatcher.subscribe(:all)
    stream_events_loop(conn)
  end

  defp stream_events_loop(conn) do
    receive do
      {:exo_event, event_key, payload, context} ->
        data = Jason.encode!(%{event: to_string(event_key), payload: payload, context: context})

        case chunk(conn, "data: #{data}\n\n") do
          {:ok, new_conn} -> stream_events_loop(new_conn)
          {:error, _} -> conn
        end
    after
      20_000 ->
        case chunk(conn, ": ping\n\n") do
          {:ok, new_conn} -> stream_events_loop(new_conn)
          {:error, _} -> conn
        end
    end
  end

  def verify_admin_auth(conn) do
    auth_header = Plug.Conn.get_req_header(conn, "authorization") |> List.first()
    dev_header = Plug.Conn.get_req_header(conn, "x-admin-token") |> List.first()
    query_token = Map.get(conn.params || %{}, "token")

    explicit_token =
      cond do
        is_binary(auth_header) and String.starts_with?(auth_header, "Bearer ") ->
          String.replace_prefix(auth_header, "Bearer ", "")

        is_binary(auth_header) and auth_header != "" ->
          auth_header

        is_binary(dev_header) and dev_header != "" ->
          dev_header

        is_binary(query_token) and query_token != "" ->
          query_token

        true ->
          nil
      end

    has_auth_plugin = PluginRegistry.fetch_service(:auth) != nil

    token_to_verify =
      cond do
        explicit_token != nil ->
          explicit_token

        not has_auth_plugin ->
          "dev:local"

        Application.get_env(:exoforge, :require_admin_auth, false) ->
          nil

        true ->
          "dev:admin"
      end

    if is_nil(token_to_verify) do
      {:error, :unauthenticated}
    else
      if not has_auth_plugin do
        {:ok, %{player_id: "local_dev", scopes: ["admin"]}}
      else
        case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token_to_verify}) do
          {:ok, %{player_id: player_id, scopes: scopes}} ->
            if "admin" in scopes or player_id == "admin" do
              {:ok, %{player_id: player_id, scopes: scopes}}
            else
              {:error, :forbidden}
            end

          _ ->
            {:error, :unauthenticated}
        end
      end
    end
  end
end
