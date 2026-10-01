defmodule Exoforge.Std.Database.Adapters.Sandbox do
  @moduledoc """
  In-memory, ETS-backed isolated database adapter.
  Used for local tests, development, and offline environments where PostgreSQL is not available.
  Enforces 100% strict isolation: each plugin receives its own ETS database table.
  """
  @behaviour Exoforge.Std.Database.Adapter

  @impl true
  def ensure_database(plugin_id, _config) do
    table = table_name(plugin_id)

    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
        # Schema metadata record
        :ets.insert(table, {:__meta__, %{tables: MapSet.new(), created_at: System.system_time(:millisecond)}})
        {:ok, %{status: :created, table: table, plugin: plugin_id}}

      _tid ->
        {:ok, %{status: :exists, table: table, plugin: plugin_id}}
    end
  end

  @impl true
  def connection_config(plugin_id, _config) do
    {:ok,
     %{
       url: "sandbox://localhost/exoforge_#{clean_id(plugin_id)}",
       database: "exoforge_#{clean_id(plugin_id)}",
       schema: "plugin_#{clean_id(plugin_id)}",
       driver: :sandbox,
       pool_size: 1
     }}
  end

  @impl true
  def health_check(_config) do
    {:ok, %{status: "ok", driver: :sandbox}}
  end

  @impl true
  def reset(plugin_id, _config) do
    table = table_name(plugin_id)

    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
      :ets.insert(table, {:__meta__, %{tables: MapSet.new(), created_at: System.system_time(:millisecond)}})
    end

    :ok
  end

  @impl true
  def execute(plugin_id, query, args, _config) when is_binary(query) do
    ensure_database(plugin_id, %{})
    table = table_name(plugin_id)
    normalized_query = String.trim(query)

    cond do
      String.match?(normalized_query, ~r/^CREATE\s+TABLE/i) ->
        handle_create_table(table, normalized_query)

      String.match?(normalized_query, ~r/^INSERT\s+INTO/i) ->
        handle_insert(table, normalized_query, args)

      String.match?(normalized_query, ~r/^SELECT/i) ->
        handle_select(table, normalized_query, args)

      String.match?(normalized_query, ~r/^UPDATE/i) ->
        handle_update(table, normalized_query, args)

      String.match?(normalized_query, ~r/^DELETE\s+FROM/i) ->
        handle_delete(table, normalized_query, args)

      String.match?(normalized_query, ~r/^DROP\s+TABLE/i) ->
        handle_drop(table, normalized_query)

      true ->
        {:error, {:unsupported_query, query}}
    end
  end

  def execute(plugin_id, %{action: action} = command, _args, _config) do
    ensure_database(plugin_id, %{})
    table = table_name(plugin_id)

    case action do
      :put ->
        tbl = to_string(command[:table])
        id = to_string(command[:id])
        data = command[:data] || %{}
        record = Map.put(data, "id", id)
        :ets.insert(table, {{tbl, id}, record})
        track_table(table, tbl)
        {:ok, %{rows: [record], num_rows: 1}}

      :get ->
        tbl = to_string(command[:table])
        id = to_string(command[:id])

        case :ets.lookup(table, {tbl, id}) do
          [{{^tbl, ^id}, record}] -> {:ok, %{rows: [record], num_rows: 1}}
          [] -> {:ok, %{rows: [], num_rows: 0}}
        end

      :delete ->
        tbl = to_string(command[:table])
        id = to_string(command[:id])
        :ets.delete(table, {tbl, id})
        {:ok, %{rows: [], num_rows: 1}}

      :all ->
        tbl = to_string(command[:table])
        rows = get_all_rows_for_table(table, tbl)
        {:ok, %{rows: rows, num_rows: length(rows)}}

      other ->
        {:error, {:unknown_action, other}}
    end
  end

  ## ---- SQL PARSING & EXECUTION HELPERS ----

  defp handle_create_table(table, query) do
    # Regex: CREATE TABLE [IF NOT EXISTS] <name> (...)
    case Regex.run(~r/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)/i, query) do
      [_, tbl_name] ->
        track_table(table, tbl_name)
        {:ok, %{rows: [], num_rows: 0}}

      _ ->
        {:error, {:syntax_error, "Unable to parse CREATE TABLE: #{query}"}}
    end
  end

  defp handle_insert(table, query, args) do
    # Form: INSERT INTO table_name (col1, col2) VALUES ($1, $2)
    # or: INSERT INTO table_name (col1, col2) VALUES ('v1', 'v2')
    regex = ~r/INSERT\s+INTO\s+([a-zA-Z0-9_]+)\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/i

    case Regex.run(regex, query) do
      [_, tbl_name, cols_str, vals_str] ->
        cols = cols_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&strip_quotes/1)

        values = resolve_values(vals_str, args)

        if length(cols) != length(values) do
          {:error, {:column_value_mismatch, "Expected #{length(cols)} values, got #{length(values)}"}}
        else
          row =
            Enum.zip(cols, values)
            |> Enum.into(%{})

          id = Map.get(row, "id") || Map.get(row, :id) || System.unique_integer([:positive, :monotonic]) |> to_string()
          row = Map.put(row, "id", id)

          :ets.insert(table, {{tbl_name, id}, row})
          track_table(table, tbl_name)
          {:ok, %{rows: [row], num_rows: 1}}
        end

      _ ->
        {:error, {:syntax_error, "Unable to parse INSERT query: #{query}"}}
    end
  end

  defp handle_select(table, query, args) do
    # Regex: SELECT ... FROM <tbl> [WHERE col = val]
    regex = ~r/SELECT\s+(.*?)\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.*))?/i

    case Regex.run(regex, query) do
      [_, _fields_str, tbl_name, where_clause] ->
        all_rows = get_all_rows_for_table(table, tbl_name)
        filtered_rows = filter_rows(all_rows, where_clause, args)
        {:ok, %{rows: filtered_rows, num_rows: length(filtered_rows)}}

      [_, _fields_str, tbl_name] ->
        all_rows = get_all_rows_for_table(table, tbl_name)
        {:ok, %{rows: all_rows, num_rows: length(all_rows)}}

      _ ->
        {:error, {:syntax_error, "Unable to parse SELECT query: #{query}"}}
    end
  end

  defp handle_update(table, query, args) do
    # UPDATE <tbl> SET col = val, ... [WHERE col = val]
    regex = ~r/UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.*?)(?:\s+WHERE\s+(.*))?$/i

    case Regex.run(regex, query) do
      [_, tbl_name, set_clause, where_clause] ->
        updates = parse_set_clause(set_clause, args)
        all_rows = get_all_rows_for_table(table, tbl_name)
        matching = filter_rows(all_rows, where_clause, args)

        updated_rows =
          Enum.map(matching, fn row ->
            new_row = Map.merge(row, updates)
            id = Map.get(new_row, "id")
            :ets.insert(table, {{tbl_name, id}, new_row})
            new_row
          end)

        {:ok, %{rows: updated_rows, num_rows: length(updated_rows)}}

      [_, tbl_name, set_clause] ->
        updates = parse_set_clause(set_clause, args)
        all_rows = get_all_rows_for_table(table, tbl_name)

        updated_rows =
          Enum.map(all_rows, fn row ->
            new_row = Map.merge(row, updates)
            id = Map.get(new_row, "id")
            :ets.insert(table, {{tbl_name, id}, new_row})
            new_row
          end)

        {:ok, %{rows: updated_rows, num_rows: length(updated_rows)}}

      _ ->
        {:error, {:syntax_error, "Unable to parse UPDATE query: #{query}"}}
    end
  end

  defp handle_delete(table, query, args) do
    regex = ~r/DELETE\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.*))?/i

    case Regex.run(regex, query) do
      [_, tbl_name, where_clause] ->
        all_rows = get_all_rows_for_table(table, tbl_name)
        matching = filter_rows(all_rows, where_clause, args)

        Enum.each(matching, fn row ->
          id = Map.get(row, "id")
          :ets.delete(table, {tbl_name, id})
        end)

        {:ok, %{rows: [], num_rows: length(matching)}}

      [_, tbl_name] ->
        all_rows = get_all_rows_for_table(table, tbl_name)

        Enum.each(all_rows, fn row ->
          id = Map.get(row, "id")
          :ets.delete(table, {tbl_name, id})
        end)

        {:ok, %{rows: [], num_rows: length(all_rows)}}

      _ ->
        {:error, {:syntax_error, "Unable to parse DELETE query: #{query}"}}
    end
  end

  defp handle_drop(table, query) do
    case Regex.run(~r/DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)/i, query) do
      [_, tbl_name] ->
        all_rows = get_all_rows_for_table(table, tbl_name)
        Enum.each(all_rows, fn row ->
          id = Map.get(row, "id")
          :ets.delete(table, {tbl_name, id})
        end)
        untrack_table(table, tbl_name)
        {:ok, %{rows: [], num_rows: 0}}

      _ ->
        {:error, {:syntax_error, "Unable to parse DROP TABLE: #{query}"}}
    end
  end

  defp get_all_rows_for_table(table, tbl_name) do
    match_spec = [{{{tbl_name, :_}, :"$1"}, [], [:"$1"]}]
    :ets.select(table, match_spec)
  end

  defp filter_rows(rows, nil, _args), do: rows
  defp filter_rows(rows, "", _args), do: rows

  defp filter_rows(rows, where_clause, args) do
    # Simple WHERE clause matching: col = val [AND col2 = val2]
    conditions = String.split(where_clause, ~r/\s+AND\s+/i)

    Enum.filter(rows, fn row ->
      Enum.all?(conditions, fn cond_str ->
        case Regex.run(~r/([a-zA-Z0-9_]+)\s*(=|!=|<>)\s*(.*)/, String.trim(cond_str)) do
          [_, col, op, val_str] ->
            target_val = resolve_single_value(val_str, args)
            actual_val = Map.get(row, col) || Map.get(row, String.to_atom(col))

            case op do
              "=" -> to_string(actual_val) == to_string(target_val)
              "!=" -> to_string(actual_val) != to_string(target_val)
              "<>" -> to_string(actual_val) != to_string(target_val)
              _ -> true
            end

          _ ->
            true
        end
      end)
    end)
  end

  defp parse_set_clause(set_clause, args) do
    set_clause
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn assign, acc ->
      case String.split(assign, "=", parts: 2) do
        [col, val] ->
          resolved = resolve_single_value(val, args)
          Map.put(acc, strip_quotes(String.trim(col)), resolved)

        _ ->
          acc
      end
    end)
  end

  defp resolve_values(vals_str, args) when is_list(args) do
    tokens = vals_str |> String.split(",") |> Enum.map(&String.trim/1)

    Enum.map(tokens, fn token ->
      case Regex.run(~r/^\$(\d+)$/, token) do
        [_, idx_str] ->
          idx = String.to_integer(idx_str) - 1
          Enum.at(args, idx)

        nil ->
          strip_quotes(token)
      end
    end)
  end

  defp resolve_values(vals_str, args) when is_map(args) do
    tokens = vals_str |> String.split(",") |> Enum.map(&String.trim/1)

    Enum.map(tokens, fn token ->
      case Regex.run(~r/^\$([a-zA-Z0-9_]+)$/, token) do
        [_, key] ->
          Map.get(args, key) || Map.get(args, String.to_atom(key))

        nil ->
          strip_quotes(token)
      end
    end)
  end

  defp resolve_single_value(val_str, args) do
    trimmed = String.trim(val_str)

    case Regex.run(~r/^\$(\d+)$/, trimmed) do
      [_, idx_str] when is_list(args) ->
        idx = String.to_integer(idx_str) - 1
        Enum.at(args, idx)

      _ ->
        case Regex.run(~r/^\$([a-zA-Z0-9_]+)$/, trimmed) do
          [_, key] when is_map(args) ->
            Map.get(args, key) || Map.get(args, String.to_atom(key))

          _ ->
            strip_quotes(trimmed)
        end
    end
  end

  defp strip_quotes(str) do
    trimmed = String.trim(str)

    cond do
      String.starts_with?(trimmed, "'") and String.ends_with?(trimmed, "'") ->
        String.slice(trimmed, 1..-2//1)

      String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") ->
        String.slice(trimmed, 1..-2//1)

      true ->
        trimmed
    end
  end

  defp track_table(table, tbl_name) do
    case :ets.lookup(table, :__meta__) do
      [{:__meta__, meta}] ->
        new_tables = MapSet.put(meta.tables, tbl_name)
        :ets.insert(table, {:__meta__, %{meta | tables: new_tables}})

      _ ->
        :ok
    end
  end

  defp untrack_table(table, tbl_name) do
    case :ets.lookup(table, :__meta__) do
      [{:__meta__, meta}] ->
        new_tables = MapSet.delete(meta.tables, tbl_name)
        :ets.insert(table, {:__meta__, %{meta | tables: new_tables}})

      _ ->
        :ok
    end
  end

  defp clean_id(plugin_id) do
    plugin_id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.downcase()
  end

  defp table_name(plugin_id) do
    String.to_atom("exo_db_#{clean_id(plugin_id)}")
  end
end
