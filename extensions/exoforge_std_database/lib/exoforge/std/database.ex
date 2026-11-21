defmodule Exoforge.Std.Database do
  @moduledoc """
  Standard database extension for Exoforge: the SQL helper over the `lldb` driver layer (ADR 005).

  Provides the `:database` service contract. It reaches the engine only through the `:lldb` service,
  so it names no engine. Each extension's tables live in its own isolated namespace, so a query sees
  only the caller's own tables; a table it cannot see comes back with a hint pointing at the owning
  extension's action (for example a `get_many`) or a generated typed stub.

  ### How it works
  - Statements go through `ActionDispatcher.dispatch_internal(:lldb, ...)`, and this module never names a driver.
  - `Exoforge.Std.Database.Store` classifies each table as a key-value document table, a typed resource table, or a missing declared resource, and plans SQL from `Exoforge.Std.Database.Dialect`.
  - Key-value helpers create the document table on first use, and batch operations run as one transaction.
  - A DDL statement forgets the cached table kind in `Exoforge.Std.Database.KindCache`, whose entries expire after five seconds.
  - Schema planning is a dry run that reports what a declared resource would do without applying anything.
  - Resetting an extension drops its whole namespace through `:lldb`.

  ### Depends on
  `:lldb`.
  """
  use Exoforge.Extension, provides: [:database]

  @manifest %{
    category: "Storage",
    system: true,
    title: "Database",
    icon: "🗄️",
    dashboard_view: nil,
    dependencies: [Exoforge.Std.Services.Lldb]
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.{Include, KindCache, Store}

  def children, do: [KindCache]

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction execute(payload) do
    plugin = extract_plugin(payload)
    operation = extract_operation(payload)
    arguments = extract_arguments(payload)

    with {:ok, columns} <- Include.parse(fetch_any(payload, [:include], nil)),
         {:ok, plans} <- plan_includes(plugin, operation, columns) do
      result =
        case operation do
          %{} = command -> Store.run(plugin, command)
          _ ->
            result = lldb(:exec, %{namespace: plugin, operation: operation, arguments: arguments})
            if ddl?(operation), do: KindCache.forget(plugin)
            result
        end

      case result do
        {:ok, rows} when is_list(rows) -> with_included({:ok, %{rows: rows}}, plans)
        {:ok, %{rows: rows} = res} when plans != [] and is_list(rows) -> with_included({:ok, res}, plans)
        res -> res
      end
    end
  end

  @impl true
  defaction table_columns(payload) do
    plugin = extract_plugin(payload)
    table = fetch_any(payload, [:table, "table"], "")

    lldb(:table_columns, %{namespace: plugin, table: table})
  end

  @doc "Dry-run schema planner for an extension's declared resources (staff/studio scope, applies nothing)."
  defaction plan_schema(payload), scope: :studio do
    plugin = fetch_any(payload, [:extension, :plugin, :id, :namespace], :default)
    lldb(:plan_schema, %{namespace: plugin, resources: fetch_any(payload, [:resources], nil)})
  end

  ## ---- DIRECT ELIXIR FACADE ----

  @doc "Direct helper to execute a query against a plugin's isolated database."
  def execute(plugin, query, args \\ [])
  def execute(plugin, %{} = command, _args), do: Store.run(plugin, command)

  def execute(plugin, query, args) do
    result = lldb(:exec, %{namespace: plugin, operation: query, arguments: args})
    if ddl?(query), do: KindCache.forget(plugin)
    result
  end

  @doc "Direct helper to reset/clear a plugin's database."
  def reset!(plugin) do
    KindCache.forget(plugin)
    lldb(:drop_namespace, %{namespace: plugin})
  end

  @doc "Key-value helper: put document into plugin's database."
  def put(plugin, table, id, data) do
    exec(plugin, %{action: :put, table: table, id: id, data: data})
  end

  @doc "Key-value helper: get document from plugin's database."
  def get(plugin, table, id) do
    case exec(plugin, %{action: :get, table: table, id: id}) do
      {:ok, %{rows: [record]}} -> {:ok, record}
      {:ok, %{rows: []}} -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Key-value helper: delete document from plugin's database."
  def delete(plugin, table, id) do
    exec(plugin, %{action: :delete, table: table, id: id})
  end

  @doc "Key-value helper: retrieve all documents from table."
  def all(plugin, table) do
    case exec(plugin, %{action: :all, table: table}) do
      {:ok, %{rows: rows}} -> {:ok, rows}
      error -> error
    end
  end

  @doc "Executes an ordered list of write operations atomically in a single transaction."
  def batch(plugin, operations) when is_list(operations) do
    exec(plugin, %{action: :batch, operations: operations})
  end

  ## ---- PRIVATE HELPERS ----

  defp exec(plugin, command), do: Store.run(plugin, command)

  defp plan_includes(_plugin, _operation, []), do: {:ok, []}

  defp plan_includes(plugin, operation, columns) do
    root_table =
      case operation do
        %{} = command -> fetch_any(command, [:table], nil) |> then(&(&1 && to_string(&1)))
        sql -> Include.table_of_sql(sql)
      end

    Include.plan(plugin, root_table, columns)
  end

  # `included` rides next to `rows`; a warning (a reference to a resource nobody deploys) never fails the query.
  defp with_included(result, []), do: result

  defp with_included({:ok, %{rows: rows} = res}, plans) do
    {included, warnings} = Include.fetch(plans, rows)
    res = Map.put(res, :included, included)
    {:ok, if(warnings == [], do: res, else: Map.put(res, :warnings, warnings))}
  end

  # A statement that changes tables: what this extension remembers about them is stale.
  defp ddl?(query) when is_binary(query), do: Regex.match?(~r/^\s*(create|alter|drop|truncate)\b/i, query)
  defp ddl?(_), do: false

  defp lldb(action, payload), do: ActionDispatcher.dispatch_internal(:lldb, action, payload)

  defp fetch_any(map, keys, default) when is_map(map) do
    Enum.find_value(keys, default, fn k ->
      Map.get(map, k) || Map.get(map, to_string(k))
    end)
  end

  defp fetch_any(_, _, default), do: default

  defp extract_plugin(p), do: fetch_any(p, [:extension, :plugin, :namespace], :default)
  defp extract_operation(p) when is_binary(p), do: p
  defp extract_operation(p), do: fetch_any(p, [:operation, :query, :sql], "")
  defp extract_arguments(p), do: fetch_any(p, [:arguments, :params, :args], [])
end
