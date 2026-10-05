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
    id_atom = Exoforge.Atoms.existing(manifest_id, manifest_id)

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
      Enum.flat_map(manifest_services(manifest), fn meta ->
        resources = Map.get(meta, :resources, []) |> sanitize_for_json()

        Enum.map(resources, fn res ->
          %{
            plugin_id: manifest.id,
            plugin_name: manifest.name,
            service: clean_service_name(Map.get(meta, :name, "unknown")),
            contract: Map.get(meta, :__contract__),
            resource: res
          }
        end)
      end)
    end)
  end

  @doc """
  Returns a manifest's service metadata, regardless of source: WASM plugins
  declare it in the manifest, Elixir plugins provide a contract module.
  """
  def manifest_services(manifest) do
    case Map.get(manifest, :services, []) do
      [] ->
        manifest
        |> Map.get(:provides, [])
        |> Enum.map(fn contract_ref ->
          contract_mod = resolve_contract_module(contract_ref)

          if is_atom(contract_mod) and Code.ensure_loaded?(contract_mod) and
               function_exported?(contract_mod, :__service_metadata__, 0) do
            Map.put(contract_mod.__service_metadata__(), :__contract__, contract_mod)
          else
            %{name: contract_ref, actions: [], events: [], resources: []}
          end
        end)

      declared ->
        declared
    end
  end

  @doc "Fetches a specific resource declaration by name."
  def fetch_resource(resource_name) do
    case Enum.find(all_resources(), fn r -> to_string(r.resource.name) == to_string(resource_name) end) do
      nil -> {:error, :not_found}
      found -> {:ok, found}
    end
  end

  @doc "Dynamically retrieves data rows for any declared resource via the resource store."
  def fetch_resource_rows(resource_name, caller_scopes \\ :internal) do
    case Exoforge.ActionDispatcher.dispatch(
           :resource_store,
           :list,
           %{
             resource: to_string(resource_name),
             limit: 1000,
             _auth: %{scopes: caller_scopes}
           },
           caller_scopes: caller_scopes
         ) do
      {:ok, %{rows: rows}} when is_list(rows) ->
        normalize_resource_rows(resource_name, rows)

      _ ->
        legacy_resource_rows(resource_name)
    end
  end

  defp normalize_resource_rows(resource_name, rows) do
    pk_key =
      case fetch_resource(resource_name) do
        {:ok, %{resource: res}} -> to_string(res.primary_key || "id")
        _ -> "id"
      end

    Enum.map(rows, fn row ->
      id = fetch_key(row, pk_key) || fetch_key(row, "id") || "item_1"
      Map.put(row, :id, id)
    end)
  end

  # Fallback when the resource store plugin is not loaded.
  defp legacy_resource_rows(resource_name) do
    case fetch_resource(resource_name) do
      {:ok, %{plugin_id: plugin_id, resource: res}} ->
        table_name = to_string(res.name)

        list_action =
          res
          |> Map.get(:actions, [])
          |> List.wrap()
          |> Enum.map(&to_string/1)
          |> Enum.find(&String.starts_with?(&1, "list_"))
          |> case do
            nil -> :all
            name -> Exoforge.Atoms.existing(name, :all)
          end

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

      _ ->
        []
    end
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

  # WASM plugins carry their contract metadata in the manifest; Elixir plugins
  # carry it in the provided contract module. Both are normalized here.
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
      Code.ensure_loaded?(contract_ref) and
          function_exported?(contract_ref, :__service_metadata__, 0) ->
        contract_ref

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

end
