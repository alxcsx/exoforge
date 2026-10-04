defmodule Exoforge.Std.Dashboard.Extensions do
  @moduledoc """
  Dashboard-facing shaping of plugin manifests.

  Turns registry manifests into the extension summaries the Studio renders (actions,
  resources, events, dashboard view, trap stats). This lives here rather than in the kernel
  so the kernel stays free of dashboard concerns — a different dashboard implementation can
  shape manifests its own way.
  """

  alias Exoforge.PluginRegistry

  @doc "Returns structured extensions summary for the Producer Studio dashboard."
  def dashboard_extensions do
    PluginRegistry.all_manifests()
    |> Enum.map(fn manifest ->
      provides = Map.get(manifest, :provides, [])
      clean_provides = Enum.map(provides, &PluginRegistry.clean_service_name/1)
      clean_dependencies = Enum.map(Map.get(manifest, :dependencies, []), &PluginRegistry.clean_service_name/1)

      services = Enum.map(PluginRegistry.manifest_services(manifest), &normalize_service_metadata/1)

      category = Map.get(manifest, :category) || "Extension"

      stats =
        if Code.ensure_loaded?(Exoforge.Drivers.Runtime.WasmPluginRunner) and
             function_exported?(Exoforge.Drivers.Runtime.WasmPluginRunner, :get_stats, 1) do
          Exoforge.Drivers.Runtime.WasmPluginRunner.get_stats(manifest.id)
        else
          %{traps_count: 0, last_trap: nil}
        end

      dashboard_view =
        cond do
          Map.get(manifest, :dashboard_view) ->
            Map.get(manifest, :dashboard_view)

          is_atom(manifest.entry_point) and Code.ensure_loaded?(manifest.entry_point) and
              function_exported?(manifest.entry_point, :dashboard_view, 0) ->
            manifest.entry_point.dashboard_view()

          is_atom(manifest.entry_point) and Code.ensure_loaded?(manifest.entry_point) and
              function_exported?(manifest.entry_point, :__dashboard_view__, 0) ->
            manifest.entry_point.__dashboard_view__()

          true ->
            nil
        end

      all_actions =
        Enum.flat_map(services, fn svc ->
          actions = Map.get(svc, :actions) || Map.get(svc, "actions") || []

          Enum.map(actions, fn act ->
            params = normalize_action_params(Map.get(act, :params) || Map.get(act, "params") || [])
            name = to_string(Map.get(act, :name) || Map.get(act, "name"))
            doc = Map.get(act, :doc) || Map.get(act, "doc") || "No description provided."
            mode = to_string(Map.get(act, :mode) || Map.get(act, "mode") || "sync")

            %{
              name: name,
              service: svc[:name] || svc["name"],
              doc: doc,
              mode: mode,
              params: params,
              returns: Map.get(act, :returns) || Map.get(act, "returns")
            }
          end)
        end)

      all_resources = Enum.flat_map(services, fn s -> Map.get(s, :resources) || Map.get(s, "resources") || [] end)
      all_events = Enum.flat_map(services, fn s -> Map.get(s, :events) || Map.get(s, "events") || [] end)

      # Plugins do not have UI by default. Only plugins declaring an explicit dashboard_view
      # are classified as having visual controls / dashboard views.
      has_custom = not is_nil(dashboard_view)

      %{
        id: manifest.id,
        name: manifest.name,
        version: to_string(manifest.version),
        type: Map.get(manifest, :type, :native),
        status: :active,
        category: category,
        system: Map.get(manifest, :system, false),
        provides: clean_provides,
        dependencies: clean_dependencies,
        services: services,
        resources: all_resources,
        actions: all_actions,
        events: all_events,
        actions_count: length(all_actions),
        events_count: length(all_events),
        resources_count: length(all_resources),
        traps_count: Map.get(stats, :traps_count, 0),
        last_trap: Map.get(stats, :last_trap),
        dashboard_view: dashboard_view,
        title: Map.get(manifest, :title),
        icon: Map.get(manifest, :icon),
        has_custom_view: has_custom,
        has_visual_controls: has_custom,
        has_dashboard_view: has_custom
      }
    end)
  end

  defp normalize_service_metadata(meta) do
    name = Map.get(meta, :name) || Map.get(meta, "name") || "unknown"

    meta
    |> Map.put(:name, PluginRegistry.clean_service_name(name))
    |> PluginRegistry.sanitize_for_json()
  end

  defp safe_type(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> str
  end

  defp safe_type(atom) when is_atom(atom), do: atom
  defp safe_type(_), do: :string

  @doc "Normalizes action parameter definitions into [%{name: string, type: atom, optional: boolean}]."
  def normalize_action_params(params) do
    cond do
      is_map(params) ->
        Enum.map(params, fn {k, v} ->
          type =
            case v do
              m when is_map(m) -> Map.get(m, :type) || Map.get(m, "type") || :string
              l when is_list(l) -> Keyword.get(l, :type, :string)
              atom when is_atom(atom) -> atom
              str when is_binary(str) -> safe_type(str)
              _ -> :string
            end

          optional =
            case v do
              m when is_map(m) -> Map.get(m, :optional, false) || Map.get(m, "optional", false)
              l when is_list(l) -> Keyword.get(l, :optional, false)
              _ -> false
            end

          %{name: to_string(k), type: type, optional: !!optional}
        end)

      is_list(params) and Keyword.keyword?(params) ->
        Enum.map(params, fn {k, v} ->
          type =
            case v do
              m when is_map(m) -> Map.get(m, :type) || Map.get(m, "type") || :string
              l when is_list(l) -> Keyword.get(l, :type, :string)
              atom when is_atom(atom) -> atom
              str when is_binary(str) -> safe_type(str)
              _ -> :string
            end

          optional =
            case v do
              m when is_map(m) -> Map.get(m, :optional, false) || Map.get(m, "optional", false)
              l when is_list(l) -> Keyword.get(l, :optional, false)
              _ -> false
            end

          %{name: to_string(k), type: type, optional: !!optional}
        end)

      is_list(params) ->
        Enum.map(params, fn
          {k, v} ->
            type =
              case v do
                m when is_map(m) -> Map.get(m, :type) || Map.get(m, "type") || :string
                l when is_list(l) -> Keyword.get(l, :type, :string)
                atom when is_atom(atom) -> atom
                str when is_binary(str) -> safe_type(str)
                _ -> :string
              end

            optional =
              case v do
                m when is_map(m) -> Map.get(m, :optional, false) || Map.get(m, "optional", false)
                l when is_list(l) -> Keyword.get(l, :optional, false)
                _ -> false
              end

            %{name: to_string(k), type: type, optional: !!optional}

          item when is_map(item) ->
            name = Map.get(item, :name) || Map.get(item, "name") || "param"
            type = Map.get(item, :type) || Map.get(item, "type") || :string
            optional = Map.get(item, :optional, false) || Map.get(item, "optional", false)

            %{
              name: to_string(name),
              type: safe_type(type),
              optional: !!optional
            }

          other ->
            %{name: to_string(other), type: :string, optional: false}
        end)

      true ->
        []
    end
  end
end
