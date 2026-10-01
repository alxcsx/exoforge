import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "exoforge_prod_secret_key_base_default_generated_for_production_nodes_1234567890_super_secure"

  host = System.get_env("PHX_HOST") || "localhost"
  dashboard_port = String.to_integer(System.get_env("PORT") || System.get_env("DASHBOARD_PORT") || "4005")
  gateway_port = String.to_integer(System.get_env("GATEWAY_PORT") || "4000")
  http_port = String.to_integer(System.get_env("HTTP_PORT") || "4001")

  config :exoforge,
    start_gateway: true,
    gateway_port: gateway_port,
    ws_port: gateway_port,
    http_port: http_port

  config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
    url: [host: host, port: dashboard_port],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: dashboard_port
    ],
    secret_key_base: secret_key_base,
    server: true

  if database_url = System.get_env("DATABASE_URL") do
    config :exoforge, :database,
      url: database_url,
      driver: :postgres
  end

  scan_paths =
    [
      System.get_env("PLUGINS_PATH"),
      "/app/plugins",
      "plugins",
      "_build/prod/lib",
      "plugins_csharp"
    ]
    |> Enum.reject(&is_nil/1)

  config :exoforge, :module_loader, scan_path: scan_paths
end
