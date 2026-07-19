defmodule Exoforge.Domain.ExoModuleRegistry do
  use GenServer
  require Logger
  alias Exoforge.Domain.Manifest
  # -- Client API
  def start_link(_opt) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # -- Write Operations
  def register(%Manifest{} = manifest) do
    GenServer.call(__MODULE__, {:register, manifest})
  end

  def set_override(tag, caller_context \\ :global, manifest_id) do
    GenServer.call(__MODULE__, {:set_override, tag, caller_context, manifest_id})
  end

  # -- Read Operations

  def fetch_by_tag(tag, caller_id \\ :global) do
    case :ets.lookup(:exo_overrides_mem, {tag, caller_id}) do
      [{{^tag, ^caller_id}, manifest_id}] ->
        fetch_manifest(manifest_id)

      [] ->
        case :ets.lookup(:exo_overrides_mem, {tag, :global}) do
          [{{^tag, :global}, manifest_id}] -> fetch_manifest(manifest_id)
          [] -> nil
        end
    end
  end

  def fetch_by_id(manifest_id), do: fetch_manifest(manifest_id)

  def fetch_by_behaviour(behaviours) when is_list(behaviours) do
    find_by(fn manifest ->
      implements = Map.get(manifest, :implements) || []
      Enum.all?(behaviours, fn b -> b in implements end)
    end)
  end

  @spec find_by((any() -> any())) :: any()
  def find_by(predicate) when is_function(predicate, 1) do
    :ets.foldl(
      fn {_, manifest}, acc -> if predicate.(manifest), do: [manifest | acc], else: acc end,
      [],
      :exo_modules_mem
    )
  end

  def module_ids do
    :ets.select(:exo_modules_mem, [{{:"$1", :_}, [], [:"$1"]}])
  end

  defp fetch_manifest(manifest_id) do
    case :ets.lookup(:exo_modules_mem, manifest_id) do
      [{^manifest_id, manifest}] -> manifest
      [] -> nil
    end
  end

  # -- Server Callbacks
  @impl true
  def init(_opts) do
    # Prevent the process from crashing on exit signals, so we can clean up the ETS tables and DETS file properly.
    Process.flag(:trap_exit, true)

    # This ETS Table holds the current registered modules.
    :ets.new(:exo_modules_mem, [:set, :named_table, :protected, read_concurrency: true])

    # This ETS Table holds the configs and overrides, it persists to disk
    :ets.new(:exo_config_mem, [:set, :named_table, :protected, read_concurrency: true])

    {:ok, _} = :dets.open_file(:exo_config_disk, type: :set, file: ~c"exo_config.dets")
    :dets.to_ets(:exo_config_disk, :exo_config_mem)

    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("[ExoModuleRegistry] Gracefully closing DETS file before shutdown...")
    :dets.sync(:exo_config_disk)
    :dets.close(:exo_config_disk)
  end

  @impl true
  def handle_call({:register, %Manifest{} = manifest}, _from, state) do
    :ets.insert(:exo_modules_mem, {manifest.id, manifest})
    {:reply, :ok, state}
  end

  def handle_call({:set_override, tag, caller_context, manifest_id}, _from, state) do
    key = {tag, caller_context}
    :ets.insert(:exo_config_mem, {key, manifest_id})
    :dets.insert(:exo_config_disk, {key, manifest_id})
    {:reply, :ok, state}
  end
end
