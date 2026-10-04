defmodule Exoforge.DrawerRegistry do
  @moduledoc """
  Resource inspector side-drawers.

  Merges hooks declared for a resource with the tabs a resource declares via
  `drawer([...])` metadata, sorted ascending by order. Binary resource names are
  resolved through `Exoforge.PluginRegistry` (never `String.to_atom/1`), so an
  unknown name from a URL cannot grow the atom table.
  """
  alias Exoforge.UIHookRegistry

  @doc "Lists all tabs for a resource (declared + hooked), sorted by order."
  def list_tabs(resource) when is_atom(resource) do
    do_list_tabs(resource)
  end

  def list_tabs(resource) when is_binary(resource) do
    case Exoforge.PluginRegistry.fetch_resource(resource) do
      {:ok, %{resource: %{name: name}}} -> do_list_tabs(name)
      _ -> []
    end
  end

  defp do_list_tabs(resource_atom) do
    hooked = UIHookRegistry.list_hooks(resource_atom)
    hooked_ids = MapSet.new(hooked, & &1.id)

    declared =
      resource_atom
      |> declared_tab_ids()
      |> Enum.reject(&MapSet.member?(hooked_ids, &1))
      |> Enum.map(fn tab_id -> Map.put(default_spec(tab_id), :resource, resource_atom) end)

    (hooked ++ declared)
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

    %{id: tab_id, title: title, label: title, order: 100}
  end
end
