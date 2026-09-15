defmodule Exoforge.PluginRegistry do
  alias Exoforge.Domain.Manifest

  def initialize_ets do
    Process.flag(:trap_exit, true)

    :ets.new(:exo_plugins_mem, [:set, :named_table, :protected, read_concurrency: true])
    :ets.new(:exo_services_mem, [:set, :named_table, :protected, read_concurrency: true])
  end

  # Register a plugin manifest
  def register(%Manifest{} = manifest) do
    id = Map.get(manifest, :id)
    :ets.insert(:exo_plugins_mem, {id, manifest})

    provides = Map.get(manifest, :provides, [])
    context = Map.get(manifest, :context, :global)

    Enum.each(provides, fn service_type ->
      key = {service_type, context}
      :ets.insert(:exo_services_mem, {key, manifest})
    end)

    :ok
  end

  # Fetch service by type and context
  def fetch_service(type, context \\ :global) do
    case :ets.lookup(:exo_services_mem, {type, context}) do
      [{{^type, ^context}, manifest}] -> manifest
      [] when context != :global -> fetch_service(type, :global)
      [] -> nil
    end
  end

  # Fetch all services of a given type
  def fetch_services(type) do
    :ets.match_object(:exo_services_mem, {{type, :_}, :_})
    |> Enum.map(fn {_key, manifest} -> manifest end)
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
end
