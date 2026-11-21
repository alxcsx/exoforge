defmodule Exoforge.Std.Database.Include do
  @moduledoc """
  The host side of `Include`: the rows a foreign key column points at, fetched with the rows of the query.

  `database.execute` takes an optional `include: [%{column: "item_id"}]`. For each entry the column must
  be a declared foreign key of one of the caller's own resources (`references: "<resource>.<column>"`
  in its manifest, the same declaration the Studio and the schema use). The referenced resource may be
  owned by another extension; its rows live in that extension's own namespace, so they are read there,
  with one query per include for all the distinct values.

  The answer is `included: %{"item_id" => %{"<fk value>" => row}}`. A row that is missing, or that the
  original caller may not read, is simply absent: the navigation stays null. A player may read a
  referenced resource only when it is `allow_player_read`; server, studio and internal callers always
  may (the rule of `resource_store`). The caller's scopes are those of the request that started the
  chain (`Exoforge.RequestContext.scopes/0`), not of the nested internal dispatch.

  Failures: a column that is not a declared foreign key of the caller is `{:error, {:invalid_include, message}}`.
  A reference to a resource no deployed extension declares is not an error: the column is left out of
  `included` and a `missing_reference` warning says why.
  """

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.{Coerce, Dialect, JsonColumns}

  @doc "The include entries of a `database.execute` payload as column names, or `{:error, ...}`."
  def parse(nil), do: {:ok, []}

  def parse(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case column_of(entry) do
        col when is_binary(col) and col != "" -> {:cont, {:ok, [col | acc]}}
        _ -> {:halt, {:error, {:invalid_include, "each include needs a column"}}}
      end
    end)
    |> case do
      {:ok, cols} -> {:ok, cols |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  def parse(_), do: {:error, {:invalid_include, "include must be a list of {column}"}}

  defp column_of(%{} = entry), do: to_s(Map.get(entry, "column") || Map.get(entry, :column))
  defp column_of(col) when is_binary(col), do: col
  defp column_of(_), do: nil

  @doc """
  Checks every include against the caller's declared foreign keys, before any query runs.

  `root_table` is the table the query reads (nil when unknown). Returns `{:ok, plans}` where a plan is
  `%{column:, target: info | nil, ref: "res.col"}` (`target` nil: the referenced resource is not deployed).
  """
  def plan(plugin, root_table, columns) do
    entries = Exoforge.ExtensionRegistry.all_resources()
    own = Enum.filter(entries, &(to_string(&1.plugin_id) == to_string(plugin)))

    Enum.reduce_while(columns, {:ok, []}, fn column, {:ok, acc} ->
      case declared_reference(own, root_table, column) do
        {:ok, ref} -> {:cont, {:ok, [%{column: column, ref: ref, target: resolve(ref, entries)} | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, plans} -> {:ok, Enum.reverse(plans)}
      error -> error
    end
  end

  # The caller's resource the query reads, when it can be told (`root_table`), else every resource of the
  # caller that declares the column; the answer must be one reference.
  defp declared_reference(own, root_table, column) do
    rooted = if root_table, do: Enum.filter(own, &(root_table in table_names(&1.resource))), else: []
    candidates = if rooted == [], do: own, else: rooted

    refs =
      candidates
      |> Enum.flat_map(fn %{resource: res} ->
        for col <- get(res, :columns) || [],
            to_s(get(col, :name)) == column,
            fk?(col),
            ref = to_s(get(col, :references)),
            ref != "",
            do: ref
      end)
      |> Enum.uniq()

    case refs do
      [ref] ->
        if match?([_, _], String.split(ref, ".", parts: 2)),
          do: {:ok, ref},
          else: {:error, {:invalid_include, "column '#{column}' has a malformed reference '#{ref}'"}}

      [] ->
        {:error, {:invalid_include, "'#{column}' is not a declared foreign key (ForeignKey + References) of this extension's resources"}}

      _ ->
        {:error, {:invalid_include, "'#{column}' references different resources in this extension; include it from a query on one table"}}
    end
  end

  # `foreign_key` is only ever turned off on purpose; a column with `references` is a foreign key.
  defp fk?(col), do: get(col, :foreign_key) not in [false, "false"]

  defp resolve(ref, entries) do
    [name, column] = String.split(ref, ".", parts: 2)

    found =
      Enum.find(entries, &(to_s(get(&1.resource, :name)) == name)) ||
        Enum.find(entries, &(name in table_names(&1.resource)))

    case found do
      nil -> nil
      %{} = entry -> %{entry: entry, table: table_of(entry.resource), column: column}
    end
  end

  @doc """
  Reads the referenced rows for `rows`. Returns `{included, warnings}`.

  Runs one query per include (per distinct referenced resource), never one per row.
  """
  def fetch(plans, rows) do
    scopes = Exoforge.RequestContext.scopes() || []

    Enum.reduce(plans, {%{}, []}, fn plan, {included, warnings} ->
      case plan.target do
        nil ->
          warning = %{code: "missing_reference", column: plan.column, references: plan.ref}
          {included, warnings ++ [warning]}

        target ->
          {Map.put(included, plan.column, load(target, values(rows, plan.column), scopes)), warnings}
      end
    end)
  end

  defp values(rows, column) do
    rows
    |> Enum.map(&row_value(&1, column))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp row_value(row, column) when is_map(row) do
    Map.get(row, column) || Map.get(row, String.to_existing_atom(column))
  rescue
    ArgumentError -> nil
  end

  defp row_value(_, _), do: nil

  defp load(_target, [], _scopes), do: %{}

  defp load(%{entry: entry, table: table, column: column}, values, scopes) do
    with true <- readable?(entry.resource, scopes),
         namespace = entry.plugin_id,
         {:ok, %{exists: true, columns: cols}} <-
           ActionDispatcher.dispatch_internal(:lldb, :introspect, %{namespace: namespace, table: table}),
         types = Map.new(cols, &{&1.name, Map.take(&1, [:type, :tz])}),
         true <- Map.has_key?(types, column),
         [_ | _] = keys <- coerce(column, types, values) do
      placeholders = keys |> Enum.with_index(1) |> Enum.map_join(", ", fn {_, i} -> Dialect.placeholder(i) end)
      sql = "SELECT * FROM #{Dialect.quote_ident(table)} WHERE #{Dialect.quote_ident(column)} IN (#{placeholders})"

      case ActionDispatcher.dispatch_internal(:lldb, :exec, %{namespace: namespace, operation: sql, arguments: keys}) do
        {:ok, %{rows: found}} ->
          {:ok, %{rows: decoded}} = JsonColumns.decode(%{action: :all, table: table}, {:ok, %{rows: Enum.map(found, &Coerce.row/1)}})
          Map.new(decoded, &{to_s(Map.get(&1, column)), &1})

        _ ->
          %{}
      end
    else
      _ -> %{}
    end
  rescue
    ArgumentError -> %{}
  end

  # A value that cannot be the column's type cannot match a row: it is dropped, not an error.
  defp coerce(column, types, values) do
    values
    |> Enum.flat_map(fn value ->
      case Coerce.value(column, Map.get(types, column), value) do
        {:ok, coerced} when not is_nil(coerced) -> [coerced]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  # The rule of `resource_store`: a resource opted in with `allow_player_read` is readable by anyone;
  # otherwise staff (studio and up), service tokens and internal callers only.
  defp readable?(resource, scopes) do
    get(resource, :allow_player_read) == true or staff?(scopes)
  end

  defp staff?(:internal), do: true

  defp staff?(scopes) do
    Exoforge.Auth.Roles.satisfies?(scopes, Exoforge.Auth.Roles.studio()) or
      Exoforge.Auth.Roles.has?(scopes, Exoforge.Auth.Roles.service())
  end

  @doc "The table a SQL text reads from (the first `FROM`), or nil. Used only to tell which resource an include belongs to."
  def table_of_sql(sql) when is_binary(sql) do
    case Regex.run(~r/\bfrom\s+(?:"?[A-Za-z0-9_]+"?\.)?"?([A-Za-z0-9_]+)"?/i, sql) do
      [_, table] -> String.downcase(table)
      _ -> nil
    end
  end

  def table_of_sql(_), do: nil

  ## ---- resource maps (atom- or string-keyed, JSON-sanitized) ----

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp get(_, _), do: nil

  defp to_s(nil), do: ""
  defp to_s(value), do: to_string(value)

  defp table_names(resource) do
    [get(resource, :name), get(resource, :table), source_table(get(resource, :source))]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_s/1)
  end

  defp table_of(resource), do: source_table(get(resource, :source)) || to_s(get(resource, :table) || get(resource, :name))

  defp source_table({:table, t}), do: t
  defp source_table([:table, t]), do: t
  defp source_table(["table", t]), do: t
  defp source_table(%{table: t}), do: t
  defp source_table(%{"table" => t}), do: t
  defp source_table(_), do: nil
end
