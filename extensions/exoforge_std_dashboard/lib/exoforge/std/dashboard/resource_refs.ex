defmodule Exoforge.Std.Dashboard.ResourceRefs do
  @moduledoc """
  Foreign keys in the Studio: what a column that `references: "<resource>.<column>"` means for the
  Data tab.

  A manifest column may declare `references`. This module turns that into three things the Studio
  shows without knowing which extension owns either side:

    * a link from the value to the row it points at (`links/3`)
    * a picker of the referenced rows for the create/edit form (`options/3`)
    * the reverse list, "Referenced by", on the row that is pointed at (`referenced_by/4`)

  The referenced resource is found across every extension's resources, by resource name or by table
  name (the same rule as `ExtensionRegistry.fetch_resource/1`).

  Every read of a referenced resource runs with the viewer's scopes (`opts.scopes`, default none),
  never as internal: a resource or row the viewer may not read is treated as unresolved, so it shows
  as plain text, offers no picker and is left out of "Referenced by". `opts` may also override the
  reads (`:entries`, `:list`, `:get`) so the logic is testable without a database.
  """

  use Phoenix.Component

  alias Exoforge.ExtensionRegistry

  # A picker over more rows than this is not a picker, it is a scroll bar: use a text input.
  @max_options 200
  # One bounded fetch per referenced resource per render; past it a hint says so instead of guessing.
  @scan_limit 1000
  # The reverse list shows at most this many rows per referencing resource.
  @max_referrers 20
  @label_columns ~w(name nome title)

  @type entry :: %{resource: map()}

  ## ---- columns and resources ----

  @doc "`{resource, column}` a column references, or nil. Accepts atom or string keys."
  def parse(nil), do: nil

  def parse(column) when is_map(column) do
    case get(column, :references) do
      ref when is_binary(ref) or is_atom(ref) and not is_nil(ref) ->
        case String.split(to_string(ref), ".", parts: 2) do
          [resource, col] when resource != "" and col != "" -> {resource, col}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def parse(_), do: nil

  @doc "The resource entry (as `ExtensionRegistry.all_resources/0` lists it) named `name`, or nil."
  def resolve(name, entries) do
    name = to_string(name)

    # A resource name beats a table name: two resources may share a table, never a name.
    Enum.find(entries, &(to_string(res_name(&1)) == name)) ||
      Enum.find(entries, &(name in table_names(&1.resource)))
  end

  @doc "Canonical name of a resource entry."
  def res_name(%{resource: resource}), do: get(resource, :name)

  @doc "Primary key column of a resource, as a string."
  def primary_key(resource), do: to_string(get(resource, :primary_key) || "id")

  @doc "The value of a row's primary key."
  def row_id(resource, row), do: field(row, primary_key(resource)) || field(row, "id")

  @doc "Column name used as the human label of a resource's rows (name, nome or title), or nil."
  def label_column(resource) do
    names = for c <- get(resource, :columns) || [], do: to_string(get(c, :name))
    Enum.find(@label_columns, &(&1 in names))
  end

  @doc "A row's human label, or nil."
  def label(resource, row) do
    with col when is_binary(col) <- label_column(resource),
         value when value not in [nil, ""] <- field(row, col) do
      to_string(value)
    else
      _ -> nil
    end
  end

  @doc "Path of a row's page: `/resources/<resource>?focus=row:<value>`."
  def path(resource_name, value) do
    "/resources/#{resource_name}?focus=row:#{URI.encode_www_form(to_string(value))}"
  end

  ## ---- links ----

  @doc """
  What each foreign-key value on `rows` points at, keyed by `{column, value}` (both strings).

    * `%{status: :found, path: ..., label: ...}` - the referenced row exists
    * `%{status: :missing, resource: ...}` - the referenced resource has no such row
    * `%{status: :unchecked, limit: n}` - the resource is larger than the first `n` rows checked
      and the column cannot be queried, so the row could not be confirmed either way

  Values whose referenced resource is unknown or unreadable to the viewer are left out: the cell
  stays plain text. The referenced resource is fetched once per call (bounded), not once per value.
  """
  def links(columns, rows, opts \\ %{}) do
    ctx = new_ctx(opts)
    entries = ctx.io.entries.()

    try do
      for column <- columns,
          {ref_name, ref_col} <- [parse(column)],
          entry = resolve(ref_name, entries),
          row <- rows,
          value = field(row, column.key),
          value not in [nil, ""],
          result = link(entry, ref_col, value, ctx),
          into: %{} do
        {{to_string(column.key), to_string(value)}, result}
      end
    after
      :ets.delete(ctx.cache)
    end
  end

  defp link(%{resource: resource} = entry, ref_col, value, ctx) do
    case lookup(entry, ref_col, value, ctx) do
      {:found, row} ->
        %{
          status: :found,
          path: path(res_name(entry), row_id(resource, row) || value),
          label: label(resource, row)
        }

      :missing ->
        %{status: :missing, resource: res_name(entry), column: ref_col}

      :unchecked ->
        %{status: :unchecked, resource: res_name(entry), column: ref_col, limit: @scan_limit}

      :denied ->
        nil
    end
  end

  # The referenced resource's first rows are fetched once and indexed; only a value beyond the
  # fetched window asks the store again, and only if the store can answer exactly.
  defp lookup(%{resource: resource} = entry, ref_col, value, ctx) do
    case target(entry, ctx) do
      :denied ->
        :denied

      %{complete?: complete?} = target ->
        case Map.get(index(entry, ref_col, target, ctx), to_string(value)) do
          nil when complete? -> :missing
          nil -> beyond_window(entry, resource, ref_col, value, ctx)
          row -> {:found, row}
        end
    end
  end

  defp beyond_window(entry, resource, ref_col, value, ctx) do
    name = res_name(entry)

    cond do
      ref_col == primary_key(resource) ->
        case safe(fn -> ctx.io.get.(name, value) end, :error) do
          {:ok, nil} -> :missing
          {:ok, row} -> {:found, row}
          _ -> :denied
        end

      filterable?(resource, ref_col) ->
        case safe(fn -> ctx.io.list.(name, %{filter: %{ref_col => value}, limit: 1}) end, :error) do
          {:ok, %{rows: []}} -> :missing
          {:ok, %{rows: [row | _]}} -> if same?(field(row, ref_col), value), do: {:found, row}, else: :unchecked
          _ -> :denied
        end

      true ->
        :unchecked
    end
  end

  # A resource's first rows, fetched once per call. `:denied` when the viewer may not read it.
  defp target(entry, ctx) do
    name = to_string(res_name(entry))

    case :ets.lookup(ctx.cache, {:target, name}) do
      [{_, target}] ->
        target

      [] ->
        target =
          case safe(fn -> ctx.io.list.(res_name(entry), %{limit: @scan_limit, offset: 0}) end, :error) do
            {:ok, %{rows: rows} = result} when is_list(rows) ->
              %{rows: rows, complete?: (result[:total] || length(rows)) <= length(rows)}

            _ ->
              :denied
          end

        :ets.insert(ctx.cache, {{:target, name}, target})
        target
    end
  end

  defp index(entry, ref_col, target, ctx) do
    key = {:index, to_string(res_name(entry)), ref_col}

    case :ets.lookup(ctx.cache, key) do
      [{_, index}] ->
        index

      [] ->
        # First row wins when a non-key column repeats a value.
        index =
          target.rows
          |> Enum.reverse()
          |> Map.new(&{to_string(field(&1, ref_col)), &1})

        :ets.insert(ctx.cache, {key, index})
        index
    end
  end

  ## ---- form pickers ----

  @doc """
  The picker for each foreign-key column of a form: `%{column => [{value, text}]}`, or `:text` when
  the list is large (over #{@max_options}), unreadable by the viewer, or the referenced resource is
  unknown. Columns without `references` are absent.
  """
  def options(columns, opts \\ %{}) do
    ctx = new_ctx(opts)
    entries = ctx.io.entries.()

    try do
      for column <- columns, {ref_name, ref_col} <- [parse(column)], into: %{} do
        {to_string(column.key), picker(resolve(ref_name, entries), ref_col, ctx)}
      end
    after
      :ets.delete(ctx.cache)
    end
  end

  defp picker(nil, _ref_col, _ctx), do: :text

  defp picker(%{resource: resource} = entry, ref_col, ctx) do
    case safe(fn -> ctx.io.list.(res_name(entry), %{limit: @max_options + 1, offset: 0}) end, :error) do
      {:ok, %{rows: rows} = result}
      when is_list(rows) and length(rows) <= @max_options ->
        if (result[:total] || length(rows)) <= @max_options do
          for row <- rows, value = field(row, ref_col), value not in [nil, ""] do
            {to_string(value), option_text(resource, row, value)}
          end
        else
          :text
        end

      _ ->
        :text
    end
  end

  defp option_text(resource, row, value) do
    case label(resource, row) do
      nil -> to_string(value)
      label -> "#{value} · #{label}"
    end
  end

  ## ---- referenced by ----

  @doc """
  Rows in other resources whose `references` point at `row` of resource `res_name`:
  `[%{resource: name, rows: [%{id:, label:, path:}], more: integer, checked: nil | integer}]`.

  Groups with no row, and resources the viewer may not read, are omitted. A referencing column that
  the store can filter is asked exactly; otherwise the referencing resource's first rows are
  scanned and `checked` says how many, so the list does not pretend to be complete.
  """
  def referenced_by(res_name, row, opts \\ %{}) do
    ctx = new_ctx(opts)
    entries = ctx.io.entries.()

    try do
      case resolve(res_name, entries) do
        nil ->
          []

        target ->
          for %{resource: resource} = entry <- entries,
              ref_cols = referencing_columns(resource, target, entries),
              ref_cols != [],
              found = group(entry, ref_cols, row, ctx),
              found.rows != [] do
            found
          end
      end
    after
      :ets.delete(ctx.cache)
    end
  end

  # Own columns of `resource` that point at `target`: `[{column, referenced_column}]`.
  defp referencing_columns(resource, target, entries) do
    for column <- get(resource, :columns) || [],
        {ref_name, ref_col} <- [parse(column)],
        resolved = resolve(ref_name, entries),
        resolved == target,
        do: {to_string(get(column, :name)), ref_col}
  end

  defp group(%{resource: resource} = entry, ref_cols, row, ctx) do
    name = res_name(entry)

    wanted =
      for {col, ref_col} <- ref_cols,
          value = field(row, ref_col),
          value not in [nil, ""],
          do: {col, value}

    result =
      cond do
        wanted == [] -> nil
        Enum.all?(wanted, fn {col, _} -> filterable?(resource, col) end) -> query_referrers(entry, wanted, ctx) || scan_referrers(entry, wanted, ctx)
        true -> scan_referrers(entry, wanted, ctx)
      end

    with {matching, more, checked} <- result do
      shown =
        for r <- Enum.take(matching, @max_referrers) do
          id = row_id(resource, r)
          %{id: to_string(id), label: label(resource, r), path: path(name, id)}
        end

      %{resource: to_string(name), rows: shown, more: more, checked: checked}
    else
      _ -> nil
    end
  end

  # Exact: the store filters each referencing column. nil when the store cannot be trusted to have
  # filtered (a row came back that does not match), so the caller falls back to the scan; :denied
  # surfaces as no group.
  defp query_referrers(entry, wanted, ctx) do
    name = res_name(entry)

    results =
      Enum.map(wanted, fn {col, value} ->
        case safe(fn -> ctx.io.list.(name, %{filter: %{col => value}, limit: @max_referrers + 1}) end, :error) do
          {:ok, %{rows: rows} = result} when is_list(rows) ->
            if Enum.all?(rows, &same?(field(&1, col), value)),
              do: {:ok, rows, result[:total] || length(rows)},
              else: :unfiltered

          _ ->
            :denied
        end
      end)

    cond do
      :denied in results -> {[], 0, nil}
      :unfiltered in results -> nil
      true ->
        rows = results |> Enum.flat_map(fn {:ok, rows, _} -> rows end) |> Enum.uniq_by(&row_id(entry.resource, &1))
        total = results |> Enum.map(fn {:ok, _, total} -> total end) |> Enum.max()
        {rows, max(total - @max_referrers, 0), nil}
    end
  end

  # Bounded: only the first rows of the referencing resource are checked, and the result says so.
  defp scan_referrers(entry, wanted, ctx) do
    case target(entry, ctx) do
      :denied ->
        {[], 0, nil}

      %{rows: rows, complete?: complete?} ->
        matching =
          Enum.filter(rows, fn candidate ->
            Enum.any?(wanted, fn {col, value} -> same?(field(candidate, col), value) end)
          end)

        if complete?,
          do: {matching, max(length(matching) - @max_referrers, 0), nil},
          else: {matching, 0, length(rows)}
    end
  end

  ## ---- components ----

  attr :groups, :list, default: []

  @doc "The 'Referenced by' list of a row drawer. Renders nothing when no row points here."
  def referenced_by_list(assigns) do
    ~H"""
    <div :if={@groups != []} class="space-y-2" data-referenced-by>
      <span class="text-[10px] text-gray-400 uppercase font-semibold tracking-wider">Referenced by</span>
      <div :for={group <- @groups} class="p-2.5 bg-gray-50 rounded-xl border border-gray-100 text-xs space-y-1">
        <div class="font-mono font-semibold text-gray-600"><%= group.resource %></div>
        <div class="flex flex-wrap gap-1.5">
          <.link
            :for={r <- group.rows}
            navigate={r.path}
            class="font-mono text-primary-700 hover:text-primary-900 hover:underline"
          ><%= r.id %><span :if={r.label} class="text-gray-400"> · <%= r.label %></span></.link>
          <span :if={group.more > 0} class="text-gray-400">and <%= group.more %> more</span>
          <span :if={group.checked} class="text-gray-400 italic">first <%= group.checked %> rows checked</span>
        </div>
      </div>
    </div>
    """
  end

  attr :link, :map, default: nil
  attr :value, :any, default: nil

  @doc "A foreign-key value: a link when the row exists, plain text with a muted hint when not."
  def fk_value(%{link: %{status: :found}} = assigns) do
    ~H"""
    <.link
      navigate={@link.path}
      class="inline-flex items-center gap-1 font-mono font-semibold text-primary-700 hover:text-primary-900 hover:underline"
      title={@link.label || "Open #{@value}"}
    >
      <span><%= @value %></span><span class="text-[10px]">↗</span>
    </.link>
    <span :if={@link.label} class="text-[10px] text-gray-400"><%= @link.label %></span>
    """
  end

  def fk_value(%{link: %{status: :missing}} = assigns) do
    ~H"""
    <span class="font-mono font-medium text-gray-800"><%= @value %></span>
    <span
      class="text-[10px] text-gray-400 italic"
      title={"No row in #{@link.resource} where #{@link.column} = #{@value}"}
    >no match</span>
    """
  end

  def fk_value(%{link: %{status: :unchecked}} = assigns) do
    ~H"""
    <span class="font-mono font-medium text-gray-800"><%= @value %></span>
    <span
      class="text-[10px] text-gray-400 italic"
      title={"#{@link.resource} is larger than the first #{@link.limit} rows checked, and #{@link.column} cannot be queried"}
    >first <%= @link.limit %> rows checked</span>
    """
  end

  def fk_value(assigns) do
    ~H"""
    <span class="font-mono font-medium text-gray-800"><%= @value %></span>
    """
  end

  ## ---- registry-backed defaults ----

  defp new_ctx(opts) do
    opts = opts || %{}
    scopes = Map.get(opts, :scopes, [])

    io = %{
      entries: Map.get(opts, :entries, &ExtensionRegistry.all_resources/0),
      list: Map.get(opts, :list, &list(&1, &2, scopes)),
      get: Map.get(opts, :get, &fetch_row_result(&1, &2, scopes))
    }

    %{io: io, cache: :ets.new(:ref_cache, [:set, :private])}
  end

  # The store enforces who may read which resource; its refusal is the viewer's "no".
  defp list(name, params, scopes) do
    payload = Map.merge(%{resource: to_string(name), _auth: %{scopes: scopes}}, params)

    case Exoforge.ActionDispatcher.dispatch(:resource_store, :list, payload, caller_scopes: scopes) do
      {:ok, %{rows: rows} = result} when is_list(rows) -> {:ok, result}
      _ -> :error
    end
  end

  defp fetch_row_result(name, id, scopes) do
    payload = %{resource: to_string(name), id: id, optional: true, _auth: %{scopes: scopes}}

    case Exoforge.ActionDispatcher.dispatch(:resource_store, :get, payload, caller_scopes: scopes) do
      {:ok, %{row: row}} when is_map(row) -> {:ok, row}
      {:ok, _} -> {:ok, nil}
      _ -> :error
    end
  end

  @doc "One row of a resource by primary key, as the viewer may read it, or nil."
  def fetch_row(name, id, scopes) do
    case safe(fn -> fetch_row_result(name, id, scopes) end, :error) do
      {:ok, row} -> row
      _ -> nil
    end
  end

  ## ---- helpers ----

  defp same?(a, b), do: not is_nil(a) and to_string(a) == to_string(b)

  defp filterable?(resource, col) do
    Enum.any?(get(resource, :columns) || [], fn c ->
      to_string(get(c, :name)) == to_string(col) and get(c, :filterable) == true
    end)
  end

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp get(_, _), do: nil

  defp field(row, key) when is_map(row) do
    case Map.fetch(row, key) do
      {:ok, v} ->
        v

      :error ->
        Enum.find_value(row, fn {k, v} -> if to_string(k) == to_string(key), do: v end)
    end
  end

  defp field(_, _), do: nil

  defp table_names(resource) do
    source =
      case get(resource, :source) do
        {:table, t} -> t
        [:table, t] -> t
        ["table", t] -> t
        %{table: t} -> t
        %{"table" => t} -> t
        _ -> nil
      end

    [get(resource, :table), source] |> Enum.reject(&is_nil/1) |> Enum.map(&to_string/1)
  end
end
