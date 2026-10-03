defmodule Exoforge.Std.Dashboard.AuthHook do
  @moduledoc """
  LiveView `on_mount` hook that requires an authenticated admin session.

  Any LiveView mounted without a valid `admin_player_id` in the session is
  redirected to the login page. This guards the Studio and Resource views.
  """
  import Phoenix.LiveView

  def on_mount(:require_admin, _params, session, socket) do
    case Exoforge.Std.Dashboard.Auth.player_id(session) do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      _player_id ->
        scopes = Exoforge.Std.Dashboard.Auth.scopes(session)

        if Exoforge.Auth.Roles.rank_of(scopes) >= 2 do
          {:cont, socket}
        else
          {:halt, redirect(socket, to: "/login")}
        end
    end
  end
end
