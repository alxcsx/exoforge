defmodule Exoforge.Std.Dashboard.ExtensionPresenter do
  @moduledoc """
  Presentation helpers for plugin/extension maps.

  Display names and icons come from the plugin's own metadata: `dashboard_view`
  for plugins with a visual view, or the manifest `title`/`icon` for headless
  plugins. Falls back to a humanized id. There is no central name table.
  """

  @doc "Human-friendly name for an extension map, manifest, id, or nil."
  def display_name(nil), do: ""

  def display_name(%{} = ext) do
    dashboard_view(ext, :title) || Map.get(ext, :title) || humanize(Map.get(ext, :name) || Map.get(ext, :id))
  end

  def display_name(other), do: humanize(other)

  @doc "Icon for an extension map, or the default puzzle piece."
  def icon(%{} = ext), do: dashboard_view(ext, :icon) || Map.get(ext, :icon) || "🧩"
  def icon(_), do: "🧩"

  defp dashboard_view(ext, key) do
    case Map.get(ext, :dashboard_view) do
      %{} = dv -> Map.get(dv, key) || Map.get(dv, to_string(key))
      _ -> nil
    end
  end

  defp humanize(nil), do: ""

  defp humanize(id) do
    id
    |> to_string()
    |> String.replace_prefix("exoforge_std_", "")
    |> String.replace_prefix("Elixir.Exoforge.", "")
    |> String.replace_prefix("Std.Services.", "")
    |> String.replace("_", " ")
    |> Macro.camelize()
  end
end
