defmodule Exoforge.Auth.Request do
  @moduledoc """
  Finds a caller's bearer token in an inbound request.

  The transports (`exoforge_std_http`, `exoforge_std_ws`, the dashboard API) receive requests
  differently but look for a token the same way, so the rules live here rather than being copied
  three times: the `Authorization` header first, then a `token` query parameter, then the auth
  cookie.

  This module deliberately takes plain header/param/cookie maps instead of a `Plug.Conn`, so the
  kernel stays free of a Plug dependency and the parsing can be tested without a connection.
  """

  @cookie_names ["exo_auth_token", "exoforge_auth_token"]
  @query_key "token"

  @doc """
  First token found, or `nil`. Precedence: `Authorization` header, query parameter, cookie.

  `headers` is a `Plug.Conn`-style header list; `query_params` and `cookies` are maps.
  """
  def token(headers, query_params, cookies) do
    bearer(headers) || query(query_params) || cookie(cookies)
  end

  @doc """
  Token from an `Authorization` header, with or without the `Bearer ` prefix.

      iex> Exoforge.Auth.Request.bearer([{"authorization", "Bearer abc"}])
      "abc"
      iex> Exoforge.Auth.Request.bearer([{"authorization", "abc"}])
      "abc"
      iex> Exoforge.Auth.Request.bearer([])
      nil
  """
  def bearer(headers) do
    headers
    |> List.wrap()
    |> Enum.find_value(&authorization_header/1)
  end

  @doc "Value of the first named header, trimmed, or `nil`."
  def header(headers, name) do
    target = String.downcase(to_string(name))

    headers
    |> List.wrap()
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == target, do: clean(value), else: nil
    end)
  end

  @doc "Token from a `token` query parameter, or `nil`."
  def query(query_params) do
    case Map.get(query_params || %{}, @query_key) do
      token when is_binary(token) -> clean(token)
      _ -> nil
    end
  end

  @doc "Token from the auth cookie, or `nil`."
  def cookie(cookies) do
    cookies = cookies || %{}

    Enum.find_value(@cookie_names, fn name ->
      case Map.get(cookies, name) do
        value when is_binary(value) -> clean(value)
        _ -> nil
      end
    end)
  end

  @doc "Cookie names carrying the auth token, in precedence order."
  def cookie_names, do: @cookie_names

  defp authorization_header({key, value}) do
    if String.downcase(to_string(key)) == "authorization", do: strip_scheme(value), else: nil
  end

  defp authorization_header(_), do: nil

  # "Bearer abc" and "abc" both mean the token is everything after the scheme, if there is one.
  # Trim first: a header with leading whitespace would otherwise miss the scheme and be returned
  # whole, token and all.
  defp strip_scheme(value) do
    value = String.trim(to_string(value))

    case String.split(value, " ", parts: 2) do
      [scheme, token] ->
        if String.downcase(scheme) == "bearer", do: clean(token), else: clean(value)

      [token] ->
        clean(token)
    end
  end

  defp clean(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
