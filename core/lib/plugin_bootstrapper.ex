defmodule Exoforge.PluginBootstrapper do
  require Logger
  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.Drivers.Runtime.ElixirPluginRunner

  def boot do
    loader_config = Application.get_env(:exoforge, :module_loader, [])
    driver = Keyword.get(loader_config, :driver, Exoforge.Drivers.Loaders.ManifestLoader)
    path = Keyword.get(loader_config, :scan_path, "plugins")

    PluginRegistry.initialize_ets()

    case run(driver, path) do
      [] ->
        Logger.warning("[Exoforge] no plugins found at #{path}")

      loaded ->
        Logger.info("[Exoforge] loaded #{length(loaded)} plugins: #{Enum.map_join(loaded, ", ", & &1.id)}")

        dashboard_port =
          Application.get_env(:exoforge_std_dashboard, Exoforge.Std.Dashboard.Endpoint, [])
          |> Keyword.get(:http, [])
          |> Keyword.get(:port, 4005)

        ws_port = Application.get_env(:exoforge, :ws_port) || Application.get_env(:exoforge, :gateway_port, 4000)
        http_port = Application.get_env(:exoforge, :http_port, 4001)

        Logger.info("""
        [Exoforge Endpoints]
          • Game Producer Studio (UI): http://localhost:#{dashboard_port}
          • REST API Gateway:          http://localhost:#{http_port}
          • WebSocket Gateway:         ws://localhost:#{ws_port}/ws
        """)
    end

    :ok
  end

  def run(driver, path) do
    manifests = driver.load_plugins(path) |> sort!()
    Enum.each(manifests, &initialize_and_register/1)
    manifests
  end

  defp initialize_and_register(%Manifest{} = manifest) do
    runner = runner_for(manifest.type)

    manifest =
      if function_exported?(runner, :prepare_manifest, 1) do
        runner.prepare_manifest(manifest)
      else
        manifest
      end

    PluginRegistry.register(manifest)
    runner.load(manifest)
  end

  defp runner_for(:elixir), do: ElixirPluginRunner
  defp runner_for(:wasm), do: Exoforge.Drivers.Runtime.WasmPluginRunner
  defp runner_for(mod) when is_atom(mod), do: mod

  @spec sort!([%Manifest{}]) :: [%Manifest{}]
  def sort!(manifests) do
    graph = :digraph.new()

    try do
      # Create Nodes
      Enum.each(manifests, &:digraph.add_vertex(graph, &1.id, &1))

      service_providers =
        manifests
        |> Enum.flat_map(fn m ->
          Enum.flat_map(m.provides, fn p ->
            Enum.map(service_keys(p), &{&1, m.id})
          end)
        end)
        |> Enum.group_by(fn {service, _id} -> service end, fn {_service, id} -> id end)

      # Create Links
      for m <- manifests, req <- m.dependencies do
        case find_providers(service_providers, req) do
          {:ok, providers} -> Enum.each(providers, &:digraph.add_edge(graph, &1, m.id))
          :error -> raise "[Missing Dependency]: Plugin `#{m.id}` requires service `#{req}`, which is not provided."
        end
      end

      # Sort
      case :digraph_utils.topsort(graph) do
        false ->
          cycles = :digraph_utils.cyclic_strong_components(graph)
          raise "[Failed To Register Dependencies]: Circular dependency detected: #{inspect(cycles)}"

        sorted_ids ->
          Enum.map(sorted_ids, fn id -> elem(:digraph.vertex(graph, id), 1) end)
      end
    after
      :digraph.delete(graph)
    end
  end

  defp service_keys(service), do: PluginRegistry.service_keys(service)

  defp find_providers(service_providers, req) do
    Enum.find_value(service_keys(req), :error, fn key ->
      case Map.fetch(service_providers, key) do
        {:ok, providers} -> {:ok, providers}
        :error -> nil
      end
    end)
  end
end
