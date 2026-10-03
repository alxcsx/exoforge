defmodule Exoforge.PluginRegistry do
  use GenServer
  alias Exoforge.Domain.Manifest

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    initialize_ets()
    {:ok, %{}}
  end

  def initialize_ets do
    ensure_table(:exo_plugins_mem, :set)
    ensure_table(:exo_services_mem, :bag)
    :ok
  end

  defp ensure_table(table_name, type) do
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, [type, :named_table, :public, read_concurrency: true])

      _ ->
        :ets.delete_all_objects(table_name)
        table_name
    end
  end

  # Register a plugin manifest
  def register(%Manifest{} = manifest) do
    id = Map.get(manifest, :id)
    :ets.insert(:exo_plugins_mem, {id, manifest})

    provides = Map.get(manifest, :provides, [])
    context = Map.get(manifest, :context, :global)

    existing = :ets.match_object(:exo_services_mem, {{:_, :_}, %{id: id}})
    Enum.each(existing, &:ets.delete_object(:exo_services_mem, &1))

    Enum.each(provides, fn service_type ->
      Enum.each(service_keys(service_type), fn k ->
        key = {k, context}
        :ets.insert(:exo_services_mem, {key, manifest})
      end)
    end)

    :ok
  end

  # Unregister a plugin manifest and its services
  def unregister(manifest_id) do
    id_atom =
      try do
        if is_atom(manifest_id), do: manifest_id, else: String.to_existing_atom(to_string(manifest_id))
      rescue
        _ -> manifest_id
      end

    :ets.delete(:exo_plugins_mem, manifest_id)
    if id_atom != manifest_id, do: :ets.delete(:exo_plugins_mem, id_atom)

    existing =
      :ets.match_object(:exo_services_mem, {{:_, :_}, %{id: manifest_id}}) ++
        :ets.match_object(:exo_services_mem, {{:_, :_}, %{id: id_atom}})

    Enum.each(existing, &:ets.delete_object(:exo_services_mem, &1))
    :ok
  end

  # Fetch service by type and context
  def fetch_service(type, context \\ :global) do
    Enum.find_value(service_keys(type), fn k ->
      case :ets.lookup(:exo_services_mem, {k, context}) do
        [{{^k, ^context}, manifest} | _] ->
          manifest

        [] when context != :global ->
          case :ets.lookup(:exo_services_mem, {k, :global}) do
            [{{^k, :global}, manifest} | _] -> manifest
            [] -> nil
          end

        [] ->
          nil
      end
    end)
  end

  # Fetch manifest by ID
  def fetch_manifest(manifest_id) do
    case :ets.lookup(:exo_plugins_mem, manifest_id) do
      [{^manifest_id, manifest}] -> manifest
      [] -> nil
    end
  end

  # Fetch manifest by entry point module
  def fetch_by_module(module) do
    case :ets.match_object(:exo_plugins_mem, {:_, %{entry_point: module}}) do
      [{_, manifest} | _] -> manifest
      [] -> nil
    end
  end

  @doc "Retrieves all registered plugin manifests."
  def all_manifests do
    case :ets.info(:exo_plugins_mem) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(:exo_plugins_mem)
        |> Enum.map(fn {_id, manifest} -> manifest end)
    end
  end

  @doc "Retrieves all declared resources across all registered plugins and their contracts."
  def all_resources do
    all_manifests()
    |> Enum.flat_map(fn manifest ->
      provides = Map.get(manifest, :provides, [])

      Enum.flat_map(provides, fn contract_ref ->
        contract_mod = resolve_contract_module(contract_ref)

        if is_atom(contract_mod) and Code.ensure_loaded?(contract_mod) and
             function_exported?(contract_mod, :__service_metadata__, 0) do
          meta = contract_mod.__service_metadata__()
          resources = Map.get(meta, :resources, []) |> sanitize_for_json()

          Enum.map(resources, fn res ->
            %{
              plugin_id: manifest.id,
              plugin_name: manifest.name,
              service: clean_service_name(meta.name),
              contract: contract_mod,
              resource: res
            }
          end)
        else
          []
        end
      end)
    end)
  end

  @doc "Fetches a specific resource declaration by name."
  def fetch_resource(resource_name) do
    case Enum.find(all_resources(), fn r -> to_string(r.resource.name) == to_string(resource_name) end) do
      nil -> {:error, :not_found}
      found -> {:ok, found}
    end
  end

  @doc "Dynamically retrieves data rows for any declared resource from its providing plugin or database."
  def fetch_resource_rows(resource_name) do
    case fetch_resource(resource_name) do
      {:ok, %{plugin_id: plugin_id, resource: res}} ->
        table_name = to_string(res.name)
        pk_key = to_string(res.primary_key || "id")

        list_action =
          res
          |> Map.get(:actions, [])
          |> List.wrap()
          |> Enum.map(&to_string/1)
          |> Enum.find(&String.starts_with?(&1, "list_"))
          |> case do
            nil -> :all
            name -> String.to_existing_atom(name)
          end

        rows =
          case Exoforge.ActionDispatcher.dispatch(plugin_id, list_action, %{}) do
            {:ok, %{rows: r}} when is_list(r) ->
              r

            {:ok, %{players: r}} when is_list(r) ->
              r

            {:ok, r} when is_list(r) ->
              r

            _ ->
              if valid_identifier?(table_name) do
                case Exoforge.ActionDispatcher.dispatch(:database, :execute, %{
                       plugin: plugin_id,
                       operation: "SELECT * FROM #{table_name}"
                     }) do
                  {:ok, %{rows: r}} when is_list(r) -> r
                  _ -> []
                end
              else
                []
              end
          end

        normalized =
          Enum.map(rows, fn row ->
            id =
              fetch_key(row, pk_key) || fetch_key(row, "id") || "item_1"

            Map.put(row, :id, id)
          end)

        normalized

      _ ->
        []
    end
  end

  @doc "Returns structured extensions summary for the Producer Studio dashboard."
  def dashboard_extensions do
    all_manifests()
    |> Enum.map(fn manifest ->
      provides = Map.get(manifest, :provides, [])
      clean_provides = Enum.map(provides, &clean_service_name/1)
      clean_dependencies = Enum.map(Map.get(manifest, :dependencies, []), &clean_service_name/1)

      services =
        Enum.map(provides, fn contract_ref ->
          contract_mod = resolve_contract_module(contract_ref)

          meta =
            if is_atom(contract_mod) and Code.ensure_loaded?(contract_mod) and
                 function_exported?(contract_mod, :__service_metadata__, 0) do
              contract_mod.__service_metadata__()
            else
              %{name: contract_ref, actions: [], events: [], resources: []}
            end

          meta
          |> Map.put(:name, clean_service_name(Map.get(meta, :name, contract_ref)))
          |> sanitize_for_json()
        end)

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

      has_custom = not is_nil(dashboard_view)
      has_controls = has_custom or all_actions != [] or all_resources != [] or all_events != []

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
        has_custom_view: has_custom,
        has_visual_controls: has_controls,
        has_dashboard_view: has_controls
      }
    end)
  end

  @doc "Sanitizes data structures containing keywords or tuples into JSON-encodable maps and lists."
  def sanitize_for_json(data) do
    cond do
      match?(%Version{}, data) ->
        to_string(data)

      is_struct(data) and not match?(%DateTime{}, data) and not match?(%NaiveDateTime{}, data) and
        not match?(%Date{}, data) and not match?(%Time{}, data) ->
        data |> Map.from_struct() |> sanitize_for_json()

      is_map(data) ->
        Map.new(data, fn {k, v} -> {k, sanitize_for_json(v)} end)

      is_list(data) ->
        if Keyword.keyword?(data) do
          Map.new(data, fn {k, v} -> {k, sanitize_for_json(v)} end)
        else
          Enum.map(data, &sanitize_for_json/1)
        end

      is_tuple(data) ->
        Tuple.to_list(data) |> Enum.map(&sanitize_for_json/1)

      true ->
        data
    end
  end

  @doc "Strips Elixir., Exoforge.Std.Services., and module namespaces to return a clean snake_case service identifier."
  def clean_service_name(name) when is_atom(name), do: clean_service_name(to_string(name))

  def clean_service_name(name) when is_binary(name) do
    cleaned =
      name
      |> String.replace("Elixir.", "")
      |> String.replace("Exoforge.Std.Services.", "")
      |> String.replace("Exoforge.Services.", "")
      |> String.replace("Exoforge.", "")
      |> String.replace("Std.Services.", "")
      |> String.replace("Services.", "")

    cleaned
    |> String.split(".", trim: true)
    |> Enum.map_join("_", &Macro.underscore/1)
  end

  def clean_service_name(other), do: to_string(other)

  @doc "Resolves a contract atom or shorthand to its full contract module."
  def resolve_contract_module(contract_ref) when is_binary(contract_ref) do
    case fetch_service(contract_ref) do
      %{entry_point: entry_point} when is_atom(entry_point) -> entry_point
      _ -> contract_ref
    end
  end

  def resolve_contract_module(contract_ref) when is_atom(contract_ref) do
    str = to_string(contract_ref)
    clean = clean_service_name(str)

    cond do
      String.starts_with?(str, "Elixir.Exoforge.Std.Services.") ->
        contract_ref

      (mod = Module.concat([Exoforge, Std, Services, Macro.camelize(clean)])) && Code.ensure_loaded?(mod) ->
        mod

      (manifest = fetch_service(contract_ref)) && is_atom(manifest.entry_point) &&
          Code.ensure_loaded?(manifest.entry_point) ->
        manifest.entry_point

      (manifest = fetch_service(clean)) && is_atom(manifest.entry_point) && Code.ensure_loaded?(manifest.entry_point) ->
        manifest.entry_point

      true ->
        contract_ref
    end
  end

  def resolve_contract_module(other), do: other

  def service_keys(service) when is_atom(service) do
    str = to_string(service)
    clean = clean_service_name(str)
    shorthand = Module.concat([Exoforge, Std, Services, Macro.camelize(clean)])

    [service, str, clean, shorthand] |> Enum.uniq()
  end

  def service_keys(service) when is_binary(service) do
    [service, clean_service_name(service)] |> Enum.uniq()
  end

  def service_keys(other), do: [other]

  defp valid_identifier?(name), do: name =~ ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  defp fetch_key(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Enum.find_value(map, fn {map_key, value} -> if to_string(map_key) == key, do: value end)
    end
  end

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
              str when is_binary(str) -> String.to_atom(str)
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
              str when is_binary(str) -> String.to_atom(str)
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
                str when is_binary(str) -> String.to_atom(str)
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
              type: if(is_atom(type), do: type, else: String.to_atom(to_string(type))),
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
