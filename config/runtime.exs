import Config

if config_env() == :prod do
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

  host = System.get_env("PHX_HOST") || "localhost"
  dashboard_port = String.to_integer(System.get_env("PORT") || System.get_env("DASHBOARD_PORT") || "4005")
  gateway_port = String.to_integer(System.get_env("GATEWAY_PORT") || "4000")
  http_port = String.to_integer(System.get_env("HTTP_PORT") || "4001")

  config :exoforge,
    start_gateway: true,
    gateway_port: gateway_port,
    ws_port: gateway_port,
    http_port: http_port,
    # The dashboard endpoint below reads PORT directly, so mirror it here: everything that asks
    # Exoforge.Endpoints.dashboard_port/0 must agree with the port the Studio actually listens on.
    dashboard_port: dashboard_port,
    studio_host: host,
    allow_dev_tokens: false,
    require_admin_auth: true,
    admin: [
      email: System.get_env("EXOFORGE_ADMIN_EMAIL"),
      password: System.get_env("EXOFORGE_ADMIN_PASSWORD")
    ],
    studio: [
      email: System.get_env("EXOFORGE_STUDIO_EMAIL"),
      password: System.get_env("EXOFORGE_STUDIO_PASSWORD")
    ]

  # The shape usage records are stamped with. A deployment names its own title and studio; the
  # defaults from config.exs ("local") stand in for a self-hosted instance until there is more
  # than one Title to distinguish.
  config :exoforge, :instance,
    title_id: System.get_env("EXOFORGE_TITLE_ID") || "local",
    studio_id: System.get_env("EXOFORGE_STUDIO_ID") || "local"

  config :exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint,
    url: [host: host, port: dashboard_port],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: dashboard_port
    ],
    secret_key_base: secret_key_base,
    # The salt signs LiveView sockets (M33 Fix 30); demanded, like the key base, and
    # baked into the local defaults (compose) so a self-hosted instance stays zero-config.
    live_view: [signing_salt: System.fetch_env!("LIVEVIEW_SIGNING_SALT")],
    server: true

  if database_url = System.get_env("DATABASE_URL") do
    config :exoforge, :database,
      url: database_url,
      driver: :postgres
  end

  # The release's own applications live in `lib/` beside `bin/`, not under `_build/prod/lib` - which
  # is a checkout path and does not exist in a release. Without this a containerised server boots with
  # no standard plugins at all: no database, no auth, and nothing louder than a warning.
  release_lib = Path.join([:code.root_dir(), "lib"])

  scan_paths =
    [
      System.get_env("PLUGINS_PATH") || "plugins",
      "_build/prod/lib",
      release_lib,
      "plugins_csharp",
      "priv/data/uploaded_plugins"
    ]
    |> Enum.uniq()

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

    _ ->
      :ok
  end
end
