import Config

config :exoforge,
  start_gateway: false,
  gateway_port: 4002,
  allow_dev_tokens: true,
  require_admin_auth: false,
  admin: [email: "admin@exoforge.local", password: "exoforge"],
  studio: [email: "studio@exoforge.local", password: "studio"]

config :exoforge, :module_loader,
  driver: Exoforge.Drivers.Loaders.ManifestLoader,
  scan_path: ["_build/test/lib", "plugins_csharp"]

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: 4005],
  server: false
