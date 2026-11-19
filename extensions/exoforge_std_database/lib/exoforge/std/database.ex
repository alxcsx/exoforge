defmodule Exoforge.Std.Database do
  @moduledoc """
  Standard database extension for Exoforge: the SQL helper over the `lldb` driver layer (ADR 005).

  Provides the `:database` service contract. It reaches the engine only through the `:lldb` service,
  so it names no engine. Each extension's tables live in its own isolated namespace, so a query sees
  only the caller's own tables; a table it cannot see comes back with a hint pointing at the owning
  extension's action (for example a `get_many`) or a generated typed stub.
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
  alias Exoforge.Std.Database.Store

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction execute(payload) do
    plugin = extract_plugin(payload)
    operation = extract_operation(payload)
    arguments = extract_arguments(payload)

    result =
      case operation do
        %{} = command -> Store.run(plugin, command)
        _ -> lldb(:exec, %{namespace: plugin, operation: operation, arguments: arguments})
      end

    case result do
      {:ok, rows} when is_list(rows) -> {:ok, %{rows: rows}}
      res -> res
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
    lldb(:exec, %{namespace: plugin, operation: query, arguments: args})
  end

  @doc "Direct helper to reset/clear a plugin's database."
  def reset!(plugin) do
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
