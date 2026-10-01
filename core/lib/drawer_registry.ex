defmodule Exoforge.DrawerRegistry do
  @moduledoc """
  Registry for resource inspector side-drawers and their tabs.
  Allows core and extension plugins to contribute tabs into any resource's inspector drawer.
  """
  use GenServer

  @default_tab_defs %{
    overview: %{id: :overview, label: "Overview & Stats", order: 10, view_type: :declarative},
    attributes: %{id: :attributes, label: "Attributes", order: 20, view_type: :declarative},
    transactions: %{id: :transactions, label: "Transactions & Ledger", order: 30, view_type: :declarative},
    inventory: %{id: :inventory, label: "Inventory & Items", order: 40, view_type: :declarative},
    sessions: %{id: :sessions, label: "Logins & Sessions", order: 50, view_type: :declarative},
    events: %{id: :events, label: "Real-Time Event Log", order: 60, view_type: :declarative},
    moderation: %{id: :moderation, label: "Moderation & Notes", order: 70, view_type: :declarative}
  }

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
        :exo_drawer_tabs_mem
    end
    :ok
  end

  @doc """
  Registers or overrides a tab definition for a specific resource.
  """
  def register_tab(resource, tab_id, tab_spec \\ %{}) when is_atom(resource) and is_atom(tab_id) do
    default_spec = Map.get(@default_tab_defs, tab_id, %{
      id: tab_id,
      label: Macro.to_string(tab_id) |> String.replace("_", " ") |> String.capitalize(),
      order: 100,
      view_type: :declarative
    })

    spec =
      default_spec
      |> Map.merge(tab_spec)
      |> Map.put(:id, tab_id)
      |> Map.put(:resource, resource)

    :ets.insert(:exo_drawer_tabs_mem, {{resource, tab_id}, spec})
    :ok
  end

  @doc """
  Unregisters a tab from a resource.
  """
  def unregister_tab(resource, tab_id) when is_atom(resource) and is_atom(tab_id) do
    :ets.delete(:exo_drawer_tabs_mem, {resource, tab_id})
    :ok
  end

  @doc """
  Retrieves a specific tab for a resource.
  """
  def get_tab(resource, tab_id) when is_atom(resource) and is_atom(tab_id) do
    case :ets.lookup(:exo_drawer_tabs_mem, {resource, tab_id}) do
      [{{^resource, ^tab_id}, spec}] -> spec
      [] -> Map.get(@default_tab_defs, tab_id)
    end
  end

  @doc """
  Lists all tabs for a given resource, combining registered tabs with declared resource tabs.
  Returns tabs sorted ascending by order.
  """
  def list_tabs(resource) when is_atom(resource) or is_binary(resource) do
    resource_atom = if is_binary(resource), do: String.to_atom(resource), else: resource

    # 1. Fetch explicitly registered tabs from ETS
    registered_tabs =
      case :ets.info(:exo_drawer_tabs_mem) do
        :undefined ->
          []

        _ ->
          :ets.match_object(:exo_drawer_tabs_mem, {{resource_atom, :_}, :_})
          |> Enum.map(fn {_key, spec} -> spec end)
      end

    registered_ids = MapSet.new(Enum.map(registered_tabs, & &1.id))

    # 2. Check declared drawer tabs from resource metadata in PluginRegistry
    declared_tab_ids =
      case Exoforge.PluginRegistry.fetch_resource(resource_atom) do
        {:ok, %{resource: %{drawer: tabs}}} when is_list(tabs) -> tabs
        _ -> []
      end

    declared_tabs =
      declared_tab_ids
      |> Enum.reject(&MapSet.member?(registered_ids, &1))
      |> Enum.map(fn tab_id ->
        default_spec = Map.get(@default_tab_defs, tab_id, %{
          id: tab_id,
          label: Macro.to_string(tab_id) |> String.replace("_", " ") |> String.capitalize(),
          order: 100,
          view_type: :declarative
        })
        Map.put(default_spec, :resource, resource_atom)
      end)

    all_tabs = registered_tabs ++ declared_tabs

    final_tabs =
      if Enum.empty?(all_tabs) and resource_atom in [:players, :users] do
        @default_tab_defs
        |> Map.values()
        |> Enum.map(&Map.put(&1, :resource, resource_atom))
      else
        all_tabs
      end

    final_tabs
    |> Enum.sort_by(&Map.get(&1, :order, 100))
  end
end
