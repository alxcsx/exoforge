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

  @impl true
  def ensure_database(plugin_id, config) do
    path = db_path(plugin_id, config)
    File.mkdir_p!(Path.dirname(path))

    with {:ok, conn} <- open(path) do
      _ = Exqlite.Sqlite3.execute(conn, kv_ddl())
      Exqlite.Sqlite3.close(conn)
      {:ok, %{status: :ok, database: database_name(plugin_id), path: path, plugin: plugin_id}}
    end
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
    _ = File.rm(db_path(plugin_id, config))
    :ok
  end

  @impl true
  def execute(plugin_id, sql, args, config) when is_binary(sql) do
    with {:ok, args} <- positional_args(args),
         {:ok, conn} <- open_for(plugin_id, config) do
      result = run_sql(conn, sql, args)
      Exqlite.Sqlite3.close(conn)
      result
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

  # A missing table in a plugin's isolated database means "no data" for reads.
  # Writes to a missing table still surface the error.
  defp table_error(reason, true) when is_binary(reason) do
    if String.contains?(reason, "no such table") do
      {:ok, %{rows: [], num_rows: 0}}
    else
      {:error, reason}
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
  defp normalize_args(args) when is_list(args), do: args
  defp normalize_args(other), do: [other]

  ## ---- KEY-VALUE OPERATIONS ----

  defp kv_put(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])
    data = command[:data] || %{}
    record = Map.put(data, "id", id)

    with {:ok, conn} <- open_for(plugin_id, config) do
      res =
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
            put_into_kv(conn, tbl, id, record)
        end

      Exqlite.Sqlite3.close(conn)
      res
    end
  end

  defp kv_get(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])

    with {:ok, conn} <- open_for(plugin_id, config) do
      res =
        case real_table_info(conn, tbl) do
          {:ok, %{pk: pk_col}} ->
            safe_tbl = String.replace(tbl, "\"", "")
            safe_pk = String.replace(pk_col, "\"", "")

            case run_sql(conn, "SELECT * FROM \"#{safe_tbl}\" WHERE \"#{safe_pk}\" = $1", [id]) do
              {:ok, %{rows: [row | _]}} ->
                {:ok, %{rows: [row], num_rows: 1}}

              _ ->
                get_from_kv(conn, tbl, id)
            end

          :error ->
            get_from_kv(conn, tbl, id)
        end

      Exqlite.Sqlite3.close(conn)
      res
    end
  end

  defp kv_delete(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])

    with {:ok, conn} <- open_for(plugin_id, config) do
      res =
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

      Exqlite.Sqlite3.close(conn)
      res
    end
  end

  defp kv_all(plugin_id, command, config) do
    tbl = to_string(command[:table])

    with {:ok, conn} <- open_for(plugin_id, config) do
      res =
        case real_table_info(conn, tbl) do
          {:ok, _} ->
            safe_tbl = String.replace(tbl, "\"", "")

            case run_sql(conn, "SELECT * FROM \"#{safe_tbl}\"", []) do
              {:ok, %{rows: rows}} -> {:ok, %{rows: rows, num_rows: length(rows)}}
              error -> error
            end

          :error ->
            case run_sql(conn, "SELECT data FROM kv WHERE tbl = $1", [tbl]) do
              {:ok, %{rows: rows}} ->
                decoded = Enum.map(rows, &decode(&1["data"]))
                {:ok, %{rows: decoded, num_rows: length(decoded)}}

              error ->
                error
            end
        end

      Exqlite.Sqlite3.close(conn)
      res
    end
  end

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

  defp open_for(plugin_id, config) do
    path = db_path(plugin_id, config)
    File.mkdir_p!(Path.dirname(path))

    with {:ok, conn} <- open(path) do
      _ = Exqlite.Sqlite3.execute(conn, kv_ddl())
      {:ok, conn}
    end
  end

  defp open(path), do: Exqlite.Sqlite3.open(path)

  defp kv_ddl do
    "CREATE TABLE IF NOT EXISTS kv (tbl text, id text, data text, PRIMARY KEY (tbl, id))"
  end

  defp encode(data), do: data |> :erlang.term_to_binary() |> Base.encode64()

  defp decode(nil), do: %{}

  defp decode(str) do
    str |> Base.decode64!() |> :erlang.binary_to_term([:safe])
  rescue
    _ -> %{}
  end

  defp db_path(plugin_id, config) do
    Path.join(data_dir(config), "#{database_name(plugin_id)}.db")
  end

  defp data_dir(config) do
    Map.get(config || %{}, :data_dir) ||
      Path.join([File.cwd!(), "priv", "data", "sqlite"])
  end

  defp database_name(plugin_id), do: "exoforge_#{Exoforge.Std.Database.clean_id(plugin_id)}"
end
