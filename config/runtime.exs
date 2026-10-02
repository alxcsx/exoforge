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
      System.get_env("PLUGINS_PATH") || "plugins",
      "_build/prod/lib",
      "plugins_csharp"
    ]

  config :exoforge, :module_loader, scan_path: scan_paths

  # Cluster formation & discovery
  cluster_strategy =
    System.get_env("CLUSTER_STRATEGY") ||
      if(System.get_env("KUBERNETES_SERVICE_HOST"), do: "kubernetes", else: "local")

  case cluster_strategy do
    "kubernetes" ->
      k8s_service = System.get_env("K8S_SERVICE_NAME") || "exoforge-nodes.exoforge.svc.cluster.local"
      k8s_app = System.get_env("K8S_APP_NAME") || "exoforge"

      topologies = [
        k8s_dns: [
          strategy: Cluster.Strategy.Kubernetes.DNS,
          config: [
            service: k8s_service,
            application_name: k8s_app
          ]
        ]
      ]

      config :libcluster, topologies: topologies
      config :exoforge, :entity_adapter, Exoforge.Entities.Adapters.Horde

    "epmd" ->
      topologies = [
        epmd: [
          strategy: Cluster.Strategy.Epmd,
          config: [
            hosts: [:"exoforge@127.0.0.1"]
          ]
        ]
      ]

      config :libcluster, topologies: topologies
      config :exoforge, :entity_adapter, Exoforge.Entities.Adapters.Horde

    _ ->
      :ok
  end
end
