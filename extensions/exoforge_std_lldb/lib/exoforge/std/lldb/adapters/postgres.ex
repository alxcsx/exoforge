defmodule Exoforge.Std.Lldb.Adapters.Postgres do
  # Postgrex connect timeout, in milliseconds.
  @connect_timeout 3000
  # Keep per-extension pools small so N extensions stay well under Postgres max_connections (100).
  @default_pool_size 4

  @moduledoc """
  PostgreSQL database adapter providing strict per-plugin multi-tenant isolation.
  Acts as the middleground between PostgreSQL and all Exoforge plugins.
  Supports both multi-database provisioning (CREATE DATABASE exoforge_<plugin>)
  and schema isolation (CREATE SCHEMA IF NOT EXISTS plugin_<plugin>) with dedicated search_paths.
  """
  @behaviour Exoforge.Std.Lldb.Adapter

  require Logger

  @impl true
  def ensure_database(plugin_id, config) do
    _ = valid_plugin_id!(plugin_id)
    db_name = valid_ident!(database_name(plugin_id, config))
    schema_name = valid_ident!(schema_name(plugin_id, config))
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
                  Postgrex.query(conn, "CREATE DATABASE #{quote_ident(db_name)}", [])

                  Logger.info("[Database] Provisioned dedicated database #{db_name} for plugin #{inspect(plugin_id)}")

                  {:ok, %{status: :created, database: db_name, plugin: plugin_id}}

                {:ok, _} ->
                  {:ok, %{status: :exists, database: db_name, plugin: plugin_id}}

                {:error, reason} ->
                  Logger.warning("[Database] Error checking/creating database #{db_name}: #{inspect(reason)}, falling back to schema")

                  ensure_schema(conn, valid_ident!(root_database(config)), schema_name, plugin_id, config)
              end

            _schema_mode ->
              ensure_schema(conn, valid_ident!(root_database(config)), schema_name, plugin_id, config)
          end
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Deterministic per-extension PostgreSQL LOGIN role name (`<= 63` bytes).
  Includes an 8-character hash of the target database name because roles are cluster-global.
  """
  def role_name(plugin_id, config) do
    clean = valid_plugin_id!(plugin_id)
    db = valid_ident!(target_database(plugin_id, config))
    valid_ident!(cap_ident("ext_#{db_hash(db)}_", clean))
  end

  defp ensure_schema(conn, db_name, schema_name, plugin_id, config) do
    with {:ok, %Postgrex.Result{rows: [[admin_user, is_super, is_createrole]]}} <-
           Postgrex.query(
             conn,
             "SELECT current_user, rolsuper, rolcreaterole FROM pg_roles WHERE rolname = current_user",
             []
           ) do
      db_reads = declared_db_reads(plugin_id, config)

      if not is_super and not is_createrole do
        if db_reads != [] do
          {:error,
           {:createrole_required,
            "Extension #{plugin_id} declares db_read (#{Enum.join(db_reads, ", ")}), which requires CREATEROLE or SUPERUSER privilege on database role #{admin_user}"}}
        else
          :persistent_term.put({__MODULE__, :role_mode, db_name, schema_name}, :single_user)

          case Postgrex.query(conn, "CREATE SCHEMA IF NOT EXISTS #{quote_ident(schema_name)}", []) do
            {:ok, _} ->
              Logger.info("[Database] Provisioned dedicated schema #{schema_name} for plugin #{inspect(plugin_id)}")
              {:ok, %{status: :ready, schema: schema_name, plugin: plugin_id}}

            {:error, reason} ->
              {:error, {:schema_creation_failed, reason}}
          end
        end
      else
        provision_role_and_schema(conn, db_name, schema_name, plugin_id, admin_user, db_reads, config)
      end
    else
      {:error, reason} ->
        {:error, {:schema_creation_failed, reason}}
    end
  end

  defp provision_role_and_schema(conn, db_name, schema_name, plugin_id, admin_user, db_reads, config) do
    role = role_name(plugin_id, config)
    pass = role_password(role, config)
    pool_size = pool_size_for(plugin_id, config)
    conn_limit = valid_conn_limit!(Map.get(config, :connection_limit, pool_size + 2))
    stmt_timeout = valid_timeout!(Map.get(config, :statement_timeout, "30s"))
    idle_timeout = valid_timeout!(Map.get(config, :idle_in_transaction_session_timeout, "60s"))

    try do
      case Postgrex.query(conn, "SELECT 1 FROM pg_roles WHERE rolname = $1", [role]) do
        {:ok, %Postgrex.Result{num_rows: 0}} ->
          case Postgrex.query(
                 conn,
                 "CREATE ROLE #{quote_ident(role)} WITH LOGIN PASSWORD '#{pass}' CONNECTION LIMIT #{conn_limit}",
                 []
               ) do
            {:ok, _} ->
              :ok

            {:error, %Postgrex.Error{postgres: %{code: :duplicate_object}}} ->
              exec_ddl!(
                conn,
                "ALTER ROLE #{quote_ident(role)} WITH LOGIN PASSWORD '#{pass}' CONNECTION LIMIT #{conn_limit}"
              )

            {:error, reason} ->
              throw({:ddl_failed, reason})
          end

        {:ok, _} ->
          exec_ddl!(
            conn,
            "ALTER ROLE #{quote_ident(role)} WITH LOGIN PASSWORD '#{pass}' CONNECTION LIMIT #{conn_limit}"
          )

        {:error, reason} ->
          throw({:ddl_failed, reason})
      end

      exec_ddl!(
        conn,
        "GRANT #{quote_ident(role)} TO #{quote_ident(admin_user)} WITH SET TRUE, INHERIT FALSE"
      )

      exec_ddl!(
        conn,
        "ALTER ROLE #{quote_ident(role)} SET statement_timeout = '#{stmt_timeout}'"
      )

      exec_ddl!(
        conn,
        "ALTER ROLE #{quote_ident(role)} SET idle_in_transaction_session_timeout = '#{idle_timeout}'"
      )

      _ = Postgrex.query(conn, "REVOKE CREATE ON DATABASE #{quote_ident(db_name)} FROM PUBLIC", [])

      exec_ddl!(
        conn,
        "CREATE SCHEMA IF NOT EXISTS #{quote_ident(schema_name)} AUTHORIZATION #{quote_ident(role)}"
      )

      migrate_schema_ownership!(conn, db_name, schema_name, role)
      reconcile_db_reads!(conn, db_name, schema_name, plugin_id, role, db_reads, admin_user, config)

      :persistent_term.put({__MODULE__, :role_mode, db_name, schema_name}, :role)
      Logger.info("[Database] Provisioned dedicated schema #{schema_name} for plugin #{inspect(plugin_id)}")
      {:ok, %{status: :ready, schema: schema_name, role: role, plugin: plugin_id}}
    catch
      {:ddl_failed, reason} ->
        {:error, {:schema_creation_failed, reason}}
    end
  end

  defp migrate_schema_ownership!(conn, db_name, schema_name, role) do
    schema_owner =
      case Postgrex.query(
             conn,
             "SELECT r.rolname FROM pg_namespace n JOIN pg_roles r ON r.oid = n.nspowner WHERE n.nspname = $1",
             [schema_name]
           ) do
        {:ok, %Postgrex.Result{rows: [[owner]]}} -> owner
        _ -> nil
      end

    unowned_tables =
      case Postgrex.query(
             conn,
             "SELECT tablename FROM pg_tables WHERE schemaname = $1 AND tableowner <> $2",
             [schema_name, role]
           ) do
        {:ok, %Postgrex.Result{rows: rows}} -> Enum.map(rows, fn [t] -> t end)
        _ -> []
      end

    if unowned_tables != [] or (is_binary(schema_owner) and schema_owner != role) do
      stop_pool(db_name, schema_name)

      if schema_owner != role do
        exec_ddl!(conn, "GRANT ALL ON SCHEMA #{quote_ident(schema_name)} TO #{quote_ident(role)}")
      else
        with_role!(conn, role, fn ->
          exec_ddl!(conn, "GRANT ALL ON SCHEMA #{quote_ident(schema_name)} TO #{quote_ident(role)}")
        end)
      end

      Enum.each(unowned_tables, fn tbl ->
        exec_ddl!(
          conn,
          "ALTER TABLE #{quote_ident(schema_name)}.#{quote_ident(tbl)} OWNER TO #{quote_ident(role)}"
        )
      end)

      if is_binary(schema_owner) and schema_owner != role do
        exec_ddl!(conn, "ALTER SCHEMA #{quote_ident(schema_name)} OWNER TO #{quote_ident(role)}")
      end
    end
  end

  defp reconcile_db_reads!(conn, db_name, schema_name, plugin_id, reader_role, db_reads, admin_user, config) do
    desired_pairs =
      Enum.flat_map(db_reads, fn owner_id ->
        owner_role = role_name(owner_id, config)
        owner_schema = schema_name(owner_id, config)

        if schema_and_role_exist?(conn, owner_schema, owner_role) do
          grant_read_as_owner!(conn, owner_schema, owner_role, reader_role, admin_user)
          [{owner_schema, owner_role}]
        else
          Logger.warning(
            "[Database] Skipping db_read grant from #{owner_id} to #{plugin_id}: target schema #{owner_schema} or role #{owner_role} does not exist yet"
          )

          []
        end
      end)
      |> MapSet.new()

    granted_owners_for_reader(conn, db_hash(db_name), reader_role)
    |> Enum.reject(&MapSet.member?(desired_pairs, &1))
    |> Enum.each(fn {stale_schema, stale_role} ->
      revoke_read_as_owner!(conn, stale_schema, stale_role, reader_role, admin_user)
    end)

    # Also reconcile any already-provisioned reader that declares this extension as an owner.
    clean_self = valid_plugin_id!(plugin_id)

    Enum.each(registered_readers_of(clean_self, config), fn other_reader_id ->
      other_reader_role = role_name(other_reader_id, config)
      other_reader_schema = schema_name(other_reader_id, config)

      if schema_and_role_exist?(conn, other_reader_schema, other_reader_role) do
        grant_read_as_owner!(conn, schema_name, reader_role, other_reader_role, admin_user)
      end
    end)
  end

  defp grant_read_as_owner!(conn, owner_schema, owner_role, reader_role, admin_user) do
    exec_ddl!(
      conn,
      "GRANT #{quote_ident(owner_role)} TO #{quote_ident(admin_user)} WITH SET TRUE, INHERIT FALSE"
    )

    with_role!(conn, owner_role, fn ->
      exec_ddl!(
        conn,
        "GRANT USAGE ON SCHEMA #{quote_ident(owner_schema)} TO #{quote_ident(reader_role)}"
      )

      exec_ddl!(
        conn,
        "GRANT SELECT ON ALL TABLES IN SCHEMA #{quote_ident(owner_schema)} TO #{quote_ident(reader_role)}"
      )

      exec_ddl!(
        conn,
        "ALTER DEFAULT PRIVILEGES FOR ROLE #{quote_ident(owner_role)} IN SCHEMA #{quote_ident(owner_schema)} GRANT SELECT ON TABLES TO #{quote_ident(reader_role)}"
      )
    end)
  end

  defp revoke_read_as_owner!(conn, owner_schema, owner_role, reader_role, admin_user) do
    exec_ddl!(
      conn,
      "GRANT #{quote_ident(owner_role)} TO #{quote_ident(admin_user)} WITH SET TRUE, INHERIT FALSE"
    )

    with_role!(conn, owner_role, fn ->
      exec_ddl!(
        conn,
        "REVOKE ALL ON ALL TABLES IN SCHEMA #{quote_ident(owner_schema)} FROM #{quote_ident(reader_role)}"
      )

      exec_ddl!(
        conn,
        "REVOKE USAGE ON SCHEMA #{quote_ident(owner_schema)} FROM #{quote_ident(reader_role)}"
      )

      exec_ddl!(
        conn,
        "ALTER DEFAULT PRIVILEGES FOR ROLE #{quote_ident(owner_role)} IN SCHEMA #{quote_ident(owner_schema)} REVOKE SELECT ON TABLES FROM #{quote_ident(reader_role)}"
      )
    end)
  end

  defp with_role!(conn, role, fun) do
    exec_ddl!(conn, "SET ROLE #{quote_ident(role)}")

    try do
      fun.()
    after
      _ = Postgrex.query(conn, "RESET ROLE", [])
    end
  end

  defp exec_ddl!(conn, sql) do
    case Postgrex.query(conn, sql, []) do
      {:ok, res} -> res
      {:error, reason} -> throw({:ddl_failed, reason})
    end
  end

  defp schema_and_role_exist?(conn, schema_name, role_name) do
    sql = """
    SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = $1)
       AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $2)
    """

    case Postgrex.query(conn, sql, [schema_name, role_name]) do
      {:ok, %Postgrex.Result{rows: [[true]]}} -> true
      _ -> false
    end
  end

  defp granted_owners_for_reader(conn, hash, reader_role) do
    sql = """
    SELECT n.nspname, r.rolname
    FROM pg_namespace n
    JOIN pg_roles r ON r.oid = n.nspowner
    WHERE r.rolname LIKE $1
      AND r.rolname <> $2
      AND (
        has_schema_privilege($2, n.oid, 'USAGE')
        OR EXISTS (
          SELECT 1 FROM pg_class c
          WHERE c.relnamespace = n.oid AND c.relkind IN ('r', 'v', 'm', 'p')
            AND has_table_privilege($2, c.oid, 'SELECT')
        )
        OR EXISTS (
          SELECT 1 FROM pg_default_acl d
          WHERE d.defaclnamespace = n.oid
            AND array_to_string(d.defaclacl, ',') LIKE '%' || $2 || '=%'
        )
      )
    """

    case Postgrex.query(conn, sql, ["ext_#{hash}_%", reader_role]) do
      {:ok, %Postgrex.Result{rows: rows}} -> Enum.map(rows, fn [s, r] -> {s, r} end)
      _ -> []
    end
  end

  defp declared_db_reads(plugin_id, config) do
    clean_self = valid_plugin_id!(plugin_id)

    from_config =
      case Map.get(config, :db_read) do
        list when is_list(list) ->
          list

        map when is_map(map) ->
          Map.get(map, plugin_id) || Map.get(map, clean_self) || []

        _ ->
          []
      end

    from_registry =
      case find_manifest_for(clean_self) do
        nil -> []
        manifest -> Map.get(manifest, :db_read) || []
      end

    (List.wrap(from_config) ++ List.wrap(from_registry))
    |> Enum.map(&valid_plugin_id!/1)
    |> Enum.reject(&(&1 == clean_self))
    |> Enum.uniq()
  end

  defp registered_readers_of(owner_clean_id, config) do
    Exoforge.ExtensionRegistry.all_manifests()
    |> Enum.flat_map(fn m ->
      reader_clean = valid_plugin_id!(m.id)

      if reader_clean != owner_clean_id and owner_clean_id in declared_db_reads(reader_clean, config) do
        [reader_clean]
      else
        []
      end
    end)
    |> Enum.uniq()
  rescue
    _ -> []
  end

  @doc """
  Dry-run declarative schema planner for an extension's declared resources.
  Reads live schema state from PostgreSQL and computes the reconciliation plan without applying any DDL.
  """
  def plan_schema(plugin_id, resources_override, config) do
    clean_self = valid_plugin_id!(plugin_id)
    schema_name = valid_ident!(schema_name(clean_self, config))
    resources = resolve_manifest_resources(clean_self, resources_override)

    with {:ok, {mode, conn}} <- pooled_connection(clean_self, schema_name, config) do
      try do
        with {:ok, live_state} <-
               Exoforge.Std.Lldb.Schema.read_live_state(conn, schema_name, resources),
             {:ok, plan_res} <- Exoforge.Std.Lldb.Schema.plan(resources, live_state) do
          {:ok, Map.put(plan_res, :extension, to_string(plugin_id))}
        end
      after
        if mode == :unmanaged, do: GenServer.stop(conn)
      end
    end
  end

  @impl true
  def apply_schema(plugin_id, resources_override, migrations_override, config) do
    clean_self = valid_plugin_id!(plugin_id)
    schema_name = valid_ident!(schema_name(clean_self, config))
    resources = resolve_manifest_resources(clean_self, resources_override)
    migrations = resolve_manifest_migrations(clean_self, migrations_override)

    with {:ok, {mode, conn}} <- pooled_connection(clean_self, schema_name, config) do
      try do
        Exoforge.Std.Lldb.Schema.reconcile(conn, schema_name, resources, migrations)
      after
        if mode == :unmanaged, do: GenServer.stop(conn)
      end
    end
  end

  @impl true
  def reset_table(plugin_id, table, config) do
    clean_self = valid_plugin_id!(plugin_id)
    schema_name = valid_ident!(schema_name(clean_self, config))
    tbl = to_string(table)

    with {:ok, {mode, conn}} <- pooled_connection(clean_self, schema_name, config) do
      try do
        with {:ok, _} <- query_pooled(conn, "DROP TABLE IF EXISTS #{quote_ident(schema_name)}.#{quote_ident(tbl)} CASCADE", []) do
          # The ledger is the table's history: it starts again with the table. It may not exist yet.
          _ = query_pooled(conn, "DELETE FROM #{quote_ident(schema_name)}.\"_exo_schema\" WHERE table_name = $1", [tbl])
          {:ok, %{table: tbl, dropped: true}}
        end
      after
        if mode == :unmanaged, do: GenServer.stop(conn)
      end
    end
  end

  defp resolve_manifest_resources(_clean_self, resources) when is_list(resources), do: resources

  defp resolve_manifest_migrations(_clean_self, migrations) when is_list(migrations), do: migrations

  defp resolve_manifest_migrations(clean_self, _) do
    case find_manifest_for(clean_self) do
      nil -> []
      manifest -> Map.get(manifest, :migrations) || []
    end
  rescue
    _ -> []
  end

  defp resolve_manifest_resources(clean_self, _) do
    case find_manifest_for(clean_self) do
      nil ->
        []

      manifest ->
        Exoforge.ExtensionRegistry.manifest_services(manifest)
        |> Enum.flat_map(fn svc -> Map.get(svc, :resources) || Map.get(svc, "resources") || [] end)
    end
  rescue
    _ -> []
  end

  defp find_manifest_for(clean_id) do
    Exoforge.ExtensionRegistry.all_manifests()
    |> Enum.find(fn m ->
      Exoforge.Std.Lldb.clean_id(m.id) == clean_id or
        Enum.any?(m.provides || [], fn p ->
          Exoforge.Std.Lldb.clean_id(Exoforge.Domain.Manifest.service_name(p)) == clean_id
        end)
    end)
  rescue
    _ -> nil
  end

  @impl true
  def connection_config(plugin_id, config) do
    db_name = valid_ident!(database_name(plugin_id, config))
    schema_name = valid_ident!(schema_name(plugin_id, config))
    role = role_name(plugin_id, config)
    host = Map.get(config, :host, "localhost")
    port = Map.get(config, :port, 5432)
    pool_size = pool_size_for(plugin_id, config)

    url = "postgres://#{role}@#{host}:#{port}/#{db_name}?search_path=#{schema_name}"

    {:ok,
     %{
       url: url,
       database: db_name,
       schema: schema_name,
       role: role,
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
    db_name = valid_ident!(target_database(plugin_id, config))
    schema_name = valid_ident!(schema_name(plugin_id, config))
    role = role_name(plugin_id, config)

    stop_pool(db_name, schema_name)

    case connect_root(config) do
      {:ok, conn} ->
        try do
          case Postgrex.query(
                 conn,
                 "SELECT current_user, EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1)",
                 [role]
               ) do
            {:ok, %Postgrex.Result{rows: [[admin_user, true]]}} ->
              _ =
                Postgrex.query(
                  conn,
                  "GRANT #{quote_ident(role)} TO #{quote_ident(admin_user)} WITH SET TRUE, INHERIT FALSE",
                  []
                )

              _ =
                Postgrex.query(
                  conn,
                  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND usename = $2 AND pid <> pg_backend_pid()",
                  [db_name, role]
                )

              Enum.each(granted_owners_for_reader(conn, db_hash(db_name), role), fn {owner_schema, owner_role} ->
                revoke_read_as_owner!(conn, owner_schema, owner_role, role, admin_user)
              end)

              migrate_schema_ownership!(conn, db_name, schema_name, role)

              with_role!(conn, role, fn ->
                exec_ddl!(conn, "DROP OWNED BY #{quote_ident(role)} CASCADE")
              end)

              exec_ddl!(conn, "DROP ROLE #{quote_ident(role)}")

            _ ->
              :ok
          end

          _ = Postgrex.query(conn, "DROP SCHEMA IF EXISTS #{quote_ident(schema_name)} CASCADE", [])
          :persistent_term.erase({__MODULE__, :role_mode, db_name, schema_name})
          :ok
        catch
          {:ddl_failed, reason} -> {:error, reason}
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

  # The driver runs SQL. Key-value commands are the database layer's to turn into SQL.
  def execute(_plugin_id, other, _args, _config), do: {:error, {:unsupported_operation, other}}

  defp quote_ident(name), do: ~s("#{valid_ident!(name)}")

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

  @impl true
  def transaction(_plugin_id, [], _config), do: {:ok, %{results: [], num_rows: 0}}

  def transaction(plugin_id, statements, config) when is_list(statements) do
    schema_name = schema_name(plugin_id, config)

    with {:ok, {mode, conn}} <- pooled_connection(plugin_id, schema_name, config) do
      try do
        case Postgrex.transaction(conn, fn tx_conn ->
               statements
               |> Enum.with_index()
               |> Enum.map(fn {{sql, args}, idx} ->
                 with {:ok, params} <- positional_args(args),
                      {:ok, result} <- query_pooled(tx_conn, sql, params) do
                   result
                 else
                   {:error, reason} ->
                     Postgrex.rollback(tx_conn, %{index: idx, reason: reason, message: transaction_message(reason)})
                 end
               end)
             end) do
          {:ok, results} ->
            {:ok, %{results: results, num_rows: results |> Enum.map(&Map.get(&1, :num_rows, 0)) |> Enum.sum()}}

          {:error, %{index: _} = err} ->
            {:error, err}

          {:error, reason} ->
            {:error, %{index: 0, reason: reason, message: transaction_message(reason)}}
        end
      after
        # An unmanaged connection (no pool supervisor running) is per-call, as before.
        if mode == :unmanaged, do: GenServer.stop(conn)
      end
    end
  end

  defp transaction_message({:postgres_error, msg}) when is_binary(msg), do: msg
  defp transaction_message(other), do: inspect(other)

  @impl true
  def introspect(plugin_id, table, config) do
    schema_name = schema_name(plugin_id, config)
    tbl = to_string(table)

    columns_sql =
      "SELECT column_name, data_type, is_nullable FROM information_schema.columns " <>
        "WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position"

    primary_key_sql =
      "SELECT kcu.column_name " <>
        "FROM information_schema.table_constraints tc " <>
        "JOIN information_schema.key_column_usage kcu " <>
        "ON tc.constraint_name = kcu.constraint_name " <>
        "AND tc.table_schema = kcu.table_schema " <>
        "AND tc.table_name = kcu.table_name " <>
        "WHERE tc.constraint_type = 'PRIMARY KEY' " <>
        "AND tc.table_schema = $1 AND tc.table_name = $2 " <>
        "ORDER BY kcu.ordinal_position"

    with {:ok, %{rows: rows}} <- execute(plugin_id, columns_sql, [schema_name, tbl], config) do
      case rows do
        [] ->
          {:ok, %{exists: false, columns: [], primary_key: []}}

        _ ->
          columns =
            Enum.map(rows, fn row ->
              native = to_string(row["data_type"])

              %{
                name: to_string(row["column_name"]),
                type: logical_type(native),
                tz: native == "timestamp with time zone",
                nullable: row["is_nullable"] == "YES"
              }
            end)

          primary_key =
            case execute(plugin_id, primary_key_sql, [schema_name, tbl], config) do
              {:ok, %{rows: pk_rows}} -> Enum.map(pk_rows, &to_string(&1["column_name"]))
              _ -> []
            end

          {:ok, %{exists: true, columns: columns, primary_key: primary_key}}
      end
    end
  end

  # PostgreSQL's catalog names, in the engine-neutral vocabulary the manifest uses (ADR 005).
  defp logical_type(native) do
    case native do
      "smallint" -> "int16"
      "integer" -> "int32"
      "bigint" -> "int64"
      "real" -> "float32"
      "double precision" -> "float64"
      n when n in ["numeric", "decimal"] -> "decimal"
      "boolean" -> "bool"
      n when n in ["text", "character varying", "character", "varchar"] -> "text"
      "uuid" -> "uuid"
      n when n in ["timestamp without time zone", "timestamp with time zone"] -> "timestamp"
      "bytea" -> "bytes"
      n when n in ["json", "jsonb"] -> "json"
      _ -> "other"
    end
  end

  @impl true
  def dialect(_config) do
    %{
      name: "postgres",
      # `$1, $2, ...`; the other style is `?`.
      placeholder: "numbered",
      identifier_quote: "\"",
      # `INSERT ... ON CONFLICT (key) DO UPDATE`; the fallback is a delete followed by an insert.
      upsert: "on_conflict",
      # Appended to a placeholder that carries JSON text.
      json_cast: "::jsonb",
      transactional_ddl: true,
      types: %{
        "text" => "text",
        "int16" => "smallint",
        "int32" => "integer",
        "int64" => "bigint",
        "float32" => "real",
        "float64" => "double precision",
        "decimal" => "numeric",
        "bool" => "boolean",
        "uuid" => "uuid",
        "timestamp" => "timestamptz",
        "timestamp_naive" => "timestamp",
        "bytes" => "bytea",
        "json" => "jsonb"
      }
    }
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
        {:error, {:postgres_error, missing_relation_hint(msg)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A missing relation is usually another extension's table, which this schema cannot see; the fix
  # is that extension's action or a stub, never SQL that reaches further.
  defp missing_relation_hint(msg) when is_binary(msg) do
    if String.contains?(msg, "relation") and String.contains?(msg, "does not exist"),
      do: msg <> Exoforge.Std.Lldb.cross_extension_hint(),
      else: msg
  end

  defp missing_relation_hint(msg), do: msg

  ## ---- PRIVATE HELPERS ----

  defp connect_root(config) do
    Postgrex.start_link(connection_opts(root_database(config), config) ++ [pool_size: 1])
  end

  # One supervised pool per (database, schema) pair, named so a second start finds the first
  # (M33 Fix 8): a query reuses an established connection instead of dialing per call, and the
  # supervisor restarts a pool that drops. Each extension's pool connects AS its own LOGIN role
  # with its search_path startup parameter, so no SET ROLE is ever used at query time.
  defp pooled_connection(plugin_id, schema_name, config) do
    target_db = target_database(plugin_id, config)

    if :persistent_term.get({__MODULE__, :role_mode, target_db, schema_name}, nil) == nil do
      _ = ensure_database(plugin_id, config)
    end

    if Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) != nil do
      supervise_pooled(plugin_id, target_db, schema_name, config)
    else
      # ponytail: unsupervised single connection for direct adapter use (tests without the
      # plugin's supervision tree); the tree is the upgrade path.
      unmanaged_connection(plugin_id, target_db, schema_name, config)
    end
  end

  defp supervise_pooled(plugin_id, target_db, schema_name, config) do
    name = {:via, Registry, {Exoforge.Std.Lldb.PoolRegistry, {target_db, schema_name}}}

    opts =
      extension_connection_opts(plugin_id, target_db, schema_name, config)
      |> Keyword.merge(
        name: name,
        pool_size: pool_size_for(plugin_id, config),
        parameters: [search_path: "#{quote_ident(schema_name)}, public"]
      )

    case DynamicSupervisor.start_child(Exoforge.Std.Lldb.PoolSupervisor, Postgrex.child_spec(opts)) do
      {:ok, pid} -> {:ok, {:managed, pid}}
      {:error, {:already_started, pid}} -> {:ok, {:managed, pid}}
      {:error, reason} -> {:error, {:connection_failed, reason}}
    end
  end

  defp unmanaged_connection(plugin_id, target_db, schema_name, config) do
    opts =
      extension_connection_opts(plugin_id, target_db, schema_name, config)
      |> Keyword.merge(
        pool_size: 1,
        parameters: [search_path: "#{quote_ident(schema_name)}, public"]
      )

    case Postgrex.start_link(opts) do
      {:ok, conn} -> {:ok, {:unmanaged, conn}}
      {:error, reason} -> {:error, {:connection_failed, reason}}
    end
  end

  defp stop_pool(target_db, schema_name) do
    if Process.whereis(Exoforge.Std.Lldb.PoolRegistry) != nil and
         Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) != nil do
      case Registry.lookup(Exoforge.Std.Lldb.PoolRegistry, {target_db, schema_name}) do
        [{pid, _} | _] when is_pid(pid) ->
          _ = DynamicSupervisor.terminate_child(Exoforge.Std.Lldb.PoolSupervisor, pid)
          :ok

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp extension_connection_opts(plugin_id, target_db, schema_name, config) do
    case :persistent_term.get({__MODULE__, :role_mode, target_db, schema_name}, :role) do
      :single_user ->
        connection_opts(target_db, config)

      _role_mode ->
        role = role_name(plugin_id, config)
        pass = role_password(role, config)

        [
          hostname: Map.get(config, :host, "localhost"),
          port: Map.get(config, :port, 5432),
          username: role,
          password: pass,
          database: target_db,
          timeout: @connect_timeout
        ]
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

  defp role_password(role, config) when is_binary(role) do
    secret =
      case Map.get(config, :role_secret) || System.get_env("EXOFORGE_DB_ROLE_SECRET") do
        s when is_binary(s) and s != "" -> s
        _ -> to_string(Map.get(config, :password, ""))
      end

    :crypto.mac(:hmac, :sha256, secret, role)
    |> Base.encode16(case: :lower)
  end

  # An extension's own setting (`pool_sizes: %{"auth" => 8}`) wins over the shared default (`pool_size`), which
  # wins over the built-in one. A busy extension can have more connections without everyone paying for them.
  defp pool_size_for(plugin_id, config) do
    own = config |> Map.get(:pool_sizes, %{}) |> Map.get(Exoforge.Std.Lldb.clean_id(plugin_id))
    positive(own) || positive(Map.get(config, :pool_size)) || @default_pool_size
  end

  defp positive(n) when is_integer(n) and n > 0, do: n
  defp positive(_), do: nil

  defp root_database(config), do: valid_ident!(Map.get(config, :database, "postgres"))

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
    prefix = valid_ident!(Map.get(config, :db_prefix, "exoforge_"))
    clean = valid_plugin_id!(plugin_id)
    valid_ident!(cap_ident(prefix, clean))
  end

  defp schema_name(plugin_id, config) do
    prefix = valid_ident!(Map.get(config, :schema_prefix, "plugin_"))
    clean = valid_plugin_id!(plugin_id)
    valid_ident!(cap_ident(prefix, clean))
  end

  defp db_hash(db_name) do
    :crypto.hash(:sha256, to_string(db_name))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  defp cap_ident(prefix, clean) do
    full = prefix <> clean

    if byte_size(full) <= 63 do
      full
    else
      hash = :crypto.hash(:sha256, clean) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      keep = 63 - byte_size(prefix) - 1 - 8
      prefix <> binary_part(clean, 0, keep) <> "_" <> hash
    end
  end

  defp valid_plugin_id!(nil), do: "default"

  defp valid_plugin_id!(plugin_id)
       when is_binary(plugin_id) or is_atom(plugin_id) or is_integer(plugin_id) do
    str = plugin_id |> to_string() |> String.downcase()

    if str != "" and Regex.match?(~r/^[a-z0-9_]+$/, str) do
      str
    else
      raise ArgumentError, "invalid SQL identifier: #{inspect(plugin_id)}"
    end
  end

  defp valid_plugin_id!(_), do: "default"

  defp valid_ident!(name) do
    str = to_string(name)

    if byte_size(str) in 1..63 and Regex.match?(~r/^[a-z0-9_]+$/, str) do
      str
    else
      raise ArgumentError, "invalid SQL identifier: #{inspect(name)}"
    end
  end

  defp valid_conn_limit!(limit) when is_integer(limit) and limit >= -1, do: limit

  defp valid_conn_limit!(limit),
    do: raise(ArgumentError, "invalid connection_limit: #{inspect(limit)}")

  defp valid_timeout!(timeout) when is_integer(timeout) and timeout >= 0, do: "#{timeout}ms"

  defp valid_timeout!(timeout) when is_binary(timeout) do
    if Regex.match?(~r/^[0-9]+(ms|s|min|h|d)?$/, timeout) do
      timeout
    else
      raise ArgumentError, "invalid timeout setting: #{inspect(timeout)}"
    end
  end

  defp valid_timeout!(timeout),
    do: raise(ArgumentError, "invalid timeout setting: #{inspect(timeout)}")
end
