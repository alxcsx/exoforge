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
    end

    :ok
  end

  def run(driver, path) do
    manifests = driver.load_plugins(path) |> sort!()
    Enum.each(manifests, &initialize_and_register/1)
    manifests
  end

  defp initialize_and_register(%Manifest{type: :elixir} = manifest) do
    PluginRegistry.register(manifest)
    ElixirPluginRunner.load(manifest)
  end

  @spec sort!([%Manifest{}]) :: [%Manifest{}]
  def sort!(manifests) do
    graph = :digraph.new()

    try do
      # Create Nodes
      Enum.each(manifests, &:digraph.add_vertex(graph, &1.id, &1))

      service_providers =
        manifests
        |> Enum.flat_map(fn m -> Enum.map(m.provides, &{&1, m.id}) end)
        |> Enum.group_by(fn {service, _id} -> service end, fn {_service, id} -> id end)

      # Create Links
      for m <- manifests, req <- m.dependencies do
        case Map.fetch(service_providers, req) do
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
end
