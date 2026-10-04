defmodule Exoforge.Std.Dashboard.LoginController do
  @moduledoc """
  Renders the Studio sign-in page.

  The guarded LiveViews redirect here when no session is present; the form
  posts to `ApiController.login/2`, which establishes the session.
  """
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  def show(conn, params) do
    if authenticated?(conn) do
      redirect(conn, to: "/")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, render_login(params["error"]))
    end
  end

  defp authenticated?(conn) do
    present?(get_session(conn, "admin_player_id")) or present?(get_session(conn, "admin_user_id"))
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp render_login(error) do
    csrf = Plug.CSRFProtection.get_csrf_token()
    dev_admin? = Exoforge.Config.allow_dev_tokens?()

    error_html =
      if error,
        do: ~s(<div class="error">#{error}</div>),
        else: ""

    dev_form =
      if dev_admin? do
        """
        <form action="/login" method="post">
          <input type="hidden" name="_csrf_token" value="#{csrf}" />
          <input type="hidden" name="dev_admin" value="true" />
          <button type="submit" class="secondary">⚡ Quick Dev Sign-In</button>
        </form>
        """
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
        .error { background:#fef2f2; border:1px solid #fecaca; color:#b91c1c; border-radius:8px; padding:.6rem .8rem; font-size:.85rem; margin-bottom:1rem; }
        .secondary { width:100%; padding:.6rem; border-radius:.75rem; background:#f3f4f6; border:1px solid #e5e7eb; color:#374151; font-weight:700; font-size:.8rem; cursor:pointer; }
        .secondary:hover { background:#e5e7eb; }
      </style>
    </head>
    <body class="min-h-screen bg-[#f3f4f6] flex items-center justify-center p-4">
      <div class="w-full max-w-sm bg-white rounded-2xl shadow-[0_20px_40px_-15px_rgba(0,0,0,0.12)] border border-gray-200 p-8">
        <div class="flex items-center gap-2 mb-6">
          <span class="text-2xl font-extrabold tracking-tight" style="color:#7c3aed">EXO</span>
          <span class="text-2xl font-extrabold tracking-tight text-gray-900">FORGE</span>
        </div>
        <h1 class="text-lg font-semibold text-gray-900 mb-1">Sign in to the Studio</h1>
        <p class="text-sm text-gray-500 mb-6">An account is required to continue.</p>
        #{error_html}
        <form action="/login" method="post" class="space-y-4">
          <input type="hidden" name="_csrf_token" value="#{csrf}" />
          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1" for="email">Email / Account ID</label>
            <input id="email" name="email" type="text" required autocomplete="username"
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
        #{dev_form}
      </div>
    </body>
    </html>
    """
  end
end
