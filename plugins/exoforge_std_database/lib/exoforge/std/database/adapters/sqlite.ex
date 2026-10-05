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
    with {:ok, conn} <- open_for(plugin_id, config) do
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

  defp normalize_args(nil), do: []
  defp normalize_args(args) when is_list(args), do: args
  defp normalize_args(args) when is_map(args), do: Map.values(args)
  defp normalize_args(other), do: [other]

  ## ---- KEY-VALUE OPERATIONS ----

  defp kv_put(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])
    record = Map.put(command[:data] || %{}, "id", id)

    sql =
      "INSERT INTO kv (tbl, id, data) VALUES ($1, $2, $3) " <>
        "ON CONFLICT(tbl, id) DO UPDATE SET data = excluded.data"

    _ = run(plugin_id, config, sql, [tbl, id, encode(record)])
    {:ok, %{rows: [record], num_rows: 1}}
  end

  defp kv_get(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])

    case run(plugin_id, config, "SELECT data FROM kv WHERE tbl = $1 AND id = $2", [tbl, id]) do
      {:ok, %{rows: [row | _]}} -> {:ok, %{rows: [decode(row["data"])], num_rows: 1}}
      {:ok, _} -> {:ok, %{rows: [], num_rows: 0}}
      error -> error
    end
  end

  defp kv_delete(plugin_id, command, config) do
    tbl = to_string(command[:table])
    id = to_string(command[:id])

    case run(plugin_id, config, "DELETE FROM kv WHERE tbl = $1 AND id = $2", [tbl, id]) do
      {:ok, result} -> {:ok, %{result | rows: []}}
      error -> error
    end
  end

  defp kv_all(plugin_id, command, config) do
    tbl = to_string(command[:table])

    case run(plugin_id, config, "SELECT data FROM kv WHERE tbl = $1", [tbl]) do
      {:ok, %{rows: rows}} ->
        decoded = Enum.map(rows, &decode(&1["data"]))
        {:ok, %{rows: decoded, num_rows: length(decoded)}}

      error ->
        error
    end
  end

  defp run(plugin_id, config, sql, args) do
    with {:ok, conn} <- open_for(plugin_id, config) do
      result = run_sql(conn, sql, args)
      Exqlite.Sqlite3.close(conn)
      result
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
