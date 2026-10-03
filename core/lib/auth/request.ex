defmodule Exoforge.Auth.Request do
  @moduledoc """
  Extracts an authentication token from a `Plug.Conn`.

  Shared by the HTTP and WebSocket ingress plugins and the Studio so token
  handling is defined once. Accepts `Authorization: Bearer <token>`, a bare
  `Authorization` value, an arbitrary header (e.g. `x-admin-token`), or a
  `?token=` query parameter.
  """

  @auth_header "authorization"
  @bearer_prefix "Bearer "

  def auth_header, do: @auth_header

  @doc "Token from the Authorization header, the `token` query parameter, or cross-port `exo_auth_token` cookie."
  def token(conn), do: bearer(conn) || query(conn) || cookie(conn)

  @doc "Token from the shared cross-port auth cookie (e.g. `exo_auth_token`)."
  def cookie(conn, name \\ "exo_auth_token") do
    conn = Plug.Conn.fetch_cookies(conn)

    case Map.get(conn.req_cookies, name) do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> nil
    end
  end

  @doc "Token from the Authorization header (Bearer or bare value)."
  def bearer(conn) do
    case header(conn, @auth_header) do
      @bearer_prefix <> token -> String.trim(token)
      "bearer " <> token -> String.trim(token)
      token -> token
    end
  end

  @doc "Token from an arbitrary request header."
  def header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) |> List.first() do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> nil
    end
  end

  @doc "Token from the `token` query parameter."
  def query(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params["token"] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end
end
