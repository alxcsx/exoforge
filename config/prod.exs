import Config

config :exoforge,
  start_gateway: true,
  gateway_port: String.to_integer(System.get_env("GATEWAY_PORT") || "4000")

config :exoforge, :module_loader,
  driver: Exoforge.Drivers.Loaders.ManifestLoader,
  scan_path: [
    System.get_env("PLUGINS_PATH") || "_build/prod/lib",
    "plugins_csharp"
  ]

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || System.get_env("DASHBOARD_PORT") || "4005")],
  server: true,
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 4005]
