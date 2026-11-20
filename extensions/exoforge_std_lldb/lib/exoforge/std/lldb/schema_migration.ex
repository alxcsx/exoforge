defmodule Exoforge.Std.Lldb.SchemaMigration do
  @moduledoc """
  Brings a table to the shape of the extension version being deployed with plain `ALTER TABLE` statements.

  The reconciler applies what is safe on its own. A change that is not safe (a type change, a `NOT NULL` column
  that existing rows cannot fill) needs a migration. The migrations arrive in the manifest, written as attributes in
  the extension's source, each leading to an extension version (`To = "1.2.0"`), so nothing of the extension runs:
  each step is an operation (`rename`, `convert`, `fill`, `drop`, `set_not_null`) rendered here as SQL.

  The table's ledger records the extension version it was last reconciled at. A deploy runs the migrations with a
  `To` after that and not past the deploy's own version, in order. A column the manifest no longer lists is retired,
  not dropped; only an explicit `drop` removes it, and only once no row is stamped below that migration's version.

  The steps for one table run in ONE transaction (PostgreSQL DDL is transactional), under a lock timeout so
  a blocked `ALTER` fails the deploy instead of queueing every query behind it. Afterwards the table is
  compared with the manifest again, inside the same transaction: any difference left rolls everything back,
  so a migration that does not lead to the declared shape never half-applies.

  Without a migration for an unsafe change, or when the table is already at a newer version than the deploy,
  nothing is changed and the reason is returned.
  """
  alias Exoforge.Std.Lldb.Schema

  @default_lock_timeout "5s"

  @doc """
  `Schema.reconcile/3` for resources that may need migrating. `version` is the encoded extension version being
  deployed (`Exoforge.VersionStamp`); `migrations` are the manifest's, each `%{resource, to, ops}`.
  """
  def reconcile(conn, schema, resources, migrations, version \\ 0) do
    with {:ok, s} <- Schema.validate_ident(schema),
         :ok <- Schema.ensure_ledgers(conn, s),
         {:ok, plan} <- read_plan(conn, s, resources, version),
         {:ok, work} <- decide(plan, resources, List.wrap(migrations), version) do
      case work do
        [] -> Schema.apply(conn, plan)
        _ -> run(conn, s, plan, work)
      end
    end
  end

  # Reading the tables (are they empty, are there nulls) queries them, so it waits behind anyone holding an
  # exclusive lock on one. Take a shared lock on each under the lock timeout first: if the table is busy
  # the deploy fails now, and the reads that follow cannot wait.
  defp read_plan(conn, schema, resources, version) do
    qs = Schema.quote_ident!(schema)

    result =
      Postgrex.transaction(conn, fn tx ->
        Schema.run_tx!(tx, "SET LOCAL lock_timeout = '#{lock_timeout()}'", [])

        with {:ok, normalized} <- Schema.normalized_resources(resources) do
          existing = Schema.existing_tables(tx, schema)

          for %{table: table} <- normalized, MapSet.member?(existing, table) do
            Schema.run_tx!(tx, "LOCK TABLE #{qs}.#{Schema.quote_ident!(table)} IN ACCESS SHARE MODE", [])
          end
        end

        with {:ok, live} <- Schema.read_live_state(tx, schema, resources),
             {:ok, plan} <- Schema.plan(resources, live, version) do
          plan
        else
          {:error, reason} -> Postgrex.rollback(tx, reason)
        end
      end)

    case result do
      {:ok, plan} -> {:ok, plan}
      {:error, reason} -> {:error, translate(reason)}
    end
  end

  ## ---- what has to be migrated ----

  defp decide(plan, resources, migrations, version) do
    unsafe_by_table = plan.ops |> Enum.filter(&(&1.safety == :unsafe)) |> Enum.group_by(& &1.table)

    result =
      plan.versions
      |> Enum.sort()
      |> Enum.reduce_while({:ok, [], []}, fn {table, info}, {:ok, work, stuck} ->
        %{live: live, resource: resource} = info
        ops = Map.get(unsafe_by_table, table, [])
        # A table with no ledger row was not made by a versioned deploy: history says nothing about it.
        steps = if Map.get(info, :known, false), do: steps_for(migrations, resource, live, version), else: []

        cond do
          live > version ->
            {:halt, {:error, {:version_downgrade, %{table: table, resource: resource, live: live, manifest: version}}}}

          steps != [] ->
            item = %{table: table, resource: resource, steps: steps, version: version, raw: raw_resource(resources, table)}
            {:cont, {:ok, [item | work], stuck}}

          ops == [] ->
            {:cont, {:ok, work, stuck}}

          # unsafe, and no migration leads here: the version was not raised, or the migration was not written
          live == version ->
            annotated = Enum.map(ops, &Map.merge(&1, %{live_version: live, manifest_version: version, resource: resource}))
            {:cont, {:ok, work, stuck ++ annotated}}

          true ->
            {:halt,
             {:error,
              {:migration_missing,
               %{
                 table: table,
                 resource: resource,
                 live: live,
                 manifest: version,
                 changes: Enum.map(ops, &%{column: &1[:column], change: &1.op, reason: &1.reason})
               }}}}
        end
      end)

    case result do
      {:ok, work, []} -> {:ok, Enum.reverse(work)}
      {:ok, _work, stuck} -> {:error, Schema.unsafe_error(stuck)}
      error -> error
    end
  end

  # The migrations of one resource that lead to a version after the table's and not beyond the deploy's, oldest first.
  defp steps_for(migrations, resource, live, version) do
    migrations
    |> Enum.filter(fn m ->
      to = Exoforge.VersionStamp.encode(g(m, :to))
      g(m, :resource) == resource and to > live and to <= version
    end)
    |> Enum.sort_by(&Exoforge.VersionStamp.encode(g(&1, :to)))
  end

  defp raw_resource(resources, table) do
    Enum.find(resources, fn raw ->
      case Schema.normalized_resources([raw]) do
        {:ok, [%{table: ^table}]} -> true
        _ -> false
      end
    end)
  end

  ## ---- running it ----

  defp run(conn, schema, plan, work) do
    qs = Schema.quote_ident!(schema)
    migrating = MapSet.new(work, & &1.table)

    result =
      Postgrex.transaction(conn, fn tx ->
        Schema.run_tx!(tx, "SET LOCAL lock_timeout = '#{lock_timeout()}'", [])
        Schema.run_tx!(tx, "SELECT pg_advisory_xact_lock(hashtext($1))", [schema])

        Enum.each(work, &migrate_table!(tx, schema, qs, &1))

        # What else the plan wanted, for the tables that needed no migration.
        plan.ops
        |> Enum.reject(&MapSet.member?(migrating, &1.table))
        |> Enum.each(&run_sql!(tx, &1))

        Enum.each(plan.table_hashes, fn {table, hash, ops} ->
          if not MapSet.member?(migrating, table) and is_binary(hash) and hash != "" do
            Schema.record_ledger(tx, qs, table, hash, ledger_plan(ops), plan.version)
          end
        end)

        %{applied: length(plan.ops), ops: plan.ops, migrated: Enum.map(work, & &1.table)}
      end)

    case result do
      {:ok, summary} -> {:ok, summary}
      {:error, reason} -> {:error, translate(reason)}
    end
  end

  defp migrate_table!(tx, schema, qs, %{table: table, raw: raw, steps: steps, version: version} = item) do
    qt = Schema.quote_ident!(table)
    {:ok, [resource]} = Schema.normalized_resources([raw])

    # The stamp the gate below counts on; a table made before rows were stamped gains it here.
    Schema.run_tx!(tx, ~s|ALTER TABLE #{qs}.#{qt} ADD COLUMN IF NOT EXISTS "_v" bigint NOT NULL DEFAULT 0|, [])

    for step <- steps do
      gate_drops!(tx, qs, qt, item, step)

      for op <- List.wrap(g(step, :ops)) do
        case render(op, qs, qt, resource) do
          {:ok, statements} -> Enum.each(statements, &Schema.run_tx!(tx, &1, []))
          {:error, reason} -> Postgrex.rollback(tx, {:invalid_migration, %{table: table, resource: item.resource, reason: reason}})
        end
      end
    end

    # The verify gate: the table must now be what the manifest says, bar what is safe to finish by itself.
    {:ok, live} = Schema.read_live_state(tx, schema, [raw])
    {:ok, remaining} = Schema.plan([raw], live, version)

    case Enum.filter(remaining.ops, &(&1.safety == :unsafe)) do
      [] ->
        Enum.each(remaining.ops, &run_sql!(tx, &1))
        steps_json = steps |> Enum.map(&%{"to" => g(&1, :to)}) |> Jason.encode!()
        Schema.record_ledger(tx, qs, table, resource.schema_hash, steps_json, version)

      left ->
        Postgrex.rollback(
          tx,
          {:migration_incomplete,
           %{table: table, resource: item.resource, remaining: Enum.map(left, &%{column: &1[:column], change: &1.op, reason: &1.reason})}}
        )
    end
  end

  # A drop destroys what is in the column. A row still stamped below the migration's version has not been brought
  # up to date, so the column may be the only copy of its data: refuse until none is left.
  defp gate_drops!(tx, qs, qt, item, step) do
    if Enum.any?(List.wrap(g(step, :ops)), &(g(&1, :op) == "drop")) do
      to = Exoforge.VersionStamp.encode(g(step, :to))
      %{rows: [[below]]} = Schema.run_tx!(tx, ~s|SELECT count(*) FROM #{qs}.#{qt} WHERE "_v" < $1|, [to])

      if below > 0 do
        Postgrex.rollback(
          tx,
          {:rows_below_version, %{table: item.table, resource: item.resource, rows: below, to: g(step, :to), decl: g(step, :decl)}}
        )
      end
    end
  end

  defp run_sql!(tx, op) do
    op.sql
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.each(&Schema.run_tx!(tx, &1, []))
  end

  defp ledger_plan(ops) do
    ops
    |> Enum.map(&%{"op" => to_string(&1.op), "safety" => to_string(&1.safety), "table" => &1.table, "column" => &1.column, "reason" => &1.reason})
    |> Jason.encode!()
  end

  # A blocked ALTER is the one failure a deployer can fix by trying again at a quieter time.
  defp translate(%Postgrex.Error{postgres: %{code: :lock_not_available} = pg}) do
    {:lock_timeout, %{message: pg[:message], timeout: lock_timeout()}}
  end

  defp translate(other), do: other

  @doc false
  def lock_timeout do
    value = Application.get_env(:exoforge_std_lldb, :schema_lock_timeout, @default_lock_timeout)
    if is_binary(value) and Regex.match?(~r/^\d+(ms|s|min)$/, value), do: value, else: @default_lock_timeout
  end

  ## ---- one operation as SQL ----

  defp render(op, qs, qt, resource) do
    table = "#{qs}.#{qt}"

    case g(op, :op) do
      "rename" ->
        with {:ok, from} <- ident(g(op, :from)), {:ok, to} <- ident(g(op, :to)) do
          {:ok, ["ALTER TABLE #{table} RENAME COLUMN #{from} TO #{to}"]}
        end

      "convert" ->
        with {:ok, column} <- ident(g(op, :column)),
             {:ok, native} <- Schema.validate_storage_type(g(op, :to)) do
          {:ok,
           [
             "ALTER TABLE #{table} ALTER COLUMN #{column} DROP DEFAULT",
             "ALTER TABLE #{table} ALTER COLUMN #{column} TYPE #{native} USING #{column}::#{native}"
           ]}
        end

      "fill" ->
        with {:ok, column} <- ident(g(op, :column)),
             {:ok, col} <- manifest_column(resource, g(op, :column)),
             {:ok, literal} when not is_nil(literal) <- default_literal(col, g(op, :value)) do
          nullability = if col.nullable, do: "", else: " NOT NULL"
          add = "ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS #{column} #{col.storage}#{nullability} DEFAULT #{literal}"
          # Existing rows are filled; a default the manifest does not declare is not kept.
          drop_default = if is_nil(col.default_sql), do: ["ALTER TABLE #{table} ALTER COLUMN #{column} DROP DEFAULT"], else: []
          {:ok, [add | drop_default]}
        else
          {:ok, nil} -> {:error, "fill needs a value"}
          error -> error
        end

      "drop" ->
        with {:ok, column} <- ident(g(op, :column)) do
          {:ok, ["ALTER TABLE #{table} DROP COLUMN IF EXISTS #{column}"]}
        end

      "set_not_null" ->
        with {:ok, column} <- ident(g(op, :column)),
             {:ok, col} <- manifest_column(resource, g(op, :column)),
             {:ok, literal} <- default_literal(col, g(op, :value)) do
          fill = if literal, do: ["UPDATE #{table} SET #{column} = #{literal} WHERE #{column} IS NULL"], else: []
          {:ok, fill ++ ["ALTER TABLE #{table} ALTER COLUMN #{column} SET NOT NULL"]}
        end

      other ->
        {:error, {:unknown_operation, other}}
    end
  end

  defp ident(name) do
    with {:ok, valid} <- Schema.validate_ident(name || ""), do: {:ok, Schema.quote_ident!(valid)}
  end

  defp manifest_column(resource, name) do
    case Enum.find(resource.columns, &(&1.name == name)) do
      nil -> {:error, {:unknown_column, name}}
      col -> {:ok, col}
    end
  end

  defp default_literal(_col, nil), do: {:ok, nil}
  defp default_literal(col, value), do: Schema.build_default_literal(col.name, col.storage, value)

  # Manifest maps come with atom keys from the loader and string keys from anywhere else.
  defp g(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp g(_, _), do: nil
end
