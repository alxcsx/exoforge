defmodule Exoforge.Std.Database.Adapters.Postgres do
  # Postgrex connect timeout, in milliseconds.
  @connect_timeout 3000
  # Keep per-extension pools small so N extensions stay well under Postgres max_connections (100).
  @default_pool_size 2

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
    pool_size = Map.get(config, :pool_size, @default_pool_size)

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
    schema_name = schema_name(plugin_id, config)
    tbl = to_string(command[:table])

    case real_table_info(plugin_id, schema_name, tbl, config) do
      {:resource_table, info} ->
        execute_resource_kv(action, plugin_id, schema_name, tbl, info, command, config)

      :missing when action in [:put, :get, :all] ->
        if declared_resource_table?(tbl) do
          {:error, {:missing_resource_table, tbl}}
        else
          execute_doc_kv(action, plugin_id, schema_name, tbl, command, config)
        end

      _ ->
        execute_doc_kv(action, plugin_id, schema_name, tbl, command, config)
    end
  end

  defp execute_resource_kv(:put, plugin_id, schema_name, tbl, %{columns: cols, types: types, pk: pk_col}, command, config) do
    id = to_string(command[:id])
    data = command[:data] || %{}
    record = Map.put(data, "id", id)
    data_with_pk = Map.put(data, pk_col, id)

    valid_pairs =
      Enum.flat_map(cols, fn col ->
        case Map.fetch(data_with_pk, col) do
          {:ok, val} ->
            [{col, val}]

          :error ->
            case Enum.find(data_with_pk, fn {k, _} -> to_string(k) == col end) do
              {_, val} -> [{col, val}]
              nil -> []
            end
        end
      end)

    if valid_pairs == [] do
      execute_doc_kv(:put, plugin_id, schema_name, tbl, command, config)
    else
      with {:ok, coerced_pairs} <- coerce_pairs(valid_pairs, types) do
        safe_schema = quote_ident(schema_name)
        safe_tbl = quote_ident(tbl)
        safe_pk = quote_ident(pk_col)
        {names, values} = Enum.unzip(coerced_pairs)
        placeholders = Enum.map_join(1..length(names), ", ", &"$#{&1}")

        updates =
          names
          |> Enum.reject(&(&1 == pk_col))
          |> Enum.map_join(", ", fn col ->
            q = quote_ident(col)
            "#{q} = EXCLUDED.#{q}"
          end)

        sql =
          "INSERT INTO #{safe_schema}.#{safe_tbl} (#{Enum.map_join(names, ", ", &quote_ident/1)}) " <>
            "VALUES (#{placeholders}) " <>
            if(updates == "",
              do: "ON CONFLICT (#{safe_pk}) DO NOTHING",
              else: "ON CONFLICT (#{safe_pk}) DO UPDATE SET #{updates}"
            )

        with {:ok, _} <- execute(plugin_id, sql, values, config) do
          {:ok, %{rows: [record], num_rows: 1}}
        end
      end
    end
  end

  defp execute_resource_kv(:get, plugin_id, schema_name, tbl, %{types: types, pk: pk_col}, command, config) do
    with {:ok, id} <- coerce_value(pk_col, Map.get(types, pk_col), to_string(command[:id])) do
      sql = "SELECT * FROM #{quote_ident(schema_name)}.#{quote_ident(tbl)} WHERE #{quote_ident(pk_col)} = $1"

      case execute(plugin_id, sql, [id], config) do
        {:ok, %{rows: [row | _]}} -> {:ok, %{rows: [decode_resource_row(row)], num_rows: 1}}
        {:ok, %{rows: []}} -> {:ok, %{rows: [], num_rows: 0}}
        error -> error
      end
    end
  end

  defp execute_resource_kv(:delete, plugin_id, schema_name, tbl, %{types: types, pk: pk_col}, command, config) do
    with {:ok, id} <- coerce_value(pk_col, Map.get(types, pk_col), to_string(command[:id])) do
      sql = "DELETE FROM #{quote_ident(schema_name)}.#{quote_ident(tbl)} WHERE #{quote_ident(pk_col)} = $1"
      execute(plugin_id, sql, [id], config)
    end
  end

  defp execute_resource_kv(:all, plugin_id, schema_name, tbl, _info, _command, config) do
    sql = "SELECT * FROM #{quote_ident(schema_name)}.#{quote_ident(tbl)}"

    with {:ok, %{rows: rows}} <- execute(plugin_id, sql, [], config) do
      decoded = Enum.map(rows, &decode_resource_row/1)
      {:ok, %{rows: decoded, num_rows: length(decoded)}}
    end
  end

  defp execute_resource_kv(other, _plugin_id, _schema_name, _tbl, _info, _command, _config),
    do: {:error, {:unknown_action, other}}

  defp execute_doc_kv(action, plugin_id, schema_name, tbl, command, config) do
    # Convenience key-value / document emulation on top of Postgres
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

  defp real_table_info(plugin_id, schema_name, tbl, config) do
    cols_sql =
      "SELECT column_name, data_type FROM information_schema.columns " <>
        "WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position"

    case execute(plugin_id, cols_sql, [schema_name, to_string(tbl)], config) do
      {:ok, %{rows: []}} ->
        :missing

      {:ok, %{rows: rows}} ->
        cols = Enum.map(rows, &to_string(&1["column_name"]))

        if Enum.sort(cols) == ["data", "id", "updated_at"] do
          :kv_table
        else
          types = Map.new(rows, &{to_string(&1["column_name"]), to_string(&1["data_type"])})

          pk_sql =
            "SELECT kcu.column_name " <>
              "FROM information_schema.table_constraints tc " <>
              "JOIN information_schema.key_column_usage kcu " <>
              "ON tc.constraint_name = kcu.constraint_name " <>
              "AND tc.table_schema = kcu.table_schema " <>
              "AND tc.table_name = kcu.table_name " <>
              "WHERE tc.constraint_type = 'PRIMARY KEY' " <>
              "AND tc.table_schema = $1 AND tc.table_name = $2 " <>
              "ORDER BY kcu.ordinal_position LIMIT 1"

          pk_col =
            case execute(plugin_id, pk_sql, [schema_name, tbl], config) do
              {:ok, %{rows: [%{"column_name" => col} | _]}} -> to_string(col)
              _ -> "id"
            end

          {:resource_table, %{columns: cols, types: types, pk: pk_col}}
        end

      _ ->
        :missing
    end
  end

  defp coerce_pairs(pairs, types) do
    Enum.reduce_while(pairs, {:ok, []}, fn {col, val}, {:ok, acc} ->
      case coerce_value(col, Map.get(types, col), val) do
        {:ok, coerced} -> {:cont, {:ok, [{col, coerced} | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp coerce_value(_col, _type, nil), do: {:ok, nil}

  defp coerce_value(col, type, val) when type in ["integer", "smallint", "bigint"] do
    cond do
      is_integer(val) ->
        {:ok, val}

      is_float(val) and trunc(val) == val ->
        {:ok, trunc(val)}

      is_binary(val) ->
        case Integer.parse(String.trim(val)) do
          {n, ""} -> {:ok, n}
          _ -> {:error, {:invalid_value, col, type}}
        end

      true ->
        {:error, {:invalid_value, col, type}}
    end
  end

  defp coerce_value(col, type, val) when type in ["numeric", "decimal", "real", "double precision"] do
    cond do
      is_number(val) ->
        {:ok, val}

      is_binary(val) ->
        case Float.parse(String.trim(val)) do
          {n, ""} -> {:ok, n}
          _ -> {:error, {:invalid_value, col, type}}
        end

      true ->
        {:error, {:invalid_value, col, type}}
    end
  end

  defp coerce_value(col, "boolean" = type, val) do
    cond do
      is_boolean(val) ->
        {:ok, val}

      val in [1, "1", "true", "t", "TRUE", "True"] ->
        {:ok, true}

      val in [0, "0", "false", "f", "FALSE", "False"] ->
        {:ok, false}

      is_binary(val) ->
        case String.downcase(String.trim(val)) do
          s when s in ["true", "t", "1"] -> {:ok, true}
          s when s in ["false", "f", "0"] -> {:ok, false}
          _ -> {:error, {:invalid_value, col, type}}
        end

      true ->
        {:error, {:invalid_value, col, type}}
    end
  end

  defp coerce_value(col, "timestamp without time zone" = type, val) do
    case val do
      %NaiveDateTime{} ->
        {:ok, val}

      %DateTime{} ->
        {:ok, DateTime.to_naive(val)}

      s when is_binary(s) ->
        case NaiveDateTime.from_iso8601(s) do
          {:ok, ndt} ->
            {:ok, ndt}

          {:error, _} ->
            case DateTime.from_iso8601(s) do
              {:ok, dt, _} -> {:ok, DateTime.to_naive(dt)}
              {:error, _} -> {:error, {:invalid_value, col, type}}
            end
        end

      _ ->
        {:error, {:invalid_value, col, type}}
    end
  end

  defp coerce_value(col, "timestamp with time zone" = type, val) do
    case val do
      %DateTime{} ->
        {:ok, val}

      %NaiveDateTime{} ->
        {:ok, DateTime.from_naive!(val, "Etc/UTC")}

      s when is_binary(s) ->
        case DateTime.from_iso8601(s) do
          {:ok, dt, _} ->
            {:ok, dt}

          {:error, _} ->
            case NaiveDateTime.from_iso8601(s) do
              {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
              {:error, _} -> {:error, {:invalid_value, col, type}}
            end
        end

      _ ->
        {:error, {:invalid_value, col, type}}
    end
  end

  defp coerce_value(col, type, val) when type in ["json", "jsonb"] do
    cond do
      is_binary(val) -> {:ok, val}
      is_map(val) or is_list(val) -> {:ok, Jason.encode!(val)}
      true -> {:error, {:invalid_value, col, type}}
    end
  end

  defp coerce_value(_col, _type, val), do: {:ok, val}

  defp decode_resource_row(row) when is_map(row) do
    Map.new(row, fn {col, val} -> {col, decode_resource_value(val)} end)
  end

  defp decode_resource_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp decode_resource_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp decode_resource_value(%Decimal{} = dec), do: Decimal.to_float(dec)
  defp decode_resource_value(val), do: val

  defp declared_resource_table?(tbl) do
    table = to_string(tbl)

    case Exoforge.ExtensionRegistry.fetch_resource(table) do
      {:ok, %{resource: res}} -> table_source(res) == table
      _ -> false
    end
  rescue
    _ -> false
  end

  defp table_source(res) when is_map(res) do
    source = Map.get(res, :source) || Map.get(res, "source")

    case source do
      {:table, t} -> to_string(t)
      [:table, t] -> to_string(t)
      ["table", t] -> to_string(t)
      %{table: t} -> to_string(t)
      %{"table" => t} -> to_string(t)
      _ -> Map.get(res, :table) || Map.get(res, "table")
    end
  end

  defp table_source(_), do: nil

  defp quote_ident(name), do: ~s("#{String.replace(to_string(name), "\"", "")}")


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
        pool_size: Map.get(config, :pool_size, @default_pool_size),
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
