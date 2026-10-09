defmodule Exoforge.Std.Dashboard.AuthHook do
  @moduledoc """
  LiveView `on_mount` hook that requires an authenticated Studio session.

  Any LiveView mounted without a real account session is redirected to the
  login page, so logged-out users cannot reach the dashboard.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_studio, _params, session, socket) do
    scopes = session["admin_scopes"] || []

    # A session proves a login happened; a staff rank proves the login was a Studio account
    # (M33 Fix 26): a player's session is refused rather than promoted to staff.
    if Exoforge.Auth.Roles.rank_of(scopes) >= 2 do
      {:cont, assign(socket, :current_scopes, scopes)}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end
end
