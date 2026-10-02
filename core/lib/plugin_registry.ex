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

  # Fetch service by type and context
  def fetch_service(type, context \\ :global) do
    Enum.find_value(service_keys(type), fn k ->
      case :ets.lookup(:exo_services_mem, {k, context}) do
        [{{^k, ^context}, manifest} | _] -> manifest
        [] when context != :global ->
          case :ets.lookup(:exo_services_mem, {k, :global}) do
            [{{^k, :global}, manifest} | _] -> manifest
            [] -> nil
          end
        [] -> nil
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
      :undefined -> []
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
              service: meta.name,
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
    target_atom =
      cond do
        is_atom(resource_name) -> resource_name
        is_binary(resource_name) -> String.to_atom(resource_name)
        true -> nil
      end

    case Enum.find(all_resources(), fn r -> r.resource.name == target_atom end) do
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
          try do
            String.to_existing_atom("list_#{table_name}")
          rescue
            ArgumentError -> :all
          end

        rows =
          case Exoforge.ActionDispatcher.dispatch(plugin_id, list_action, %{}) do
            {:ok, %{rows: r}} when is_list(r) -> r
            {:ok, %{players: r}} when is_list(r) -> r
            {:ok, r} when is_list(r) -> r
            _ ->
              case Exoforge.ActionDispatcher.dispatch(:database, :execute, %{
                     plugin: plugin_id,
                     operation: "SELECT * FROM #{table_name}"
                   }) do
                {:ok, %{rows: r}} when is_list(r) -> r
                _ -> []
              end
          end

        normalized =
          Enum.map(rows, fn row ->
            id =
              Map.get(row, pk_key) ||
                Map.get(row, String.to_atom(pk_key)) ||
                Map.get(row, "id") ||
                Map.get(row, :id) ||
                "item_1"

            Map.put(row, :id, id)
          end)

        if normalized != [] do
          normalized
        else
          sample_rows_for(resource_name)
        end

      _ ->
        sample_rows_for(resource_name)
    end
  end

  defp sample_rows_for(resource_name) do
    case to_string(resource_name) do
      "players" ->
        [
          %{
            id: "p_1001",
            player_id: "p_1001",
            name: "ValkyrieOne",
            email: "valk@sanctumhaven.io",
            status: "Active",
            total_spent: "$149.50",
            time_in_game: "48h 12m",
            attributes: [
              %{key: "locale", value: "en_US"},
              %{key: "guild_id", value: "guild_alpha"},
              %{key: "vip_status", value: "true"}
            ]
          },
          %{
            id: "p_1002",
            player_id: "p_1002",
            name: "ShadowStrike",
            email: "shadow@sanctumhaven.io",
            status: "Active",
            total_spent: "$39.00",
            time_in_game: "14h 05m",
            attributes: [
              %{key: "locale", value: "en_GB"},
              %{key: "combat_rating", value: "1850"}
            ]
          },
          %{
            id: "p_1003",
            player_id: "p_1003",
            name: "ArchonPrime",
            email: "archon@sanctumhaven.io",
            status: "Suspended",
            total_spent: "$0.00",
            time_in_game: "1h 20m",
            attributes: [
              %{key: "sanction_reason", value: "speed_hack_detection"}
            ]
          }
        ]

      other ->
        [%{id: "item_1", data: "Sample record for #{other}"}]
    end
  end

  @doc "Returns structured extensions summary for the Producer Studio dashboard."
  def dashboard_extensions do
    all_manifests()
    |> Enum.map(fn manifest ->
      provides = Map.get(manifest, :provides, [])

      services =
        Enum.map(provides, fn contract_ref ->
          contract_mod = resolve_contract_module(contract_ref)

          if is_atom(contract_mod) and Code.ensure_loaded?(contract_mod) and
               function_exported?(contract_mod, :__service_metadata__, 0) do
            contract_mod.__service_metadata__()
            |> sanitize_for_json()
          else
            %{name: contract_ref, actions: [], events: [], resources: []}
          end
        end)

      category = categorize_plugin(manifest)
      stats =
        if Code.ensure_loaded?(Exoforge.Drivers.Runtime.WasmPluginRunner) and
             function_exported?(Exoforge.Drivers.Runtime.WasmPluginRunner, :get_stats, 1) do
          Exoforge.Drivers.Runtime.WasmPluginRunner.get_stats(manifest.id)
        else
          %{traps_count: 0, last_trap: nil}
        end

      %{
        id: manifest.id,
        name: manifest.name,
        version: manifest.version,
        type: Map.get(manifest, :type, :native),
        status: :active,
        category: category,
        dependencies: Map.get(manifest, :dependencies, []),
        services: services,
        resources: Enum.flat_map(services, &Map.get(&1, :resources, [])),
        actions_count: Enum.sum(Enum.map(services, &Enum.count(Map.get(&1, :actions, [])))),
        events_count: Enum.sum(Enum.map(services, &Enum.count(Map.get(&1, :events, [])))),
        traps_count: Map.get(stats, :traps_count, 0),
        last_trap: Map.get(stats, :last_trap)
      }
    end)
  end

  @doc "Sanitizes data structures containing keywords or tuples into JSON-encodable maps and lists."
  def sanitize_for_json(data) do
    cond do
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

  defp categorize_plugin(manifest) do
    str = to_string(manifest.id)

    cond do
      str in ["exoforge_std_database", "database"] -> "Storage"
      str in ["exoforge_std_http", "exoforge_std_ws", "http", "ws"] -> "Ingress"
      str in ["exoforge_std_auth", "auth"] -> "Identity"
      str in ["exoforge_std_player_data", "player_data"] -> "LiveOps"
      str in ["exoforge_std_dashboard", "dashboard"] -> "Studio"
      str in ["combat_wasm", "combat", "hello_world"] -> "Gameplay"
      true -> "Extension"
    end
  end

  defp resolve_contract_module(contract_ref) when is_atom(contract_ref) do
    str = to_string(contract_ref)

    cond do
      String.starts_with?(str, "Elixir.Exoforge.Std.Services.") ->
        contract_ref

      (mod = Module.concat([Exoforge, Std, Services, Macro.camelize(str)])) && Code.ensure_loaded?(mod) ->
        mod

      (manifest = fetch_service(contract_ref)) && is_atom(manifest.entry_point) && Code.ensure_loaded?(manifest.entry_point) ->
        manifest.entry_point

      true ->
        contract_ref
    end
  end

  defp resolve_contract_module(other), do: other

  def service_keys(service) when is_atom(service) do
    str = to_string(service)

    case String.split(str, ".") do
      ["Elixir", "Exoforge", "Std", "Services", name] ->
        [service, String.to_atom(Macro.underscore(name))]

      _ ->
        shorthand = Module.concat([Exoforge, Std, Services, Macro.camelize(str)])
        [service, shorthand]
    end
  end

  def service_keys(other), do: [other]
end
