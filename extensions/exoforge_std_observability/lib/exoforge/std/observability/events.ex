defmodule Exoforge.Std.Observability.Events do
  @moduledoc """
  The cluster-wide event history: a ring in ETS for the live tail and a persisted store the Studio
  and the other surfaces read through `observability.events`.

  Ingest is batched: the producer buffers events and flushes them in one multi-row INSERT every
  250 ms or eighty rows (SQLite's bind limit is 999 parameters). Each flush also bumps hourly
  rollups, so "events per hour" survives the raw rows being archived or deleted.

  Retention is by day: a daily maintenance pass exports every day older than
  `EXOFORGE_EVENT_HOT_DAYS` (default 30) to `events-YYYY-MM-DD.ndjson.gz` under
  `EXOFORGE_EVENT_ARCHIVE_DIR` (default `priv/data/event-archive`), records the file in
  `event_archives`, and only then deletes the day. A failed export keeps the rows: data is never
  dropped because its archive could not be written.

  Rollups and the archive catalog are kept indefinitely; they are tiny. Archive search streams the
  matching day files (bounded by the caller's date range), so an old request id is still findable
  without a columnar database.
  """
  use GenServer

  require Logger

  @table :exo_observability_events
  @max_events 50
  @db_table "events"
  @rollup_table "event_rollups"
  @archive_table "event_archives"

  @flush_interval_ms 250
  @flush_batch 80
  @archive_page 5_000
  @search_cap 500
  @day_ms 86_400_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## ---- lifecycle ----

  @impl true
  def init(_opts) do
    init_table()
    ensure_schema()
    warmup_from_db()

    try do
      Exoforge.EventDispatcher.subscribe(:all, topic: :global)
    rescue
      _ -> :ok
    end

    # One pass shortly after boot (an instance that was down over its retention boundary catches
    # up), then daily.
    Process.send_after(self(), :maintain, 10_000)
    :timer.send_interval(@day_ms, self(), :maintain)

    {:ok, %{buffer: [], timer: nil}}
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, state) do
    if duplicate?(event_key, payload) do
      {:noreply, state}
    else
      {:noreply, ingest(item(event_key, payload, context), state)}
    end
  end

  def handle_info(:flush, state), do: {:noreply, flush(state)}

  def handle_info(:maintain, state) do
    state = flush(state)
    # Archiving a busy day reads and writes a lot; the store keeps accepting events meanwhile.
    Task.start(fn -> maintain() end)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:flush, _from, state) do
    state = flush(state)
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    clear_db()
    {:reply, :ok, %{state | buffer: [], timer: nil}}
  end

  defp ingest(item, state) do
    insert_ring(item)

    state = %{state | buffer: [item | state.buffer]}

    cond do
      length(state.buffer) >= @flush_batch ->
        flush(state)

      state.timer == nil ->
        %{state | timer: Process.send_after(self(), :flush, @flush_interval_ms)}

      true ->
        state
    end
  end

  defp flush(%{buffer: []} = state), do: %{state | timer: nil}

  defp flush(state) do
    items = Enum.reverse(state.buffer)
    persist(items)
    %{state | buffer: [], timer: nil}
  end

  ## ---- public API ----

  @doc "Records one event into the ring and the write buffer."
  def record(event_key, payload, context \\ %{}) do
    item = item(event_key, payload, context)
    insert_ring(item)

    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:buffer, item})
    else
      persist([item])
    end

    item
  end

  @impl true
  def handle_cast({:buffer, item}, state), do: {:noreply, ingest(item, state)}

  @doc "Flushes the write buffer now (tests and shutdown)."
  def flush! do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :flush, 30_000)
    else
      :ok
    end
  end

  @doc "The most recent events, newest first."
  def list(limit \\ 50) do
    init_table()

    try do
      case :ets.tab2list(@table) do
        [] ->
          warmup_from_db()

          case :ets.tab2list(@table) do
            [] -> []
            list -> sort_and_take(list, limit)
          end

        list ->
          sort_and_take(list, limit)
      end
    rescue
      _ -> []
    end
  end

  @doc "The stored events of one request, oldest first (ring first, then the archive)."
  def for_rid(rid) when is_binary(rid) and rid != "" do
    from_ring =
      list(@max_events)
      |> Enum.filter(fn event ->
        context = Map.get(event, :context) || %{}
        to_string(context[:rid] || context["rid"] || "") == rid
      end)

    case from_ring do
      [] -> archive_for_rid(rid, 100)
      events -> Enum.reverse(events)
    end
  end

  def for_rid(_), do: []

  @doc """
  Queries one page. Filters: `:rid`, `:player` (origin), `:event`, `:status`, `:since_ms`,
  `:until_ms`. Returns `%{events, total, limit, offset, capped}`.

  A range that starts inside the hot window is a SQL page; an older range streams the archive and
  is capped at #{@search_cap} rows (`capped: true`).
  """
  def query(filters, limit \\ 25, offset \\ 0) do
    limit = max(limit, 1)
    offset = max(offset, 0)
    since = int_filter(filters, :since_ms) || 0

    if since == 0 or since >= hot_cutoff_ms() do
      page(filters, limit, offset)
    else
      found = search(filters, @search_cap)

      %{
        events: Enum.slice(found, offset, limit),
        total: length(found),
        limit: limit,
        offset: offset,
        capped: length(found) >= @search_cap
      }
    end
  end

  @doc "One SQL page over the hot table."
  def page(filters, limit \\ 25, offset \\ 0) do
    {where_sql, args} = where(filters)

    limit = max(limit, 1)
    offset = max(offset, 0)

    sql =
      "SELECT id, at, day, event, origin, rid, status, payload, context, time, timestamp " <>
        "FROM #{@db_table}#{where_sql} ORDER BY at DESC LIMIT #{limit} OFFSET #{offset}"

    counter =
      "SELECT COUNT(*) AS n FROM #{@db_table}#{where_sql}"

    events = run_query(sql, args) |> Enum.map(&row_to_item/1)

    total =
      case run_query(counter, args) do
        [row | _] -> int(row["n"] || row[:n], length(events))
        [] -> length(events)
      end

    %{events: events, total: total, limit: limit, offset: offset, capped: false}
  end

  @doc "Searches the hot table and, for older ranges, the archived day files. Newest first."
  def search(filters, limit \\ 100) do
    limit = max(limit, 1)

    hot =
      page(filters, limit, 0).events
      |> filter_until(filters)

    if length(hot) >= limit do
      Enum.take(hot, limit)
    else
      archived = archive_until(archive_days(filters), filters, limit - length(hot), [])

      (hot ++ archived)
      |> Enum.sort_by(& &1.at, :desc)
      |> Enum.take(limit)
    end
  end

  @doc "Drops the ring and the persisted history (a Studio/admin reset)."
  def clear do
    init_table()

    try do
      :ets.delete_all_objects(@table)
    rescue
      _ -> :ok
    end

    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear, 30_000)
    else
      clear_db()
    end

    :ok
  end

  defp clear_db do
    for table <- [@db_table, @rollup_table] do
      run_query_ok("DELETE FROM #{table}", [])
    end

    :ok
  end

  @doc "Drops one caller's hot events (account deletion). Archived files are not rewritten."
  def purge_origin(origin) when is_binary(origin) and origin != "" do
    run_query("DELETE FROM #{@db_table} WHERE origin = $1", [origin])
    :ok
  end

  @doc """
  Runs the retention pass synchronously: roll up, archive, then delete every day older than the
  hot window. Returns the archived days.
  """
  def maintain do
    cutoff = Date.utc_today() |> Date.add(-hot_days()) |> Date.to_iso8601()

    # The request log ages out with the events; archived days are not re-scanned for log lines, so
    # the hot window is the log window too.
    Exoforge.ExtensionLogs.prune(hot_cutoff_ms())

    days =
      run_query(
        "SELECT DISTINCT day FROM #{@db_table} WHERE day IS NOT NULL AND day != '' AND day < $1 ORDER BY day",
        [cutoff]
      )
      |> Enum.map(&to_string(&1["day"] || &1[:day]))
      |> Enum.reject(&(&1 == ""))

    Enum.flat_map(days, fn day ->
      case archive_day(day) do
        :ok -> [day]
        :error -> []
      end
    end)
  end

  @doc "The newest day still inside the hot window (YYYY-MM-DD)."
  def hot_cutoff_day, do: Date.utc_today() |> Date.add(-hot_days()) |> Date.to_iso8601()

  defp hot_cutoff_ms do
    case Date.from_iso8601(hot_cutoff_day()) do
      {:ok, date} ->
        date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix(:millisecond)

      _ ->
        0
    end
  end

  ## ---- ingest ----

  defp item(event_key, payload, context) do
    at = System.system_time(:millisecond)
    context = context || %{}

    %{
      id: "ev_#{System.unique_integer([:positive])}",
      event: to_string(event_key),
      at: at,
      day: day(at),
      origin: to_string(context[:origin] || context["origin"] || context[:source] || ""),
      rid: to_string(context[:rid] || context["rid"] || ""),
      status: status(payload),
      payload: payload,
      context: context,
      time: Calendar.strftime(DateTime.from_unix!(at, :millisecond), "%H:%M:%S"),
      timestamp: at * 1000
    }
  end

  defp status(payload) when is_map(payload) do
    to_string(payload[:status] || payload["status"] || "")
  end

  defp status(_payload), do: ""

  defp day(ms), do: Calendar.strftime(DateTime.from_unix!(ms, :millisecond), "%Y-%m-%d")

  defp insert_ring(item) do
    init_table()

    try do
      :ets.insert(@table, {-item.timestamp, item})
      trim()
    rescue
      _ -> :ok
    end
  end

  defp duplicate?(event_key, payload) do
    key_str = to_string(event_key)
    recent = list(5)
    now_us = System.system_time(:microsecond)

    Enum.any?(recent, fn e ->
      to_string(e[:event]) == key_str and
        e[:payload] == payload and
        now_us - Map.get(e, :timestamp, 0) < 1_500_000
    end)
  end

  defp trim do
    if :ets.info(@table, :size) > @max_events do
      keys = :ets.select_reverse(@table, [{{:"$1", :_}, [], [:"$1"]}], 10)

      case keys do
        {drop_keys, _} -> Enum.each(drop_keys, &:ets.delete(@table, &1))
        _ -> :ok
      end
    end
  rescue
    _ -> :ok
  end

  defp sort_and_take(list, limit) do
    list
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 1))
  end

  ## ---- persistence ----

  defp persist([]), do: :ok

  defp persist(items) do
    try do
      ensure_schema()

      {placeholders, args} = insert_values(items)

      run_query(
        "INSERT INTO #{@db_table} (id, at, day, event, origin, rid, status, payload, context, time, timestamp) " <>
          "VALUES #{placeholders}",
        args
      )

      persist_rollups(items)
      :ok
    rescue
      e ->
        Logger.warning("[Observability] event flush failed: #{Exception.message(e)}")
        :ok
    end
  end

  defp insert_values(items) do
    columns = 11

    placeholders =
      items
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {_item, row} ->
        "(" <>
          Enum.map_join(0..(columns - 1), ", ", fn col -> "$#{row * columns + col + 1}" end) <>
          ")"
      end)

    args =
      Enum.flat_map(items, fn item ->
        [
          item.id,
          item.at,
          item.day,
          item.event,
          item.origin,
          item.rid,
          item.status,
          json(item.payload),
          json(item.context),
          item.time,
          item.timestamp
        ]
      end)

    {placeholders, args}
  end

  defp persist_rollups(items) do
    items
    |> Enum.group_by(fn item ->
      {item.day, hour(item.at), item.event, item.origin, item.status}
    end)
    |> Enum.each(fn {{day, hour, event, origin, status}, grouped} ->
      run_query(
        "INSERT INTO #{@rollup_table} (day, hour, event, origin, status, n) VALUES ($1, $2, $3, $4, $5, $6) " <>
          "ON CONFLICT (day, hour, event, origin, status) DO UPDATE SET n = n + excluded.n",
        [day, hour, event, origin, status, length(grouped)]
      )
    end)
  end

  defp hour(ms), do: DateTime.from_unix!(ms, :millisecond).hour

  defp json(value) do
    case Jason.encode(value) do
      {:ok, bin} -> bin
      _ -> inspect(value)
    end
  end

  ## ---- schema ----

  def init_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :ordered_set])
        rescue
          _ -> @table
        end

      _ ->
        @table
    end
  end

  defp ensure_schema do
    case :ets.info(:exo_observability_events_schema) do
      :undefined ->
        case do_create_schema() do
          :ok ->
            try do
              :ets.new(:exo_observability_events_schema, [:named_table, :public, :set])
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
    statements = [
      """
      CREATE TABLE IF NOT EXISTS #{@db_table} (
        id text PRIMARY KEY,
        at integer,
        day text,
        event text,
        origin text,
        rid text,
        status text,
        payload text,
        context text,
        time text,
        timestamp integer
      )
      """,
      "CREATE INDEX IF NOT EXISTS #{@db_table}_day ON #{@db_table} (day)",
      "CREATE INDEX IF NOT EXISTS #{@db_table}_rid ON #{@db_table} (rid)",
      "CREATE INDEX IF NOT EXISTS #{@db_table}_origin_day ON #{@db_table} (origin, day)",
      "CREATE INDEX IF NOT EXISTS #{@db_table}_at ON #{@db_table} (at)",
      """
      CREATE TABLE IF NOT EXISTS #{@rollup_table} (
        day text, hour integer, event text, origin text, status text, n integer,
        PRIMARY KEY (day, hour, event, origin, status)
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{@archive_table} (
        day text PRIMARY KEY, path text, rows integer, bytes integer, created_at integer
      )
      """
    ]

    # A store created before these columns existed gains them; CREATE TABLE IF NOT EXISTS does not.
    alters =
      for {column, type} <- [
            {"at", "integer"},
            {"day", "text"},
            {"origin", "text"},
            {"rid", "text"},
            {"status", "text"}
          ],
          not column_exists?(@db_table, column),
          do: "ALTER TABLE #{@db_table} ADD COLUMN #{column} #{type}"

    result =
      Enum.reduce(statements ++ alters, :ok, fn sql, acc ->
        case run_query_ok(sql, []) do
          :ok -> acc
          :error -> :retry
        end
      end)

    backfill_days()

    result
  rescue
    _ -> :retry
  catch
    _, _ -> :retry
  end

  defp column_exists?(table, column) do
    case Exoforge.ActionDispatcher.dispatch_internal(:database, :table_columns, %{
           plugin: :observability,
           table: table
         }) do
      {:ok, %{columns: columns}} -> to_string(column) in columns
      _ -> false
    end
  end

  # Rows written before the day column existed still need a day to age out by.
  defp backfill_days do
    rows =
      run_query(
        "SELECT id, timestamp FROM #{@db_table} WHERE day IS NULL OR day = '' LIMIT 5000",
        []
      )

    Enum.each(rows, fn row ->
      id = to_string(row["id"] || row[:id])
      ms = int(row["timestamp"] || row[:timestamp], 0)

      if ms > 0 do
        run_query_ok("UPDATE #{@db_table} SET day = $1, at = $2 WHERE id = $3", [day(ms), ms, id])
      end
    end)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp warmup_from_db do
    ensure_schema()

    rows =
      run_query(
        "SELECT id, at, day, event, origin, rid, status, payload, context, time, timestamp " <>
          "FROM #{@db_table} ORDER BY at DESC LIMIT #{@max_events}",
        []
      )

    Enum.each(rows, fn row ->
      case row_to_item(row) do
        nil -> :ok
        item -> :ets.insert_new(@table, {-item.timestamp, item})
      end
    end)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  ## ---- archive ----

  defp archive_day(day) do
    dir = archive_dir()

    with :ok <- File.mkdir_p(dir),
         {:ok, path, rows, bytes} <- write_archive(day, Path.join(dir, "events-#{day}.ndjson.gz")) do
      at = System.system_time(:millisecond)

      run_query_ok(
        "DELETE FROM #{@archive_table} WHERE day = $1",
        [day]
      )

      case run_query_ok(
             "INSERT INTO #{@archive_table} (day, path, rows, bytes, created_at) VALUES ($1, $2, $3, $4, $5)",
             [day, path, rows, bytes, at]
           ) do
        :ok ->
          run_query_ok("DELETE FROM #{@db_table} WHERE day = $1", [day])
          Logger.info("[Observability] archived #{rows} events for #{day} to #{path}")
          :ok

        :error ->
          Logger.warning(
            "[Observability] could not record the archive for #{day}; keeping the rows"
          )

          :error
      end
    else
      {:error, reason} ->
        Logger.warning(
          "[Observability] could not archive #{day} (#{inspect(reason)}); keeping the rows"
        )

        :error
    end
  end

  # Streams the day in pages so a busy day does not have to fit in memory: one gzip member, written
  # chunk by chunk.
  defp write_archive(day, path) do
    {:ok, fd} = :file.open(path, [:write, :binary, :raw])
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, 31, 8, :default)

    try do
      {rows, rollups} = write_pages(fd, z, day, 0, 0, %{})
      :ok = :file.write(fd, :zlib.deflate(z, "", :finish))
      bytes = File.stat!(path).size

      persist_archive_rollups(rollups)

      {:ok, path, rows, bytes}
    rescue
      e -> {:error, Exception.message(e)}
    after
      :zlib.deflateEnd(z)
      :zlib.close(z)
      :file.close(fd)
    end
  end

  defp write_pages(fd, z, day, offset, rows, rollups) do
    rows_page =
      run_query(
        "SELECT id, at, day, event, origin, rid, status, payload, context, time, timestamp " <>
          "FROM #{@db_table} WHERE day = $1 ORDER BY at ASC LIMIT #{@archive_page} OFFSET #{offset}",
        [day]
      )

    case rows_page do
      [] ->
        {rows, rollups}

      rows_page ->
        lines = Enum.map(rows_page, &(Jason.encode!(archive_row(&1)) <> "\n"))
        :ok = :file.write(fd, :zlib.deflate(z, Enum.join(lines)))

        rollups =
          Enum.reduce(rows_page, rollups, fn row, acc ->
            key =
              {row["day"] || day, hour(int(row["at"], 0)), row["event"], row["origin"] || "",
               row["status"] || ""}

            Map.update(acc, key, 1, &(&1 + 1))
          end)

        write_pages(fd, z, day, offset + @archive_page, rows + length(rows_page), rollups)
    end
  end

  defp persist_archive_rollups(rollups) do
    Enum.each(rollups, fn {{day, hour, event, origin, status}, n} ->
      run_query(
        "INSERT INTO #{@rollup_table} (day, hour, event, origin, status, n) VALUES ($1, $2, $3, $4, $5, $6) " <>
          "ON CONFLICT (day, hour, event, origin, status) DO UPDATE SET n = n + excluded.n",
        [day, hour, event, origin, status, n]
      )
    end)
  end

  # Both the database rows and the decoded archive lines carry these fields, so this stays a
  # string-keyed map end to end: it is also what gets written back out as JSON.
  defp archive_row(row) do
    %{
      "id" => row["id"],
      "at" => int(row["at"], 0),
      "day" => row["day"],
      "event" => row["event"],
      "origin" => row["origin"],
      "rid" => row["rid"],
      "status" => row["status"],
      "payload" => decode(row["payload"]),
      "context" => decode(row["context"])
    }
  end

  # Archived days inside the caller's range, newest first.
  defp archive_days(filters) do
    {clauses, args} = day_range(filters)

    sql =
      "SELECT day, path FROM #{@archive_table}" <>
        if(clauses == [], do: "", else: " WHERE " <> Enum.join(clauses, " AND ")) <>
        " ORDER BY day DESC"

    run_query(sql, args) |> Enum.map(&{to_string(&1["day"]), to_string(&1["path"])})
  end

  defp day_range(filters) do
    since = int_filter(filters, :since_ms)
    until_ms = int_filter(filters, :until_ms)

    clauses = []
    args = []

    {clauses, args} =
      if since && since > 0 do
        {clauses ++ ["day >= $#{length(args) + 1}"], args ++ [day(since)]}
      else
        {clauses, args}
      end

    if until_ms && until_ms > 0 do
      {clauses ++ ["day <= $#{length(args) + 1}"], args ++ [day(until_ms)]}
    else
      {clauses, args}
    end
  end

  defp archived_matching({day, path}, filters, limit) do
    path
    |> File.stream!([:compressed, :utf8], :line)
    |> Stream.map(&decode_line/1)
    |> Stream.reject(&is_nil/1)
    |> Stream.map(&archive_row/1)
    |> Stream.filter(&matches?(&1, filters))
    |> Enum.take(limit)
    |> Enum.map(&archive_row_to_item/1)
  rescue
    e ->
      Logger.warning("[Observability] archive #{day} unreadable: #{Exception.message(e)}")
      []
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, map} -> stringify_keys(map)
      _ -> nil
    end
  end

  defp archive_for_rid(rid, limit) do
    archive_until(archive_days(%{rid: rid}), %{rid: rid}, limit, [])
  end

  # Newest day first, and no further once the caller's limit is filled: an old rid should not scan
  # every file the instance has ever archived.
  defp archive_until([], _filters, _remaining, acc), do: acc

  defp archive_until(_days, _filters, remaining, acc) when remaining <= 0, do: acc

  defp archive_until([day | days], filters, remaining, acc) do
    matches = archived_matching(day, filters, remaining)
    archive_until(days, filters, remaining - length(matches), acc ++ matches)
  end

  ## ---- queries ----

  defp where(filters) do
    clauses = []
    args = []

    {clauses, args} =
      append(clauses, args, "rid", string_filter(filters, :rid))

    {clauses, args} =
      append(clauses, args, "origin", string_filter(filters, :player))

    {clauses, args} =
      append(clauses, args, "event", string_filter(filters, :event))

    {clauses, args} =
      append(clauses, args, "status", string_filter(filters, :status))

    {clauses, args} =
      case int_filter(filters, :since_ms) do
        nil -> {clauses, args}
        0 -> {clauses, args}
        ms -> {clauses ++ ["at >= $#{length(args) + 1}"], args ++ [ms]}
      end

    {clauses, args} =
      case int_filter(filters, :until_ms) do
        nil -> {clauses, args}
        0 -> {clauses, args}
        ms -> {clauses ++ ["at <= $#{length(args) + 1}"], args ++ [ms]}
      end

    sql = if clauses == [], do: "", else: " WHERE " <> Enum.join(clauses, " AND ")
    {sql, args}
  end

  defp append(clauses, args, _column, nil), do: {clauses, args}
  defp append(clauses, args, _column, ""), do: {clauses, args}

  defp append(clauses, args, column, value) do
    {clauses ++ ["#{column} = $#{length(args) + 1}"], args ++ [value]}
  end

  defp matches?(row, filters) do
    string_filter(filters, :rid) |> blank_or(&(&1 == row["rid"])) &&
      string_filter(filters, :player) |> blank_or(&(&1 == row["origin"])) &&
      string_filter(filters, :event) |> blank_or(&(&1 == row["event"])) &&
      string_filter(filters, :status) |> blank_or(&(&1 == row["status"]))
  end

  defp blank_or(nil, _fun), do: true
  defp blank_or("", _fun), do: true
  defp blank_or(value, fun), do: fun.(value)

  defp filter_until(events, filters) do
    case int_filter(filters, :until_ms) do
      nil -> events
      0 -> events
      until_ms -> Enum.filter(events, &(&1.at <= until_ms))
    end
  end

  ## ---- db helpers ----

  defp run_query(sql, args) do
    case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: :observability,
           operation: sql,
           arguments: args
         }) do
      {:ok, %{rows: rows}} when is_list(rows) -> rows
      _ -> []
    end
  end

  defp run_query_ok(sql, args) do
    case Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: :observability,
           operation: sql,
           arguments: args
         }) do
      {:ok, _} -> :ok
      :ok -> :ok
      _ -> :error
    end
  end

  defp row_to_item(row) do
    timestamp = int(row["timestamp"] || row[:timestamp], 0)
    at = int(row["at"] || row[:at], div(timestamp, 1000))

    %{
      id: to_string(row["id"] || row[:id] || ""),
      event: to_string(row["event"] || row[:event] || ""),
      at: at,
      day: to_string(row["day"] || row[:day] || day(at)),
      origin: to_string(row["origin"] || row[:origin] || ""),
      rid: to_string(row["rid"] || row[:rid] || ""),
      status: to_string(row["status"] || row[:status] || ""),
      payload: decode(row["payload"] || row[:payload]),
      context: decode(row["context"] || row[:context]),
      time: to_string(row["time"] || row[:time] || ""),
      timestamp: timestamp
    }
  rescue
    _ -> nil
  end

  defp archive_row_to_item(row) do
    at = int(row["at"], 0)
    timestamp = at * 1000

    %{
      id: row["id"],
      event: row["event"],
      at: at,
      day: row["day"],
      origin: row["origin"],
      rid: row["rid"],
      status: row["status"],
      payload: row["payload"],
      context: row["context"],
      time: Calendar.strftime(DateTime.from_unix!(at, :millisecond), "%H:%M:%S"),
      timestamp: timestamp
    }
  end

  defp decode(nil), do: %{}

  defp decode(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      _ -> value
    end
  end

  defp decode(value), do: value

  defp stringify_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp string_filter(filters, key) when is_map(filters) do
    case Map.get(filters, key) || Map.get(filters, to_string(key)) do
      nil -> nil
      "" -> ""
      value -> to_string(value)
    end
  end

  defp string_filter(_filters, _key), do: nil

  defp int_filter(filters, key) when is_map(filters) do
    case Map.get(filters, key) || Map.get(filters, to_string(key)) do
      nil ->
        nil

      n when is_integer(n) ->
        n

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp int_filter(_filters, _key), do: nil

  defp int(nil, default), do: default
  defp int(n, _default) when is_integer(n), do: n

  defp int(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp int(_, default), do: default

  ## ---- config ----

  defp hot_days do
    raw =
      System.get_env("EXOFORGE_EVENT_HOT_DAYS") ||
        Application.get_env(:exoforge, :event_hot_days, 30)

    case Integer.parse(to_string(raw)) do
      {n, _} -> n |> max(1) |> min(365)
      :error -> 30
    end
  end

  defp archive_dir do
    System.get_env("EXOFORGE_EVENT_ARCHIVE_DIR") ||
      Path.join([
        System.get_env("EXOFORGE_DATA_DIR") || Path.join(File.cwd!(), "priv/data"),
        "event-archive"
      ])
  end
end
