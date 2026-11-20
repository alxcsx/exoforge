defmodule Exoforge.Std.Lldb.MigrationRunner do
  @moduledoc "Run hand-written extension migrations against the shared migration ledger."

  alias Exoforge.Std.Lldb.{Schema, SchemaMigration}

  @doc "Applies unapplied migrations in version order, one transaction at a time."
  def run(conn, namespace, migrations) do
    with {:ok, schema} <- Schema.validate_ident(namespace),
         :ok <- Schema.ensure_ledgers(conn, schema),
         {:ok, migrations} <- normalize(migrations) do
      migrations
      |> Enum.sort_by(& &1.version)
      |> Enum.reduce_while({:ok, %{applied: [], skipped: []}}, fn migration, {:ok, result} ->
        case run_one(conn, schema, migration) do
          {:ok, :applied} -> {:cont, {:ok, %{result | applied: result.applied ++ [migration.version]}}}
          {:ok, :skipped} -> {:cont, {:ok, %{result | skipped: result.skipped ++ [migration.version]}}}
          {:error, reason} -> {:halt, {:error, {:migration_failed, %{version: migration.version, name: migration.name, reason: reason}}}}
        end
      end)
    end
  end

  defp run_one(conn, schema, migration) do
    qs = Schema.quote_ident!(schema)

    Postgrex.transaction(conn, fn tx ->
      Schema.run_tx!(tx, "SET LOCAL lock_timeout = '#{SchemaMigration.lock_timeout()}'", [])
      Schema.run_tx!(tx, "SELECT pg_advisory_xact_lock(hashtext($1))", [schema])

      case Schema.run_tx!(tx, ~s|SELECT 1 FROM #{qs}."_exo_migrations" WHERE "id" = $1|, [to_string(migration.version)]).rows do
        [] ->
          started = System.monotonic_time(:millisecond)
          Enum.each(migration.sql, &Schema.run_tx!(tx, &1, []))
          duration = System.monotonic_time(:millisecond) - started

          Schema.run_tx!(
            tx,
            ~s|INSERT INTO #{qs}."_exo_migrations" ("id", "name", "duration_ms", "checksum") VALUES ($1, $2, $3, $4)|,
            [to_string(migration.version), migration.name, duration, checksum(migration.sql)]
          )

          :applied

        _ ->
          :skipped
      end
    end)
  end

  defp normalize(migrations) when is_list(migrations) do
    migrations
    |> Enum.reduce_while({:ok, []}, fn migration, {:ok, acc} ->
      with version when is_integer(version) and version > 0 <- get(migration, :version),
           name when is_binary(name) and name != "" <- get(migration, :name),
           sql when is_list(sql) and sql != [] <- get(migration, :sql) |> List.wrap(),
           true <- Enum.all?(sql, &(is_binary(&1) and &1 != "")) do
        {:cont, {:ok, [%{version: version, name: name, sql: sql} | acc]}}
      else
        _ -> {:halt, {:error, {:invalid_migration, migration}}}
      end
    end)
    |> then(fn
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end)
  end

  defp normalize(_), do: {:error, {:invalid_migration, :migrations}}

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp get(_, _), do: nil

  defp checksum(sql), do: :crypto.hash(:sha256, Enum.join(sql, "\n")) |> Base.encode16(case: :lower)
end
