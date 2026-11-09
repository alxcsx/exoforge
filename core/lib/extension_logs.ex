defmodule Exoforge.ExtensionLogs do
  # Declared before the moduledoc so the number can be stated in one place.
  @max_per_second 100

  @moduledoc """
  Bounded, in-memory record of the most recent log lines each extension emitted.
  """

  @table :exo_extension_logs
  @rate_table :exo_extension_log_rate
  @max_lines 200

  @type level :: 0 | 1 | 2 | 3
  @type entry :: %{
          at: integer(),
          level: level(),
          level_name: String.t(),
          message: String.t(),
          rid: String.t() | nil
        }

  @doc "The per-extension ceiling on lines per second; `append/3` refuses the rest of the second past it."
  def rate_limit, do: @max_per_second

  @doc """
  Records one line for an extension. Older lines are dropped past #{@max_lines} per extension, and an extension
  is held to #{@max_per_second} lines per second: past that nothing is recorded and `:rate_limited`
  is returned, so the line never reaches the server log either.

  The fourth argument is the clock the rate window is measured against, defaulting to the monotonic
  time. It exists so a test can cross a window without sleeping.
  """
  def append(extension_id, level, message, now_ms \\ System.monotonic_time(:millisecond))

  def append(extension_id, level, message, now_ms) when is_binary(message) do
    table = ensure_table()
    id = to_string(extension_id)

    if allowed?(id, now_ms) do
      if :ets.select_count(table, [{{id, :_, :_, :_, :_}, [], [true]}]) >= @max_lines do
        drop_oldest(table, id)
      end

      at = System.system_time(:millisecond)
      lvl = normalize_level(level)
      rid = Exoforge.RequestContext.rid()
      :ets.insert(table, {id, at, lvl, message, rid})
      persist_async(id, at, lvl, message, rid)
      :ok
    else
      :rate_limited
    end
  end

  def append(_extension_id, _level, _message, _now_ms), do: :ok

  @doc "Recent lines for an extension, newest last. `limit` caps how many are returned."
  def list(extension_id, limit \\ 100) do
    table = ensure_table()
    id = to_string(extension_id)

    entries =
      case :ets.lookup(table, id) do
        [] ->
          # If ETS has no logs for this extension, try loading persisted logs from DB
          load_from_db(id, limit)

        cached ->
          Enum.map(cached, fn
            {_id, at, level, message, rid} ->
              %{at: at, level: level, level_name: level_name(level), message: message, rid: rid}

            # Lines written before the rid column existed.
            {_id, at, level, message} ->
              %{at: at, level: level, level_name: level_name(level), message: message, rid: nil}
          end)
      end

    entries
    |> Enum.sort_by(& &1.at)
    |> Enum.take(-max(limit, 1))
  end

  @doc """
  Newest-first page of recent lines, for a paged viewer.

  Resolves to `%{entries, total, page, pages}`; `total` is what is retained (in memory or loaded
  from the persisted table), not a lifetime count.
  """
  def page(extension_id, opts \\ []) do
    per_page = max(Keyword.get(opts, :per_page, 25), 1)
    requested = max(Keyword.get(opts, :page, 1), 1)

    entries = list(extension_id, 2_000) |> Enum.reverse()
    total = length(entries)
    pages = max(ceil(total / per_page), 1)
    page = min(requested, pages)

    %{
      entries: Enum.slice(entries, (page - 1) * per_page, per_page),
      total: total,
      page: page,
      pages: pages
    }
  end

  @doc """
  The lines emitted during one request, oldest first, formatted for a client response.

  This is what a `rid` buys over the old "everything in the last 50 ms" heuristic: concurrent
  requests no longer read each other's logs.
  """
  def for_rid(rid) do
    entries_for_rid(rid)
    |> Enum.map(fn entry -> "[#{String.upcase(entry.level_name)}] #{entry.message}" end)
  end

  @doc "The same lines as `for_rid/1`, structured for the request timeline."
  def entries_for_rid(rid) when is_binary(rid) and rid != "" do
    ensure_table()

    from_memory =
      @table
      |> :ets.tab2list()
      |> Enum.filter(fn
        {_id, _at, _level, _message, ^rid} -> true
        _ -> false
      end)
      |> Enum.sort_by(fn {_id, at, _level, _message, _rid} -> at end)
      |> Enum.map(fn {_id, at, level, message, _rid} ->
        %{at: at, level: level, level_name: level_name(level), message: message, rid: rid}
      end)

    case from_memory do
      [] -> from_db_for_rid(rid)
      entries -> entries
    end
  end

  def entries_for_rid(_), do: []

  @doc "Drops persisted lines older than `before_ms` (the retention pass calls this)."
  def prune(before_ms) when is_integer(before_ms) do
    Task.start(fn ->
      try do
        ensure_schema()

        Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
          plugin: :extension_logs,
          operation: "DELETE FROM extension_logs WHERE timestamp < $1",
          arguments: [before_ms]
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  defp from_db_for_rid(rid) do
    try do
      ensure_schema()

      case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
             plugin: :extension_logs,
             operation:
               "SELECT level, level_name, message, timestamp, rid FROM extension_logs WHERE rid = $1 ORDER BY timestamp ASC LIMIT 500",
             arguments: [rid]
           }) do
        {:ok, %{rows: rows}} when is_list(rows) ->
          Enum.map(rows, fn row ->
            at = String.to_integer(to_string(row["timestamp"] || "0"))
            level = String.to_integer(to_string(row["level"] || "1"))

            %{
              at: at,
              level: level,
              level_name: to_string(row["level_name"] || level_name(level)),
              message: to_string(row["message"] || ""),
              rid: to_string(row["rid"] || rid)
            }
          end)

        _ ->
          []
      end
    rescue
      _ -> []
    end
  end

  @doc "Drops every recorded line for an extension (called when it is removed)."
  def clear(extension_id) do
    id = to_string(extension_id)
    :ets.delete(ensure_table(), id)
    :ets.delete(ensure_rate_table(), id)

    Task.start(fn ->
      try do
        Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
          plugin: :extension_logs,
          operation: "DELETE FROM extension_logs WHERE extension_id = $1",
          arguments: [id]
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  @doc "How many lines are currently held for an extension."
  def count(extension_id) do
    :ets.select_count(ensure_table(), [{{to_string(extension_id), :_, :_, :_, :_}, [], [true]}])
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> Exoforge.TableOwner.ensure_started()
      _ -> @table
    end

    init_table()
  end

  @doc "Creates the table if it does not exist. Called by `Exoforge.TableOwner`, its owner."
  def init_table do
    case :ets.info(@table) do
      :undefined ->
        # `duplicate_bag`: several lines can share a millisecond, and we must keep them all.
        :ets.new(@table, [:duplicate_bag, :named_table, :public, read_concurrency: true])

      _ ->
        @table
    end
  end

  defp ensure_rate_table do
    case :ets.info(@rate_table) do
      :undefined ->
        :ets.new(@rate_table, [:set, :named_table, :public, write_concurrency: true])

      _ ->
        @rate_table
    end
  end

  # One counter per plugin per second window, so a flood is bounded without a timer that would
  # have to be cleaned up. The table holds at most one entry per plugin: the next line in a new
  # window overwrites it.
  defp allowed?(id, now_ms) do
    table = ensure_rate_table()
    window = div(now_ms, 1000)

    case :ets.lookup(table, id) do
      [{^id, ^window, count}] when count >= @max_per_second ->
        false

      [{^id, ^window, count}] ->
        :ets.insert(table, {id, window, count + 1})
        true

      _ ->
        :ets.insert(table, {id, window, 1})
        true
    end
  end

  defp drop_oldest(table, id) do
    case table |> :ets.lookup(id) |> Enum.min_by(fn tuple -> elem(tuple, 1) end, fn -> nil end) do
      nil -> :ok
      oldest -> :ets.delete_object(table, oldest)
    end
  end

  # Levels mirror the C# HostBridge: 0 debug, 1 info, 2 warning, 3 error.
  defp normalize_level(level) when level in 0..3, do: level
  defp normalize_level(_), do: 1

  defp level_name(0), do: "debug"
  defp level_name(1), do: "info"
  defp level_name(2), do: "warning"
  defp level_name(3), do: "error"
  defp level_name(_), do: "info"

  defp persist_async(id, at, level, message, rid) do
    if id not in ["database", "lldb", "extension_logs"] do
      Task.start(fn ->
        try do
          ensure_schema()

          Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
            plugin: :extension_logs,
            operation: """
            INSERT INTO extension_logs (id, extension_id, level, level_name, message, timestamp, rid)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            arguments: [
              "log_#{System.unique_integer([:positive])}",
              id,
              level,
              level_name(level),
              message,
              at,
              rid
            ]
          })
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end
      end)
    end
  end

  defp load_from_db(extension_id, limit) do
    try do
      ensure_schema()

      case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
             plugin: :extension_logs,
             operation:
               "SELECT level, level_name, message, timestamp, rid FROM extension_logs WHERE extension_id = $1 ORDER BY timestamp DESC LIMIT $2",
             arguments: [to_string(extension_id), limit]
           }) do
        {:ok, %{rows: rows}} when is_list(rows) ->
          Enum.map(rows, fn row ->
            at = String.to_integer(to_string(row["timestamp"] || "0"))
            level = String.to_integer(to_string(row["level"] || "1"))

            %{
              at: at,
              level: level,
              level_name: to_string(row["level_name"] || level_name(level)),
              message: to_string(row["message"] || ""),
              rid: Map.get(row, "rid")
            }
          end)

        _ ->
          []
      end
    rescue
      _ -> []
    catch
      _, _ -> []
    end
  end

  defp ensure_schema do
    case :ets.info(:exo_extension_logs_schema) do
      :undefined ->
        case do_create_schema() do
          :ok ->
            try do
              :ets.new(:exo_extension_logs_schema, [:named_table, :public, :set])
            rescue
              _ -> :ok
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp do_create_schema do
    try do
      case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
             plugin: :extension_logs,
             operation: """
             CREATE TABLE IF NOT EXISTS extension_logs (
               id text PRIMARY KEY,
               extension_id text,
               level integer,
               level_name text,
               message text,
               timestamp integer,
               rid text
             )
             """
           }) do
        {:ok, _} ->
          # A table created before the rid column existed gains it; CREATE TABLE does not add it.
          unless column_exists?("extension_logs", "rid") do
            _ =
              Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
                plugin: :extension_logs,
                operation: "ALTER TABLE extension_logs ADD COLUMN rid text"
              })
          end

          :ok

        :ok ->
          :ok

        _ ->
          :retry
      end
    rescue
      _ -> :retry
    catch
      _, _ -> :retry
    end
  end

  defp column_exists?(table, column) do
    case Exoforge.ActionDispatcher.dispatch_internal(:database, :table_columns, %{
           plugin: :extension_logs,
           table: table
         }) do
      {:ok, %{columns: columns}} -> to_string(column) in columns
      _ -> false
    end
  end
end
