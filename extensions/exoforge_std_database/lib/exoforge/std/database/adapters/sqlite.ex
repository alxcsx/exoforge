defmodule Exoforge.Std.Database.Adapters.Sqlite do
  @moduledoc """
  SQLite-backed local database adapter.

  Each plugin gets its own SQLite database file, mirroring the per-plugin
  isolation of the PostgreSQL adapter. Uses a real SQL engine, so plugins run
  the same `$1`-parameterized SQL locally as in production — no SQL emulation.

  Chosen automatically for development, tests, and offline environments; set
  `DATABASE_URL` to use PostgreSQL instead.
  """
  @behaviour Exoforge.Std.Database.Adapter

  # A table's declared boolean columns, learned from its own schema. Filled on first use through
  # this module's connection process (one per plugin database) and dropped by any schema change.
  @boolean_columns_cache {__MODULE__, :boolean_columns}

  @impl true
  def ensure_database(plugin_id, config) do
    path = db_path(plugin_id, config)
    Exoforge.Std.Database.Adapters.Sqlite.Connection.ensure_started(plugin_id, config)
    {:ok, %{status: :ok, database: database_name(plugin_id), path: path, plugin: plugin_id}}
  end

  @impl true
  def connection_config(plugin_id, config) do
    {:ok,
     %{
       url: "sqlite://#{db_path(plugin_id, config)}",
       database: database_name(plugin_id),
       schema: "plugin_#{Exoforge.Std.Database.clean_id(plugin_id)}",
       driver: :sqlite,
       pool_size: 1
     }}
  end

  @impl true
  def health_check(_config), do: {:ok, %{status: "ok", driver: :sqlite}}

  @impl true
  def reset(plugin_id, config) do
    # An open SQLite handle keeps the old inode alive after File.rm/1. The next query would then
    # write through that handle (or fail as readonly) while the new file on disk stays empty. Stop
    # the pooled connection first so reset gives the caller a genuinely fresh database.
    stop_connection(plugin_id)
    _ = File.rm(db_path(plugin_id, config))
    :ok
  end

  @impl true
  def execute(plugin_id, sql, args, config) when is_binary(sql) do
    with {:ok, args} <- positional_args(args) do
      Exoforge.Std.Database.Adapters.Sqlite.Connection.run(plugin_id, config, fn conn ->
        run_sql(conn, sql, args)
      end)
    end
  end

  def execute(plugin_id, %{action: action} = command, _args, config) do
    case action do
      :put -> kv_put(plugin_id, command, config)
      :get -> kv_get(plugin_id, command, config)
      :delete -> kv_delete(plugin_id, command, config)
      :all -> kv_all(plugin_id, command, config)
      other -> {:error, {:unknown_action, other}}
    end
  end

  @impl true
  def table_columns(plugin_id, table, config) do
    case execute(plugin_id, "PRAGMA table_info(#{table})", [], config) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &to_string(&1["name"]))}
      error -> error
    end
  end

  ## ---- SQL EXECUTION ----

  defp run_sql(conn, sql, args) do
    read? = String.match?(sql, ~r/^\s*SELECT/i)

    # A statement that changes the schema outdates what was learned about a table's columns.
    if not read? and String.match?(sql, ~r/^\s*(?:CREATE|ALTER|DROP)\b/i) do
      Process.delete(@boolean_columns_cache)
    end

    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          do_run(conn, stmt, args, read?)
        rescue
          e in ArgumentError -> {:error, {:bind_error, Exception.message(e)}}
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        table_error(reason, read?)
    end
  end

  defp do_run(conn, stmt, args, read?) do
    with :ok <- Exqlite.Sqlite3.bind(stmt, normalize_args(args)),
         {:ok, columns} <- Exqlite.Sqlite3.columns(conn, stmt),
         {:ok, raw_rows} <- Exqlite.Sqlite3.fetch_all(conn, stmt) do
      rows = Enum.map(raw_rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)
      {:ok, %{rows: rows, num_rows: max(length(rows), changes(conn))}}
    else
      {:error, reason} -> table_error(reason, read?)
    end
  end

  defp changes(conn) do
    case Exqlite.Sqlite3.changes(conn) do
      {:ok, n} when is_integer(n) -> n
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp table_error(reason, _read?), do: {:error, reason}

  # A map's values have no order, so binding them to positional parameters would make the query's
  # meaning depend on an implementation detail (M33 Fix 10). Key-value work is the command path.
  defp positional_args(args) when is_list(args), do: {:ok, args}
  defp positional_args(nil), do: {:ok, []}
  defp positional_args(args) when is_map(args), do: {:error, :positional_args_must_be_list}

  defp positional_args(other), do: {:ok, [other]}

  defp normalize_args(nil), do: []
  defp normalize_args(args) when is_list(args), do: Enum.map(args, &normalize_arg/1)
  defp normalize_args(other), do: [normalize_arg(other)]

  # exqlite binds any atom as text, so `true` would be stored as "true". A boolean is an integer in
  # SQLite; storing 1/0 keeps comparisons and `DEFAULT false` on the same representation.
  defp normalize_arg(true), do: 1
  defp normalize_arg(false), do: 0
  defp normalize_arg(value), do: value

  ## ---- KEY-VALUE OPERATIONS ----

  defp kv_put(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])
    data = command[:data] || %{}
    record = Map.put(data, "id", id)

    Exoforge.Std.Database.Adapters.Sqlite.Connection.run(plugin_id, config, fn conn ->
      case real_table_info(conn, tbl) do
        {:ok, %{columns: cols, pk: pk_col}} ->
          data_with_pk = Map.put(data, pk_col, id)

          valid_pairs =
            Enum.flat_map(cols, fn col ->
              case Map.fetch(data_with_pk, col) do
                {:ok, val} ->
                  [{col, val}]

                :error ->
                  case Map.fetch(data_with_pk, String.to_atom(col)) do
                    {:ok, val} -> [{col, val}]
                    :error -> []
                  end
              end
            end)

          if valid_pairs == [] do
            put_into_kv(conn, tbl, id, record)
          else
            safe_tbl = String.replace(tbl, "\"", "")
            safe_pk = String.replace(pk_col, "\"", "")
            {names, values} = Enum.unzip(valid_pairs)
            placeholders = Enum.map_join(1..length(names), ", ", &"$#{&1}")

            updates =
              names
              |> Enum.reject(&(&1 == pk_col))
              |> Enum.map_join(", ", fn col ->
                "\"#{String.replace(col, "\"", "")}\" = excluded.\"#{String.replace(col, "\"", "")}\""
              end)

            sql =
              "INSERT INTO \"#{safe_tbl}\" (" <>
                Enum.map_join(names, ", ", &"\"#{String.replace(&1, "\"", "")}\"") <>
                ") VALUES (#{placeholders}) " <>
                if(updates == "",
                  do: "ON CONFLICT(\"#{safe_pk}\") DO NOTHING",
                  else: "ON CONFLICT(\"#{safe_pk}\") DO UPDATE SET #{updates}"
                )

            case run_sql(conn, sql, values) do
              {:ok, _} ->
                _ = run_sql(conn, "DELETE FROM kv WHERE tbl = $1 AND id = $2", [tbl, id])
                {:ok, %{rows: [record], num_rows: 1}}

              error ->
                error
            end
          end

        :error ->
          if declared_resource_table?(tbl) do
            {:error, {:missing_resource_table, tbl}}
          else
            put_into_kv(conn, tbl, id, record)
          end
      end
    end)
  end

  defp kv_get(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])

    Exoforge.Std.Database.Adapters.Sqlite.Connection.run(plugin_id, config, fn conn ->
      case real_table_info(conn, tbl) do
        {:ok, %{pk: pk_col}} ->
          safe_tbl = String.replace(tbl, "\"", "")
          safe_pk = String.replace(pk_col, "\"", "")

          case run_sql(conn, "SELECT * FROM \"#{safe_tbl}\" WHERE \"#{safe_pk}\" = $1", [id]) do
            {:ok, %{rows: [row | _]}} ->
              {:ok, %{rows: [decode_row(conn, tbl, row)], num_rows: 1}}

            _ ->
              get_from_kv(conn, tbl, id)
          end

        :error ->
          if declared_resource_table?(tbl) do
            {:error, {:missing_resource_table, tbl}}
          else
            get_from_kv(conn, tbl, id)
          end
      end
    end)
  end

  defp kv_delete(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])

    Exoforge.Std.Database.Adapters.Sqlite.Connection.run(plugin_id, config, fn conn ->
      case real_table_info(conn, tbl) do
        {:ok, %{pk: pk_col}} ->
          safe_tbl = String.replace(tbl, "\"", "")
          safe_pk = String.replace(pk_col, "\"", "")
          _ = run_sql(conn, "DELETE FROM \"#{safe_tbl}\" WHERE \"#{safe_pk}\" = $1", [id])
          _ = run_sql(conn, "DELETE FROM kv WHERE tbl = $1 AND id = $2", [tbl, id])
          {:ok, %{rows: [], num_rows: 1}}

        :error ->
          case run_sql(conn, "DELETE FROM kv WHERE tbl = $1 AND id = $2", [tbl, id]) do
            {:ok, result} -> {:ok, %{result | rows: []}}
            error -> error
          end
      end
    end)
  end

  defp kv_all(plugin_id, command, config) do
    tbl = to_string(command[:table])

    Exoforge.Std.Database.Adapters.Sqlite.Connection.run(plugin_id, config, fn conn ->
      case real_table_info(conn, tbl) do
        {:ok, _} ->
          safe_tbl = String.replace(tbl, "\"", "")

          case run_sql(conn, "SELECT * FROM \"#{safe_tbl}\"", []) do
            {:ok, %{rows: rows}} ->
              decoded = Enum.map(rows, &decode_row(conn, tbl, &1))
              {:ok, %{rows: decoded, num_rows: length(decoded)}}

            error ->
              error
          end

        :error ->
          if declared_resource_table?(tbl) do
            {:error, {:missing_resource_table, tbl}}
          else
            case run_sql(conn, "SELECT data FROM kv WHERE tbl = $1", [tbl]) do
              {:ok, %{rows: rows}} ->
                decoded = Enum.map(rows, &decode(&1["data"]))
                {:ok, %{rows: decoded, num_rows: length(decoded)}}

              error ->
                error
            end
          end
      end
    end)
  end

  defp stop_connection(plugin_id) do
    with sup when is_pid(sup) <- Process.whereis(Exoforge.Std.Database.PoolSupervisor),
         [{pid, _}] <- Registry.lookup(Exoforge.Std.Database.PoolRegistry, {:sqlite, plugin_id}) do
      _ = DynamicSupervisor.terminate_child(sup, pid)
      :ok
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp declared_resource_table?(tbl) do
    table = to_string(tbl)

    case Exoforge.ExtensionRegistry.fetch_resource(table) do
      {:ok, %{resource: res}} -> table_source(res) == table
      _ -> false
    end
  rescue
    _ -> false
  end

  # A resource can be declared by its name while its table has another name, and manifests may
  # carry the source as an atom tuple/list or a JSON object. Match every shape the registry's
  # sanitizer can produce.
  defp table_source(res) when is_map(res) do
    source =
      Map.get(res, :source) ||
        Map.get(res, "source")

    source_table(source) ||
      table_name(Map.get(res, :table) || Map.get(res, "table"))
  end

  defp table_source(_), do: nil

  defp source_table({:table, table}), do: table_name(table)
  defp source_table([:table, table]), do: table_name(table)
  defp source_table(["table", table]), do: table_name(table)
  defp source_table(%{table: table}), do: table_name(table)
  defp source_table(%{"table" => table}), do: table_name(table)
  defp source_table(_), do: nil

  defp table_name(table) when is_binary(table) and table != "", do: table
  defp table_name(table) when is_atom(table) and not is_nil(table), do: to_string(table)
  defp table_name(_), do: nil

  defp real_table_info(_conn, "kv"), do: :error

  defp real_table_info(conn, tbl) do
    safe_tbl = String.replace(tbl, "\"", "")

    case run_sql(conn, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = $1", [safe_tbl]) do
      {:ok, %{rows: [%{"name" => ^safe_tbl} | _]}} ->
        case run_sql(conn, "PRAGMA table_info(\"#{safe_tbl}\")", []) do
          {:ok, %{rows: rows}} when rows != [] ->
            cols = Enum.map(rows, &to_string(&1["name"]))
            pk_row = Enum.find(rows, fn r -> (r["pk"] || 0) > 0 end)
            pk_col = if pk_row, do: to_string(pk_row["name"]), else: "id"
            {:ok, %{columns: cols, pk: pk_col}}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  # The KV command path names its table, so the declared schema is known there. Values written
  # before booleans were bound as integers hold the text "true"/"false"; both shapes decode.
  defp decode_row(conn, tbl, row) do
    case boolean_columns(conn, tbl) do
      [] ->
        row

      columns ->
        booleans = MapSet.new(columns)

        Map.new(row, fn {column, value} ->
          {column, if(MapSet.member?(booleans, column), do: to_boolean(value), else: value)}
        end)
    end
  end

  defp boolean_columns(conn, tbl) do
    cache = Process.get(@boolean_columns_cache, %{})

    case Map.fetch(cache, tbl) do
      {:ok, columns} ->
        columns

      :error ->
        columns = load_boolean_columns(conn, tbl)
        Process.put(@boolean_columns_cache, Map.put(cache, tbl, columns))
        columns
    end
  end

  # SQLite keeps the declared type verbatim, so its own schema answers what a column means.
  defp load_boolean_columns(conn, tbl) do
    safe_tbl = String.replace(tbl, "\"", "")

    case run_sql(conn, "PRAGMA table_info(\"#{safe_tbl}\")", []) do
      {:ok, %{rows: rows}} ->
        for row <- rows, boolean_type(row["type"]), do: to_string(row["name"])

      _ ->
        []
    end
  end

  defp boolean_type(type) when is_binary(type),
    do: String.contains?(String.downcase(type), "bool")

  defp boolean_type(_type), do: false

  defp to_boolean(nil), do: nil
  defp to_boolean(true), do: true
  defp to_boolean(false), do: false
  defp to_boolean(1), do: true
  defp to_boolean(0), do: false

  defp to_boolean(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "t" -> true
      "1" -> true
      "false" -> false
      "f" -> false
      "0" -> false
      _ -> value
    end
  end

  defp to_boolean(value), do: value

  defp put_into_kv(conn, tbl, id, record) do
    sql =
      "INSERT INTO kv (tbl, id, data) VALUES ($1, $2, $3) " <>
        "ON CONFLICT(tbl, id) DO UPDATE SET data = excluded.data"

    case run_sql(conn, sql, [tbl, id, encode(record)]) do
      {:ok, _} -> {:ok, %{rows: [record], num_rows: 1}}
      error -> error
    end
  end

  defp get_from_kv(conn, tbl, id) do
    case run_sql(conn, "SELECT data FROM kv WHERE tbl = $1 AND id = $2", [tbl, id]) do
      {:ok, %{rows: [row | _]}} -> {:ok, %{rows: [decode(row["data"])], num_rows: 1}}
      {:ok, _} -> {:ok, %{rows: [], num_rows: 0}}
      error -> error
    end
  end

  ## ---- HELPERS ----

  defp encode(data), do: data |> :erlang.term_to_binary() |> Base.encode64()

  defp decode(nil), do: %{}

  defp decode(str) do
    str |> Base.decode64!() |> :erlang.binary_to_term([:safe])
  rescue
    _ -> %{}
  end

  def db_path(plugin_id, config) do
    Path.join(data_dir(config), "#{database_name(plugin_id)}.db")
  end

  defp data_dir(config) do
    Map.get(config || %{}, :data_dir) ||
      Path.join([File.cwd!(), "priv", "data", "sqlite"])
  end

  defp database_name(plugin_id), do: "exoforge_#{Exoforge.Std.Database.clean_id(plugin_id)}"
end

defmodule Exoforge.Std.Database.Adapters.Sqlite.Connection do
  use GenServer

  def ensure_started(plugin_id, config) do
    if Process.whereis(Exoforge.Std.Database.PoolRegistry) == nil do
      Registry.start_link(keys: :unique, name: Exoforge.Std.Database.PoolRegistry)
    end

    if Process.whereis(Exoforge.Std.Database.PoolSupervisor) == nil do
      DynamicSupervisor.start_link(name: Exoforge.Std.Database.PoolSupervisor, strategy: :one_for_one)
    end

    case Registry.lookup(Exoforge.Std.Database.PoolRegistry, {:sqlite, plugin_id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               Exoforge.Std.Database.PoolSupervisor,
               {__MODULE__, {plugin_id, config}}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end

  def run(plugin_id, config, func) do
    {:ok, pid} = ensure_started(plugin_id, config)
    GenServer.call(pid, {:run, func}, 15_000)
  end

  def start_link({plugin_id, config}) do
    GenServer.start_link(__MODULE__, {plugin_id, config}, name: via_tuple(plugin_id))
  end

  @impl true
  def init({plugin_id, config}) do
    path = Exoforge.Std.Database.Adapters.Sqlite.db_path(plugin_id, config)
    File.mkdir_p!(Path.dirname(path))

    case Exqlite.Sqlite3.open(path) do
      {:ok, conn} ->
        kv_ddl = "CREATE TABLE IF NOT EXISTS kv (tbl text, id text, data text, PRIMARY KEY (tbl, id))"
        _ = Exqlite.Sqlite3.execute(conn, kv_ddl)
        {:ok, %{conn: conn}}

      error ->
        {:stop, error}
    end
  end

  @impl true
  def handle_call({:run, func}, _from, %{conn: conn} = state) do
    result = func.(conn)
    {:reply, result, state}
  end

  defp via_tuple(plugin_id) do
    {:via, Registry, {Exoforge.Std.Database.PoolRegistry, {:sqlite, plugin_id}}}
  end
end
