defmodule Exoforge.Std.Dashboard.Layouts do
  @moduledoc """
  Root and application layout components for the Exoforge Game Producer & Designer Studio.
  Design tokens and Dark/Light theme engine for the Exoforge Studio shell.
  """
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="dark">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>EXOFORGE - Game Producer & Designer Studio</title>
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
        </script>
        <link rel="stylesheet" href="/vendor/exoforge-studio.css">
        <!-- Tailwind CSS, vendored locally: instant load, no network dependency, and no
             third-party script the page does not control (M33 Fix 36) -->
        <script src="/vendor/tailwind.js"></script>
        <script>
          if (typeof tailwind !== 'undefined') {
            tailwind.config = {
              darkMode: 'class',
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
                    'card': 'var(--exo-shadow-card)'
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
            background: transparent;
          }
          .custom-scrollbar::-webkit-scrollbar-thumb {
            background: rgba(139, 92, 246, 0.35);
            border-radius: 9999px;
          }
          .prof-tab-btn { justify-content: flex-start; text-align: left; }
          .prof-tab-btn .prof-tab-label { min-width: 0; display: flex; align-items: center; gap: 0.625rem; }
          .prof-tab-btn .prof-tab-badge { margin-left: auto; flex-shrink: 0; }
        </style>
        <script defer src="/vendor/phoenix.js"></script>
        <script defer src="/vendor/phoenix_live_view.js"></script>
        <script>
          window.ExoforgeTheme = {
            get: function() {
              try {
                return localStorage.getItem('exo_theme') || 'dark';
              } catch (e) {
                return 'dark';
              }
            },
            set: function(mode) {
              var next = mode === 'light' ? 'light' : 'dark';
              try { localStorage.setItem('exo_theme', next); } catch (e) {}
              var root = document.documentElement;
              root.classList.remove('dark', 'light');
              root.classList.add(next);
              window.dispatchEvent(new CustomEvent('exoforge:theme', { detail: { theme: next } }));
              return next;
            },
            toggle: function() {
              var current = document.documentElement.classList.contains('light') ? 'light' : 'dark';
              return this.set(current === 'dark' ? 'light' : 'dark');
            }
          };

          document.addEventListener("click", function(e) {
            document.querySelectorAll("details.exo-menu[open]").forEach(function(menu) {
              if (!menu.contains(e.target)) {
                menu.removeAttribute("open");
              }
            });
          });

          document.addEventListener("DOMContentLoaded", function() {
            if (window.LiveView && window.Phoenix) {
              const metaEl = document.querySelector("meta[name='csrf-token']");
              const csrfToken = metaEl ? metaEl.getAttribute("content") : "";

              const Hooks = {
                StudioDispatcher: {
                  mounted() {
                    window._studioDispatcher = this;
                  },
                  destroyed() {
                    if (window._studioDispatcher === this) {
                      window._studioDispatcher = null;
                    }
                  }
                },
                MicrofrontendLoader: {
                  mounted() {
                    this.load();
                  },
                  updated() {
                    this.load();
                  },
                  load() {
                    const entry = this.el.dataset.entry;
                    const element = this.el.dataset.element;
                    if (!entry) return;
                    import(entry)
                      .then((mod) => {
                        console.log("[Exoforge MFE] Loaded successfully:", entry);
                        const customEl = element ? this.el.querySelector(element) : null;
                        const target = customEl || this.el;
                        if (customEl) {
                          customEl.style.display = 'block';
                        }
                        if (mod && typeof mod.mount === 'function') {
                          mod.mount(target);
                        } else if (customEl && typeof customEl.connectedCallback === 'function' && !customEl.hasChildNodes()) {
                          customEl.connectedCallback();
                        }
                      })
                      .catch((err) => {
                        console.error("[Exoforge MFE] Error loading module:", entry, err);
                        this.el.innerHTML = `
                          <div class="p-6 bg-red-50 border border-red-200 rounded-xl text-red-700">
                            <h3 class="font-bold text-sm">Failed to load plugin microfrontend</h3>
                            <p class="text-xs mt-1 text-red-600 font-mono">${err && err.message ? err.message : String(err)}</p>
                            <p class="text-[11px] text-gray-500 mt-2 font-mono">Entry: ${entry}</p>
                          </div>
                        `;
                      });
                  }
                }
              };

              const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
                params: { _csrf_token: csrfToken },
                hooks: Hooks
              });

              window.Exoforge = {
                httpBaseUri: "/api",
                theme: window.ExoforgeTheme,
                dispatch: async function(service, action, payload = {}) {
                  // 1. Primary: If LiveView WebSocket is connected, push over the socket (0 HTTP roundtrips)
                  if (window._studioDispatcher && window.liveSocket && window.liveSocket.isConnected()) {
                    return new Promise((resolve) => {
                      window._studioDispatcher.pushEvent("studio_dispatch", { service, action, payload }, (reply) => {
                        resolve(reply);
                      });
                    });
                  }

                  // 2. Fallback: If socket is disconnected or unavailable, fall back to standard HTTP REST
                  const csrf = metaEl ? metaEl.getAttribute("content") : "";
                  const cookieMatch = document.cookie.match(/(?:^|;\s*)exo_auth_token=([^;]+)/);
                  const token = cookieMatch ? decodeURIComponent(cookieMatch[1].trim()) : "";

                  const headers = {
                    "content-type": "application/json",
                    "x-csrf-token": csrf
                  };
                  if (token) {
                    headers["authorization"] = "Bearer " + token;
                  }

                  const resp = await fetch(`/api/${encodeURIComponent(service)}/${encodeURIComponent(action)}`, {
                    method: "POST",
                    credentials: "same-origin",
                    headers: headers,
                    body: JSON.stringify(payload)
                  });
                  return await resp.json();
                },
                callAction: async function(service, action, payload = {}) {
                  const res = await this.dispatch(service, action, payload);
                  if (res && res.status === "ok") {
                    return res.data;
                  }
                  throw new Error(res && res.error ? res.error : "Action failed");
                },
                notifySuccess: function(msg) {
                  console.log("[Exoforge Studio]", msg);
                  window.dispatchEvent(new CustomEvent("exoforge:toast", { detail: { message: msg, type: "success" } }));
                }
              };

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
    <main id="studio-main" phx-hook="StudioDispatcher">
      <%= @inner_content %>
    </main>
    """
  end
end
