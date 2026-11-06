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

                  Logger.info("[Database] Provisioned dedicated database #{db_name} for plugin #{inspect(plugin_id)}")

                  {:ok, %{status: :created, database: db_name, plugin: plugin_id}}

                {:ok, _} ->
                  {:ok, %{status: :exists, database: db_name, plugin: plugin_id}}

                {:error, reason} ->
                  Logger.warning("[Database] Error checking/creating database #{db_name}: #{inspect(reason)}, falling back to schema")

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
        Logger.info("[Database] Provisioned dedicated schema #{schema_name} for plugin #{inspect(plugin_id)}")

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

    with {:ok, params} <- positional_args(args),
         {:ok, {mode, conn}} <- pooled_connection(plugin_id, schema_name, config) do
      try do
        query_pooled(conn, query, params)
      after
        # An unmanaged connection (no pool supervisor running) is per-call, as before.
        if mode == :unmanaged, do: GenServer.stop(conn)
      end
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


  @impl true
  def table_columns(plugin_id, table, config) do
    schema_name = schema_name(plugin_id, config)

    case execute(
           plugin_id,
           "SELECT column_name FROM information_schema.columns " <>
             "WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position",
           [schema_name, to_string(table)],
           config
         ) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &to_string(&1["column_name"]))}
      error -> error
    end
  end

  defp query_pooled(conn, query, params) do
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
    Postgrex.start_link(connection_opts(root_database(config), config) ++ [pool_size: 1])
  end

  # One supervised pool per (database, schema) pair, named so a second start finds the first
  # (M33 Fix 8): a query reuses an established connection instead of dialing per call, and the
  # supervisor restarts a pool that drops. The search_path is a startup parameter, so every
  # connection in the pool opens inside the plugin's schema and no per-query SET is needed.
  defp pooled_connection(plugin_id, schema_name, config) do
    if Process.whereis(Exoforge.Std.Database.PoolSupervisor) != nil do
      supervise_pooled(plugin_id, schema_name, config)
    else
      # ponytail: unsupervised single connection for direct adapter use (tests without the
      # plugin's supervision tree); the tree is the upgrade path.
      unmanaged_connection(plugin_id, config)
    end
  end

  defp supervise_pooled(plugin_id, schema_name, config) do
    name = {:via, Registry, {Exoforge.Std.Database.PoolRegistry, {target_database(plugin_id, config), schema_name}}}

    opts =
      connection_opts(target_database(plugin_id, config), config)
      |> Keyword.merge(
        name: name,
        pool_size: Map.get(config, :pool_size, 10),
        parameters: [search_path: ~s("#{schema_name}", public)]
      )

    case DynamicSupervisor.start_child(Exoforge.Std.Database.PoolSupervisor, Postgrex.child_spec(opts)) do
      {:ok, pid} -> {:ok, {:managed, pid}}
      {:error, {:already_started, pid}} -> {:ok, {:managed, pid}}
      {:error, reason} -> {:error, {:connection_failed, reason}}
    end
  end

  defp unmanaged_connection(plugin_id, config) do
    case Postgrex.start_link(connection_opts(target_database(plugin_id, config), config) ++ [pool_size: 1]) do
      {:ok, conn} -> {:ok, {:unmanaged, conn}}
      {:error, reason} -> {:error, {:connection_failed, reason}}
    end
  end

  defp connection_opts(target_db, config) do
    [
      hostname: Map.get(config, :host, "localhost"),
      port: Map.get(config, :port, 5432),
      username: Map.get(config, :username, "postgres"),
      password: Map.get(config, :password, ""),
      database: target_db,
      timeout: @connect_timeout
    ]
  end

  defp root_database(config), do: Map.get(config, :database, "postgres")

  defp target_database(plugin_id, config) do
    if Map.get(config, :isolation_mode, :schema) == :database do
      database_name(plugin_id, config)
    else
      root_database(config)
    end
  end

  # A map's values have no order, so binding them to positional parameters would make the query's
  # meaning depend on an implementation detail (M33 Fix 10). Key-value work is the command path.
  defp positional_args(args) when is_list(args), do: {:ok, args}
  defp positional_args(nil), do: {:ok, []}
  defp positional_args(args) when is_map(args), do: {:error, :positional_args_must_be_list}

  defp positional_args(_), do: {:ok, []}

  defp database_name(plugin_id, config) do
    prefix = Map.get(config, :db_prefix, "exoforge_")
    "#{prefix}#{Exoforge.Std.Database.clean_id(plugin_id)}"
  end

  defp schema_name(plugin_id, config) do
    prefix = Map.get(config, :schema_prefix, "plugin_")
    "#{prefix}#{Exoforge.Std.Database.clean_id(plugin_id)}"
  end
end
