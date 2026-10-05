defmodule Exoforge.Drivers.Runtime.NativePluginRunner do
  @moduledoc """
  Runs a C# plugin compiled to a self-contained native binary (NativeAOT).

  The binary is spawned as an OS process and speaks newline-delimited JSON over stdio:

      host  -> plugin   {"type":"action","id":1,"action":"move","payload":{...}}
      plugin -> host    {"type":"action_result","id":1,"status":"ok","data":1}
      plugin -> host    {"type":"host_call","id":7,"op":"emit_event","args":{...}}
      host  -> plugin   {"type":"host_call_result","id":7,"result":true}

  Host calls are synchronous: the plugin blocks reading the reply, so the runner answers them
  inline while waiting for the action result. This keeps the plugin free of any WASM/C toolchain
  while preserving the same manifest/contract surface.
  """
  @behaviour Exoforge.Contracts.PluginRunner
  use GenServer
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.Domain.Manifest
  alias Exoforge.EventDispatcher
  alias Exoforge.WorkerRegistry

  @runner_key :native_runner

  @doc "Prepares the manifest by ensuring the proxy module is created and set as entry_point."
  def prepare_manifest(%Manifest{} = manifest) do
    Exoforge.Drivers.Runtime.PluginProxy.prepare(manifest, __MODULE__, native_module_name(manifest))
  end

  @impl true
  def load(%Manifest{} = manifest) do
    case find_binary_path(manifest) do
      {:ok, binary_path} ->
        updated_manifest = prepare_manifest(manifest)
        Exoforge.PluginRegistry.register(updated_manifest)

        runner_name = via_name(manifest.id)
        sup_name = Module.concat([Exoforge, Plugins, module_name(manifest), Supervisor])

        child_spec = %{
          id: sup_name,
          start: {
            Supervisor,
            :start_link,
            [
              [
                %{
                  id: __MODULE__,
                  start: {__MODULE__, :start_link, [{updated_manifest, binary_path, runner_name}]}
                }
              ],
              [name: sup_name, strategy: :one_for_one]
            ]
          },
          type: :supervisor
        }

        DynamicSupervisor.start_child(Exoforge.PluginSupervisor, child_spec)

      {:error, reason} ->
        Logger.error("[NativePluginRunner] No binary for #{manifest.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def start_link({%Manifest{} = manifest, binary_path, name}) do
    GenServer.start_link(__MODULE__, {manifest, binary_path}, name: name)
  end

  @doc "Forwards an inbound BEAM event to the plugin process as an `event` frame."
  def dispatch_event(plugin_id, event_key, payload, _context) do
    case WorkerRegistry.lookup(plugin_id, @runner_key) do
      {:ok, pid} ->
        send(pid, {:forward_event, event_key, payload})
        :ok

      _ ->
        :ignored
    end
  end

  @doc "Executes an action on a running native plugin."
  def execute_action(plugin_id, action, payload, timeout \\ 5000) do
    case WorkerRegistry.lookup(plugin_id, @runner_key) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, {:execute_action, to_string(action), payload}, timeout)
        catch
          :exit, {:timeout, _} -> {:error, :timeout}
          :exit, reason -> {:error, {:plugin_crashed, reason}}
        end

      {:error, :not_found} ->
        {:error, {:plugin_not_running, plugin_id}}
    end
  end

  @impl true
  def init({manifest, binary_path}) do
    Logger.info("[NativePluginRunner] Starting native plugin #{manifest.id} from #{binary_path}")

    port =
      Port.open({:spawn_executable, binary_path}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide
      ])

    # Subscribe to the events this plugin declared so the host can forward them. The declared
    # topic matters: EventDispatcher keys subscriptions by {event, topic}.
    Enum.each(declared_events(manifest), fn
      {event, topic} when is_binary(topic) and topic != "" -> EventDispatcher.subscribe(event, topic: topic)
      {event, _topic} -> EventDispatcher.subscribe(event)
    end)

    {:ok, %{manifest: manifest, port: port, buffer: "", pending: %{}, seq: 0}}
  end

  @impl true
  def handle_call({:execute_action, action, payload}, from, state) do
    seq = state.seq + 1
    request = Jason.encode!(%{type: "action", id: seq, action: action, payload: payload || %{}})

    Port.command(state.port, request <> "\n")

    {:noreply, %{state | seq: seq, pending: Map.put(state.pending, seq, from)}}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, %{port: port} = state) do
    {lines, rest} = split_lines(state.buffer <> chunk)
    state = Enum.reduce(lines, %{state | buffer: rest}, &handle_line/2)
    {:noreply, state}
  end

  def handle_info({:forward_event, event_key, payload}, state) do
    send_event(state, event_key, payload)
    {:noreply, state}
  end

  def handle_info({:exo_event, event_key, payload, _context}, state) do
    send_event(state, event_key, payload)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("[NativePluginRunner] Plugin #{state.manifest.id} exited with status #{status}")

    Enum.each(state.pending, fn {_id, from} ->
      GenServer.reply(from, {:error, {:plugin_exited, status}})
    end)

    {:stop, {:plugin_exited, status}, %{state | pending: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp send_event(state, event_key, payload) do
    frame = Jason.encode!(%{type: "event", event: to_string(event_key), payload: sanitize(payload)})
    Port.command(state.port, frame <> "\n")
  rescue
    _ -> :ok
  end

  defp declared_events(manifest) do
    manifest
    |> Exoforge.PluginRegistry.manifest_services()
    |> Enum.flat_map(fn svc -> Map.get(svc, :events) || Map.get(svc, "events") || [] end)
    |> Enum.map(fn
      %{name: name, topic: topic} -> {name, topic}
      %{"name" => name, "topic" => topic} -> {name, topic}
      %{name: name} -> {name, nil}
      %{"name" => name} -> {name, nil}
      other -> {other, nil}
    end)
  end

  # -- Wire protocol --

  defp handle_line("", state), do: state

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "action_result"} = msg} ->
        reply_action_result(msg, state)

      {:ok, %{"type" => "host_call"} = msg} ->
        answer_host_call(msg, state)
        state

      {:ok, _other} ->
        state

      {:error, reason} ->
        Logger.warning("[NativePluginRunner] Bad frame from #{state.manifest.id}: #{inspect(reason)}")
        state
    end
  end

  defp reply_action_result(msg, state) do
    id = Map.get(msg, "id")

    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        state

      {from, pending} ->
        reply =
          case Map.get(msg, "status") do
            "ok" -> {:ok, Map.get(msg, "data")}
            _ -> {:error, normalize_error(Map.get(msg, "error"))}
          end

        GenServer.reply(from, reply)
        %{state | pending: pending}
    end
  end

  defp answer_host_call(%{"id" => id, "op" => op, "args" => args}, state) do
    result = run_host_call(op, args || %{}, state.manifest)
    response = Jason.encode!(%{type: "host_call_result", id: id, result: sanitize(result)})
    Port.command(state.port, response <> "\n")
  end

  defp answer_host_call(_, _state), do: :ok

  # -- Host capabilities --

  defp run_host_call("emit_event", args, _manifest) do
    topic = Map.get(args, "topic", "")
    event = Map.get(args, "event", "")
    payload = Map.get(args, "payload")

    # Subscriptions are keyed by atom (see declared_events/1), so normalise here.
    event_key = Exoforge.Atoms.existing(event, event)

    opts = if topic == "", do: [], else: [topic: topic]
    EventDispatcher.broadcast(event_key, payload, opts)
    true
  end

  defp run_host_call("db_put", args, manifest) do
    db_put(manifest, Map.get(args, "table"), Map.get(args, "key"), Map.get(args, "value"))
  end

  defp run_host_call("db_get", args, manifest) do
    case db_get(manifest, Map.get(args, "table"), Map.get(args, "key")) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp run_host_call("db_all", args, manifest) do
    case db_all(manifest, Map.get(args, "table")) do
      {:ok, rows} when is_list(rows) -> rows
      _ -> []
    end
  end

  defp run_host_call("db_delete", args, manifest) do
    db_delete(manifest, Map.get(args, "table"), Map.get(args, "key"))
  end

  defp run_host_call("call_action", args, _manifest) do
    service = Map.get(args, "service", "")
    action = Map.get(args, "action", "")
    payload = Map.get(args, "payload")

    case ActionDispatcher.dispatch(Exoforge.Atoms.existing(service, service), Exoforge.Atoms.existing(action, action), payload) do
      {:ok, result} -> result
      :ok -> true
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp run_host_call("log", args, manifest) do
    Logger.info("[#{manifest.id}] #{Map.get(args, "message", "")}")
    true
  end

  defp run_host_call("clock_now", _args, _manifest), do: System.system_time(:millisecond)

  defp run_host_call(_op, _args, _manifest), do: false

  # Key-value helpers exposed by the :database plugin (same shape the WASM host bridge uses).
  # Resolved dynamically so the kernel never links against a plugin module.
  defp db_put(manifest, table, key, value) do
    db_call(:put, [manifest.id, table, key, value])
    true
  end

  defp db_get(manifest, table, key), do: db_call(:get, [manifest.id, table, key])

  defp db_all(manifest, table), do: db_call(:all, [manifest.id, table])

  defp db_delete(manifest, table, key) do
    db_call(:delete, [manifest.id, table, key])
    true
  end

  defp db_call(fun, args) do
    apply(Module.concat([Exoforge, Std, Database]), fun, args)
  end

  # -- Helpers --

  defp sanitize(result), do: Exoforge.PluginRegistry.sanitize_for_json(result)

  defp normalize_error(nil), do: "unknown_error"
  defp normalize_error(error) when is_binary(error), do: error
  defp normalize_error(error), do: inspect(error)


  defp split_lines(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp find_binary_path(manifest) do
    dir = manifest.physical_path || ""

    # `prepare_manifest/1` replaces entry_point with the proxy module, so the binary is
    # always named after the plugin id.
    candidates =
      [
        Path.join(dir, to_string(manifest.id)),
        if(is_binary(manifest.entry_point), do: Path.join(dir, manifest.entry_point))
      ]
      |> Enum.reject(&is_nil/1)

    case Enum.find(candidates, &File.regular?/1) do
      nil -> {:error, {:binary_not_found, candidates}}
      path -> {:ok, path}
    end
  end

  defp native_module_name(manifest), do: Module.concat([Exoforge, Plugins, manifest.id, Native])

  defp via_name(plugin_id), do: WorkerRegistry.via_tuple(plugin_id, @runner_key)

  defp module_name(manifest) do
    if is_atom(manifest.entry_point) and manifest.entry_point != nil do
      manifest.entry_point
    else
      manifest.id
    end
  end
end
