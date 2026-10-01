import Config

config :exoforge, :module_loader,
  driver: Exoforge.Drivers.Loaders.ManifestLoader,
  scan_path: ["_build/dev/lib", "plugins_csharp"]

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: 4005],
  server: true
