import Config

config :exoforge,
  start_gateway: false,
  gateway_port: 4002

config :exoforge, :module_loader,
  driver: Exoforge.Drivers.Loaders.ManifestLoader,
  scan_path: ["_build/test/lib", "plugins_csharp"]

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: 4005],
  server: false
