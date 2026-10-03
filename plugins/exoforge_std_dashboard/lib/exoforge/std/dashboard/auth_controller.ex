defmodule Exoforge.Std.Dashboard.AuthController do
  @moduledoc """
  Session login/logout for the Exoforge Studio.

  The dashboard and gateways require an account; the first admin account is
  bootstrapped from the environment (see `Exoforge.Std.Auth.ensure_admin_account/0`).
  """
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  alias Exoforge.ActionDispatcher

  def login_form(conn, _params) do
    html(conn, 200, render_login(nil))
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case ActionDispatcher.dispatch(:auth, :login, %{email: email, password: password}) do
      {:ok, %{player_id: player_id, scopes: scopes, role: role}} when role in [:admin, :studio] ->
        conn
        |> Plug.Conn.configure_session(renew: true)
        |> Exoforge.Std.Dashboard.Auth.put(player_id, scopes)
        |> redirect(to: "/")

      {:ok, _non_studio} ->
        html(conn, 403, render_login("This account does not have Studio access."))

      _ ->
        html(conn, 401, render_login("Invalid email or password."))
    end
  end

  def login(conn, _params) do
    html(conn, 400, render_login("Email and password are required."))
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/login")
  end

  defp html(conn, status, body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end

  defp render_login(error) do
    csrf = Plug.CSRFProtection.get_csrf_token()

    admin_email =
      System.get_env("EXOFORGE_ADMIN_EMAIL") ||
        Application.get_env(:exoforge, :admin, [])[:email] || "admin@exoforge.local"

    error_html =
      if error do
        ~s(<div class="error">#{error}</div>)
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>EXOFORGE - Sign in</title>
      <script src="https://cdn.tailwindcss.com"></script>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');
        body { font-family: 'Inter', sans-serif; }
        .error { background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 8px; padding: .6rem .8rem; font-size: .85rem; margin-bottom: 1rem; }
      </style>
    </head>
    <body class="min-h-screen bg-[#f3f4f6] flex items-center justify-center p-4">
      <div class="w-full max-w-sm bg-white rounded-2xl shadow-[0_20px_40px_-15px_rgba(0,0,0,0.12)] border border-gray-200 p-8">
        <div class="flex items-center gap-2 mb-6">
          <span class="text-2xl font-extrabold tracking-tight text-primary-600" style="color:#7c3aed">EXO</span>
          <span class="text-2xl font-extrabold tracking-tight text-gray-900">FORGE</span>
        </div>
        <h1 class="text-lg font-semibold text-gray-900 mb-1">Sign in to the Studio</h1>
        <p class="text-sm text-gray-500 mb-6">Admin account required.</p>
        #{error_html}
        <form method="post" action="/login" class="space-y-4">
          <input type="hidden" name="_csrf_token" value="#{csrf}" />
          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1" for="email">Email / Username</label>
            <input id="email" name="email" type="text" required autocomplete="username"
                   value="#{admin_email}"
                   class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500" />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1" for="password">Password</label>
            <input id="password" name="password" type="password" required autocomplete="current-password"
                   class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500" />
          </div>
          <button type="submit"
                  class="w-full rounded-lg bg-[#7c3aed] hover:bg-[#6d28d9] text-white text-sm font-semibold py-2.5 transition-colors">
            Sign in
          </button>
        </form>
      </div>
    </body>
    </html>
    """
  end
end
