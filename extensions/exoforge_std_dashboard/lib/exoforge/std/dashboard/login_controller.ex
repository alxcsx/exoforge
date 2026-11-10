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
      # If the session carried a stale or player-only login, clear it so it doesn't loop.
      conn =
        if present?(get_session(conn, "admin_player_id")) or present?(get_session(conn, "admin_user_id")) do
          clear_session(conn)
        else
          conn
        end

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, render_login(params["error"]))
    end
  end

  defp authenticated?(conn) do
    scopes = get_session(conn, "admin_scopes") || []

    (present?(get_session(conn, "admin_player_id")) or present?(get_session(conn, "admin_user_id"))) and
      Exoforge.Auth.Roles.rank_of(scopes) >= 2
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp render_login(error) do
    csrf = Plug.CSRFProtection.get_csrf_token()

    # The error travels in the URL; it never travels into the HTML unescaped (M33 Fix 25).
    error_html =
      if error,
        do: ~s(<div class="error p-3 bg-red-50 border border-red-200 text-red-700 rounded-xl text-xs font-semibold mb-4">#{Plug.HTML.html_escape(to_string(error))}</div>),
        else: ""

    """
    <!DOCTYPE html>
    <html lang="en" class="dark">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>EXOFORGE - Sign in</title>
      <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
      <link rel="alternate icon" href="/favicon.ico" />
      <script>
        (function() {
          try {
            var saved = localStorage.getItem('exo_theme') || 'dark';
            var root = document.documentElement;
            if (saved === 'light') {
              root.classList.remove('dark');
              root.classList.add('light');
            } else {
              root.classList.remove('light');
              root.classList.add('dark');
            }
          } catch (e) {}
        })();
        function toggleLoginTheme() {
          var root = document.documentElement;
          var next = root.classList.contains('light') ? 'dark' : 'light';
          root.classList.remove('dark', 'light');
          root.classList.add(next);
          try { localStorage.setItem('exo_theme', next); } catch (e) {}
        }
      </script>
      <link rel="stylesheet" href="/vendor/exoforge-studio.css" />
      <script src="/vendor/tailwind.js"></script>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');
        body { font-family: 'Inter', sans-serif; }
      </style>
    </head>
    <body class="min-h-screen bg-[#f3f4f6] flex flex-col items-center justify-center p-4 relative">
      <button
        type="button"
        onclick="toggleLoginTheme()"
        class="fixed top-4 right-4 w-9 h-9 rounded-xl bg-white border border-gray-200 text-gray-600 hover:text-gray-900 flex items-center justify-center shadow-sm transition-colors"
        title="Toggle Dark / Light Theme"
        aria-label="Toggle Dark / Light Theme"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 4V2 M12 22v-2 M4 12H2 M22 12h-2 M5.64 5.64L4.22 4.22 M19.78 19.78l-1.42-1.42 M5.64 18.36l-1.42 1.42 M19.78 4.22l-1.42 1.42 M12 7a5 5 0 100 10 5 5 0 000-10z" />
        </svg>
      </button>

      <div class="w-full max-w-sm bg-white rounded-2xl shadow-card border border-gray-200 p-8">
        <div class="flex items-center gap-3 mb-6">
          <img src="/favicon.svg" alt="Exoforge" class="w-9 h-9 rounded-xl shadow-sm" />
          <div class="flex items-center">
            <span class="text-2xl font-extrabold tracking-tight text-purple-600">EXO</span>
            <span class="text-2xl font-extrabold tracking-tight text-gray-900">FORGE</span>
          </div>
        </div>
        <h1 class="text-lg font-bold text-gray-900 mb-1">Sign in to the Studio</h1>
        <p class="text-xs text-gray-500 mb-6">Enter your studio credentials to continue.</p>
        #{error_html}
        <form action="/login" method="post" class="space-y-4">
          <input type="hidden" name="_csrf_token" value="#{csrf}" />
          <div>
            <label class="block text-xs font-bold text-gray-600 mb-1.5" for="email">Email / Account ID</label>
            <input id="email" name="email" type="text" required autocomplete="username"
                   placeholder="admin@exoforge.local"
                   class="w-full rounded-xl border border-gray-200 bg-gray-50 px-3.5 py-2.5 text-xs font-medium text-gray-900 focus:outline-none focus:border-purple-500" />
          </div>
          <div>
            <label class="block text-xs font-bold text-gray-600 mb-1.5" for="password">Password</label>
            <input id="password" name="password" type="password" required autocomplete="current-password"
                   placeholder="••••••••"
                   class="w-full rounded-xl border border-gray-200 bg-gray-50 px-3.5 py-2.5 text-xs font-medium text-gray-900 focus:outline-none focus:border-purple-500" />
          </div>
          <button type="submit"
                  class="w-full rounded-xl bg-purple-600 hover:bg-purple-700 text-white text-xs font-bold py-2.5 transition-colors shadow-sm">
            Sign in
          </button>
        </form>
      </div>

      <footer class="mt-6 text-center text-[11px] text-gray-400 font-mono">
        Exoforge v#{Exoforge.BuildInfo.version()} (#{Exoforge.BuildInfo.commit_hash()}) • Built #{Exoforge.BuildInfo.build_date()}
      </footer>
    </body>
    </html>
    """
  end
end
