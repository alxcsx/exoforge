defmodule Exoforge.PluginBootstrapper do
  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.Drivers.Runtime.ElixirPluginRunner

  def run(driver, path) do
    driver.load_modules(path)
    |> sort!()
    |> Enum.each(&initialize_and_register/1)
  end

  defp initialize_and_register(%Manifest{type: :elixir} = manifest) do
    ElixirPluginRunner.load(manifest)
    PluginRegistry.register(manifest)
  end

  @spec sort!([Manifest.t()]) :: [Manifest.t()]
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
