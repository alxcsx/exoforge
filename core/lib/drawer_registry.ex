defmodule Exoforge.DrawerRegistry do
  @moduledoc """
  Compatibility layer delegating resource inspector side-drawers to `Exoforge.UIHookRegistry`.

  Eliminates redundant ETS storage by sharing `:exo_ui_hooks_mem` with the unified UI hook engine.
  """
  use GenServer
  alias Exoforge.UIHookRegistry

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    UIHookRegistry.initialize_ets()
    {:ok, %{}}
  end

  def initialize_ets, do: UIHookRegistry.initialize_ets()

  @doc "Registers or overrides a tab definition for a specific resource."
  def register_tab(resource, tab_id, tab_spec \\ %{}) when is_atom(resource) and is_atom(tab_id) do
    UIHookRegistry.register_hook(resource, tab_id, tab_spec)
  end

  @doc "Unregisters a tab from a resource."
  def unregister_tab(resource, tab_id) when is_atom(resource) and is_atom(tab_id) do
    UIHookRegistry.unregister_hook(resource, tab_id)
  end

  @doc """
  Lists all tabs for a resource, combining explicitly registered tabs with tabs
  declared in the resource's `drawer([...])` metadata, sorted ascending by order.
  """
  def list_tabs(resource) when is_atom(resource) or is_binary(resource) do
    resource_atom = if is_binary(resource), do: String.to_atom(resource), else: resource

    registered_tabs = UIHookRegistry.list_hooks(resource_atom)
    registered_ids = MapSet.new(registered_tabs, & &1.id)

    declared_tabs =
      resource_atom
      |> declared_tab_ids()
      |> Enum.reject(&MapSet.member?(registered_ids, &1))
      |> Enum.map(fn tab_id ->
        tab_id
        |> default_spec()
        |> Map.put(:resource, resource_atom)
      end)

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
    title = tab_id |> to_string() |> String.replace("_", " ") |> String.capitalize()

    %{
      id: tab_id,
      title: title,
      label: title,
      order: 100,
      view_type: :declarative
    }
  end
end
