defmodule Exoforge.Std.Resources do
  @moduledoc """
  Schema-driven persistence for declared resources.

  Sits on top of the `:database` contract and turns a resource's `columns`
  metadata into storage: it derives table DDL, runs additive migrations, and
  provides generic `list/get/create/update/delete/upsert`.

  A resource opts in by declaring a `source`:

      resource :players do
        source({:table, "players"})   # store-managed table + CRUD
      end

  Read-only projections can delegate instead of owning a table:

      source({:action, :list_players})  # delegate reads to a plugin action
      source({:query, "SELECT ..."})    # custom read SQL

  Resources without a `source` are not store-managed and fall back to the
  plugin's own `list_*` action.
  """
  use Exoforge.Plugin, provides: [:resource_store]

  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.PluginRegistry

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database],
    category: "Storage",
    system: true,
    dashboard_view: %{id: :resources, title: "Resource Store", icon: "🗄️"}
  }

  @cache :exo_resource_migrated

  ## ---- LIFECYCLE ----

  def on_init(_manifest) do
    ensure_cache()
    run_migrations(nil)
    :ok
  end

  ## ---- MIGRATIONS ----

  @doc "Ensures tables exist for every store-managed resource (additive only)."
  def run_migrations(target \\ nil) do
    ensure_cache()

    PluginRegistry.all_resources()
    |> Enum.filter(fn info ->
      target == nil or to_string(info.resource.name) == to_string(target)
    end)
    |> Enum.reduce(0, fn info, acc ->
      case migrate_resource(info) do
        :ok -> acc + 1
        _ -> acc
      end
    end)
  end

  defp migrate_resource(%{plugin_id: pid, resource: res}) do
    case table_source(res) do
      nil ->
        :skip

      table ->
        key = {pid, table}
        _ = db(pid, "CREATE TABLE IF NOT EXISTS #{table} (#{column_defs(res)})")
        repair_primary_key(pid, table, res)
        reconcile_columns(pid, table, res)
        mark_migrated(key)
        :ok
    end
  end

  # `CREATE TABLE IF NOT EXISTS` does not repair a table that already exists, so one created by an
  # older schema keeps what it had. Without a PRIMARY KEY every upsert against it fails forever with
  # "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint" - and nothing said so,
  # because the one caller that mattered discarded the result.
  #
  # A UNIQUE INDEX satisfies a column-targeted `ON CONFLICT` exactly as a PRIMARY KEY does, so the
  # data does not have to move: one statement, no rows copied, nothing to recover if it fails.
  defp repair_primary_key(pid, table, res) do
    pk = to_string(res.primary_key || :id)

    case db(pid, "CREATE UNIQUE INDEX IF NOT EXISTS #{table}_#{pk}_key ON #{table} (#{pk})") do
      {:ok, _} ->
        :ok

      error ->
        # Duplicate keys, or a column the table does not have. Say it out loud: the alternative is an
        # upsert that reports success and writes nothing.
        Logger.warning(
          "[Resources] #{table} could not be given a unique key on #{pk} " <>
            "(#{inspect(error)}); upserts against it will keep failing."
        )

        :ok
    end
  end

  # Additive reconciliation: `ADD COLUMN` for anything the resource declares that the table does not
  # have.
  #
  # It used to compare against a bookkeeping table rather than the table itself, and treat an empty
  # bookkeeping table as "nothing to do" - so a resource that gained a column recorded it and never
  # added it, and every write naming that column failed with "table has no column named". The database
  # already knows which columns exist; asking it is both correct and one table fewer.
  #
  # Renames and type changes still need an explicit migration (documented ceiling), and SQLite cannot
  # add a CHECK to an existing table, so a column that gains choices keeps them on new tables only.
  defp reconcile_columns(pid, table, res) do
    existing = existing_columns(pid, table)

    Enum.each(res.columns || [], fn column ->
      name = to_string(column.name)

      unless name in existing do
        _ =
          db(
            pid,
            "ALTER TABLE #{table} ADD COLUMN #{name} #{sql_type(column.type)}#{default_clause(column)}"
          )
      end
    end)
  end

  defp existing_columns(pid, table) do
    # The adapter answers with its own dialect (M33 Fix 9); a PRAGMA is SQLite-only.
    case ActionDispatcher.dispatch(:database, :table_columns, %{plugin: pid, table: table}) do
      {:ok, %{columns: columns}} -> columns
      _ -> []
    end
  end

  defp column_defs(res) do
    pk = to_string(res.primary_key || :id)
    pk_col = Enum.find(res.columns || [], &(to_string(&1.name) == pk))
    pk_type = if pk_col, do: sql_type(pk_col.type), else: "text"

    cols =
      (res.columns || [])
      |> Enum.reject(&(to_string(&1.name) == pk))
      |> Enum.map(fn c -> "#{c.name} #{sql_type(c.type)}#{default_clause(c)}#{choices_clause(c)}" end)

    Enum.join(["#{pk} #{pk_type} PRIMARY KEY" | cols], ", ")
  end

  # A column that declares its choices is a closed set, so the database enforces it too - anything
  # writing SQL directly is held to the same schema as the API.
  defp choices_clause(column) do
    choices = column[:choices] || column["choices"]

    if is_list(choices) and choices != [] do
      values = Enum.map_join(choices, ", ", &"'#{&1}'")
      " CHECK (#{column[:name] || column["name"]} IN (#{values}))"
    else
      ""
    end
  end

  # A column's default, as SQL. Quoted for text and left bare for numbers, so the database's idea of
  # the type matches the schema's rather than the value's spelling.
  defp default_clause(column) do
    value = column[:default] || column["default"]
    type = column[:type] || column["type"]

    cond do
      is_nil(value) -> ""
      type == :string -> " DEFAULT '#{value}'"
      true -> " DEFAULT #{value}"
    end
  end

  ## ---- ACTIONS ----

  @impl true
  defaction migrate(payload), scope: Exoforge.Auth.Roles.studio() do
    target = param(payload, :resource)
    {:ok, %{migrated: run_migrations(target)}}
  end

  @impl true
  defaction list(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)

    with {:ok, info} <- resource_info(name) do
      ensure_migrated(info)

      case normalize_source(info.resource) do
        {:action, action} -> delegate_list(info.plugin_id, action, payload)
        {:query, sql} -> query_list(info.plugin_id, sql)
        {:table, _} -> table_list(info, payload)
        nil -> list_without_source(info, payload)
      end
    end
  end

  @impl true
  defaction get(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)
    id = param(payload, :id)

    with {:ok, info} <- resource_info(name) do
      ensure_migrated(info)
      res = info.resource
      table = table_for(res)
      pk = to_string(res.primary_key || :id)

      case db(info.plugin_id, "SELECT * FROM #{table} WHERE #{pk} = $1", [id]) do
        {:ok, %{rows: [row | _]}} -> {:ok, %{row: row}}
        {:ok, _} -> {:error, :not_found}
        error -> error
      end
    end
  end

  ## ---- WRITES ----

  @impl true
  defaction create(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)
    attrs = param(payload, :attributes) || %{}

    with {:ok, info} <- resource_info(name),
         {:ok, pairs} <- writable_pairs(info.resource, attrs) do
      ensure_migrated(info)

      if table_source(info.resource) == nil do
        kv_write(info, Map.new(pairs))
      else
        table = table_for(info.resource)
        {names, values} = Enum.unzip(pairs)
        placeholders = Enum.map_join(1..length(names), ", ", &"$#{&1}")

        case db(
               info.plugin_id,
               "INSERT INTO #{table} (#{Enum.join(names, ", ")}) VALUES (#{placeholders})",
               values
             ) do
          {:ok, _} -> fetch_created(info, attrs)
          error -> error
        end
      end
    end
  end

  @impl true
  defaction update(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)
    id = param(payload, :id)
    attrs = param(payload, :attributes) || %{}

    with {:ok, info} <- resource_info(name),
         {:ok, pairs} <- writable_pairs(info.resource, attrs) do
      ensure_migrated(info)

      if table_source(info.resource) == nil do
        kv_write(info, Map.new(pairs))
      else
        table = table_for(info.resource)
        pk = to_string(info.resource.primary_key || :id)
        {names, values} = Enum.unzip(pairs)

        assignments =
          names
          |> Enum.with_index(1)
          |> Enum.map_join(", ", fn {n, i} -> "#{n} = $#{i}" end)

        sql = "UPDATE #{table} SET #{assignments} WHERE #{pk} = $#{length(names) + 1}"

        case db(info.plugin_id, sql, values ++ [id]) do
          {:ok, _} -> get(%{resource: name, id: id})
          error -> error
        end
      end
    end
  end

  @impl true
  defaction delete(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)
    id = param(payload, :id)

    with {:ok, info} <- resource_info(name) do
      ensure_migrated(info)
      res = info.resource
      table = table_for(res)
      pk = to_string(res.primary_key || :id)

      case db(info.plugin_id, "DELETE FROM #{table} WHERE #{pk} = $1", [id]) do
        {:ok, _} -> {:ok, %{deleted: true}}
        error -> error
      end
    end
  end

  @impl true
  @doc "Deletes every row of a resource. Table-backed resources are truncated; KV-backed ones are emptied key by key."
  defaction clear(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)

    with {:ok, info} <- resource_info(name) do
      ensure_migrated(info)
      res = info.resource

      result =
        case table_source(res) do
          nil -> kv_clear(info)
          table -> db(info.plugin_id, "DELETE FROM #{table}", [])
        end

      case result do
        {:ok, _} -> {:ok, %{cleared: true}}
        error -> error
      end
    end
  end

  # Native plugins keep rows in the host KV store, so clearing means dropping each key.
  @impl true
  defaction upsert(payload), scope: Exoforge.Auth.Roles.studio() do
    name = resource_name(payload)
    attrs = param(payload, :attributes) || %{}

    with {:ok, info} <- resource_info(name),
         {:ok, pairs} <- writable_pairs(info.resource, attrs) do
      ensure_migrated(info)
      res = info.resource

      if table_source(res) == nil do
        kv_write(info, Map.new(pairs))
      else
        table = table_for(res)
        pk = to_string(res.primary_key || :id)
        {names, values} = Enum.unzip(pairs)
        placeholders = Enum.map_join(1..length(names), ", ", &"$#{&1}")

        updates =
          names
          |> Enum.reject(&(&1 == pk))
          |> Enum.map_join(", ", fn n -> "#{n} = excluded.#{n}" end)

        conflict = if updates == "", do: "DO NOTHING", else: "DO UPDATE SET #{updates}"

        sql =
          "INSERT INTO #{table} (#{Enum.join(names, ", ")}) VALUES (#{placeholders}) " <>
            "ON CONFLICT(#{pk}) #{conflict}"

        case db(info.plugin_id, sql, values) do
          {:ok, _} -> fetch_created(info, attrs)
          error -> error
        end
      end
    end
  end

  ## ---- QUERY BUILDING ----

  defp kv_clear(%{plugin_id: pid, resource: res}) do
    db = Module.concat([Exoforge, Std, Database])
    table = to_string(res.name)
    pk = to_string(res.primary_key || :id)

    case apply(db, :all, [pid, table]) do
      {:ok, rows} when is_list(rows) ->
        Enum.each(rows, fn row ->
          id = row["id"] || row[pk]
          if id, do: apply(db, :delete, [pid, table, to_string(id)])
        end)

        {:ok, %{rows: []}}

      other ->
        other
    end
  rescue
    _ -> {:ok, %{rows: []}}
  end

  defp list_without_source(info, payload) do
    case list_action(info.resource) do
      nil -> table_or_kv_list(info, payload)
      action -> delegate_list(info.plugin_id, action, payload)
    end
  end

  # A resource with no declared source may be backed by a real table the plugin created, or by
  # the host KV bridge native plugins write through. Use the table when it looks like the
  # resource (its primary key is present); otherwise read the KV store.
  defp table_or_kv_list(info, payload) do
    case table_list(info, payload) do
      {:ok, %{rows: [first | _]} = result} ->
        pk = to_string(info.resource.primary_key || :id)

        if Map.has_key?(first, pk), do: {:ok, result}, else: kv_list(info, payload)

      _ ->
        kv_list(info, payload)
    end
  end

  defp list_action(res) do
    res
    |> Map.get(:actions, [])
    |> action_names()
    |> Enum.find(&String.starts_with?(&1, "list_"))
    |> case do
      nil -> nil
      name -> Exoforge.Atoms.existing(name)
    end
  end

  # An empty `actions` list survives JSON sanitization as `%{}`, so accept either shape.
  defp action_names(actions) when is_list(actions), do: Enum.map(actions, &to_string/1)
  defp action_names(actions) when is_map(actions), do: Enum.map(Map.keys(actions), &to_string/1)
  defp action_names(_), do: []

  defp table_list(%{plugin_id: pid, resource: res}, payload) do
    table = table_for(res)
    {where_sql, where_args} = where_clause(res, param(payload, :filter), param(payload, :search))
    order_sql = order_clause(res, param(payload, :sort))
    limit = to_int(param(payload, :limit), 50)
    offset = to_int(param(payload, :offset), 0)

    sql = "SELECT * FROM #{table} #{where_sql} #{order_sql} LIMIT #{limit} OFFSET #{offset}"

    case db(pid, sql, where_args) do
      {:ok, %{rows: rows}} ->
        {:ok, %{rows: rows, total: count_rows(pid, table, where_sql, where_args, rows)}}

      error ->
        error
    end
  end

  # Native plugins write through the host key/value bridge, so their rows live in the plugin's
  # KV store, not in a table shaped like the resource. The database adapter's `:all` command
  # returns those records already decoded.
  # A resource with no `source` is stored by its own plugin, through the host's key-value bridge.
  # `list` already reads both kinds; without this a row made in the Studio could be listed and not
  # written, which is the asymmetry the Data tab's form walked into.
  defp kv_write(%{plugin_id: pid, resource: res}, attrs) do
    db = Module.concat([Exoforge, Std, Database])
    table = to_string(res.name)
    pk = to_string(res.primary_key || :id)

    case attrs[pk] do
      nil -> {:error, :missing_primary_key}
      id -> apply(db, :put, [pid, table, to_string(id), attrs])
    end
  rescue
    e -> {:error, e}
  end

  # Only when the resource calls its key something else. A resource whose primary key *is* `id` has
  # no duplicate to drop: the bridge's key and the resource's column are the same field.
  defp drop_stored_key(row, "id"), do: row

  defp drop_stored_key(row, pk) when is_map(row) do
    id = Map.get(row, "id")
    value = Map.get(row, pk)

    # Compared as strings: the key is always text, and the resource's own column may not be.
    if is_binary(id) and id == to_string(value), do: Map.delete(row, "id"), else: row
  end

  defp drop_stored_key(row, _pk), do: row

  defp kv_list(%{plugin_id: pid, resource: res}, payload) do
    limit = to_int(param(payload, :limit), 50)
    offset = to_int(param(payload, :offset), 0)
    db = Module.concat([Exoforge, Std, Database])

    case apply(db, :all, [pid, to_string(res.name)]) do
      {:ok, rows} when is_list(rows) ->
        # The bridge stores the row under a key and injects it as `id`, so every row carried the
        # primary key twice - once as the resource declares it and once as the store's own string.
        # Dropped here rather than in the adapter: the key is how the row is stored, and the resource
        # is what decides whether it is a field.
        pk = to_string(res.primary_key || :id)
        rows = Enum.map(rows, &drop_stored_key(&1, pk))

        {:ok, %{rows: Enum.slice(rows, offset, limit), total: length(rows)}}

      _ ->
        {:ok, %{rows: [], total: 0}}
    end
  rescue
    _ -> {:ok, %{rows: [], total: 0}}
  end

  defp count_rows(pid, table, where_sql, where_args, rows) do
    case db(pid, "SELECT COUNT(*) AS n FROM #{table} #{where_sql}", where_args) do
      {:ok, %{rows: [row | _]}} -> row["n"] || row[:n] || length(rows)
      _ -> length(rows)
    end
  end

  defp where_clause(res, filter, search) do
    filterable = for c <- res.columns || [], c.filterable, do: to_string(c.name)

    {filter_sql, filter_args} =
      (filter || %{})
      |> Enum.reduce({"", []}, fn {k, v}, {sql, args} ->
        name = to_string(k)

        if name in filterable and not is_nil(v) do
          {clause, arg} = {name, v}
          joiner = if sql == "", do: "", else: " AND "
          {sql <> joiner <> "#{clause} = $#{length(args) + 1}", args ++ [arg]}
        else
          {sql, args}
        end
      end)

    {search_sql, search_args} =
      case search do
        s when is_binary(s) and s != "" and filterable != [] ->
          pattern = "%#{s}%"

          ors =
            filterable
            |> Enum.with_index(length(filter_args) + 1)
            |> Enum.map_join(" OR ", fn {col, i} -> "#{col} LIKE $#{i}" end)

          {ors, Enum.map(filterable, fn _ -> pattern end)}

        _ ->
          {"", []}
      end

    cond do
      filter_sql == "" and search_sql == "" -> {"", []}
      filter_sql == "" -> {"WHERE (#{search_sql})", search_args}
      search_sql == "" -> {"WHERE #{filter_sql}", filter_args}
      true -> {"WHERE #{filter_sql} AND (#{search_sql})", filter_args ++ search_args}
    end
  end

  defp order_clause(res, sort) do
    sortable = for c <- res.columns || [], c.sortable, do: to_string(c.name)

    case sort do
      s when is_binary(s) and s != "" ->
        {dir, col} =
          case String.split(s, ":", parts: 2) do
            [c, "desc"] -> {"DESC", c}
            [c, "asc"] -> {"ASC", c}
            [c] -> {"ASC", c}
          end

        if col in sortable, do: "ORDER BY #{col} #{dir}", else: ""

      _ ->
        ""
    end
  end

  defp delegate_list(pid, action, payload) do
    case ActionDispatcher.dispatch(pid, action, payload) do
      {:ok, %{rows: rows}} when is_list(rows) -> {:ok, %{rows: rows, total: length(rows)}}
      {:ok, rows} when is_list(rows) -> {:ok, %{rows: rows, total: length(rows)}}
      other -> other
    end
  end

  defp query_list(pid, sql) do
    case db(pid, sql) do
      {:ok, %{rows: rows}} -> {:ok, %{rows: rows, total: length(rows)}}
      error -> error
    end
  end

  ## ---- HELPERS ----

  defp fetch_created(info, attrs) do
    pk = info.resource.primary_key || :id
    id = param(attrs, pk)

    if is_nil(id) do
      {:ok, %{row: attrs}}
    else
      get(%{resource: to_string(info.resource.name), id: id})
    end
  end

  defp writable_pairs(res, attrs) do
    allowed = for c <- res.columns || [], do: to_string(c.name)

    pairs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.filter(fn {k, _v} -> k in allowed end)

    stray = Enum.find(pairs, &out_of_choices?(&1, res))

    cond do
      pairs == [] ->
        {:error, :invalid_attributes}

      # The database would reject this too, but saying it here names the column and the value instead
      # of surfacing a constraint violation from three layers down.
      stray != nil ->
        {:error, {:not_a_choice, elem(stray, 0), elem(stray, 1)}}

      true ->
        {:ok, pairs}
    end
  end

  defp out_of_choices?({name, value}, res) do
    column = Enum.find(res.columns || [], &(to_string(&1.name) == name))
    choices = (column && (column[:choices] || column["choices"])) || []

    choices != [] and to_string(value) not in Enum.map(choices, &to_string/1)
  end

  defp resource_info(name) do
    case PluginRegistry.fetch_resource(name) do
      {:ok, info} -> {:ok, info}
      _ -> {:error, :resource_not_found}
    end
  end

  defp resource_name(payload), do: param(payload, :resource) |> to_string()

  defp table_source(res),
    do:
      (case normalize_source(res) do
         {:table, table} -> table
         _ -> nil
       end)

  defp table_for(res) do
    case normalize_source(res) do
      {:table, table} -> table
      _ -> to_string(res.name)
    end
  end

  # The resource map may have gone through JSON sanitization, so accept both
  # the tuple form `{:table, "x"}` and the list form `["table", "x"]`.
  defp normalize_source(res) do
    case Map.get(res, :source) || Map.get(res, "source") do
      {:table, t} -> {:table, to_string(t)}
      [:table, t] -> {:table, to_string(t)}
      ["table", t] -> {:table, to_string(t)}
      # The manifest is JSON, and the loader turns map keys into atoms, so a source written as an
      # object arrives with an atom key. Only the string key was matched, which meant a source
      # declared that way read as no source at all.
      %{table: t} -> {:table, to_string(t)}
      %{"table" => t} -> {:table, to_string(t)}
      {:action, a} -> {:action, to_atom(a)}
      [:action, a] -> {:action, to_atom(a)}
      ["action", a] -> {:action, to_atom(a)}
      %{action: a} -> {:action, to_atom(a)}
      %{"action" => a} -> {:action, to_atom(a)}
      {:query, q} -> {:query, q}
      [:query, q] -> {:query, q}
      ["query", q] -> {:query, q}
      %{query: q} -> {:query, q}
      %{"query" => q} -> {:query, q}
      _ -> nil
    end
  end

  defp to_atom(a) when is_atom(a), do: a
  defp to_atom(a) when is_binary(a), do: Exoforge.Atoms.existing(a, a)

  defp ensure_migrated(info) do
    key = {info.plugin_id, table_for(info.resource)}
    ensure_cache()

    unless :ets.member(@cache, key) do
      migrate_resource(info)
    end
  end

  defp ensure_cache do
    if :ets.whereis(@cache) == :undefined do
      :ets.new(@cache, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  defp mark_migrated(key), do: :ets.insert(@cache, {key, true})

  defp db(plugin_id, sql, args \\ []) do
    ActionDispatcher.dispatch(:database, :execute, %{
      plugin: plugin_id,
      operation: sql,
      arguments: args
    })
  end

  defp param(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, to_string(key))
  end

  defp param(_payload, _key), do: nil

  defp to_int(nil, default), do: default
  defp to_int(n, _default) when is_integer(n), do: n
  defp to_int(n, _default) when is_binary(n), do: String.to_integer(n)
  defp to_int(_n, default), do: default

  defp sql_type(:integer), do: "integer"
  defp sql_type(:float), do: "real"
  defp sql_type(:boolean), do: "boolean"
  defp sql_type(:utc_datetime), do: "timestamp"
  defp sql_type(:datetime), do: "timestamp"
  defp sql_type(:map), do: "text"
  defp sql_type(:term), do: "text"
  defp sql_type(_), do: "text"
end
