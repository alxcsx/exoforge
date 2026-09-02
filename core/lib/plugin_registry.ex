defmodule Exoforge.PluginRegistry do
  use GenServer
  require Logger
  alias Exoforge.Domain.Manifest

  def start_link(_opt) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register(%Manifest{} = manifest) do
    GenServer.call(__MODULE__, {:register, manifest})
  end

  def fetch_service(type, context \\ :global) do
    case :ets.lookup(:exo_services_mem, {type, context}) do
      [{{^type, ^context}, manifest}] -> manifest
      [] when context != :global -> fetch_service(type, :global)
      [] -> nil
    end
  end

  def fetch_services(type) do
    :ets.foldl(
      fn
        {{^type, _context}, manifest}, acc -> [manifest | acc]
        _, acc -> acc
      end,
      [],
      :exo_services_mem
    )
  end

  def fetch_manifest(manifest_id) do
    case :ets.lookup(:exo_plugins_mem, manifest_id) do
      [{^manifest_id, manifest}] -> manifest
      [] -> nil
    end
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    :ets.new(:exo_plugins_mem, [:set, :named_table, :protected, read_concurrency: true])
    :ets.new(:exo_services_mem, [:set, :named_table, :protected, read_concurrency: true])

    {:ok, _} = :dets.open_file(:exo_services_disk, type: :set, file: ~c"exo_services.dets")
    :dets.to_ets(:exo_services_disk, :exo_services_mem)

    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("[PluginRegistry] Gracefully closing DETS files...")
    :dets.sync(:exo_services_disk)
    :dets.close(:exo_services_disk)
  end

  @impl true
  def handle_call({:register, %Manifest{id: id} = manifest}, _from, state) do
    :ets.insert(:exo_plugins_mem, {id, manifest})

    # 2. Automatically register everything this manifest provides
    provides = Map.get(manifest, :provides, [])
    context = Map.get(manifest, :context, :global)

    Enum.each(provides, fn service_type ->
      key = {service_type, context}
      # Store the manifest or its entry point as the service handler
      :ets.insert(:exo_services_mem, {key, manifest})
      :dets.insert(:exo_services_disk, {key, manifest})
    end)

    {:reply, :ok, state}
  end
end
