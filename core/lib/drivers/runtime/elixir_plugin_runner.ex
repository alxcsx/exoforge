defmodule Exoforge.Drivers.Runtime.ElixirPluginRunner do
  @behaviour Exoforge.Contracts.PluginRunner
  use GenServer
  alias Exoforge.Domain.Manifest

  # -- Public Static API
  @impl true
  def load(%Manifest{entry_point: plugin_mod} = manifest) do
    if manifest.physical_path do
      Code.append_path(Path.join(manifest.physical_path, "ebin"))
    end

    plugin_sup_name = Module.concat(plugin_mod, Supervisor)
    task_sup_name = Module.concat(plugin_mod, TaskSupervisor)
    worker_sup_name = Module.concat(plugin_mod, WorkerSupervisor)

    custom_children =
      if function_exported?(plugin_mod, :children, 0) do
        plugin_mod.children()
      else
        []
      end

    children =
      [
        {Task.Supervisor, name: task_sup_name},
        {DynamicSupervisor, name: worker_sup_name, strategy: :one_for_one},
        %{id: __MODULE__, start: {__MODULE__, :start_link, [{manifest, task_sup_name}]}}
      ] ++ custom_children

    child_spec = %{
      id: plugin_sup_name,
      start: {Supervisor, :start_link, [children, [name: plugin_sup_name, strategy: :one_for_one]]},
      type: :supervisor
    }

    # A plugin whose children fail to start must fail the boot loudly, not leave
    # the cluster running with a silently-dead subsystem.
    case DynamicSupervisor.start_child(Exoforge.PluginSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> raise "[Plugin Start Failed] #{inspect(plugin_mod)}: #{inspect(reason)}"
    end
  end

  def start_link({%Manifest{}, _task_sup_name} = args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init({%Manifest{entry_point: plugin_mod} = manifest, task_sup_name}) do
    events = plugin_mod.handled_events()

    Enum.each(events, fn event_key ->
      Exoforge.EventDispatcher.subscribe(event_key)
    end)

    case plugin_mod.init(manifest) do
      :ok -> {:ok, %{manifest: manifest, plugin_mod: plugin_mod, task_sup_name: task_sup_name}}
      {:error, reason} -> {:stop, reason}
    end
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
