defmodule Exoforge.Std.Http.Cors do
  @moduledoc """
  Manages dynamic CORS (Cross-Origin Resource Sharing) policies for HTTP Ingress.
  Provides in-memory caching via ETS for microsecond header evaluation,
  with persistence to the isolated database.
  """
  alias Exoforge.ActionDispatcher
  require Logger

  @table :exo_http_cors_config
  @settings_table "http_settings"

  @default_config %{
    "mode" => "relaxed",
    "allowed_origins" => "*",
    "allow_credentials" => true,
    "max_age" => 86400
  }

  def init do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    init_db()
    load_from_db()
    :ok
  end

  def get_config do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      :ets.insert(@table, {:config, @default_config})
      @default_config
    else
      case :ets.lookup(@table, :config) do
        [{:config, config}] when is_map(config) -> config
        _ ->
          :ets.insert(@table, {:config, @default_config})
          @default_config
      end
    end
  end

  def set_config(params) when is_map(params) do
    current = get_config()

    mode =
      case Map.get(params, "mode") || Map.get(params, :mode) do
        m when m in ["relaxed", "whitelist", "strict"] -> m
        _ -> current["mode"]
      end

    allowed_origins =
      case Map.get(params, "allowed_origins") || Map.get(params, :allowed_origins) do
        origins when is_binary(origins) ->
          String.trim(origins)

        origins when is_list(origins) ->
          origins |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.join(", ")

        _ ->
          current["allowed_origins"]
      end

    allow_credentials =
      case Map.get(params, "allow_credentials") do
        nil ->
          case Map.get(params, :allow_credentials) do
            nil -> current["allow_credentials"]
            v -> truthy?(v)
          end
        v -> truthy?(v)
      end

    max_age =
      case Map.get(params, "max_age") || Map.get(params, :max_age) do
        age when is_integer(age) and age > 0 -> age
        age when is_binary(age) ->
          case Integer.parse(age) do
            {int, ""} when int > 0 -> int
            _ -> current["max_age"]
          end
        _ -> current["max_age"]
      end

    updated = %{
      "mode" => mode,
      "allowed_origins" => allowed_origins,
      "allow_credentials" => allow_credentials,
      "max_age" => max_age
    }

    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ets.insert(@table, {:config, updated})
    persist_to_db(updated)

    Logger.info("[HTTP:CORS] Updated CORS policy: mode=#{mode}, origins=#{allowed_origins}, credentials=#{allow_credentials}")
    {:ok, updated}
  end

  def cors_headers(conn) do
    config = get_config()
    mode = config["mode"]
    req_origin = Plug.Conn.get_req_header(conn, "origin") |> List.first()

    case mode do
      "strict" ->
        []

      "relaxed" ->
        allow_origin =
          if config["allow_credentials"] && is_binary(req_origin) && req_origin != "" do
            req_origin
          else
            "*"
          end

        build_headers(allow_origin, config)

      "whitelist" ->
        allowed_list =
          (config["allowed_origins"] || "*")
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)

        matched? =
          is_binary(req_origin) &&
            Enum.any?(allowed_list, fn allowed ->
              allowed == "*" || String.downcase(allowed) == String.downcase(req_origin)
            end)

        if matched? do
          build_headers(req_origin, config)
        else
          []
        end

      _ ->
        []
    end
  end

  defp build_headers(allow_origin, config) do
    base = [
      {"access-control-allow-origin", allow_origin},
      {"access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH"},
      {"access-control-allow-headers", "Authorization, Content-Type, Accept, X-Requested-With, Origin, X-CSRF-Token"},
      {"access-control-max-age", to_string(config["max_age"] || 86400)}
    ]

    headers_with_vary =
      if allow_origin != "*" do
        [{"vary", "Origin"} | base]
      else
        base
      end

    if config["allow_credentials"] && allow_origin != "*" do
      [{"access-control-allow-credentials", "true"} | headers_with_vary]
    else
      headers_with_vary
    end
  end

  defp truthy?(val) when val in [true, "true", "1", 1], do: true
  defp truthy?(_), do: false

  defp init_db do
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :http,
        operation: "CREATE TABLE IF NOT EXISTS #{@settings_table} (key text PRIMARY KEY, value text)"
      })
  rescue
    _ -> :ok
  end

  defp load_from_db do
    case ActionDispatcher.dispatch(:database, :execute, %{
           plugin: :http,
           operation: "SELECT value FROM #{@settings_table} WHERE key = $1",
           arguments: ["cors_config"]
         }) do
      {:ok, %{rows: [row | _]}} ->
        raw = Map.get(row, "value") || Map.get(row, :value)
        case Jason.decode(raw) do
          {:ok, parsed} when is_map(parsed) ->
            :ets.insert(@table, {:config, Map.merge(@default_config, parsed)})
          _ ->
            :ets.insert(@table, {:config, @default_config})
        end

      _ ->
        :ets.insert(@table, {:config, @default_config})
    end
  rescue
    _ ->
      :ets.insert(@table, {:config, @default_config})
  end

  defp persist_to_db(config) do
    json = Jason.encode!(config)
    _ =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :http,
        operation: "INSERT INTO #{@settings_table} (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = $2",
        arguments: ["cors_config", json]
      })
  rescue
    _ -> :ok
  end
end
