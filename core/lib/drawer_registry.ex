defmodule Exoforge.DrawerRegistry do
  @moduledoc """
  Registry for resource inspector side-drawers and their tabs.

  Core and extension plugins contribute tabs into any resource's inspector
  drawer. Tab definitions come from two places, merged here:

    * explicit `register_tab/3` calls (runtime overrides), and
    * a resource's `drawer([...])` declaration in its contract metadata.

  The kernel does not hardcode any product-specific tabs; a tab without an
  explicit label gets one derived from its id.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    initialize_ets()
    {:ok, %{}}
  end

  def initialize_ets do
    case :ets.info(:exo_drawer_tabs_mem) do
      :undefined ->
        :ets.new(:exo_drawer_tabs_mem, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ets.delete_all_objects(:exo_drawer_tabs_mem)
    end

    :ok
  end

  @doc "Registers or overrides a tab definition for a specific resource."
  def register_tab(resource, tab_id, tab_spec \\ %{}) when is_atom(resource) and is_atom(tab_id) do
    spec =
      tab_id
      |> default_spec()
      |> Map.merge(tab_spec)
      |> Map.put(:id, tab_id)
      |> Map.put(:resource, resource)

    :ets.insert(:exo_drawer_tabs_mem, {{resource, tab_id}, spec})
    :ok
  end

  @doc "Unregisters a tab from a resource."
  def unregister_tab(resource, tab_id) when is_atom(resource) and is_atom(tab_id) do
    :ets.delete(:exo_drawer_tabs_mem, {resource, tab_id})
    :ok
  end

  @doc """
  Lists all tabs for a resource, combining explicitly registered tabs with tabs
  declared in the resource's `drawer([...])` metadata, sorted ascending by order.
  """
  def list_tabs(resource) when is_atom(resource) or is_binary(resource) do
    resource_atom = if is_binary(resource), do: String.to_atom(resource), else: resource

    registered_tabs =
      case :ets.info(:exo_drawer_tabs_mem) do
        :undefined ->
          []

        _ ->
          :ets.match_object(:exo_drawer_tabs_mem, {{resource_atom, :_}, :_})
          |> Enum.map(fn {_key, spec} -> spec end)
      end

    registered_ids = MapSet.new(registered_tabs, & &1.id)

    declared_tabs =
      resource_atom
      |> declared_tab_ids()
      |> Enum.reject(&MapSet.member?(registered_ids, &1))
      |> Enum.map(fn tab_id -> Map.put(default_spec(tab_id), :resource, resource_atom) end)

    (registered_tabs ++ declared_tabs)
    |> Enum.sort_by(&Map.get(&1, :order, 100))
  end

  defp declared_tab_ids(resource) do
    case Exoforge.PluginRegistry.fetch_resource(resource) do
      {:ok, %{resource: %{drawer: tabs}}} when is_list(tabs) -> tabs
      _ -> []
    end
  end

  defp default_spec(tab_id) do
    %{
      id: tab_id,
      label: tab_id |> to_string() |> String.replace("_", " ") |> String.capitalize(),
      order: 100,
      view_type: :declarative
    }
  end
end
