defmodule Exoforge.Entities do
  @moduledoc """
  Manager and public dispatch interface for stateful entity actors.
  Features:
  - Stable `call/5` and `cast/4` API keyed by `{plugin, type, id}`
  - Registry-backed lookup and DynamicSupervisor-backed actor lifecycle
  - Race-condition handling on concurrent entity activations
  - Passivation, termination, and live count metrics
  """

  @default_adapter Exoforge.Entities.Adapters.Local

  def adapter do
    Application.get_env(:exoforge, :entity_adapter, @default_adapter)
  end

  def registry_name, do: adapter().registry_name()
  def supervisor_name, do: adapter().supervisor_name()

  def registry_spec(opts \\ []) do
    adapter().registry_spec(opts)
  end

  def supervisor_spec(opts \\ []) do
    adapter().supervisor_spec(opts)
  end

  @doc """
  Returns a `:via` tuple for registering an entity in the active Registry.
  """
  def via_tuple(plugin, type, id) do
    adapter().via_tuple(plugin, type, id)
  end

  @doc """
  Invokes a synchronous call on an entity actor.
  Automatically activates (spawns and rehydrates) the entity if not currently running.
  """
  def call(plugin, type, id, message, timeout \\ 5000) do
    case get_or_start(plugin, type, id) do
      {:ok, pid} ->
        try do
          case GenServer.call(pid, {:__exo_call__, message}, timeout) do
            {:ok, _} = ok -> ok
            {:error, _} = err -> err
            :ok -> :ok
            other -> {:ok, other}
          end
        catch
          :exit, reason -> {:error, {:entity_call_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends an asynchronous cast to an entity actor, activating it if necessary.
  """
  def cast(plugin, type, id, message) do
    case get_or_start(plugin, type, id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:__exo_cast__, message})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Finds the PID of an active entity in memory without starting it.
  """
  def whereis(plugin, type, id) do
    adapter().whereis(plugin, type, id)
  end

  @doc """
  Stops an active entity gracefully, forcing snapshot persistence and passivation.
  """
  def stop(plugin, type, id, _reason \\ :normal) do
    case whereis(plugin, type, id) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        adapter().terminate_child(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} ->
            wait_unregistered(plugin, type, id)
        after
          1000 ->
            :ok
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp wait_unregistered(plugin, type, id, attempts \\ 10) do
    case whereis(plugin, type, id) do
      {:error, :not_found} ->
        :ok

      {:ok, _} when attempts > 0 ->
        :timer.sleep(5)
        wait_unregistered(plugin, type, id, attempts - 1)

      {:ok, _} ->
        :ok
    end
  end

  @doc """
  Returns the count of active entities currently in memory.
  """
  def count do
    adapter().count()
  end

  @doc """
  Lists all active entities currently running in memory with process and resource metadata.
  """
  def list_active do
    if function_exported?(adapter(), :list_active, 0) do
      adapter().list_active()
    else
      []
    end
  end

  @doc """
  Activates or gets the PID of an entity actor with race condition handling.
  """
  def get_or_start(plugin, type, id, init_opts \\ []) do
    case whereis(plugin, type, id) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      _ ->
        case resolve_entity_module(plugin, type) do
          {:ok, mod} ->
            spec = %{
              id: {plugin, type, id},
              start: {mod, :start_link, [{plugin, type, id, init_opts}]},
              restart: :temporary
            }

            case adapter().start_child(spec) do
              {:ok, pid} ->
                {:ok, pid}

              {:error, {:already_started, pid}} ->
                {:ok, pid}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Resolves the entity implementation module for a given plugin and entity type.
  """
  def resolve_entity_module(plugin, type) do
    # 1. Direct module atom
    if is_atom(type) and Code.ensure_loaded?(type) and function_exported?(type, :start_link, 1) do
      {:ok, type}
    else
      # 2. Conventional plugin child module (e.g. MyPlugin.Guild or Exoforge.Plugins.CombatWasm.Combatant)
      candidates = [
        Module.concat([Macro.camelize(to_string(plugin)), Macro.camelize(to_string(type))]),
        Module.concat([Exoforge, Plugins, Macro.camelize(to_string(plugin)), Macro.camelize(to_string(type))]),
        Module.concat([Exoforge, Std, Macro.camelize(to_string(plugin)), Macro.camelize(to_string(type))])
      ]

      case Enum.find(candidates, fn mod -> Code.ensure_loaded?(mod) and function_exported?(mod, :start_link, 1) end) do
        nil -> {:error, {:unknown_entity_type, type}}
        mod -> {:ok, mod}
      end
    end
  end
end
