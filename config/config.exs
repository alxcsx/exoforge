import Config

config :logger, :default_formatter, format: "$time [$level] $message\n"

config :logger, :console, format: "$time [$level] $message\n"

config :exoforge,
  start_gateway: true,
  gateway_port: 4000,
  require_admin_auth: true

# The shape usage records are stamped with: one Title per instance, and a studio is the account the
# bill goes to. Both are constant until there is more than one - what matters now is that the shape
# exists, so the rollup is a GROUP BY on day one rather than a migration (see plan.md, M32).
config :exoforge, :instance,
  title_id: "local",
  studio_id: "local"

config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: "exoforge_secret_key_base_for_dashboard_liveview_at_least_64_bytes_long_1234567890_exo",
  live_view: [signing_salt: "exoforge_liveview_salt_123"],
  render_errors: [
    formats: [html: Exoforge.Std.Dashboard.ErrorHTML, json: Exoforge.Std.Dashboard.ErrorJSON],
    layout: false
  ],
  pubsub_server: Exoforge.Std.Dashboard.PubSub

config :phoenix, :json_library, Jason

Config.import_config("#{config_env()}.exs")
