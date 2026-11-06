import Config

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || System.get_env("DASHBOARD_PORT") || "4005")],
  server: true,
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 4005]

# Sessions and LiveView sockets are signed with these (M33 Fix 30): a hardcoded value would let
# anyone forge a session, so production demands them from the environment and will not boot
# without them.
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise "SECRET_KEY_BASE is not set: production Studio sessions cannot be signed safely."

signing_salt =
  System.get_env("LIVEVIEW_SIGNING_SALT") ||
    raise "LIVEVIEW_SIGNING_SALT is not set: production LiveView sockets cannot be signed safely."

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  secret_key_base: secret_key_base,
  live_view: [signing_salt: signing_salt]
