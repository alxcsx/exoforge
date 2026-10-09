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

  def login(conn, params) do
    email = params["email"] || params[:email]
    password = params["password"] || params[:password]

    case ActionDispatcher.dispatch(:auth, :login, %{email: email, password: password}) do
      {:ok, result} ->
        # The Studio is staff tooling (M33 Fix 26): a player account signing in here would
        # start a session the whole dashboard trusts, so it is refused at the door.
        if Exoforge.Auth.Roles.rank_of(result.scopes) >= 2 do
          player_id = result.player_id
          token = result.token
          role = result[:role] || "Admin"

          conn
          |> clear_session()
          |> put_session("admin_user_id", player_id)
          |> put_session("admin_player_id", player_id)
          |> put_session("admin_scopes", result.scopes)
          |> put_session("user_name", player_id)
          |> put_session("user_role", role)
          |> put_session("auth_token", token)
          |> put_resp_cookie("exo_auth_token", token,
            path: "/",
            same_site: "Lax",
            http_only: true
          )
          |> put_flash(:info, "Signed in successfully as #{player_id}")
          |> redirect(to: "/")
        else
          conn
          |> put_flash(:error, "The Studio requires a staff account (studio or admin).")
          |> redirect(to: "/login?error=Staff+access+required")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: "/login?error=Invalid+email+or+password")
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_session("logged_out", true)
    |> delete_resp_cookie("exo_auth_token", path: "/")
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/login")
  end

  def overview(conn, _params) do
    data = Exoforge.Std.Dashboard.Router.build_overview_data()
    json(conn, data)
  end

  def resource_rows(conn, %{"name" => name}) do
    json(conn, %{rows: PluginRegistry.fetch_resource_rows(name, caller_scopes(conn))})
  end

  def create_resource_row(conn, %{"name" => name} = params) do
    case PluginRegistry.fetch_resource(name) do
      {:ok, %{plugin_id: plugin_id, resource: res}} ->
        case create_action(res) do
          nil ->
            conn
            |> put_status(501)
            |> json(%{status: "error", error: "resource_has_no_create_action"})

          action ->
            case ActionDispatcher.dispatch(plugin_id, action, Map.drop(params, ["name"]), caller_scopes: caller_scopes(conn)) do
              {:ok, result} ->
                json(conn, %{status: "ok", data: result})

              :ok ->
                json(conn, %{status: "ok"})

              {:error, reason} ->
                conn |> put_status(400) |> json(%{status: "error", error: inspect(reason)})
            end
        end

      _ ->
        conn
        |> put_status(404)
        |> json(%{status: "error", error: "resource_not_found"})
    end
  end

  defp create_action(res) do
    res
    |> Map.get(:actions, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.find(&String.starts_with?(&1, "create_"))
    |> case do
      nil -> nil
      name -> Exoforge.Atoms.existing(name)
    end
  end

  def extensions(conn, _params) do
    exts = Exoforge.Std.Dashboard.Extensions.dashboard_extensions()
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
        case ActionDispatcher.dispatch(service, action, payload, caller_scopes: auth_ctx.scopes) do
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

  @doc "Studio gate: an admin or studio session/token is required."
  def verify_studio_auth(conn), do: verify_auth(conn, 2)

  @doc "Admin gate: an admin session/token is required."
  def verify_admin_auth(conn), do: verify_auth(conn, 3)

  defp verify_auth(conn, min_rank) do
    case session_auth(conn) do
      {:ok, auth} ->
        if Exoforge.Auth.Roles.rank_of(auth.scopes) >= min_rank,
          do: {:ok, auth},
          else: {:error, :forbidden}

      :error ->
        token_auth(conn, min_rank)
    end
  end

  # A browser session established by the login controller grants Studio access at the scopes the
  # login verified (M33 Fix 26) — never a default admin.
  defp session_auth(conn) do
    if Map.get(conn.private, :plug_session_fetch) == :done do
      case get_session(conn, "admin_player_id") do
        player_id when is_binary(player_id) and player_id != "" ->
          scopes = get_session(conn, "admin_scopes") || []

          {:ok, %{player_id: player_id, scopes: scopes, role: Exoforge.Auth.Roles.role(scopes)}}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp token_auth(conn, min_rank) do
    token = explicit_token(conn)

    cond do
      is_binary(token) ->
        do_token_auth(token, min_rank)

      PluginRegistry.fetch_service(:auth) == nil ->
        {:ok, %{player_id: "local_dev", scopes: [Exoforge.Auth.Roles.admin()], role: :admin}}

      Exoforge.Config.require_admin_auth?() ->
        {:error, :unauthenticated}

      Exoforge.Config.allow_dev_tokens?() ->
        do_token_auth("dev:admin", min_rank)

      true ->
        {:error, :unauthenticated}
    end
  end

  defp do_token_auth(token, min_rank) do
    case ActionDispatcher.dispatch(:auth, :authenticate, %{token: token}) do
      {:ok, %{player_id: player_id, scopes: scopes}} ->
        if Exoforge.Auth.Roles.rank_of(scopes) >= min_rank do
          {:ok, %{player_id: player_id, scopes: scopes, role: Exoforge.Auth.Roles.role(scopes)}}
        else
          {:error, :forbidden}
        end

      _ ->
        {:error, :unauthenticated}
    end
  end

  # Scopes for the authenticated studio/admin session, used to authorize
  # downstream action dispatches instead of silently running them as internal.
  defp caller_scopes(conn) do
    case conn.assigns[:auth_ctx] do
      %{scopes: scopes} when is_list(scopes) -> scopes
      _ -> []
    end
  end

  defp explicit_token(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    Exoforge.Auth.Request.bearer(conn.req_headers) ||
      Exoforge.Auth.Request.header(conn.req_headers, "x-admin-token") ||
      Exoforge.Auth.Request.query(conn.query_params)
  end

  def serve_file(conn, %{"id" => id} = params) do
    bucket = params["bucket"]
    payload = if bucket, do: %{"bucket" => bucket, "id" => id}, else: %{"id" => id}

    case ActionDispatcher.dispatch(:file_bucket, :get_file_info, payload) do
      {:ok, %{file: file}} ->
        disk_path = file["disk_path"] || file[:disk_path]
        content_type = file["content_type"] || file[:content_type] || "application/octet-stream"

        if disk_path && File.exists?(disk_path) do
          conn
          |> put_resp_header("content-type", content_type)
          |> put_resp_header("cache-control", "public, max-age=86400")
          |> send_file(200, disk_path)
        else
          conn
          |> put_status(404)
          |> json(%{status: "error", error: "file_missing_on_disk"})
        end

      _ ->
        conn
        |> put_status(404)
        |> json(%{status: "error", error: "not_found"})
    end
  end
end
