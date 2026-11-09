defmodule Exoforge.Std.Dashboard.Extensions do
  @moduledoc """
  Dashboard-facing shaping of plugin manifests.

  Turns registry manifests into the extension summaries the Studio renders (actions,
  resources, events, dashboard view). This lives here rather than in the kernel
  so the kernel stays free of dashboard concerns — a different dashboard implementation can
  shape manifests its own way.
  """

  alias Exoforge.ExtensionRegistry
  alias Exoforge.Std.Dashboard.ExtensionPresenter

  @doc "Returns structured extensions summary for the Producer Studio dashboard."
  def dashboard_extensions do
    ExtensionRegistry.all_manifests()
    |> Enum.map(fn manifest ->
      provides = Map.get(manifest, :provides, [])
      clean_provides = Enum.map(provides, &ExtensionRegistry.service_alias_or_module/1)

      clean_dependencies =
        Enum.map(
          Map.get(manifest, :dependencies, []),
          &ExtensionRegistry.service_alias_or_module/1
        )

      services =
        Enum.map(ExtensionRegistry.manifest_services(manifest), &normalize_service_metadata/1)

      category = ExtensionPresenter.normalize_category(Map.get(manifest, :category))

      # Registry entries are not always structs (hand-registered or test manifests), so read the
      # entry point by key: a dot-access KeyError here silently emptied the whole action catalog.
      entry_point = Map.get(manifest, :entry_point)

      dashboard_view =
        cond do
          Map.get(manifest, :dashboard_view) ->
            Map.get(manifest, :dashboard_view)

          is_atom(entry_point) and Code.ensure_loaded?(entry_point) and
              function_exported?(entry_point, :dashboard_view, 0) ->
            entry_point.dashboard_view()

          is_atom(entry_point) and Code.ensure_loaded?(entry_point) and
              function_exported?(entry_point, :__dashboard_view__, 0) ->
            entry_point.__dashboard_view__()

          true ->
            nil
        end

      all_actions =
        Enum.flat_map(services, fn svc ->
          actions = Map.get(svc, :actions) || Map.get(svc, "actions") || []

          Enum.map(actions, fn act ->
            params =
              normalize_action_params(Map.get(act, :params) || Map.get(act, "params") || [])

            name = to_string(Map.get(act, :name) || Map.get(act, "name"))
            doc = Map.get(act, :doc) || Map.get(act, "doc") || "No description provided."
            mode = to_string(Map.get(act, :mode) || Map.get(act, "mode") || "sync")

            %{
              name: name,
              service: svc[:name] || svc["name"],
              doc: doc,
              mode: mode,
              scope: to_string(Map.get(act, :scope) || Map.get(act, "scope") || "player"),
              transport:
                to_string(Map.get(act, :transport) || Map.get(act, "transport") || "auto"),
              params: params,
              returns: Map.get(act, :returns) || Map.get(act, "returns"),
              errors: Map.get(act, :errors) || Map.get(act, "errors") || []
            }
          end)
        end)

      all_resources =
        Enum.flat_map(services, fn s ->
          Map.get(s, :resources) || Map.get(s, "resources") || []
        end)

      all_events =
        Enum.flat_map(services, fn s -> Map.get(s, :events) || Map.get(s, "events") || [] end)

      # Plugins do not have UI by default. Only plugins declaring an explicit dashboard_view
      # are classified as having visual controls / dashboard views.
      has_custom = not is_nil(dashboard_view)

      dv_title = is_map(dashboard_view) && (dashboard_view[:title] || dashboard_view["title"])
      dv_icon = is_map(dashboard_view) && (dashboard_view[:icon] || dashboard_view["icon"])
      title = Map.get(manifest, :title) || dv_title || to_string(manifest.name || manifest.id)
      raw_icon = Map.get(manifest, :icon) || dv_icon

      icon =
        if is_binary(raw_icon) and raw_icon not in ["", "🧩"] do
          raw_icon
        else
          ExtensionPresenter.default_icon_for(%{id: manifest.id, category: category})
        end

      %{
        id: manifest.id,
        name: manifest.name,
        entry_point: Map.get(manifest, :entry_point),
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
        dashboard_view: dashboard_view,
        title: title,
        icon: icon,
        has_custom_view: has_custom,
        has_visual_controls: has_custom,
        has_dashboard_view: has_custom
      }
    end)
  end

  defp normalize_service_metadata(meta) do
    name = Map.get(meta, :name) || Map.get(meta, "name") || "unknown"

    meta
    |> Map.put(:name, ExtensionRegistry.clean_service_name(name))
    |> ExtensionRegistry.sanitize_for_json()
  end

  defp safe_type(str) when is_binary(str), do: Exoforge.Atoms.existing(str, str)

  defp safe_type(atom) when is_atom(atom), do: atom
  defp safe_type(_), do: :string

  # The input-override travels with the param spec, whatever shape it arrived in: a keyword from a
  # contract, a map from a manifest, `input: :color` (an id) or a whole spec.
  defp input_override(v) do
    case v do
      m when is_map(m) -> Map.get(m, :input) || Map.get(m, "input") || nil
      l when is_list(l) -> Keyword.get(l, :input, nil)
      _ -> nil
    end
  end

  @doc "Normalizes action parameter definitions into [%{name: string, type, optional: boolean, input}]."
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

          doc =
            case v do
              m when is_map(m) ->
                Map.get(m, :doc) || Map.get(m, "doc") || Map.get(m, :description) ||
                  Map.get(m, "description")

              l when is_list(l) ->
                Keyword.get(l, :doc) || Keyword.get(l, :description)

              _ ->
                nil
            end

          %{
            name: to_string(k),
            type: type,
            optional: !!optional,
            input: input_override(v),
            doc: doc
          }
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

          doc =
            case v do
              m when is_map(m) ->
                Map.get(m, :doc) || Map.get(m, "doc") || Map.get(m, :description) ||
                  Map.get(m, "description")

              l when is_list(l) ->
                Keyword.get(l, :doc) || Keyword.get(l, :description)

              _ ->
                nil
            end

          %{
            name: to_string(k),
            type: type,
            optional: !!optional,
            input: input_override(v),
            doc: doc
          }
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

            doc =
              case v do
                m when is_map(m) ->
                  Map.get(m, :doc) || Map.get(m, "doc") || Map.get(m, :description) ||
                    Map.get(m, "description")

                l when is_list(l) ->
                  Keyword.get(l, :doc) || Keyword.get(l, :description)

                _ ->
                  nil
              end

            %{name: to_string(k), type: type, optional: !!optional, doc: doc}

          item when is_map(item) ->
            name = Map.get(item, :name) || Map.get(item, "name") || "param"
            type = Map.get(item, :type) || Map.get(item, "type") || :string
            optional = Map.get(item, :optional, false) || Map.get(item, "optional", false)

            doc =
              Map.get(item, :doc) || Map.get(item, "doc") || Map.get(item, :description) ||
                Map.get(item, "description")

            %{
              name: to_string(name),
              type: safe_type(type),
              optional: !!optional,
              input: Map.get(item, :input) || Map.get(item, "input"),
              doc: doc
            }

          other ->
            %{name: to_string(other), type: :string, optional: false, doc: nil}
        end)

      true ->
        []
    end
  end
end
