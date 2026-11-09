defmodule Exoforge.Std.Dashboard.ExtensionPresenter do
  @moduledoc """
  Presentation helpers for plugin/extension maps.

  Display names and icons come from the plugin's own metadata: `dashboard_view`
  for plugins with a visual view, or the manifest `title`/`icon` for headless
  plugins. Falls back to a humanized id. There is no central name table.
  """

  @view_cache :exo_dashboard_view_modules

  @doc """
  Drops cached view resolutions. Call it when an extension is installed, removed, or reloaded —
  that is the only thing that changes which module a view id resolves to.
  """
  def clear_view_cache do
    ensure_view_cache()
    true = :ets.match_delete(@view_cache, :_)
    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Canonical service key. Metering rows carry the extension id (`exoforge_std_file_bucket`), the
  action catalog carries the contract service (`:file_bucket`); both normalize to the same key.
  """
  def service_key(service) do
    service
    |> to_string()
    |> String.replace_prefix("exoforge_std_", "")
    |> Exoforge.ExtensionRegistry.clean_service_name()
  end

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

  @known_icons %{
    "auth" => "🛡️",
    "exoforge_std_auth" => "🛡️",
    "player_data" => "👤",
    "exoforge_std_player_data" => "👤",
    "database" => "🗄️",
    "exoforge_std_database" => "🗄️",
    "resources" => "🗃️",
    "resource_store" => "🗃️",
    "exoforge_std_resources" => "🗃️",
    "file_bucket" => "📁",
    "exoforge_std_file_bucket" => "📁",
    "ws" => "⚡",
    "exoforge_std_ws" => "⚡",
    "http" => "🌐",
    "exoforge_std_http" => "🌐",
    "extension_manager" => "⚙️",
    "exoforge_std_extension_manager" => "⚙️",
    "metering" => "📈",
    "exoforge_std_metering" => "📈",
    "dashboard" => "🎛️",
    "exoforge_std_dashboard" => "🎛️",
    "dashboard_views" => "🎨",
    "exoforge_std_dashboard_views" => "🎨"
  }

  @categories [
    {"all", "All Extensions", "🌐"},
    {"gameplay", "Gameplay", "🎮"},
    {"players", "Players", "👤"},
    {"storage", "Storage", "🗄️"},
    {"network", "Network", "🔌"},
    {"system", "System", "⚙️"}
  ]

  @doc "Standardized taxonomy of extension categories."
  def standard_categories, do: @categories

  @doc "Normalizes any raw or legacy category string into the standard taxonomy."
  def normalize_category(category) do
    case String.downcase(to_string(category || "")) do
      cat when cat in ["gameplay", "game", "combat", "sandbox"] -> "Gameplay"
      cat when cat in ["players", "player", "player_data", "identity", "auth", "data", "users"] -> "Players"
      cat when cat in ["storage", "database", "resource_store", "resources", "file_bucket", "files", "store"] -> "Storage"
      cat when cat in ["network", "networking", "ingress", "gateway", "http", "ws", "websocket", "api"] -> "Network"
      cat when cat in ["system", "management", "operations", "metering", "studio", "tools", "core", "views"] -> "System"
      "" -> "Gameplay"
      other -> String.capitalize(other)
    end
  end

  @doc "Returns the standardized category emoji icon."
  def category_icon(category) do
    case normalize_category(category) do
      "Gameplay" -> "🎮"
      "Players" -> "👤"
      "Storage" -> "🗄️"
      "Network" -> "🔌"
      "System" -> "⚙️"
      _ -> "🧩"
    end
  end

  @doc "Default icon for an extension based on its id or category."
  def default_icon_for(%{} = ext) do
    id = to_string(Map.get(ext, :id) || Map.get(ext, :name) || "")
    clean_id = id |> String.replace_prefix("exoforge_std_", "") |> String.downcase()
    category = Map.get(ext, :category)

    Map.get(@known_icons, id) ||
      Map.get(@known_icons, clean_id) ||
      (category && category_icon(category)) ||
      "🎮"
  end

  def default_icon_for(id_or_name) do
    str = to_string(id_or_name || "")
    clean = str |> String.replace_prefix("exoforge_std_", "") |> String.downcase()
    Map.get(@known_icons, str) || Map.get(@known_icons, clean) || "🎮"
  end

  @doc "Icon for an extension map, or the standardized default."
  def icon(%{} = ext) do
    raw = dashboard_view(ext, :icon) || Map.get(ext, :icon)
    if is_binary(raw) and raw not in ["", "🧩"], do: raw, else: default_icon_for(ext)
  end

  def icon(id_or_name), do: default_icon_for(id_or_name)

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
            cached_view(lookup_id, fn -> resolve_view_service(lookup_id) end)

          true ->
            nil
        end
    end
  end

  defp resolve_view_service(lookup_id) do
    case Exoforge.ActionDispatcher.dispatch_internal(:dashboard_view, :resolve_view, %{id: lookup_id}) do
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
  end

  # Resolving a view is a module lookup, but it travels the :dashboard_view contract, so an
  # uncached call is a full action dispatch: metering, an event broadcast, and a log append. The
  # Studio rebuilt its extension list every five seconds and paid that per extension; the answer
  # only changes when extensions are installed or removed, so it is cached until they are.
  defp cached_view(lookup_id, resolve) do
    key = lookup_id |> to_string()

    case :ets.lookup(ensure_view_cache(), key) do
      [{^key, mod}] ->
        mod

      [] ->
        mod = resolve.()
        :ets.insert(@view_cache, {key, mod})
        mod
    end
  rescue
    # The table is owned by whichever process created it; a lookup on a dead table just resolves.
    _ -> resolve.()
  end

  defp ensure_view_cache do
    case :ets.whereis(@view_cache) do
      :undefined ->
        try do
          :ets.new(@view_cache, [:named_table, :public, :set, read_concurrency: true])
        rescue
          _ -> @view_cache
        end

      _ ->
        @view_cache
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
