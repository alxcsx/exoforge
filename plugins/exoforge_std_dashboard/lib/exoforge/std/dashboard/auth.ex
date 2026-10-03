defmodule Exoforge.Std.Dashboard.Auth do
  @moduledoc """
  Session keys and helpers for the Studio authentication session.

  The Studio stores the authenticated account in the browser session; these
  accessors keep the key names and default scope in one place.
  """
  alias Exoforge.Auth.Roles

  @player_id_key "admin_player_id"
  @scopes_key "admin_scopes"

  def player_id_key, do: @player_id_key
  def scopes_key, do: @scopes_key

  @doc "Stores the authenticated account in the session."
  def put(conn, player_id, scopes) do
    conn
    |> Plug.Conn.put_session(@player_id_key, player_id)
    |> Plug.Conn.put_session(@scopes_key, scopes)
  end

  @doc "Reads the authenticated account id from the session."
  def player_id(session), do: session[@player_id_key]

  @doc "Reads the account scopes from the session."
  def scopes(session), do: session[@scopes_key] || [Roles.admin()]
end
