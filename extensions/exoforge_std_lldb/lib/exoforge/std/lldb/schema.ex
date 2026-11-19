defmodule Exoforge.Std.Lldb.Schema do
  import Kernel, except: [apply: 2]

  @moduledoc """
  Declarative PostgreSQL schema reconciler for declared `[ExoResource]` tables.

  Provides pure planning (`plan/2`) against live schema state (`read_live_state/3`),
  atomic application (`apply/2`) guarded by `pg_advisory_xact_lock(hashtext(schema))`,
  and automatic per-schema ledger management (`_exo_schema`, `_exo_migrations`, `_exo_rejects`).
  """

  @ident_regex ~r/^[a-z_][a-z0-9_]*$/
  @uuid_regex ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
  @int_regex ~r/^-?[0-9]+$/
  @num_regex ~r/^-?[0-9]+(\.[0-9]+)?$/

  @allowed_storage_types [
    "text",
    "integer",
    "bigint",
    "smallint",
    "boolean",
    "double precision",
    "real",
    "numeric",
    "uuid",
    "timestamptz",
    "bytea",
    "jsonb"
  ]

  @safe_widenings MapSet.new([
                    {"smallint", "integer"},
                    {"smallint", "bigint"},
                    {"smallint", "numeric"},
                    {"integer", "bigint"},
                    {"integer", "numeric"},
                    {"bigint", "numeric"},
                    {"real", "double precision"}
                  ])

  @doc """
  Validates a SQL identifier against `^[a-z_][a-z0-9_]*$` and `<= 63` bytes.
  """
  def validate_ident(name) when is_binary(name) or is_atom(name) do
    str = to_string(name)

    if byte_size(str) in 1..63 and Regex.match?(@ident_regex, str) do
      {:ok, str}
    else
      {:error, {:invalid_identifier, str}}
    end
  end

  def validate_ident(other), do: {:error, {:invalid_identifier, inspect(other)}}

  @doc """
  Returns a double-quoted validated SQL identifier, or raises `ArgumentError`.
  """
  def quote_ident!(name) do
    case validate_ident(name) do
      {:ok, str} -> ~s("#{str}")
      {:error, _} -> raise ArgumentError, "invalid SQL identifier: #{inspect(name)}"
    end
  end

  @doc """
  Validates a storage type against the allowlist.
  """
  def validate_storage_type(type) when is_binary(type) or is_atom(type) do
    str = type |> to_string() |> String.downcase() |> String.trim()

    # The manifest speaks logical types (`int32`, `decimal`, `timestamp`, ...); this engine's names for
    # them come from its dialect. Native names are still accepted.
    native = Map.get(Exoforge.Std.Lldb.Adapters.Postgres.dialect(%{}).types, str, str)

    if native in @allowed_storage_types do
      {:ok, native}
    else
      {:error, {:invalid_storage_type, str}}
    end
  end

  def validate_storage_type(other), do: {:error, {:invalid_storage_type, inspect(other)}}

  @doc """
  Builds a validated SQL default literal for an allowlisted storage type.
  """
  def build_default_literal(_col_name, _storage, nil), do: {:ok, nil}

  def build_default_literal(col_name, storage, value) do
    with {:ok, type} <- validate_storage_type(storage) do
      do_build_default_literal(to_string(col_name), type, value)
    end
  end

  defp do_build_default_literal(_col, "text", val)
       when is_binary(val) or is_atom(val) or is_number(val) do
    escaped = val |> to_string() |> String.replace("'", "''")
    {:ok, "'#{escaped}'"}
  end

  defp do_build_default_literal(col, type, val) when type in ["smallint", "integer", "bigint"] do
    str =
      cond do
        is_integer(val) -> Integer.to_string(val)
        is_binary(val) -> String.trim(val)
        true -> ""
      end

    with true <- Regex.match?(@int_regex, str),
         {n, ""} <- Integer.parse(str),
         true <- int_in_range?(type, n) do
      {:ok, Integer.to_string(n)}
    else
      _ -> {:error, {:invalid_default, col, type, val}}
    end
  end

  defp do_build_default_literal(col, type, val)
       when type in ["real", "double precision", "numeric"] do
    str =
      cond do
        is_integer(val) -> Integer.to_string(val)
        is_float(val) -> :erlang.float_to_binary(val, [:compact, decimals: 15])
        is_binary(val) -> String.trim(val)
        true -> ""
      end

    if Regex.match?(@num_regex, str) do
      {:ok, str}
    else
      {:error, {:invalid_default, col, type, val}}
    end
  end

  defp do_build_default_literal(col, "boolean", val) do
    cond do
      val in [true, "true", "TRUE"] -> {:ok, "true"}
      val in [false, "false", "FALSE"] -> {:ok, "false"}
      true -> {:error, {:invalid_default, col, "boolean", val}}
    end
  end

  defp do_build_default_literal(col, "uuid", val) when is_binary(val) do
    trimmed = String.trim(val)

    if Regex.match?(@uuid_regex, trimmed) do
      {:ok, "'#{String.downcase(trimmed)}'::uuid"}
    else
      {:error, {:invalid_default, col, "uuid", val}}
    end
  end

  defp do_build_default_literal(col, "timestamptz", val) when is_binary(val) do
    trimmed = String.trim(val)

    case DateTime.from_iso8601(trimmed) do
      {:ok, dt, _offset} ->
        iso = DateTime.to_iso8601(dt)
        {:ok, "'#{String.replace(iso, "'", "''")}'::timestamptz"}

      {:error, _} ->
        {:error, {:invalid_default, col, "timestamptz", val}}
    end
  end

  defp do_build_default_literal(col, "jsonb", val) do
    cond do
      is_binary(val) ->
        case Jason.decode(val) do
          {:ok, decoded} ->
            json = Jason.encode!(decoded)
            {:ok, "'#{String.replace(json, "'", "''")}'::jsonb"}

          {:error, _} ->
            {:error, {:invalid_default, col, "jsonb", val}}
        end

      is_map(val) or is_list(val) ->
        json = Jason.encode!(val)
        {:ok, "'#{String.replace(json, "'", "''")}'::jsonb"}

      true ->
        {:error, {:invalid_default, col, "jsonb", val}}
    end
  end

  defp do_build_default_literal(col, "bytea", val) when is_binary(val) do
    if Regex.match?(~r/^(\\x)?[0-9a-fA-F]*$/, val) do
      hex = String.replace_prefix(val, "\\x", "")

      if rem(byte_size(hex), 2) == 0 do
        {:ok, "'\\x#{String.downcase(hex)}'::bytea"}
      else
        {:error, {:invalid_default, col, "bytea", val}}
      end
    else
      {:error, {:invalid_default, col, "bytea", val}}
    end
  end

  defp do_build_default_literal(col, type, val),
    do: {:error, {:invalid_default, col, type, val}}

  defp int_in_range?("smallint", n), do: n >= -32_768 and n <= 32_767
  defp int_in_range?("integer", n), do: n >= -2_147_483_648 and n <= 2_147_483_647

  defp int_in_range?("bigint", n),
    do: n >= -9_223_372_036_854_775_808 and n <= 9_223_372_036_854_775_807

  @doc """
  Idempotently creates the three schema/migration ledger tables in `schema`:
  `_exo_schema`, `_exo_migrations`, and `_exo_rejects`.
  """
  def ensure_ledgers(conn, schema) do
    with {:ok, s} <- validate_ident(schema) do
      qs = quote_ident!(s)

      sqls = [
        """
        CREATE TABLE IF NOT EXISTS #{qs}."_exo_schema" (
          "table_name" text NOT NULL,
          "schema_hash" text NOT NULL,
          "applied_at" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "plan" jsonb NOT NULL DEFAULT '[]'::jsonb
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS #{qs}."_exo_migrations" (
          "id" text PRIMARY KEY,
          "name" text NOT NULL,
          "applied_at" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "duration_ms" integer NOT NULL DEFAULT 0,
          "rows" bigint NOT NULL DEFAULT 0,
          "checksum" text NOT NULL DEFAULT '',
          "status" text NOT NULL DEFAULT 'applied',
          "cursor" jsonb
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS #{qs}."_exo_rejects" (
          "id" bigserial PRIMARY KEY,
          "table_name" text NOT NULL,
          "row_id" text,
          "column_name" text,
          "original" jsonb,
          "target_type" text,
          "reason" text,
          "migration_id" text,
          "rejected_at" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
      ]

      Enum.reduce_while(sqls, :ok, fn sql, :ok ->
        case Postgrex.query(conn, sql, []) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @doc """
  Reads live state from `information_schema` and `pg_catalog` for `schema` and the given `resources`.
  """
  def read_live_state(conn, schema, resources \\ []) do
    with {:ok, s} <- validate_ident(schema),
         {:ok, normalized_resources} <- normalize_resources(resources) do
      ledger_hashes = read_ledger_hashes(conn, s)
      existing_tables = read_existing_tables(conn, s)

      tables =
        Enum.reduce(normalized_resources, %{}, fn res, acc ->
          tbl = res.table

          if MapSet.member?(existing_tables, tbl) do
            info = read_table_live_state(conn, s, tbl, res)
            Map.put(acc, tbl, info)
          else
            acc
          end
        end)

      {:ok,
       %{
         schema: s,
         ledger_hashes: ledger_hashes,
         tables: tables
       }}
    end
  end

  defp read_ledger_hashes(conn, schema) do
    check_sql = """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = $1 AND table_name = '_exo_schema'
    )
    """

    case Postgrex.query(conn, check_sql, [schema]) do
      {:ok, %Postgrex.Result{rows: [[true]]}} ->
        qs = quote_ident!(schema)

        sql = """
        SELECT DISTINCT ON ("table_name") "table_name", "schema_hash"
        FROM #{qs}."_exo_schema"
        ORDER BY "table_name", "applied_at" DESC
        """

        case Postgrex.query(conn, sql, []) do
          {:ok, %Postgrex.Result{rows: rows}} ->
            Map.new(rows, fn [t, h] -> {t, h} end)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp read_existing_tables(conn, schema) do
    sql = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = $1 AND table_type = 'BASE TABLE'
    """

    case Postgrex.query(conn, sql, [schema]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        rows
        |> Enum.map(fn [t] -> t end)
        |> Enum.reject(&String.starts_with?(&1, "_exo_"))
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp read_table_live_state(conn, schema, table, res) do
    qs = quote_ident!(schema)
    qt = quote_ident!(table)

    cols_sql = """
    SELECT column_name, data_type, udt_name, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = $1 AND table_name = $2
    ORDER BY ordinal_position
    """

    {:ok, %Postgrex.Result{rows: col_rows}} = Postgrex.query(conn, cols_sql, [schema, table])

    columns =
      Map.new(col_rows, fn [c_name, data_type, udt_name, is_nullable, col_default] ->
        {c_name,
         %{
           name: c_name,
           storage: canonical_pg_type(data_type, udt_name),
           raw_data_type: data_type,
           nullable: is_nullable == "YES",
           default: col_default
         }}
      end)

    column_order = Enum.map(col_rows, fn [c_name | _] -> c_name end)

    pk_sql = """
    SELECT a.attname
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(i.indkey)
    WHERE n.nspname = $1 AND c.relname = $2 AND i.indisprimary
    ORDER BY array_position(i.indkey, a.attnum)
    """

    primary_key =
      case Postgrex.query(conn, pk_sql, [schema, table]) do
        {:ok, %Postgrex.Result{rows: rows}} -> Enum.map(rows, fn [col] -> col end)
        _ -> []
      end

    idx_sql = """
    SELECT ic.relname AS index_name, i.indisunique, a.attname AS column_name
    FROM pg_index i
    JOIN pg_class tc ON tc.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = tc.relnamespace
    JOIN pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = ANY(i.indkey)
    WHERE n.nspname = $1 AND tc.relname = $2 AND NOT i.indisprimary
      AND array_length(i.indkey, 1) = 1 AND i.indpred IS NULL AND i.indexprs IS NULL
    """

    indexes =
      case Postgrex.query(conn, idx_sql, [schema, table]) do
        {:ok, %Postgrex.Result{rows: rows}} ->
          Enum.map(rows, fn [idx_name, is_unique, col_name] ->
            %{name: idx_name, unique: is_unique == true, column: col_name}
          end)

        _ ->
          []
      end

    chk_sql = """
    SELECT con.conname, pg_get_constraintdef(con.oid)
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = $1 AND rel.relname = $2 AND con.contype = 'c'
    """

    checks =
      case Postgrex.query(conn, chk_sql, [schema, table]) do
        {:ok, %Postgrex.Result{rows: rows}} ->
          Map.new(rows, fn [conname, condef] ->
            {conname, %{definition: condef, choices: parse_check_choices(condef)}}
          end)

        _ ->
          %{}
      end

    row_count =
      case Postgrex.query(conn, "SELECT COUNT(*)::bigint FROM #{qs}.#{qt}", []) do
        {:ok, %Postgrex.Result{rows: [[cnt]]}} when is_integer(cnt) -> cnt
        _ -> 0
      end

    # Check NULLs and duplicates on live columns relevant to the manifest
    {null_columns, duplicate_columns} =
      inspect_column_data(conn, qs, qt, columns, res.columns, row_count)

    %{
      exists: true,
      columns: columns,
      column_order: column_order,
      primary_key: primary_key,
      indexes: indexes,
      checks: checks,
      row_count: row_count,
      empty: row_count == 0,
      null_columns: null_columns,
      duplicate_columns: duplicate_columns
    }
  end

  defp inspect_column_data(_conn, _qs, _qt, _live_cols, _manifest_cols, 0),
    do: {MapSet.new(), MapSet.new()}

  defp inspect_column_data(conn, qs, qt, live_cols, manifest_cols, _row_count) do
    Enum.reduce(manifest_cols, {MapSet.new(), MapSet.new()}, fn mcol, {nulls, dups} ->
      cname = mcol.name

      case Map.get(live_cols, cname) do
        nil ->
          {nulls, dups}

        live_col ->
          qc = quote_ident!(cname)

          nulls =
            if live_col.nullable and not mcol.nullable do
              sql = "SELECT EXISTS (SELECT 1 FROM #{qs}.#{qt} WHERE #{qc} IS NULL)"

              case Postgrex.query(conn, sql, []) do
                {:ok, %Postgrex.Result{rows: [[true]]}} -> MapSet.put(nulls, cname)
                _ -> nulls
              end
            else
              nulls
            end

          dups =
            if mcol.unique do
              sql = """
              SELECT EXISTS (
                SELECT 1 FROM #{qs}.#{qt}
                WHERE #{qc} IS NOT NULL
                GROUP BY #{qc}
                HAVING COUNT(*) > 1
              )
              """

              case Postgrex.query(conn, sql, []) do
                {:ok, %Postgrex.Result{rows: [[true]]}} -> MapSet.put(dups, cname)
                _ -> dups
              end
            else
              dups
            end

          {nulls, dups}
      end
    end)
  end

  defp canonical_pg_type(data_type, udt_name) do
    case String.downcase(to_string(data_type)) do
      "character varying" -> "text"
      "text" -> "text"
      "integer" -> "integer"
      "bigint" -> "bigint"
      "smallint" -> "smallint"
      "boolean" -> "boolean"
      "double precision" -> "double precision"
      "real" -> "real"
      "numeric" -> "numeric"
      "decimal" -> "numeric"
      "uuid" -> "uuid"
      "timestamp with time zone" -> "timestamptz"
      "timestamp without time zone" -> "timestamp"
      "bytea" -> "bytea"
      "jsonb" -> "jsonb"
      "json" -> "json"
      _ -> String.downcase(to_string(udt_name))
    end
  end

  defp parse_check_choices(condef) when is_binary(condef) do
    # Matches single-quoted string literals inside CHECK definition
    Regex.scan(~r/'((?:[^']|'')*)'/, condef)
    |> Enum.map(fn [_, inner] -> String.replace(inner, "''", "'") end)
    |> Enum.uniq()
  end

  defp parse_check_choices(_), do: []

  @doc """
  Pure schema planning function: diffs `resources` against `live_state` and returns
  `{:ok, %{schema: schema, ops: ops, safe: boolean, skipped_tables: [...], table_hashes: [...]}}`
  or `{:error, reason}` if validation fails.
  """
  def plan(resources, live_state) when is_list(resources) and is_map(live_state) do
    schema = Map.get(live_state, :schema) || Map.get(live_state, "schema") || "public"

    with {:ok, valid_schema} <- validate_ident(schema),
         {:ok, normalized_resources} <- normalize_resources(resources) do
      ledger_hashes = Map.get(live_state, :ledger_hashes) || %{}
      live_tables = Map.get(live_state, :tables) || %{}

      {ops, skipped, table_hashes} =
        Enum.reduce(normalized_resources, {[], [], []}, fn res, {ops_acc, skip_acc, hash_acc} ->
          tbl = res.table
          live_tbl = Map.get(live_tables, tbl)
          recorded_hash = Map.get(ledger_hashes, tbl)

          cond do
            not is_nil(live_tbl) and live_tbl[:exists] == true and
              is_binary(res.schema_hash) and res.schema_hash != "" and
                recorded_hash == res.schema_hash ->
              {ops_acc, [tbl | skip_acc], hash_acc}

            is_nil(live_tbl) or live_tbl[:exists] != true ->
              create_ops = plan_create_table(valid_schema, res)
              {ops_acc ++ create_ops, skip_acc, [{tbl, res.schema_hash, create_ops} | hash_acc]}

            envelope_table?(live_tbl, res) ->
              op = %{
                op: :convert_envelope,
                safety: :unsafe,
                table: tbl,
                column: nil,
                sql: nil,
                reason:
                  "Table '#{tbl}' uses the legacy (id, data jsonb, updated_at) envelope and requires envelope conversion before typed schema reconciliation"
              }

              {ops_acc ++ [op], skip_acc, [{tbl, res.schema_hash, [op]} | hash_acc]}

            true ->
              table_ops = plan_diff_table(valid_schema, res, live_tbl)
              {ops_acc ++ table_ops, skip_acc, [{tbl, res.schema_hash, table_ops} | hash_acc]}
          end
        end)

      all_safe? = Enum.all?(ops, &(&1.safety == :safe))

      {:ok,
       %{
         schema: valid_schema,
         ops: ops,
         safe: all_safe?,
         skipped_tables: Enum.reverse(skipped),
         table_hashes: Enum.reverse(table_hashes)
       }}
    end
  end

  defp envelope_table?(live_tbl, res) do
    cols = live_tbl.columns || %{}
    col_names = cols |> Map.keys() |> Enum.sort()
    pks = live_tbl.primary_key || []
    declared_names = MapSet.new(res.columns, & &1.name)

    col_names == ["data", "id", "updated_at"] and
      pks == ["id"] and
      get_in(cols, ["id", :storage]) == "text" and
      get_in(cols, ["data", :storage]) == "jsonb" and
      not (MapSet.member?(declared_names, "data") and MapSet.member?(declared_names, "updated_at") and
             MapSet.size(declared_names) == 3)
  end

  defp plan_create_table(schema, res) do
    qs = quote_ident!(schema)
    qt = quote_ident!(res.table)

    col_defs =
      Enum.map(res.columns, fn col ->
        qc = quote_ident!(col.name)
        null_sql = if col.nullable, do: "", else: " NOT NULL"
        pk_sql = if col.primary_key, do: " PRIMARY KEY", else: ""
        def_sql = if col.default_sql, do: " DEFAULT #{col.default_sql}", else: ""
        chk_sql = enum_check_inline_sql(res.table, col)
        "#{qc} #{col.storage}#{pk_sql}#{null_sql}#{def_sql}#{chk_sql}"
      end)

    create_sql = "CREATE TABLE IF NOT EXISTS #{qs}.#{qt} (#{Enum.join(col_defs, ", ")})"

    create_op = %{
      op: :create_table,
      safety: :safe,
      table: res.table,
      column: nil,
      sql: create_sql,
      reason: "Create table '#{res.table}'"
    }

    index_ops =
      res.columns
      |> Enum.reject(& &1.primary_key)
      |> Enum.flat_map(&plan_column_indexes(schema, res.table, &1, MapSet.new(), []))

    [create_op | index_ops]
  end

  defp plan_diff_table(schema, res, live_tbl) do
    qs = quote_ident!(schema)
    qt = quote_ident!(res.table)
    live_cols = live_tbl.columns || %{}
    manifest_cols_by_name = Map.new(res.columns, &{&1.name, &1})

    # 1. Primary key check
    manifest_pks =
      res.columns
      |> Enum.filter(& &1.primary_key)
      |> Enum.map(& &1.name)

    live_pks = live_tbl.primary_key || []

    pk_ops =
      if manifest_pks != live_pks do
        [
          %{
            op: :change_primary_key,
            safety: :unsafe,
            table: res.table,
            column: List.first(manifest_pks) || List.first(live_pks),
            sql: nil,
            reason:
              "Primary key change on table '#{res.table}' from #{inspect(live_pks)} to #{inspect(manifest_pks)} is unsafe"
          }
        ]
      else
        []
      end

    # 2. Check existing / new columns in manifest order
    col_ops =
      Enum.flat_map(res.columns, fn mcol ->
        case Map.get(live_cols, mcol.name) do
          nil ->
            plan_add_column(qs, qt, res.table, mcol, live_tbl)

          lcol ->
            plan_existing_column(qs, qt, res.table, mcol, lcol, live_tbl)
        end
      end)

    # 3. Check dropped columns (live columns absent from manifest)
    drop_ops =
      live_cols
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reject(&Map.has_key?(manifest_cols_by_name, &1))
      |> Enum.map(fn dropped_col ->
        %{
          op: :drop_column,
          safety: :unsafe,
          table: res.table,
          column: dropped_col,
          sql: nil,
          reason:
            "Column '#{dropped_col}' on table '#{res.table}' is absent from the manifest; dropping columns requires an explicit migration"
        }
      end)

    # 4. Indexes & unique indexes
    index_ops =
      res.columns
      |> Enum.reject(& &1.primary_key)
      |> Enum.flat_map(fn mcol ->
        plan_column_indexes(
          schema,
          res.table,
          mcol,
          live_tbl.duplicate_columns || MapSet.new(),
          live_tbl.indexes || []
        )
      end)

    pk_ops ++ col_ops ++ drop_ops ++ index_ops
  end

  defp plan_add_column(qs, qt, table, mcol, live_tbl) do
    qc = quote_ident!(mcol.name)
    empty? = Map.get(live_tbl, :empty, Map.get(live_tbl, :row_count, 0) == 0)

    cond do
      mcol.nullable or not is_nil(mcol.default_sql) or empty? ->
        null_sql = if mcol.nullable, do: "", else: " NOT NULL"
        def_sql = if mcol.default_sql, do: " DEFAULT #{mcol.default_sql}", else: ""
        chk_sql = enum_check_inline_sql(table, mcol)

        sql =
          "ALTER TABLE #{qs}.#{qt} ADD COLUMN IF NOT EXISTS #{qc} #{mcol.storage}#{null_sql}#{def_sql}#{chk_sql}"

        [
          %{
            op: :add_column,
            safety: :safe,
            table: table,
            column: mcol.name,
            sql: sql,
            reason: "Add column '#{mcol.name}' (#{mcol.storage}) to table '#{table}'"
          }
        ]

      true ->
        [
          %{
            op: :add_column,
            safety: :unsafe,
            table: table,
            column: mcol.name,
            sql: nil,
            reason:
              "Cannot add NOT NULL column '#{mcol.name}' without a default to non-empty table '#{table}'"
          }
        ]
    end
  end

  defp plan_existing_column(qs, qt, table, mcol, lcol, live_tbl) do
    qc = quote_ident!(mcol.name)

    type_ops =
      cond do
        lcol.storage == mcol.storage ->
          []

        MapSet.member?(@safe_widenings, {lcol.storage, mcol.storage}) ->
          sql = "ALTER TABLE #{qs}.#{qt} ALTER COLUMN #{qc} TYPE #{mcol.storage}"

          [
            %{
              op: :widen_type,
              safety: :safe,
              table: table,
              column: mcol.name,
              from_type: lcol.storage,
              to_type: mcol.storage,
              sql: sql,
              reason:
                "Widen column '#{mcol.name}' on table '#{table}' from #{lcol.storage} to #{mcol.storage}"
            }
          ]

        true ->
          [
            %{
              op: :alter_type,
              safety: :unsafe,
              table: table,
              column: mcol.name,
              from_type: lcol.storage,
              to_type: mcol.storage,
              sql: nil,
              reason:
                "Incompatible or narrowing type change on '#{table}.#{mcol.name}' from #{lcol.storage} to #{mcol.storage}"
            }
          ]
      end

    null_ops =
      cond do
        lcol.nullable == mcol.nullable ->
          []

        lcol.nullable and not mcol.nullable ->
          has_nulls? = MapSet.member?(live_tbl.null_columns || MapSet.new(), mcol.name)
          has_default? = not is_nil(mcol.default_sql) or not is_nil(lcol.default)

          if not has_nulls? and has_default? do
            set_default =
              if not is_nil(mcol.default_sql) do
                ["ALTER TABLE #{qs}.#{qt} ALTER COLUMN #{qc} SET DEFAULT #{mcol.default_sql}"]
              else
                []
              end

            sql = set_default ++ ["ALTER TABLE #{qs}.#{qt} ALTER COLUMN #{qc} SET NOT NULL"]

            [
              %{
                op: :set_not_null,
                safety: :safe,
                table: table,
                column: mcol.name,
                sql: sql,
                reason:
                  "Set NOT NULL on '#{table}.#{mcol.name}' (column has a default and no NULL rows)"
              }
            ]
          else
            why =
              cond do
                has_nulls? -> "existing rows contain NULL values"
                not has_default? -> "no default is declared"
                true -> "unsafe constraint change"
              end

            [
              %{
                op: :set_not_null,
                safety: :unsafe,
                table: table,
                column: mcol.name,
                sql: nil,
                reason: "Cannot set NOT NULL on '#{table}.#{mcol.name}': #{why}"
              }
            ]
          end

        not lcol.nullable and mcol.nullable ->
          sql = "ALTER TABLE #{qs}.#{qt} ALTER COLUMN #{qc} DROP NOT NULL"

          [
            %{
              op: :drop_not_null,
              safety: :safe,
              table: table,
              column: mcol.name,
              sql: sql,
              reason: "Drop NOT NULL on '#{table}.#{mcol.name}'"
            }
          ]
      end

    enum_ops = plan_enum_check(qs, qt, table, mcol, live_tbl.checks || %{})

    type_ops ++ null_ops ++ enum_ops
  end

  defp plan_enum_check(qs, qt, table, mcol, live_checks) do
    con_name = check_constraint_name(table, mcol.name)
    live_chk = Map.get(live_checks, con_name)

    case {live_chk, mcol.choices} do
      {nil, nil} ->
        []

      {nil, choices} when is_list(choices) and choices != [] ->
        # Adding a new CHECK constraint to an existing column that had no CHECK
        [
          %{
            op: :alter_enum_check,
            safety: :unsafe,
            table: table,
            column: mcol.name,
            sql: nil,
            reason:
              "Adding enum CHECK constraint '#{con_name}' on existing column '#{table}.#{mcol.name}' is unsafe"
          }
        ]

      {%{choices: live_choices}, choices} when is_list(choices) and choices != [] ->
        live_set = MapSet.new(live_choices)
        new_set = MapSet.new(choices)

        cond do
          MapSet.equal?(live_set, new_set) ->
            []

          MapSet.subset?(live_set, new_set) ->
            qcon = quote_ident!(con_name)
            qc = quote_ident!(mcol.name)
            in_list = Enum.map_join(choices, ", ", &"'#{String.replace(&1, "'", "''")}'")

            sql =
              "ALTER TABLE #{qs}.#{qt} DROP CONSTRAINT IF EXISTS #{qcon}, ADD CONSTRAINT #{qcon} CHECK (#{qc} IN (#{in_list}))"

            [
              %{
                op: :alter_enum_check,
                safety: :safe,
                table: table,
                column: mcol.name,
                sql: sql,
                reason:
                  "Widen enum CHECK constraint '#{con_name}' on '#{table}.#{mcol.name}'"
              }
            ]

          true ->
            removed = MapSet.difference(live_set, new_set) |> MapSet.to_list() |> Enum.sort()

            [
              %{
                op: :alter_enum_check,
                safety: :unsafe,
                table: table,
                column: mcol.name,
                sql: nil,
                reason:
                  "Narrowing enum CHECK constraint '#{con_name}' on '#{table}.#{mcol.name}' (removes #{inspect(removed)}) is unsafe"
              }
            ]
        end

      {_live_chk, nil} ->
        []
    end
  end

  defp plan_column_indexes(schema, table, mcol, duplicate_cols, live_indexes) do
    qs = quote_ident!(schema)
    qt = quote_ident!(table)
    qc = quote_ident!(mcol.name)

    has_unique_idx? =
      Enum.any?(live_indexes, fn idx -> idx.column == mcol.name and idx.unique == true end)

    has_any_idx? =
      Enum.any?(live_indexes, fn idx -> idx.column == mcol.name end)

    cond do
      mcol.unique and not has_unique_idx? ->
        idx_name = cap_identifier("#{table}_#{mcol.name}_key")
        qidx = quote_ident!(idx_name)

        if MapSet.member?(duplicate_cols, mcol.name) do
          [
            %{
              op: :create_unique_index,
              safety: :unsafe,
              table: table,
              column: mcol.name,
              sql: nil,
              reason:
                "Cannot create UNIQUE index on '#{table}.#{mcol.name}': duplicate values exist in table '#{table}'"
            }
          ]
        else
          [
            %{
              op: :create_unique_index,
              safety: :safe,
              table: table,
              column: mcol.name,
              sql: "CREATE UNIQUE INDEX IF NOT EXISTS #{qidx} ON #{qs}.#{qt} (#{qc})",
              reason: "Create unique index '#{idx_name}' on '#{table}.#{mcol.name}'"
            }
          ]
        end

      mcol.indexed and not mcol.unique and not has_any_idx? ->
        idx_name = cap_identifier("#{table}_#{mcol.name}_idx")
        qidx = quote_ident!(idx_name)

        [
          %{
            op: :create_index,
            safety: :safe,
            table: table,
            column: mcol.name,
            sql: "CREATE INDEX IF NOT EXISTS #{qidx} ON #{qs}.#{qt} (#{qc})",
            reason: "Create index '#{idx_name}' on '#{table}.#{mcol.name}'"
          }
        ]

      true ->
        []
    end
  end

  defp enum_check_inline_sql(table, col) do
    case col.choices do
      choices when is_list(choices) and choices != [] ->
        con_name = check_constraint_name(table, col.name)
        qcon = quote_ident!(con_name)
        qc = quote_ident!(col.name)
        in_list = Enum.map_join(choices, ", ", &"'#{String.replace(&1, "'", "''")}'")
        " CONSTRAINT #{qcon} CHECK (#{qc} IN (#{in_list}))"

      _ ->
        ""
    end
  end

  defp check_constraint_name(table, col_name) do
    cap_identifier("#{table}_#{col_name}_check")
  end

  defp cap_identifier(ident) when byte_size(ident) <= 63, do: ident

  defp cap_identifier(ident) do
    hash = :crypto.hash(:sha256, ident) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    binary_part(ident, 0, 54) <> "_" <> hash
  end

  @doc """
  Applies a schema plan inside a single PostgreSQL transaction protected by
  `pg_advisory_xact_lock(hashtext(schema))`.

  If any op in `plan.ops` is `:unsafe`, returns `{:error, {:unsafe_schema_change, unsafe_ops}}`
  and applies nothing.
  """
  def apply(conn, %{schema: schema, ops: ops} = plan) do
    unsafe_ops = Enum.filter(ops, &(&1.safety == :unsafe))

    if unsafe_ops != [] do
      formatted =
        Enum.map(unsafe_ops, fn op ->
          Map.put_new(op, :message, format_op_message(op))
        end)

      {:error, {:unsafe_schema_change, formatted}}
    else
      with {:ok, valid_schema} <- validate_ident(schema) do
        qs = quote_ident!(valid_schema)
        table_hashes = Map.get(plan, :table_hashes, [])

        if ops == [] and table_hashes == [] do
          {:ok, %{applied: 0, ops: []}}
        else
          case Postgrex.transaction(conn, fn tx ->
                 run_tx!(tx, "SELECT pg_advisory_xact_lock(hashtext($1))", [valid_schema])

                 case ensure_ledgers(tx, valid_schema) do
                   :ok -> :ok
                   {:error, reason} -> Postgrex.rollback(tx, reason)
                 end

                 Enum.each(ops, fn op ->
                   op.sql
                   |> List.wrap()
                   |> Enum.reject(&(&1 in [nil, ""]))
                   |> Enum.each(fn stmt -> run_tx!(tx, stmt, []) end)
                 end)

                 Enum.each(table_hashes, fn {tbl, schema_hash, tbl_ops} ->
                   if is_binary(schema_hash) and schema_hash != "" do
                     plan_json =
                       tbl_ops
                       |> Enum.map(fn op ->
                         %{
                           "op" => to_string(op.op),
                           "safety" => to_string(op.safety),
                           "table" => op.table,
                           "column" => op.column,
                           "reason" => op.reason
                         }
                       end)
                       |> Jason.encode!()

                     insert_sql = """
                     INSERT INTO #{qs}."_exo_schema" ("table_name", "schema_hash", "plan")
                     VALUES ($1, $2, $3::jsonb)
                     """

                     run_tx!(tx, insert_sql, [tbl, schema_hash, plan_json])
                   end
                 end)

                 length(ops)
               end) do
            {:ok, count} -> {:ok, %{applied: count, ops: ops}}
            {:error, reason} -> {:error, reason}
          end
        end
      end
    end
  end

  defp run_tx!(tx, sql, params) do
    case Postgrex.query(tx, sql, params) do
      {:ok, res} -> res
      {:error, reason} -> Postgrex.rollback(tx, reason)
    end
  end

  defp format_op_message(op) do
    col_part = if op[:column], do: ".#{op[:column]}", else: ""
    "#{op[:table]}#{col_part} (#{op[:op]}): #{op[:reason]}"
  end

  @doc """
  Convenience helper that reads live state, plans, and applies in one call.
  """
  def reconcile(conn, schema, resources) do
    with {:ok, valid_schema} <- validate_ident(schema),
         :ok <- ensure_ledgers(conn, valid_schema),
         {:ok, live} <- read_live_state(conn, valid_schema, resources),
         {:ok, plan_res} <- plan(resources, live) do
      apply(conn, plan_res)
    end
  end

  ## ---- MANIFEST RESOURCE NORMALIZATION & VALIDATION ----

  defp normalize_resources(resources) when is_list(resources) do
    Enum.reduce_while(resources, {:ok, []}, fn res, {:ok, acc} ->
      case normalize_resource(res) do
        {:ok, :skip} -> {:cont, {:ok, acc}}
        {:ok, norm} -> {:cont, {:ok, [norm | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp normalize_resource(res) when is_map(res) do
    raw_cols = Map.get(res, :columns) || Map.get(res, "columns") || []
    raw_table = extract_table_name(res)

    if is_nil(raw_table) or raw_cols == [] do
      {:ok, :skip}
    else
      with {:ok, table} <- validate_ident(raw_table),
           {:ok, cols} <- normalize_columns(res, raw_cols) do
        schema_hash =
          case Map.get(res, :schema_hash) || Map.get(res, "schema_hash") do
            h when is_binary(h) and h != "" -> h
            _ -> compute_schema_hash(table, cols)
          end

        {:ok,
         %{
           table: table,
           schema_hash: schema_hash,
           columns: cols
         }}
      end
    end
  end

  defp extract_table_name(res) do
    source = Map.get(res, :source) || Map.get(res, "source")

    case source do
      %{table: t} when not is_nil(t) -> to_string(t)
      %{"table" => t} when not is_nil(t) -> to_string(t)
      {:table, t} when not is_nil(t) -> to_string(t)
      [:table, t] when not is_nil(t) -> to_string(t)
      ["table", t] when not is_nil(t) -> to_string(t)
      _ -> Map.get(res, :table) || Map.get(res, "table")
    end
  end

  defp normalize_columns(res, raw_cols) do
    res_pk = Map.get(res, :primary_key) || Map.get(res, "primary_key")
    res_pk_str = if res_pk, do: to_string(res_pk), else: nil

    Enum.reduce_while(raw_cols, {:ok, []}, fn col, {:ok, acc} ->
      case normalize_column(col, res_pk_str) do
        {:ok, norm_col} -> {:cont, {:ok, [norm_col | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp normalize_column(col, res_pk_str) when is_map(col) do
    raw_name = Map.get(col, :name) || Map.get(col, "name")

    raw_storage =
      Map.get(col, :storage) || Map.get(col, "storage") ||
        fallback_storage(Map.get(col, :type) || Map.get(col, "type"))

    nullable = truthy?(Map.get(col, :nullable, Map.get(col, "nullable", false)))

    explicit_pk = truthy?(Map.get(col, :primary_key, Map.get(col, "primary_key", false)))

    is_pk =
      explicit_pk or
        (is_binary(res_pk_str) and not is_nil(raw_name) and
           String.downcase(to_string(raw_name)) == String.downcase(res_pk_str))

    unique = truthy?(Map.get(col, :unique, Map.get(col, "unique", false)))
    indexed = truthy?(Map.get(col, :indexed, Map.get(col, "indexed", false)))

    raw_default =
      if Map.has_key?(col, :default),
        do: Map.get(col, :default),
        else: Map.get(col, "default")

    raw_choices = Map.get(col, :choices) || Map.get(col, "choices")
    fk = truthy?(Map.get(col, :foreign_key, Map.get(col, "foreign_key", false)))
    refs = Map.get(col, :references) || Map.get(col, "references")

    with {:ok, name} <- validate_ident(raw_name),
         {:ok, storage} <- validate_storage_type(raw_storage),
         {:ok, default_sql} <- build_default_literal(name, storage, raw_default),
         {:ok, choices} <- validate_choices(name, raw_choices) do
      {:ok,
       %{
         name: name,
         storage: storage,
         nullable: if(is_pk, do: false, else: nullable),
         primary_key: is_pk,
         unique: unique,
         indexed: indexed,
         default: raw_default,
         default_sql: default_sql,
         choices: choices,
         foreign_key: fk,
         references: if(refs, do: to_string(refs), else: nil)
       }}
    end
  end

  defp validate_choices(_col_name, nil), do: {:ok, nil}
  defp validate_choices(_col_name, []), do: {:ok, nil}

  defp validate_choices(col_name, choices) when is_list(choices) do
    if Enum.all?(choices, &(is_binary(&1) or is_atom(&1))) do
      {:ok, Enum.map(choices, &to_string/1)}
    else
      {:error, {:invalid_choices, col_name, choices}}
    end
  end

  defp validate_choices(col_name, other), do: {:error, {:invalid_choices, col_name, other}}

  defp fallback_storage(nil), do: "text"

  defp fallback_storage(type) do
    case to_string(type) do
      "string" -> "text"
      "integer" -> "integer"
      "float" -> "double precision"
      "boolean" -> "boolean"
      "map" -> "jsonb"
      "list" -> "jsonb"
      other -> other
    end
  end

  defp compute_schema_hash(table, cols) do
    sorted = Enum.sort_by(cols, & &1.name)

    body =
      Enum.map_join(sorted, "\n", fn c ->
        choices = if c.choices, do: Enum.join(c.choices, ","), else: ""
        def_str = if is_nil(c.default), do: "", else: Jason.encode!(to_string(c.default))

        "#{c.name}|#{c.storage}|#{c.nullable}|#{c.primary_key}|#{c.unique}|#{c.indexed}|#{def_str}|#{choices}"
      end)

    :crypto.hash(:sha256, "#{table}\n#{body}\n")
    |> Base.encode16(case: :lower)
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
