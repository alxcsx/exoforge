defmodule Exoforge.Std.Dashboard.Layouts do
  @moduledoc """
  Root and application layout components for the Exoforge Game Producer & Designer Studio.
  Design tokens for the Exoforge Studio shell.
  """
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>EXOFORGE - Game Producer & Designer Studio</title>
        <!-- Tailwind CSS (Vendored locally for instant load without network latency, with CDN fallback) -->
        <script src="/vendor/tailwind.js"></script>
        <script>
          if (typeof tailwind === 'undefined') {
            document.write('<script src="https://cdn.tailwindcss.com"><\/script>');
          }
        </script>
        <script>
          if (typeof tailwind !== 'undefined') {
            tailwind.config = {
              theme: {
                extend: {
                  colors: {
                    primary: {
                      50: '#f5f3ff',
                      100: '#ede9fe',
                      200: '#ddd6fe',
                      300: '#c4b5fd',
                      400: '#a78bfa',
                      500: '#8b5cf6',
                      600: '#7c3aed',
                      700: '#6d28d9',
                      800: '#5b21b6',
                      900: '#4c1d95',
                    },
                    status: {
                      healthy: '#10b981',
                      warning: '#f59e0b',
                      error: '#ef4444'
                    }
                  },
                  boxShadow: {
                    'mac': '0 20px 40px -15px rgba(0,0,0,0.12), 0 0 0 1px rgba(0,0,0,0.06)',
                    'card': '0 2px 10px -2px rgba(0, 0, 0, 0.04), 0 1px 4px -1px rgba(0, 0, 0, 0.03)'
                  }
                }
              }
            };
          }
        </script>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Inter", sans-serif;
          }
          .pulse-live {
            box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.6);
            animation: pulse-ring 2s infinite;
          }
          @keyframes pulse-ring {
            0% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.6); }
            70% { box-shadow: 0 0 0 7px rgba(16, 185, 129, 0); }
            100% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
          }
          .custom-scrollbar::-webkit-scrollbar {
            width: 5px;
            height: 5px;
          }
          .custom-scrollbar::-webkit-scrollbar-track {
            background: rgba(243, 244, 246, 0.5);
          }
          .custom-scrollbar::-webkit-scrollbar-thumb {
            background: #c4b5fd;
            border-radius: 9999px;
          }
          .prof-tab-btn { justify-content: flex-start; text-align: left; }
          .prof-tab-btn .prof-tab-label { min-width: 0; display: flex; align-items: center; gap: 0.625rem; }
          .prof-tab-btn .prof-tab-badge { margin-left: auto; flex-shrink: 0; }
        </style>
        <script defer src="/vendor/phoenix.js"></script>
        <script defer src="/vendor/phoenix_live_view.js"></script>
        <script>
          document.addEventListener("DOMContentLoaded", function() {
            if (window.LiveView && window.Phoenix) {
              const metaEl = document.querySelector("meta[name='csrf-token']");
              const csrfToken = metaEl ? metaEl.getAttribute("content") : "";
              const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
                params: { _csrf_token: csrfToken }
              });
              liveSocket.connect();
              window.liveSocket = liveSocket;
              console.log("[Exoforge Studio] Connected to BEAM via Phoenix LiveView!");
            }
          });
        </script>
      </head>
      <body class="text-gray-800 bg-[#f3f4f6] min-h-screen flex flex-col antialiased selection:bg-primary-500 selection:text-white pb-20 md:pb-8">
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main>
      <%= @inner_content %>
    </main>
    """
  end
end
