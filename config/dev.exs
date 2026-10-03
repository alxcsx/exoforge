import Config

config :exoforge,
  allow_dev_tokens: true

config :exoforge, :module_loader,
  driver: Exoforge.Drivers.Loaders.ManifestLoader,
  scan_path: ["_build/dev/lib", "plugins_csharp"]

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  http: [port: 4005],
  server: true

# First-access admin account for local development.
config :exoforge, :admin,
  email: "admin@exoforge.local",
  password: "exoforge"

# Optional studio (read-mostly) account.
config :exoforge, :studio,
  email: "studio@exoforge.local",
  password: "studio"
