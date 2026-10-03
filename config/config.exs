import Config

config :exoforge,
  start_gateway: true,
  gateway_port: 4000,
  require_admin_auth: true

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: "exoforge_secret_key_base_for_dashboard_liveview_at_least_64_bytes_long_1234567890_exo",
  live_view: [signing_salt: "exoforge_liveview_salt_123"],
  render_errors: [formats: [html: Exoforge.Std.Dashboard.ErrorHTML, json: Exoforge.Std.Dashboard.ErrorJSON], layout: false],
  pubsub_server: Exoforge.Std.Dashboard.PubSub

config :phoenix, :json_library, Jason

Config.import_config("#{config_env()}.exs")
