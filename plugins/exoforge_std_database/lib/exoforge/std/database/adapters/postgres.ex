defmodule Exoforge.Std.Database.Adapters.Postgres do
  # Postgrex connect timeout, in milliseconds.
  @connect_timeout 3000

  @moduledoc """
  PostgreSQL database adapter providing strict per-plugin multi-tenant isolation.
  Acts as the middleground between PostgreSQL and all Exoforge plugins.
  Supports both multi-database provisioning (CREATE DATABASE exoforge_<plugin>)
  and schema isolation (CREATE SCHEMA IF NOT EXISTS plugin_<plugin>) with dedicated search_paths.
  """
  @behaviour Exoforge.Std.Database.Adapter

  require Logger

  @impl true
  def ensure_database(plugin_id, config) do
    db_name = database_name(plugin_id, config)
    schema_name = schema_name(plugin_id, config)
    isolation_mode = Map.get(config, :isolation_mode, :schema)

    case connect_root(config) do
      {:ok, conn} ->
        try do
          case isolation_mode do
            :database ->
              # Create dedicated database if it doesn't exist
              case Postgrex.query(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [db_name]) do
                {:ok, %Postgrex.Result{num_rows: 0}} ->
                  # CREATE DATABASE cannot run in a transaction
                  Postgrex.query(conn, "CREATE DATABASE \"#{db_name}\"", [])

                  Logger.info(
                    "[Database] Provisioned dedicated database #{db_name} for plugin #{inspect(plugin_id)}"
                  )

                  {:ok, %{status: :created, database: db_name, plugin: plugin_id}}

                {:ok, _} ->
                  {:ok, %{status: :exists, database: db_name, plugin: plugin_id}}

                {:error, reason} ->
                  Logger.warning(
                    "[Database] Error checking/creating database #{db_name}: #{inspect(reason)}, falling back to schema"
                  )

                  ensure_schema(conn, schema_name, plugin_id)
              end

            _schema_mode ->
              ensure_schema(conn, schema_name, plugin_id)
          end
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  defp ensure_schema(conn, schema_name, plugin_id) do
    case Postgrex.query(conn, "CREATE SCHEMA IF NOT EXISTS \"#{schema_name}\"", []) do
      {:ok, _} ->
        Logger.info(
          "[Database] Provisioned dedicated schema #{schema_name} for plugin #{inspect(plugin_id)}"
        )

        {:ok, %{status: :ready, schema: schema_name, plugin: plugin_id}}

      {:error, reason} ->
        {:error, {:schema_creation_failed, reason}}
    end
  end

  @impl true
  def connection_config(plugin_id, config) do
    db_name = database_name(plugin_id, config)
    schema_name = schema_name(plugin_id, config)
    host = Map.get(config, :host, "localhost")
    port = Map.get(config, :port, 5432)
    user = Map.get(config, :username, "postgres")
    pass = Map.get(config, :password, "")
    pool_size = Map.get(config, :pool_size, 10)

    auth = if pass != "", do: "#{user}:#{pass}@", else: "#{user}@"
    url = "postgres://#{auth}#{host}:#{port}/#{db_name}?search_path=#{schema_name}"

    {:ok,
     %{
       url: url,
       database: db_name,
       schema: schema_name,
       driver: :postgres,
       pool_size: pool_size
     }}
  end

  @impl true
  def health_check(config) do
    case connect_root(config) do
      {:ok, conn} ->
        try do
          case Postgrex.query(conn, "SELECT 1", []) do
            {:ok, _} -> {:ok, %{status: "ok", driver: :postgres}}
            {:error, reason} -> {:error, {:query_failed, reason}}
          end
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, {:unreachable, reason}}
    end
  end

  @impl true
  def reset(plugin_id, config) do
    schema_name = schema_name(plugin_id, config)

    case connect_root(config) do
      {:ok, conn} ->
        try do
          Postgrex.query(conn, "DROP SCHEMA IF EXISTS \"#{schema_name}\" CASCADE", [])
          Postgrex.query(conn, "CREATE SCHEMA IF NOT EXISTS \"#{schema_name}\"", [])
          :ok
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute(plugin_id, query, args, config) when is_binary(query) do
    schema_name = schema_name(plugin_id, config)

    case connect_for_plugin(plugin_id, config) do
      {:ok, conn} ->
        try do
          # Enforce isolated search_path for this plugin
          _ = Postgrex.query(conn, "SET search_path TO \"#{schema_name}\", public", [])

          params = normalize_args(args)

          case Postgrex.query(conn, query, params) do
            {:ok, %Postgrex.Result{columns: columns, rows: rows, num_rows: num_rows}} ->
              formatted_rows =
                if columns != nil and rows != nil do
                  Enum.map(rows, fn row ->
                    Enum.zip(columns, row) |> Enum.into(%{})
                  end)
                else
                  []
                end

              {:ok, %{rows: formatted_rows, num_rows: num_rows}}

            {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
              {:error, {:postgres_error, msg}}

            {:error, reason} ->
              {:error, reason}
          end
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  def execute(plugin_id, %{action: action} = command, _args, config) do
    # Convenience key-value / document emulation on top of Postgres
    schema_name = schema_name(plugin_id, config)
    tbl = to_string(command[:table])

    create_sql = table_schema_sql(schema_name, tbl)

    case action do
      :put ->
        id = to_string(command[:id])
        data = Jason.encode!(command[:data] || %{})

        upsert_sql = """
        INSERT INTO "#{schema_name}"."#{tbl}" (id, data, updated_at)
        VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
        ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = CURRENT_TIMESTAMP;
        """

        with {:ok, _} <- execute(plugin_id, create_sql, [], config),
             {:ok, _} <- execute(plugin_id, upsert_sql, [id, data], config) do
          {:ok, %{rows: [%{"id" => id, "data" => command[:data]}], num_rows: 1}}
        end

      :get ->
        id = to_string(command[:id])
        sql = "SELECT data FROM \"#{schema_name}\".\"#{tbl}\" WHERE id = $1"

        with {:ok, _} <- execute(plugin_id, create_sql, [], config),
             {:ok, res} <- execute(plugin_id, sql, [id], config) do
          case res do
            %{rows: [%{"data" => json_data}]} ->
              data = if is_binary(json_data), do: Jason.decode!(json_data), else: json_data
              {:ok, %{rows: [Map.put(data, "id", id)], num_rows: 1}}

            %{rows: []} ->
              {:ok, %{rows: [], num_rows: 0}}
          end
        end

      :delete ->
        id = to_string(command[:id])
        sql = "DELETE FROM \"#{schema_name}\".\"#{tbl}\" WHERE id = $1"

        with {:ok, _} <- execute(plugin_id, create_sql, [], config) do
          execute(plugin_id, sql, [id], config)
        end

      :all ->
        sql = "SELECT id, data FROM \"#{schema_name}\".\"#{tbl}\""

        with {:ok, _} <- execute(plugin_id, create_sql, [], config),
             {:ok, %{rows: rows}} <- execute(plugin_id, sql, [], config) do
          decoded =
            Enum.map(rows, fn row ->
              d = if is_binary(row["data"]), do: Jason.decode!(row["data"]), else: row["data"]
              Map.put(d, "id", row["id"])
            end)

          {:ok, %{rows: decoded, num_rows: length(decoded)}}
        end

      other ->
        {:error, {:unknown_action, other}}
    end
  end

  defp table_schema_sql(schema_name, tbl) do
    """
    CREATE TABLE IF NOT EXISTS "#{schema_name}"."#{tbl}" (
      id text PRIMARY KEY,
      data jsonb NOT NULL,
      updated_at timestamp DEFAULT CURRENT_TIMESTAMP
    );
    """
  end

  ## ---- PRIVATE HELPERS ----

  defp connect_root(config) do
    opts = [
      hostname: Map.get(config, :host, "localhost"),
      port: Map.get(config, :port, 5432),
      username: Map.get(config, :username, "postgres"),
      password: Map.get(config, :password, ""),
      database: Map.get(config, :database, "postgres"),
      pool_size: 1,
      timeout: @connect_timeout
    ]

    Postgrex.start_link(opts)
  end

  defp connect_for_plugin(plugin_id, config) do
    isolation_mode = Map.get(config, :isolation_mode, :schema)

    target_db =
      if isolation_mode == :database do
        database_name(plugin_id, config)
      else
        Map.get(config, :database, "postgres")
      end

    opts = [
      hostname: Map.get(config, :host, "localhost"),
      port: Map.get(config, :port, 5432),
      username: Map.get(config, :username, "postgres"),
      password: Map.get(config, :password, ""),
      database: target_db,
      pool_size: 1,
      timeout: @connect_timeout
    ]

    Postgrex.start_link(opts)
  end

  defp normalize_args(args) when is_list(args), do: args
  defp normalize_args(args) when is_map(args), do: Map.values(args)
  defp normalize_args(_), do: []

  defp database_name(plugin_id, config) do
    prefix = Map.get(config, :db_prefix, "exoforge_")
    "#{prefix}#{Exoforge.Std.Database.clean_id(plugin_id)}"
  end

  defp schema_name(plugin_id, config) do
    prefix = Map.get(config, :schema_prefix, "plugin_")
    "#{prefix}#{Exoforge.Std.Database.clean_id(plugin_id)}"
  end

end
