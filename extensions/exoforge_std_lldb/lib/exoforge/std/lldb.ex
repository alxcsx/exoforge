defmodule Exoforge.Std.Lldb do
  @moduledoc """
  Standard low-level database driver extension for Exoforge (ADR 005).

  Owns everything specific to one database engine: connections and pools, an isolated namespace per
  extension, roles and grants, transactions, catalog introspection and health. The official
  implementation is PostgreSQL. The `lldb` service contract does not name the engine: it speaks of
  namespaces, and the engine-specific words stay in the adapter behind it.

  The `database` extension is the SQL helper on top of this one, and `resource_store` the ORM on top of that.
  """
  use Exoforge.Extension, provides: [:lldb]

  @manifest %{
    category: "Storage",
    system: true,
    title: "Database Driver",
    icon: "🗄️",
    dashboard_view: nil,
    ui_hooks: %{
      settings: [
        %{id: :database, title: "Database Engine", icon: "🗄️", order: 20}
      ]
    }
  }

  alias Exoforge.Std.Lldb.Manager

  @doc """
  SQL-safe identifier for a plugin, used for the namespace names of the engine.

  Shared by the manager and the adapter, so a plugin's storage always maps to the same names.
  """
  def clean_id(plugin_id) when is_binary(plugin_id) do
    plugin_id
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.downcase()
  end

  def clean_id(plugin_id) when is_atom(plugin_id) or is_integer(plugin_id),
    do: clean_id(to_string(plugin_id))

  # Callers are extensions, so a missing payload field can arrive as nil or a map. That is not a
  # plugin name, and `to_string/1` on it would raise inside the Manager and take the Manager down.
  def clean_id(_), do: "default"

  # A missing table is the common cross-extension mistake, and the fix is never more SQL: the
  # adapter appends this so the failure explains itself.
  @cross_extension_hint " Tables are private to each extension; to read another extension's data, call its action (e.g. a get_many) or use a generated typed stub."

  @doc "The hint appended when a query's table is missing."
  def cross_extension_hint, do: @cross_extension_hint

  def children do
    [
      # Named pools live here (M33 Fix 8): one supervisor to restart a pool that drops, one unique
      # registry to name them. Both die with the extension, which is the lifecycle owner.
      {Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry},
      {DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one},
      Manager
    ]
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction exec(payload) do
    Manager.execute(extract_namespace(payload), extract_operation(payload), extract_arguments(payload))
  end

  @impl true
  defaction provision_namespace(payload) do
    Manager.ensure_database(extract_namespace(payload))
  end

  @impl true
  defaction drop_namespace(payload) do
    Manager.reset(extract_namespace(payload))
  end

  @impl true
  defaction table_columns(payload) do
    namespace = extract_namespace(payload)
    table = fetch_any(payload, [:table, "table"], "")

    case Manager.table_columns(namespace, table) do
      {:ok, columns} -> {:ok, %{columns: columns}}
      error -> error
    end
  end

  @impl true
  defaction transaction(payload) do
    statements =
      payload
      |> fetch_any([:statements], [])
      |> Enum.map(fn
        {sql, args} -> {sql, args}
        %{} = st -> {fetch_any(st, [:sql], ""), fetch_any(st, [:args, :arguments, :params], [])}
      end)

    Manager.transaction(extract_namespace(payload), statements)
  end

  @impl true
  defaction introspect(payload) do
    Manager.introspect(extract_namespace(payload), fetch_any(payload, [:table, "table"], ""))
  end

  @impl true
  defaction dialect(), scope: :global do
    Manager.dialect()
  end

  @doc "Dry-run schema planner for an extension's declared resources (staff/studio scope, applies nothing)."
  defaction plan_schema(payload), scope: :studio do
    namespace = fetch_any(payload, [:namespace, :extension, :plugin, :id], :default)
    Manager.plan_schema(namespace, fetch_any(payload, [:resources], nil))
  end

  @impl true
  defaction apply_schema(payload) do
    Manager.apply_schema(
      extract_namespace(payload),
      fetch_any(payload, [:resources], nil),
      fetch_any(payload, [:migrations], nil),
      fetch_any(payload, [:version], nil)
    )
  end

  @impl true
  defaction run_migrations(payload) do
    Manager.run_migrations(extract_namespace(payload), fetch_any(payload, [:migrations], []))
  end

  @impl true
  defaction reset_table(payload) do
    Manager.reset_table(extract_namespace(payload), fetch_any(payload, [:table, "table"], ""))
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
  defaction health_check(), scope: :global do
    case Manager.health_check() do
      {:ok, %{status: status}} ->
        {:ok, %{status: status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## ---- PRIVATE HELPERS ----

  defp fetch_any(map, keys, default) when is_map(map) do
    Enum.find_value(keys, default, fn k ->
      Map.get(map, k) || Map.get(map, to_string(k))
    end)
  end

  defp fetch_any(_, _, default), do: default

  defp extract_namespace(p), do: fetch_any(p, [:namespace, :extension, :plugin], :default)
  defp extract_operation(p) when is_binary(p), do: p
  defp extract_operation(p), do: fetch_any(p, [:operation, :query, :sql], "")
  defp extract_arguments(p), do: fetch_any(p, [:arguments, :params, :args], [])
end
