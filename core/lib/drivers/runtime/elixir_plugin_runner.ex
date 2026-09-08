defmodule Exoforge.Drivers.Runtime.ElixirPluginRunner do
  use GenServer
  alias Exoforge.Domain.Manifest

  # -- Public Static API
  def load(%Manifest{entry_point: plugin_mod} = manifest) do
    Code.append_path(Path.join(manifest.physical_path, "ebin"))

    plugin_sup_name = Module.concat(plugin_mod, Supervisor)
    task_sup_name = Module.concat(plugin_mod, TaskSupervisor)
    snapshot_mgr_name = Module.concat(plugin_mod, SnapshotManager)
    worker_sup_name = Module.concat(plugin_mod, WorkerSupervisor)

    custom_children =
      if function_exported?(plugin_mod, :children, 0) do
        plugin_mod.children()
      else
        []
      end

    children = [
      {Task.Supervisor, name: task_sup_name},
      {Exoforge.Workers.SnapshotManager, name: snapshot_mgr_name},
      {DynamicSupervisor, name: worker_sup_name, strategy: :one_for_one},
      %{id: __MODULE__, start: {__MODULE__, :start_link, [{manifest, task_sup_name}]}}
    ] ++ custom_children

    DynamicSupervisor.start_child(
      Exoforge.PluginRootSupervisor,
      %{
        id: plugin_sup_name,
        start: {Supervisor, :start_link, [children, [name: plugin_sup_name, strategy: :one_for_one]]},
        type: :supervisor
      }
    )
  end

  def start_link({%Manifest{}, _task_sup_name} = args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init({%Manifest{entry_point: plugin_mod} = manifest, task_sup_name}) do
    events = if function_exported?(plugin_mod, :events, 0), do: plugin_mod.events(), else: []

    Enum.each(events, fn event_key ->
      Exoforge.Dispatcher.subscribe(event_key)
    end)

    if function_exported?(plugin_mod, :on_init, 1) do
      plugin_mod.on_init(manifest)
    end

    {:ok, %{manifest: manifest, plugin_mod: plugin_mod, task_sup_name: task_sup_name}}
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, state) do
    Task.Supervisor.start_child(
      state.task_sup_name,
      state.plugin_mod,
      :handle_inbound_event,
      [event_key, payload, context]
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
