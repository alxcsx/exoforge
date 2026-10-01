import Config

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || System.get_env("DASHBOARD_PORT") || "4005")],
  server: true,
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 4005]
