defmodule Exoforge.UIHookRegistry do
  @moduledoc """
  Read-only registry of UI hooks declared by plugins in their manifest.

  Plugins contribute dashboard, settings, and inspector UI through the `ui_hooks`
  map on their manifest. Hooks are resolved live from `Exoforge.PluginRegistry`,
  so unloading a plugin removes its hooks with no extra bookkeeping.

  Hook points:
    * `:overview_metric` - KPI cards on the Overview tab.
    * `:overview_widget` - Full widgets on the Overview tab.
    * `:settings` - Tabs in the Project Settings modal.
    * `:player_inspect` - Tabs in the Player Profile inspector drawer.
    * `:user_inspect` - Tabs in the user (account) inspector drawer. A spec may carry a
      `:module` (a LiveComponent) that renders the tab body.
    * `:resource_column` - Rendering for a resource column `role` (e.g. `"user_id"`). A spec
      carries the `role`, plus `target`/`focus` for a deep link into another tab.
    * Custom domain hook points.
  """

  @doc "Lists all hooks declared for a hook point, sorted ascending by order."
  def list_hooks(hook_point) do
    target = to_string(hook_point)

    Exoforge.PluginRegistry.all_manifests()
    |> Enum.flat_map(fn manifest ->
      manifest
      |> Map.get(:ui_hooks, %{})
      |> Enum.flat_map(fn {point, specs} ->
        if to_string(point) == target do
          specs
          |> List.wrap()
          |> Enum.map(&normalize_spec(&1, manifest.id))
        else
          []
        end
      end)
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.order)
  end

  defp normalize_spec(spec, plugin_id) do
    spec = if is_map(spec), do: spec, else: %{id: spec}
    id = Map.get(spec, :id) || Map.get(spec, "id")

    spec
    |> default_spec(id)
    |> Map.put(:id, id)
    |> Map.put(:plugin_id, plugin_id)
  end

  defp default_spec(spec, id) do
    title = Map.get(spec, :title) || Map.get(spec, :label) || humanize(id)

    Map.merge(%{title: title, label: title, icon: "🔌", order: 100}, spec)
  end

  defp humanize(id), do: id |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
