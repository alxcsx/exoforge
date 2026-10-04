defmodule Exoforge.Std.Dashboard.AuthHook do
  @moduledoc """
  LiveView `on_mount` hook that requires an authenticated Studio session.

  Any LiveView mounted without a real account session is redirected to the
  login page, so logged-out users cannot reach the dashboard.
  """
  import Phoenix.LiveView

  # Any of these session keys proves the browser established a session.
  @session_keys ["admin_player_id", "admin_user_id", "auth_token"]

  def on_mount(:require_studio, _params, session, socket) do
    if Enum.any?(@session_keys, &present?(session[&1])) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
