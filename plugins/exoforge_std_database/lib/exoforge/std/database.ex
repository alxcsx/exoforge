defmodule Exoforge.Std.Database do
  @moduledoc """
  Standard database plugin for Exoforge.
  Provides the :database and :lldb service contracts.
  Acts as the middleground between PostgreSQL and all other plugins,
  ensuring complete per-plugin multi-tenant isolation.
  """
  use Exoforge.Plugin, provides: [:database, :lldb]

  @manifest %{
    category: "Storage",
    system: true,
    dashboard_view: nil,
    ui_hooks: %{
      settings: [
        %{id: :database, title: "Database Engine", icon: "🗄️", order: 20}
      ]
    }
  }

  alias Exoforge.Std.Database.Manager

  def children do
    [
      Manager
    ]
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction execute(payload) do
    plugin = extract_plugin(payload)
    operation = extract_operation(payload)
    arguments = extract_arguments(payload)

    case Manager.execute(plugin, operation, arguments) do
      {:ok, rows} when is_list(rows) -> {:ok, %{rows: rows}}
      res -> res
    end
  end

  @impl true
  defaction connection_config(payload) do
    namespace =
      case payload do
        %{namespace: ns} when is_binary(ns) or is_atom(ns) -> ns
        %{"namespace" => ns} when is_binary(ns) or is_atom(ns) -> ns
        _ -> :default
      end

    case Manager.connection_config(namespace) do
      {:ok, config} ->
        {:ok,
         %{
           url: config.url,
           pool_size: config.pool_size,
           driver: config.driver
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  defaction health_check() do
    case Manager.health_check() do
      {:ok, %{status: status}} ->
        {:ok, %{status: status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## ---- DIRECT ELIXIR FACADE ----

  @doc "Direct helper to execute a query against a plugin's isolated database."
  def execute(plugin, query, args \\ []) do
    Manager.execute(plugin, query, args)
  end

  @doc "Direct helper to ensure a plugin's database exists."
  def ensure_database(plugin) do
    Manager.ensure_database(plugin)
  end

  @doc "Direct helper to retrieve connection details for a plugin."
  def get_connection_config(plugin) do
    Manager.connection_config(plugin)
  end

  @doc "Direct helper to reset/clear a plugin's database."
  def reset!(plugin) do
    Manager.reset(plugin)
  end

  @doc "Key-value helper: put document into plugin's database."
  def put(plugin, table, id, data) do
    Manager.execute(plugin, %{action: :put, table: table, id: id, data: data})
  end

  @doc "Key-value helper: get document from plugin's database."
  def get(plugin, table, id) do
    case Manager.execute(plugin, %{action: :get, table: table, id: id}) do
      {:ok, %{rows: [record]}} -> {:ok, record}
      {:ok, %{rows: []}} -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Key-value helper: delete document from plugin's database."
  def delete(plugin, table, id) do
    Manager.execute(plugin, %{action: :delete, table: table, id: id})
  end

  @doc "Key-value helper: retrieve all documents from table."
  def all(plugin, table) do
    case Manager.execute(plugin, %{action: :all, table: table}) do
      {:ok, %{rows: rows}} -> {:ok, rows}
      error -> error
    end
  end

  ## ---- PRIVATE HELPERS ----

  defp fetch_any(map, keys, default) when is_map(map) do
    Enum.find_value(keys, default, fn k ->
      Map.get(map, k) || Map.get(map, to_string(k))
    end)
  end

  defp fetch_any(_, _, default), do: default

  defp extract_plugin(p), do: fetch_any(p, [:plugin, :namespace], :default)
  defp extract_operation(p) when is_binary(p), do: p
  defp extract_operation(p), do: fetch_any(p, [:operation, :query, :sql], "")
  defp extract_arguments(p), do: fetch_any(p, [:arguments, :params, :args], [])
end
