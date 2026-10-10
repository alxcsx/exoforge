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

  @doc """
  Resolves the LiveView/LiveComponent an extension renders its controls with: an explicit
  `:module`, the `:dashboard_view` service contract, or the conventional module name.
  """
  def view_module(ext) do
    cond do
      is_map(ext) and Map.has_key?(ext, :custom_view_module) and
          not is_nil(ext[:custom_view_module]) ->
        ext[:custom_view_module]

      true ->
        resolve_view_module(ext)
    end
  end

  @doc "Icon for an extension map, or the default puzzle piece."
  def icon(%{} = ext), do: dashboard_view(ext, :icon) || Map.get(ext, :icon) || "🧩"
  def icon(_), do: "🧩"

  defp dashboard_view(ext, key) do
    case Map.get(ext, :dashboard_view) do
      %{} = dv -> Map.get(dv, key) || Map.get(dv, to_string(key))
      _ -> nil
    end
  end

  defp resolve_view_module(ext) do
    cond do
      is_map(ext) and Map.has_key?(ext, :custom_view_module) and
          not is_nil(ext[:custom_view_module]) ->
        ext[:custom_view_module]

      true ->
        do_resolve_view_module(ext)
    end
  end

  defp do_resolve_view_module(ext) do
    dv = (is_map(ext) && (ext[:dashboard_view] || ext["dashboard_view"])) || nil

    cond do
      is_map(dv) and is_atom(dv[:module]) and Code.ensure_loaded?(dv[:module]) ->
        dv[:module]

      is_map(dv) and is_binary(dv[:module]) and Code.ensure_loaded?(safe_to_atom(dv[:module])) ->
        safe_to_atom(dv[:module])

      true ->
        lookup_id =
          (is_map(dv) && (dv[:id] || dv["id"])) || (is_map(ext) && (ext[:id] || ext["id"]))

        # Check if the plugin module itself defines a DashboardView or View sub-module convention
        plugin_mod = (is_map(ext) && (ext[:entry_point] || ext["entry_point"])) || nil
        plugin_view =
          if is_atom(plugin_mod) and Code.ensure_loaded?(plugin_mod) do
            cond do
              Code.ensure_loaded?(Module.concat(plugin_mod, DashboardView)) ->
                Module.concat(plugin_mod, DashboardView)

              Code.ensure_loaded?(Module.concat(plugin_mod, View)) ->
                Module.concat(plugin_mod, View)

              true ->
                nil
            end
          else
            nil
          end

        cond do
          plugin_view != nil ->
            plugin_view

          lookup_id != nil ->
            case Exoforge.ActionDispatcher.dispatch(:dashboard_view, :resolve_view, %{id: lookup_id}) do
              {:ok, %{module: mod}} when is_atom(mod) and not is_nil(mod) ->
                if Code.ensure_loaded?(mod), do: mod, else: nil

              _ ->
                clean_name =
                  lookup_id
                  |> to_string()
                  |> String.replace_prefix("exoforge_std_", "")
                  |> Macro.camelize()

                mod = Module.concat([Exoforge.Std.DashboardViews, clean_name <> "View"])
                if Code.ensure_loaded?(mod), do: mod, else: nil
            end

          true ->
            nil
        end
    end
  end

  defp safe_to_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    _ -> nil
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
