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
  use Exoforge.Extension, provides: [:resource_store]

  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry

  @manifest %{
    dependencies: [Exoforge.Std.Services.Database],
    title: "Resource Store",
    icon: "🗃️",
    category: "Storage",
    system: true,
    dashboard_view: %{id: :resources, title: "Resource Store", icon: "🗃️"}
  }

  @cache :exo_resource_migrated

  # These columns are stored as text (`sql_type/1`), so their values cross the database boundary as
  # JSON. A map or a list bound straight to a text column is a bind/encode error in the adapter -
  # which is why a `:map` column's empty default looked like a missing value.
  @json_column_types [:map, :term, :list]

  ## ---- LIFECYCLE ----

  def on_init(_manifest) do
    ensure_cache()
    run_migrations(nil)
    :ok
  end

  ## ---- MIGRATIONS ----

  def run_migrations(target \\ nil, extension \\ nil, opts \\ []) do
    ensure_cache()
    typed_only? = Keyword.get(opts, :typed_only, false)

    resources =
      ExtensionRegistry.all_resources()
      |> Enum.filter(fn info -> not typed_only? or typed_resource?(info.resource) end)
      |> Enum.filter(fn info ->
        (target == nil or to_string(info.resource.name) == to_string(target)) and
          (extension == nil or to_string(info.extension_id) == to_string(extension) or
             to_string(info.plugin_id) == to_string(extension))
      end)

    with :ok <- validate_resources(resources) do
      Enum.reduce_while(resources, {:ok, 0}, fn info, {:ok, acc} ->
        case migrate_resource(info) do
          :ok -> {:cont, {:ok, acc + 1}}
          :skip -> {:cont, {:ok, acc}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, count} -> count
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_resources(resources) do
    Enum.reduce_while(resources, :ok, fn %{resource: res} = info, :ok ->
      case table_source(res) do
        nil ->
          {:cont, :ok}

        table ->
          case validate_resource(info, table, res) do
            :ok -> {:cont, :ok}
            {:error, _} = err -> {:halt, err}
          end
      end
    end)
  end

  defp migrate_resource(%{plugin_id: pid, resource: res} = info) do
    case table_source(res) do
      nil ->
        :skip

      table ->
        key = {pid, table}

        case validate_resource(info, table, res) do
          {:error, _} = err ->
            err

          :ok ->
            if typed_resource?(res),
              do: migrate_typed(info, table, key),
              else: migrate_legacy(info, table, key)
        end
    end
  end

  defp migrate_legacy(%{plugin_id: pid, resource: res} = info, table, key) do
    case db(pid, "CREATE TABLE IF NOT EXISTS #{table} (#{column_defs(res)})") do
      {:ok, _} ->
        repair_primary_key(pid, table, res)
        reconcile_columns(pid, table, res)
        mark_migrated(key)
        :ok

      {:error, reason} ->
        {:error, {:migration_failed, %{extension: info.extension_id, table: table, reason: reason}}}
    end
  end

  # A resource is typed when every one of its columns says what it stores (`storage`, emitted by the
  # C# generator): its table is then made and kept in line by the driver layer's reconciler (ADR 004).
  # Resources written with the Elixir DSL declare no `storage` and keep the older path above.
  defp typed_resource?(res) do
    case Map.get(res, :columns) || Map.get(res, "columns") do
      [_ | _] = columns ->
        Enum.all?(columns, fn col ->
          storage = Map.get(col, :storage) || Map.get(col, "storage")
          is_binary(storage) and storage != ""
        end)

      _ ->
        false
    end
  end

  defp migrate_typed(%{plugin_id: pid, resource: res} = info, table, key) do
    case apply_typed_schema(pid, res) do
      :ok ->
        mark_migrated(key)
        :ok

      {:error, {:unsafe_schema_change, _} = reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, {:migration_failed, %{extension: info.extension_id, table: table, reason: reason}}}
    end
  end

  defp apply_typed_schema(pid, res) do
    case lldb(:apply_schema, %{namespace: pid, resources: [res], migrations: migrations_for(pid, res)}) do
      {:ok, _} ->
        :ok

      {:error, {:unsafe_schema_change, ops}} ->
        unsafe_schema_change(pid, res, {:unsafe, ops})

      {:error, {kind, %{} = detail}}
      when kind in [:migration_missing, :version_downgrade, :migration_incomplete, :rows_below_version, :game_versions_lock_older, :game_versions_unavailable] ->
        unsafe_schema_change(pid, res, {kind, detail})

      # A table the studio owns is never rebuilt, whatever the mode: it is theirs, and its rows are theirs.
      {:error, {:schema_drift, %{items: items}}} ->
        refuse(pid, res, items,
          "This table is managed by you (SchemaVersioningMode.Manual). Apply your SQL migrations (`exo db migrate`) so it matches the " <>
            "declaration, or declare the resource Auto and let Exoforge keep it in line.")

      # Not a problem with the change: the table is busy. Rebuilding it would not help.
      {:error, {:lock_timeout, detail}} ->
        refuse(pid, res, [%{column: nil, change: :lock_timeout, reason: "the table is locked by another transaction (waited #{detail.timeout})"}],
          "Retry the deploy when traffic is lower, or raise `config :exoforge_std_lldb, :schema_lock_timeout`.")

      error ->
        error
    end
  end

  # The migrations an extension declared for one resource, from its manifest.
  defp migrations_for(pid, res) do
    name = to_string(Map.get(res, :name) || Map.get(res, "name"))

    case ExtensionRegistry.fetch_manifest(pid) do
      %{migrations: [_ | _] = all} -> Enum.filter(all, &(to_string(&1[:resource] || &1["resource"]) == name))
      _ -> []
    end
  end

  # The deploy decides what a change the table cannot take on its own means. `reset` is for development: the
  # table is dropped and made again, so its rows are gone. `refuse` (the default) fails the extension and says
  # what to write.
  defp unsafe_schema_change(pid, res, problem) do
    case schema_change_mode() do
      :reset ->
        table = table_for(res)
        Logger.warning("[ResourceStore] EXOFORGE_SCHEMA_CHANGE_MODE=reset: dropping table #{table} of #{pid} (rows are lost): #{describe(problem)}")
        lldb(:reset_table, %{namespace: pid, table: table})

        case lldb(:apply_schema, %{namespace: pid, resources: [res], migrations: migrations_for(pid, res)}) do
          {:ok, _} -> :ok
          error -> error
        end

      :refuse ->
        {changes, hint} = changes_and_hint(res, problem)
        refuse(pid, res, changes, hint)
    end
  end

  defp refuse(pid, res, changes, hint) do
    {:error,
     {:unsafe_schema_change,
      %{
        extension: to_string(pid),
        table: table_for(res),
        changes: Enum.map(changes, &Map.put(&1, :decl, declaration(res, Map.get(&1, :column)))),
        hint: hint
      }}}
  end

  @reset_hint "or set EXOFORGE_SCHEMA_CHANGE_MODE=reset to rebuild the table (its rows are lost)."

  defp changes_and_hint(res, {:unsafe, ops}) do
    live = ops |> List.first() |> then(&(&1[:live_version] || 0))

    {Enum.map(ops, &%{table: &1.table, column: Map.get(&1, :column), change: &1.op, reason: &1.reason}),
     "This change cannot be applied on its own, and the extension is still at version #{label(live)}. Raise the extension's version " <>
       "and add a migration to the new version: #{migration_how(res, "<the new version>")}, #{@reset_hint}"}
  end

  defp changes_and_hint(res, {:migration_missing, %{live: live, manifest: manifest, changes: changes}}) do
    {Enum.map(changes, &%{column: &1[:column], change: &1.change, reason: &1.reason}),
     "No migration leads from version #{label(live)} to #{label(manifest)}. " <>
       "#{upcase_first(migration_how(res, label(manifest)))}, #{@reset_hint}"}
  end

  defp changes_and_hint(_res, {:version_downgrade, %{live: live, manifest: manifest}}) do
    {[%{column: nil, change: :version, reason: "the table is at version #{label(live)} and this build is version #{label(manifest)}"}],
     "An older build is running over a newer table. Deploy version #{label(live)} or later, or set EXOFORGE_SCHEMA_CHANGE_MODE=reset in development."}
  end

  defp changes_and_hint(_res, {:migration_incomplete, %{remaining: remaining}}) do
    {Enum.map(remaining, &%{column: &1[:column], change: &1.change, reason: &1.reason}),
     "The migration ran but the table would still differ from the declared shape, so it was rolled back. Add the operations that are missing."}
  end

  defp changes_and_hint(_res, {:rows_below_version, %{rows: rows, to: to}}) do
    {[%{column: nil, change: :drop, reason: "#{rows} rows are still below version #{to}, so the column they hold would be lost"}],
     "Rows are brought up to date when they are read (or by the sweeper). Deploy the drop once none is left below #{to}, or set EXOFORGE_SCHEMA_CHANGE_MODE=reset in development."}
  end

  defp changes_and_hint(_res, {:game_versions_unavailable, %{reason: reason}}) do
    {[%{column: nil, change: :drop, reason: "the versioning extension did not answer (#{inspect(reason)}), so it is unknown which game versions still read the column"}],
     "Nothing was changed. Deploy again once the versioning extension is running."}
  end

  defp changes_and_hint(_res, {:game_versions_lock_older, %{to: to, game_versions: games}}) do
    names = Enum.map_join(games, ", ", &"#{&1.game_version} (#{&1.status})")

    {[%{column: nil, change: :drop, reason: "game versions still served lock this extension below #{to}: #{names}"}],
     "Those clients still read what the drop removes. Block or retire those game versions in the versioning extension first, or set EXOFORGE_SCHEMA_CHANGE_MODE=reset in development."}
  end

  # What to write, naming the file and the attribute.
  defp migration_how(res, to) do
    name = to_string(Map.get(res, :name) || Map.get(res, "name"))

    "add a class in its own file (for example Migrations/#{Macro.camelize(name)}/To#{String.replace(to, ~r/[^0-9A-Za-z]/, "_")}.cs) marked " <>
      "[ExoMigration(typeof(<your #{name} type>), To = \"#{to}\")] with the operations that make the change " <>
      "([ExoRename], [ExoConvert], [ExoFill], [ExoDrop], [ExoSetNotNull])"
  end

  defp label(stamp), do: Exoforge.VersionStamp.decode(stamp) || "0.0.0"

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(other), do: other

  defp describe({:unsafe, ops}), do: Enum.map_join(ops, "; ", & &1.message)
  defp describe({kind, detail}), do: "#{kind}: #{inspect(detail)}"

  # Where the column is declared in the extension's source (`Item.cs:42`), when the manifest says.
  defp declaration(res, column) when is_binary(column) do
    case Enum.find(Map.get(res, :columns) || Map.get(res, "columns") || [], &(to_string(&1[:name] || &1["name"]) == column)) do
      nil -> nil
      col -> col[:decl] || col["decl"]
    end
  end

  defp declaration(_res, _column), do: nil

  @doc "`:reset` or `:refuse`, set at the deploy site (env `EXOFORGE_SCHEMA_CHANGE_MODE`, or `config :exoforge, :schema_change_mode`). Default `:refuse`."
  def schema_change_mode do
    case System.get_env("EXOFORGE_SCHEMA_CHANGE_MODE") || Application.get_env(:exoforge, :schema_change_mode) do
      mode when mode in ["reset", :reset] -> :reset
      _ -> :refuse
    end
  end

  defp lldb(action, payload), do: ActionDispatcher.dispatch_internal(:lldb, action, payload)

  # `CREATE TABLE IF NOT EXISTS` does not repair a table that already exists, so one created by an
  # older schema keeps what it had. Without a PRIMARY KEY every upsert against it fails forever with
  # "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint" - and nothing said so,
  # because the one caller that mattered discarded the result.
  #
  # A UNIQUE INDEX satisfies a column-targeted `ON CONFLICT` exactly as a PRIMARY KEY does, so the
  # data does not have to move: one statement, no rows copied, nothing to recover if it fails.
  defp repair_primary_key(pid, table, res) do
    pk = String.downcase(to_string(res.primary_key || :id))

    pk_col =
      existing_columns(pid, table)
      |> Enum.find(&(String.downcase(to_string(&1)) == pk))
      |> Kernel.||(pk)

    case db(pid, "CREATE UNIQUE INDEX IF NOT EXISTS #{table}_#{pk}_key ON #{table} (#{pk_col})") do
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
  # Renames, type changes, and retroactive CHECK constraints on existing tables still need an
  # explicit migration (documented ceiling), so a column that gains choices keeps them on new tables only.
  defp reconcile_columns(pid, table, res) do
    existing =
      existing_columns(pid, table)
      |> Enum.map(&String.downcase(to_string(&1)))

    Enum.each(res.columns || [], fn column ->
      name = String.downcase(to_string(column.name))

      unless name in existing do
        _ =
          db(
            pid,
            "ALTER TABLE #{table} ADD COLUMN #{name} #{sql_type(column.type)}#{default_clause(column)}"
          )
      end
    end)

    relax_legacy_document_column(pid, table, res, existing)
  end

  # A table that began as a key-value document store has `data NOT NULL`. Once the resource declares
  # typed columns, rows are written without a document, and every insert would fail on that
  # constraint - which used to mean wiping the database. Keeping the column and dropping only its
  # NOT NULL leaves old rows readable (adapters that refuse ALTER COLUMN ignore it safely).
  defp relax_legacy_document_column(pid, table, res, existing) do
    declared = Enum.map(res.columns || [], &String.downcase(to_string(&1.name)))

    if "data" in existing and "data" not in declared do
      _ = db(pid, "ALTER TABLE #{table} ALTER COLUMN data DROP NOT NULL")
    end

    :ok
  end

  defp existing_columns(pid, table) do
    # The adapter answers with its own dialect via :table_columns.
    case ActionDispatcher.dispatch_internal(:database, :table_columns, %{plugin: pid, table: table}) do
      {:ok, %{columns: columns}} -> columns
      _ -> []
    end
  end

  defp column_defs(res) do
    pk = String.downcase(to_string(res.primary_key || :id))
    pk_col = Enum.find(res.columns || [], &(String.downcase(to_string(&1.name)) == pk))
    pk_type = if pk_col, do: sql_type(pk_col.type), else: "text"

    cols =
      (res.columns || [])
      |> Enum.reject(&(String.downcase(to_string(&1.name)) == pk))
      |> Enum.map(fn c ->
        name = String.downcase(to_string(c[:name] || c["name"] || c.name))
        "#{name} #{sql_type(c.type)}#{default_clause(c)}#{choices_clause(c, name)}"
      end)

    Enum.join(["#{pk} #{pk_type} PRIMARY KEY" | cols], ", ")
  end

  # A column that declares its choices is a closed set, so the database enforces it too - anything
  # writing SQL directly is held to the same schema as the API.
  defp choices_clause(column, name) do
    choices = column[:choices] || column["choices"]
    colname = name || String.downcase(to_string(column[:name] || column["name"]))

    if is_list(choices) and choices != [] do
      values = Enum.map_join(choices, ", ", &"'#{&1}'")
      " CHECK (#{colname} IN (#{values}))"
    else
      ""
    end
  end

  defp validate_resource(info, table, res) do
    pk = String.downcase(to_string(res.primary_key || :id))
    pk_down = String.downcase(pk)
    cols = res.columns || []
    names = Enum.map(cols, fn c -> to_string(c[:name] || c["name"] || c.name) end)
    down_names = Enum.map(names, &String.downcase/1)

    cond do
      pk_down != "id" and pk_down not in down_names ->
        {:error, {:invalid_resource, %{extension: info.extension_id, table: table, column: pk, reason: :primary_key_not_found}}}

      Enum.uniq(down_names) != down_names ->
        dup = down_names -- Enum.uniq(down_names)
        col = Enum.find(names, fn n -> String.downcase(n) == List.first(dup) end)
        {:error, {:invalid_resource, %{extension: info.extension_id, table: table, column: col, reason: :duplicate_column}}}

      true ->
        :ok
    end
  end

  # A column's default, as SQL. Quoted for text and left bare for numbers, so the database's idea of
  # the type matches the schema's rather than the value's spelling.
  defp default_clause(column) do
    # `||` would drop a boolean `false` default, which is a legitimate default and the common one.
    value = if is_nil(column[:default]), do: column["default"], else: column[:default]
    type = normalize_type(column[:type] || column["type"])

    cond do
      is_nil(value) -> ""
      type == :string -> " DEFAULT '#{String.replace(to_string(value), "'", "''")}'"
      true -> " DEFAULT #{value}"
    end
  end

  ## ---- ACTIONS ----

  @impl true
  defaction migrate(payload), scope: Exoforge.Auth.Roles.studio() do
    target = param(payload, :resource)
    extension = param(payload, :extension)

    case run_migrations(target, extension) do
      {:error, reason} -> {:error, reason}
      count when is_integer(count) -> {:ok, %{migrated: count}}
    end
  end

  @doc """
  Provisioning step: makes the tables of an extension's TYPED resources before the extension starts.
  Resources without declared column types are left to the lazy path. A failure is the extension's to
  report: the kernel records it as a boot failure of that extension alone (stage `:storage`).
  """
  @impl true
  defaction provision(payload), scope: Exoforge.Auth.Roles.studio() do
    case run_migrations(nil, param(payload, :extension), typed_only: true) do
      {:error, reason} -> {:error, reason}
      count when is_integer(count) -> {:ok, %{provisioned: count}}
    end
  end

  @impl true
  defaction list(payload), scope: Exoforge.Auth.Roles.player() do
    name = resource_name(payload)

    with {:ok, info} <- resource_info(name),
         :ok <- authorize_read(info, payload) do
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
  defaction get(payload), scope: Exoforge.Auth.Roles.player() do
    name = resource_name(payload)
    id = param(payload, :id)

    with {:ok, info} <- resource_info(name),
         :ok <- authorize_read(info, payload) do
      ensure_migrated(info)
      res = info.resource
      table = table_for(res)
      pk = String.downcase(to_string(res.primary_key || :id))

      target_id =
        if is_nil(id) and is_singleton?(res) do
          singleton_key(res)
        else
          id
        end

      case db(info.plugin_id, "SELECT * FROM #{table} WHERE #{pk} = $1", [coerce_id(res, target_id)]) do
        {:ok, %{rows: [row | _]}} ->
          {:ok, %{row: decode_row(res, row)}}

        {:ok, _} ->
          cond do
            is_singleton?(res) -> create_default_singleton(info, target_id)
            optional?(payload) -> {:ok, %{row: nil}}
            true -> {:error, :not_found}
          end

        error ->
          error
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

        case db(info.plugin_id, sql, values ++ [coerce_id(info.resource, id)]) do
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
      pk = String.downcase(to_string(res.primary_key || :id))

      case db(info.plugin_id, "DELETE FROM #{table} WHERE #{pk} = $1", [coerce_id(res, id)]) do
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
        pk = String.downcase(to_string(res.primary_key || :id))
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
    pk = String.downcase(to_string(res.primary_key || :id))

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

        if Map.has_key?(first, pk) and not kv_envelope_row?(first, info.resource),
          do: {:ok, result},
          else: kv_list(info, payload)

      _ ->
        kv_list(info, payload)
    end
  end

  defp kv_envelope_row?(row, res) when is_map(row) do
    declared = MapSet.new(res.columns || [], &String.downcase(to_string(&1.name)))
    Enum.sort(Map.keys(row)) == ["data", "id", "updated_at"] and not MapSet.member?(declared, "data")
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

  defp table_list(%{plugin_id: pid, resource: res} = info, payload) do
    table = table_for(res)
    {where_sql, where_args} = where_clause(res, param(payload, :filter), param(payload, :search))
    order_sql = order_clause(res, param(payload, :sort))
    limit = to_int(param(payload, :limit), 50)
    offset = to_int(param(payload, :offset), 0)

    sql = "SELECT * FROM #{table} #{where_sql} #{order_sql} LIMIT #{limit} OFFSET #{offset}"

    case db(pid, sql, where_args) do
      {:ok, %{rows: []}} ->
        if is_singleton?(res) and where_sql == "" do
          {:ok, %{row: row}} = create_default_singleton(info, singleton_key(res))
          {:ok, %{rows: [row], total: 1}}
        else
          {:ok, %{rows: [], total: 0}}
        end

      {:ok, %{rows: rows}} ->
        rows = Enum.map(rows, &decode_row(res, &1))
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
    pk = String.downcase(to_string(res.primary_key || :id))

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
        pk = String.downcase(to_string(res.primary_key || :id))
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
            |> Enum.map_join(" OR ", fn {col, i} -> "CAST(#{col} AS text) ILIKE $#{i}" end)

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
      |> Enum.map(fn {k, v} -> {to_string(k), encode_value(res, to_string(k), v)} end)
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

  defp encode_value(res, name, value) do
    if json_type?(column_type(res, name)) and (is_map(value) or is_list(value)) do
      case Jason.encode(value) do
        {:ok, json} -> json
        # ponytail: a term that is not JSON-encodable is inspected rather than dropped;
        # a binary/term column that needs fidelity should store base64 itself.
        _ -> inspect(value)
      end
    else
      value
    end
  end

  # `[:string]` and friends are lists a native extension's manifest names by element type.
  defp json_type?(type), do: type in @json_column_types or (is_binary(type) and String.starts_with?(type, "["))

  # An id arrives as a string (a URL, a form). A key column that holds numbers is bound as a number, or
  # the database refuses the parameter.
  defp coerce_id(res, id) when is_binary(id) do
    pk = String.downcase(to_string(res.primary_key || :id))

    case column_type(res, pk) do
      :integer ->
        case Integer.parse(String.trim(id)) do
          {n, ""} -> n
          _ -> id
        end

      :float ->
        case Float.parse(String.trim(id)) do
          {n, ""} -> n
          _ -> id
        end

      _ ->
        id
    end
  end

  defp coerce_id(_res, id), do: id

  defp column_type(res, name) do
    column = Enum.find(res.columns || [], &(to_string(&1.name || &1["name"]) == name))
    normalize_type((column && (column[:type] || column["type"])) || :string)
  end

  # Resources declared by a native extension arrive from manifest.json, where types are strings.
  defp normalize_type(type) when is_binary(type), do: Exoforge.Atoms.existing(type, type)
  defp normalize_type(type), do: type

  # Legacy or string-encoded boolean values may arrive as 1/0 or "true"/"false"; the resource's
  # declared columns are the schema this layer already has, so reads decode them here.
  defp decode_row(res, row) when is_map(row) do
    booleans =
      MapSet.new(
        for column <- res.columns || [],
            normalize_type(column[:type] || column["type"]) == :boolean,
            do: to_string(column[:name] || column["name"])
      )

    if MapSet.size(booleans) == 0 do
      row
    else
      Map.new(row, fn {column, value} ->
        {column, if(MapSet.member?(booleans, column), do: to_boolean(value), else: value)}
      end)
    end
  end

  defp decode_row(_res, row), do: row

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

  defp out_of_choices?({name, value}, res) do
    column = Enum.find(res.columns || [], &(to_string(&1.name) == name))
    choices = (column && (column[:choices] || column["choices"])) || []

    choices != [] and to_string(value) not in Enum.map(choices, &to_string/1)
  end

  defp resource_info(name) do
    case ExtensionRegistry.fetch_resource(name) do
      {:ok, info} -> {:ok, info}
      _ -> {:error, :resource_not_found}
    end
  end

  # Reads are player-callable at the dispatcher, but the row set is not public unless the resource
  # opts in. Staff and internal callers can always read; a player can read only a resource marked
  # `allow_player_read`. Writes stay studio-scoped.
  defp authorize_read(info, payload) do
    cond do
      allow_player_read?(info.resource) -> :ok
      internal_request?() -> :ok
      staff_scopes?(caller_scopes(payload)) -> :ok
      true -> {:error, {:forbidden_scope, %{required: :studio, caller_scopes: caller_scopes(payload), reason: :resource_not_player_readable}}}
    end
  end

  defp allow_player_read?(res) do
    (Map.get(res, :allow_player_read) || Map.get(res, "allow_player_read")) == true
  end

  defp internal_request? do
    case Exoforge.RequestContext.current() do
      %{internal: true} -> true
      _ -> false
    end
  end

  defp caller_scopes(payload) do
    case param(payload, :_auth) do
      auth when is_map(auth) -> Map.get(auth, :scopes) || Map.get(auth, "scopes") || []
      _ -> []
    end
  end

  defp staff_scopes?(:internal), do: true

  defp staff_scopes?(scopes) do
    Exoforge.Auth.Roles.satisfies?(scopes, Exoforge.Auth.Roles.studio())
  end

  defp optional?(payload), do: param(payload, :optional) in [true, "true"]

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
    ActionDispatcher.dispatch_internal(:database, :execute, %{
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

  # Native extensions declare column types in JSON, so both an atom and its string are accepted.
  defp sql_type(type) when is_binary(type), do: sql_type(Exoforge.Atoms.existing(type, type))
  defp sql_type(:integer), do: "integer"
  defp sql_type(:float), do: "real"
  defp sql_type(:boolean), do: "boolean"
  defp sql_type(:utc_datetime), do: "timestamp"
  defp sql_type(:datetime), do: "timestamp"
  defp sql_type(:map), do: "text"
  defp sql_type(:term), do: "text"
  defp sql_type(_), do: "text"

  defp is_singleton?(res) do
    res[:singleton] == true or
      res["singleton"] == true or
      to_string(res[:kind] || res["kind"]) == "singleton"
  end

  defp singleton_key(res) do
    pk_col_name = to_string(res.primary_key || :id)
    pk_col = Enum.find(res.columns || [], &(to_string(&1.name || &1["name"]) == pk_col_name))
    default_val = pk_col && (pk_col[:default] || pk_col["default"])

    if default_val && default_val != "" do
      to_string(default_val)
    else
      "default"
    end
  end

  defp create_default_singleton(info, target_id) do
    res = info.resource
    pk = String.downcase(to_string(res.primary_key || :id))
    key_val = target_id || singleton_key(res)

    default_attrs =
      (res.columns || [])
      |> Enum.reduce(%{}, fn col, acc ->
        name = to_string(col.name || col["name"])
        raw_default = if is_nil(col[:default]), do: col["default"], else: col[:default]
        type = normalize_type(col[:type] || col["type"] || :string)

        val =
          cond do
            name == pk ->
              key_val

            raw_default != nil and raw_default != "" ->
              case type do
                :integer -> if(is_integer(raw_default), do: raw_default, else: String.to_integer(to_string(raw_default)))
                :float -> if(is_float(raw_default), do: raw_default, else: String.to_float(to_string(raw_default)))
                :boolean -> raw_default in [true, "true", 1, "1"]
                _ -> to_string(raw_default)
              end

            true ->
              case type do
                :integer -> 0
                :float -> 0.0
                :boolean -> false
                :map -> %{}
                :list -> []
                _ -> ""
              end
          end

        Map.put(acc, name, val)
      end)

    case create(%{resource: to_string(res.name), attributes: default_attrs}) do
      {:ok, %{row: row}} -> {:ok, %{row: row}}
      _ -> {:ok, %{row: default_attrs}}
    end
  end
end
