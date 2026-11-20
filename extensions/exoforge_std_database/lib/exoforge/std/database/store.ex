defmodule Exoforge.Std.Database.Store do
  @moduledoc """
  Key-value and row operations over a SQL engine, written against the `lldb` driver layer (ADR 005).

  Every statement is built from the engine's dialect (`Exoforge.Std.Database.Dialect`) and run through
  the `lldb` service, so nothing here names an engine. A table is one of three things, found by
  introspecting it:

    * a **key-value table** (`id`, `data`, `updated_at`): the document store behind `Database.put/get`;
      created on first use;
    * a **typed table**, created for a declared resource: rows are real columns, coerced to the
      column's logical type;
    * a **missing declared resource table**: an error, since the resource store owns its creation.

  A batch is built before it runs, then executed as one transaction. Because the tables are inspected
  up front, a batch that creates a table with raw SQL and then writes to it with a key-value put in the
  same batch sees the table as missing: create it in an earlier call.
  """
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.{Coerce, Dialect, JsonColumns, KindCache}

  @kv_columns ["data", "id", "updated_at"]

  @doc "Runs a key-value command (`put`, `get`, `all`, `delete`) or a `batch` in a plugin's namespace."
  def run(plugin, %{action: :batch, operations: operations}) when is_list(operations),
    do: guarded(fn -> batch(plugin, operations) end)

  def run(plugin, %{"action" => "batch", "operations" => operations}) when is_list(operations),
    do: guarded(fn -> batch(plugin, operations) end)

  def run(plugin, %{action: action} = command), do: guarded(fn -> kv(plugin, action, command) end)

  defp guarded(fun) do
    fun.()
  rescue
    e ->
      Logger.error("[Database] store failure: " <> Exception.format(:error, e, __STACKTRACE__))
      {:error, {:database_error, Exception.message(e)}}
  end

  ## ---- single operations ----

  defp kv(plugin, action, command) do
    tbl = to_string(command[:table])
    command = if action == :put, do: JsonColumns.encode(command), else: command

    kind = table_kind(plugin, tbl)

    result =
      case plan(kind, action, tbl, command) do
        {:ok, statements, finish} -> run_statements(plugin, statements, finish)
        {:error, _} = err -> err
      end

    # A document operation on a table that was not there made it: from now on it is known to exist.
    if kind == :missing and match?({:ok, _}, result), do: KindCache.put(plugin, tbl, :kv)

    JsonColumns.decode(command, result)
  end

  # One statement runs as it is; several run in one transaction, so a table is never half made.
  defp run_statements(plugin, [{sql, args}], finish) do
    case lldb(:exec, %{namespace: plugin, operation: sql, arguments: args}) do
      {:ok, result} -> finish.([result])
      error -> error
    end
  end

  defp run_statements(plugin, statements, finish) do
    case lldb(:transaction, %{namespace: plugin, statements: statements}) do
      {:ok, %{results: results}} -> finish.(results)
      {:error, %{reason: reason}} -> {:error, reason}
      error -> error
    end
  end

  ## ---- what kind of table ----

  defp table_kind(plugin, tbl) do
    case KindCache.get(plugin, tbl) do
      {:ok, kind} ->
        kind

      :miss ->
        kind = introspect_kind(plugin, tbl)
        # A missing table is not remembered: it may be made the next instant.
        if kind != :missing, do: KindCache.put(plugin, tbl, kind)
        kind
    end
  end

  defp introspect_kind(plugin, tbl) do
    case lldb(:introspect, %{namespace: plugin, table: tbl}) do
      {:ok, %{exists: true, columns: columns, primary_key: primary_key}} ->
        names = Enum.map(columns, & &1.name)

        if Enum.sort(names) == @kv_columns do
          :kv
        else
          {:resource,
           %{
             columns: names,
             types: Map.new(columns, &{&1.name, Map.take(&1, [:type, :tz])}),
             pk: List.first(primary_key) || "id"
           }}
        end

      _ ->
        :missing
    end
  end

  # -> {:ok, statements, finish} | {:error, reason}; `finish` turns the results of the statements
  # (one per statement, in order) into the operation's answer.
  defp plan({:resource, info}, :put, tbl, command), do: resource_put(info, tbl, command)
  defp plan({:resource, info}, :get, tbl, command), do: resource_get(info, tbl, command)
  defp plan({:resource, info}, :delete, tbl, command), do: resource_delete(info, tbl, command)
  defp plan({:resource, _info}, :all, tbl, _command), do: resource_all(tbl)
  defp plan({:resource, _info}, other, _tbl, _command), do: {:error, {:unknown_action, other}}

  defp plan(:missing, action, tbl, command) when action in [:put, :get, :all] do
    if declared_resource_table?(tbl),
      do: {:error, {:missing_resource_table, tbl}},
      else: document(action, tbl, command, true)
  end

  defp plan(:kv, action, tbl, command), do: document(action, tbl, command, false)
  defp plan(_missing, action, tbl, command), do: document(action, tbl, command, true)

  ## ---- typed tables ----

  defp resource_put(%{columns: cols, types: types, pk: pk_col}, tbl, command) do
    id = to_string(command[:id])
    data = command[:data] || %{}
    record = Map.put(data, "id", id)
    data_with_pk = Map.put(data, pk_col, id)

    valid_pairs =
      Enum.flat_map(cols, fn col ->
        case Map.fetch(data_with_pk, col) do
          {:ok, val} ->
            [{col, val}]

          :error ->
            case Enum.find(data_with_pk, fn {k, _} -> to_string(k) == col end) do
              {_, val} -> [{col, val}]
              nil -> []
            end
        end
      end)

    if valid_pairs == [] do
      document(:put, tbl, command, true)
    else
      with {:ok, coerced} <- Coerce.pairs(valid_pairs, types) do
        statements = upsert(tbl, pk_col, Enum.map(coerced, fn {name, value} -> {name, {:param, value}} end))
        {:ok, statements, fn _ -> {:ok, %{rows: [record], num_rows: 1}} end}
      end
    end
  end

  defp resource_get(%{types: types, pk: pk_col}, tbl, command) do
    with {:ok, id} <- Coerce.value(pk_col, Map.get(types, pk_col), to_string(command[:id])) do
      sql = "SELECT * FROM #{q(tbl)} WHERE #{q(pk_col)} = #{Dialect.placeholder(1)}"

      {:ok, [{sql, [id]}],
       fn [result] ->
         case result do
           %{rows: [row | _]} -> {:ok, %{rows: [Coerce.row(row)], num_rows: 1}}
           %{rows: []} -> {:ok, %{rows: [], num_rows: 0}}
         end
       end}
    end
  end

  defp resource_delete(%{types: types, pk: pk_col}, tbl, command) do
    with {:ok, id} <- Coerce.value(pk_col, Map.get(types, pk_col), to_string(command[:id])) do
      sql = "DELETE FROM #{q(tbl)} WHERE #{q(pk_col)} = #{Dialect.placeholder(1)}"
      {:ok, [{sql, [id]}], fn [result] -> {:ok, result} end}
    end
  end

  defp resource_all(tbl) do
    {:ok, [{"SELECT * FROM #{q(tbl)}", []}],
     fn [%{rows: rows}] ->
       decoded = Enum.map(rows, &Coerce.row/1)
       {:ok, %{rows: decoded, num_rows: length(decoded)}}
     end}
  end

  ## ---- key-value (document) tables ----

  # `create?` is true when the table is not known to exist: the statement then also makes it.
  defp document(:put, tbl, command, create?) do
    id = to_string(command[:id])
    data = Jason.encode!(command[:data] || %{})

    statements =
      create_first(create?, tbl) ++
        upsert(tbl, "id", [{"id", {:param, id}}, {"data", {:json, data}}, {"updated_at", {:expr, "CURRENT_TIMESTAMP"}}])

    {:ok, statements, fn _ -> {:ok, %{rows: [%{"id" => id, "data" => command[:data]}], num_rows: 1}} end}
  end

  defp document(:get, tbl, command, create?) do
    id = to_string(command[:id])
    select = "SELECT data FROM #{q(tbl)} WHERE id = #{Dialect.placeholder(1)}"

    {:ok, create_first(create?, tbl) ++ [{select, [id]}],
     fn results ->
       case List.last(results) do
         %{rows: [%{"data" => json_data}]} ->
           data = if is_binary(json_data), do: Jason.decode!(json_data), else: json_data
           {:ok, %{rows: [Map.put(data, "id", id)], num_rows: 1}}

         %{rows: []} ->
           {:ok, %{rows: [], num_rows: 0}}
       end
     end}
  end

  defp document(:delete, tbl, command, create?) do
    id = to_string(command[:id])
    delete = "DELETE FROM #{q(tbl)} WHERE id = #{Dialect.placeholder(1)}"
    {:ok, create_first(create?, tbl) ++ [{delete, [id]}], fn results -> {:ok, List.last(results)} end}
  end

  defp document(:all, tbl, _command, create?) do
    {:ok, create_first(create?, tbl) ++ [{"SELECT id, data FROM #{q(tbl)}", []}],
     fn results ->
       %{rows: rows} = List.last(results)

       decoded =
         Enum.map(rows, fn row ->
           data = if is_binary(row["data"]), do: Jason.decode!(row["data"]), else: row["data"]
           Map.put(data, "id", row["id"])
         end)

       {:ok, %{rows: decoded, num_rows: length(decoded)}}
     end}
  end

  defp document(other, _tbl, _command, _create?), do: {:error, {:unknown_action, other}}

  defp create_first(true, tbl), do: [{create_document_table(tbl), []}]
  defp create_first(false, _tbl), do: []

  defp create_document_table(tbl) do
    "CREATE TABLE IF NOT EXISTS #{q(tbl)} (" <>
      "id #{Dialect.type(:text)} PRIMARY KEY, " <>
      "data #{Dialect.type(:json)} NOT NULL, " <>
      "updated_at #{Dialect.type(:timestamp_naive)} DEFAULT CURRENT_TIMESTAMP)"
  end

  ## ---- upsert, in the engine's way ----

  # `cols` is `[{name, {:param, value} | {:json, text} | {:expr, sql}}]`; returns the statements.
  defp upsert(tbl, pk, cols) do
    names = Enum.map(cols, &elem(&1, 0))

    {value_sql, params, _next} =
      Enum.reduce(cols, {[], [], 1}, fn
        {_name, {:expr, sql}}, {vs, ps, n} -> {[sql | vs], ps, n}
        {_name, {:param, value}}, {vs, ps, n} -> {[Dialect.placeholder(n) | vs], [value | ps], n + 1}
        {_name, {:json, value}}, {vs, ps, n} -> {[Dialect.json_placeholder(n) | vs], [value | ps], n + 1}
      end)

    insert =
      "INSERT INTO #{q(tbl)} (#{Enum.map_join(names, ", ", &q/1)}) " <>
        "VALUES (#{value_sql |> Enum.reverse() |> Enum.join(", ")})"

    params = Enum.reverse(params)

    case Dialect.upsert() do
      "on_conflict" ->
        updates =
          names
          |> Enum.reject(&(&1 == pk))
          |> Enum.map_join(", ", fn col -> "#{q(col)} = EXCLUDED.#{q(col)}" end)

        conflict =
          if updates == "",
            do: "ON CONFLICT (#{q(pk)}) DO NOTHING",
            else: "ON CONFLICT (#{q(pk)}) DO UPDATE SET #{updates}"

        [{insert <> " " <> conflict, params}]

      "delete_insert" ->
        {_, {_, pk_value}} = List.keyfind(cols, pk, 0)
        [{"DELETE FROM #{q(tbl)} WHERE #{q(pk)} = #{Dialect.placeholder(1)}", [pk_value]}, {insert, params}]
    end
  end

  ## ---- batches ----

  defp batch(_plugin, []), do: {:ok, %{rows: [], num_rows: 0}}

  defp batch(plugin, operations) do
    with {:ok, planned} <- plan_batch(plugin, operations) do
      statements = Enum.flat_map(planned, & &1.statements)

      case lldb(:transaction, %{namespace: plugin, statements: statements}) do
        {:ok, %{results: results}} ->
          {:ok, %{rows: [], num_rows: batch_rows(planned, results)}}

        {:error, %{index: statement_index} = error} ->
          {:error, %{error | index: operation_index(planned, statement_index)}}

        error ->
          error
      end
    end
  end

  defp plan_batch(plugin, operations) do
    operations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], %{}}, fn {operation, index}, {:ok, planned, kinds} ->
      case plan_batch_operation(plugin, operation, kinds) do
        {:ok, statements, finish, kinds} ->
          {:cont, {:ok, [%{index: index, statements: statements, finish: finish} | planned], kinds}}

        {:error, reason} ->
          {:halt, {:error, %{index: index, reason: reason, message: batch_message(reason)}}}
      end
    end)
    |> case do
      {:ok, planned, _kinds} -> {:ok, Enum.reverse(planned)}
      error -> error
    end
  end

  defp plan_batch_operation(plugin, operation, kinds) do
    case normalize_batch_operation(operation) do
      {:execute, sql, args} ->
        {:ok, [{sql, args}], fn [result] -> {:ok, result} end, kinds}

      {:put, table, id, data} ->
        tbl = to_string(table)
        command = JsonColumns.encode(%{action: :put, table: tbl, id: id, data: data})
        plan_table_operation(plugin, :put, tbl, command, kinds)

      {:delete, table, id} ->
        tbl = to_string(table)
        plan_table_operation(plugin, :delete, tbl, %{action: :delete, table: tbl, id: id}, kinds)

      {:error, _} = error ->
        error
    end
  end

  defp plan_table_operation(plugin, action, tbl, command, kinds) do
    {kind, kinds} =
      case Map.fetch(kinds, tbl) do
        {:ok, kind} ->
          {kind, kinds}

        :error ->
          kind = table_kind(plugin, tbl)
          {kind, Map.put(kinds, tbl, kind)}
      end

    with {:ok, statements, finish} <- plan(kind, action, tbl, command) do
      {:ok, statements, finish, kinds}
    end
  end

  defp batch_rows(planned, results) do
    {total, _rest} =
      Enum.reduce(planned, {0, results}, fn %{statements: statements, finish: finish}, {sum, rest} ->
        {mine, rest} = Enum.split(rest, length(statements))

        case finish.(mine) do
          {:ok, %{num_rows: n}} when is_integer(n) -> {sum + n, rest}
          _ -> {sum, rest}
        end
      end)

    total
  end

  # The transaction reports the failing statement; the caller wants the failing operation.
  defp operation_index(planned, statement_index) do
    Enum.reduce_while(planned, {0, 0}, fn %{index: index, statements: statements}, {first, _} ->
      last = first + length(statements) - 1
      if statement_index <= last, do: {:halt, {first, index}}, else: {:cont, {last + 1, index}}
    end)
    |> elem(1)
  end

  defp normalize_batch_operation({sql, args}) when is_binary(sql), do: {:execute, sql, args || []}
  defp normalize_batch_operation(sql) when is_binary(sql), do: {:execute, sql, []}

  defp normalize_batch_operation(op) when is_map(op) do
    raw_action =
      Map.get(op, :action) || Map.get(op, "action") ||
        Map.get(op, :op) || Map.get(op, "op") ||
        Map.get(op, :type) || Map.get(op, "type")

    sql = Map.get(op, :sql) || Map.get(op, "sql") || Map.get(op, :query) || Map.get(op, "query")

    action =
      cond do
        raw_action in [:execute, "execute", :sql, "sql"] -> :execute
        raw_action in [:put, "put"] -> :put
        raw_action in [:delete, "delete"] -> :delete
        is_nil(raw_action) and is_binary(sql) -> :execute
        true -> raw_action
      end

    case action do
      :execute when is_binary(sql) ->
        args =
          cond do
            Map.has_key?(op, :args) -> Map.get(op, :args)
            Map.has_key?(op, "args") -> Map.get(op, "args")
            Map.has_key?(op, :arguments) -> Map.get(op, :arguments)
            Map.has_key?(op, "arguments") -> Map.get(op, "arguments")
            Map.has_key?(op, :params) -> Map.get(op, :params)
            Map.has_key?(op, "params") -> Map.get(op, "params")
            true -> []
          end

        {:execute, sql, args}

      :put ->
        table = Map.get(op, :table) || Map.get(op, "table")
        id = Map.get(op, :id) || Map.get(op, "id") || Map.get(op, :key) || Map.get(op, "key")
        data = Map.get(op, :data) || Map.get(op, "data") || Map.get(op, :value) || Map.get(op, "value") || %{}

        if is_nil(table) or is_nil(id), do: {:error, :invalid_batch_operation}, else: {:put, table, id, data}

      :delete ->
        table = Map.get(op, :table) || Map.get(op, "table")
        id = Map.get(op, :id) || Map.get(op, "id") || Map.get(op, :key) || Map.get(op, "key")

        if is_nil(table) or is_nil(id), do: {:error, :invalid_batch_operation}, else: {:delete, table, id}

      other when not is_nil(other) ->
        {:error, {:unsupported_batch_action, other}}

      _ ->
        {:error, :invalid_batch_operation}
    end
  end

  defp normalize_batch_operation(_), do: {:error, :invalid_batch_operation}

  defp batch_message({:invalid_value, col, type}), do: "Invalid value for column '#{col}' (expected #{type})"
  defp batch_message({:missing_resource_table, tbl}), do: "Missing declared resource table '#{tbl}'"

  defp batch_message({:unsupported_batch_action, action}),
    do: "Unsupported batch operation '#{action}'; only execute, put, and delete are allowed"

  defp batch_message(other), do: inspect(other)

  ## ---- helpers ----

  defp q(name), do: Dialect.quote_ident(name)

  defp lldb(action, payload), do: ActionDispatcher.dispatch_internal(:lldb, action, payload)

  # A declared resource owns its table: a missing one is an error, not a document to create.
  defp declared_resource_table?(tbl) do
    table = to_string(tbl)

    case Exoforge.ExtensionRegistry.fetch_resource(table) do
      {:ok, %{resource: res}} -> table_source(res) == table
      _ -> false
    end
  rescue
    _ -> false
  end

  defp table_source(res) when is_map(res) do
    source = Map.get(res, :source) || Map.get(res, "source")

    case source do
      {:table, t} -> to_string(t)
      [:table, t] -> to_string(t)
      ["table", t] -> to_string(t)
      %{table: t} -> to_string(t)
      %{"table" => t} -> to_string(t)
      _ -> Map.get(res, :table) || Map.get(res, "table")
    end
  end

  defp table_source(_), do: nil
end
