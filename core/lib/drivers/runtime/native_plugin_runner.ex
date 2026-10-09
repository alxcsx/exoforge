defmodule Exoforge.Drivers.Runtime.NativePluginRunner do
  @moduledoc """
  Runs a C# plugin compiled to a self-contained native binary (NativeAOT).

  The binary is spawned as an OS process and speaks newline-delimited JSON over stdio. The frames
  and the handshake are `Exoforge.Drivers.Runtime.PluginProtocol`; a plugin that does not speak the
  host's protocol or cannot handle what the host sends is refused with a reason rather than fed
  frames it cannot parse. Host calls are synchronous: the plugin blocks reading the reply, so the
  runner answers them inline while waiting for the action result. This keeps the plugin free of any
  WASM/C toolchain while preserving the same manifest/contract surface.
  """
  @behaviour Exoforge.Contracts.PluginRunner
  use GenServer
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.PluginProtocol
  alias Exoforge.EventDispatcher
  alias Exoforge.WorkerRegistry

  @runner_key :native_runner

  # The OS already accounts for a process's CPU and peak memory, so metering samples it instead of
  # instrumenting the plugin. Five seconds is often enough for a billing-quality number and cheap
  # enough to leave on; `VmHWM` is a high-water mark, so a peak between samples is never lost.
  @os_sample_ms 5_000

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
                # `:transient`, not permanent: a plugin the OS killed should be replaced, but a
                # plugin that is incompatible must not be restarted forever. `refuse/2` stops with
                # `{:shutdown, ...}`, which a transient child does not restart; a crash does.
                %{
                  id: __MODULE__,
                  restart: :transient,
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
    start_link({manifest, binary_path, name, PluginProtocol.handshake_timeout_ms()})
  end

  def start_link({%Manifest{} = manifest, binary_path, name, handshake_timeout_ms}) do
    GenServer.start_link(__MODULE__, {manifest, binary_path, handshake_timeout_ms}, name: name)
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

  @doc """
  The operating-system pid of the plugin process.

  The only handle on a plugin from outside the BEAM. The OS accounts for the process's CPU and memory
  there, so this is what usage metering reads, and what makes a kill test a real one rather than a
  test of the runner's own protocol.
  """
  def os_pid(pid) when is_pid(pid), do: GenServer.call(pid, :os_pid)

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
  def init({manifest, binary_path, handshake_timeout_ms}) do
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

    Port.command(port, PluginProtocol.hello_frame() <> "\n")
    handshake_timer = Process.send_after(self(), :handshake_timeout, handshake_timeout_ms)

    # Metering is on from the first start: the first start is the uptime origin, later ones are
    # restarts.
    Exoforge.Metering.record_start(manifest.id)
    schedule_os_sample()

    {:ok,
     %{
       manifest: manifest,
       port: port,
       buffer: "",
       pending: %{},
       seq: 0,
       handshake: nil,
       handshake_timer: handshake_timer
     }}
  end

  @impl true
  def handle_call(:os_pid, _from, state) do
    # Port.info returns {:os_pid, pid}; the bare pid is what callers want.
    os_pid =
      case Port.info(state.port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    {:reply, os_pid, state}
  end

  def handle_call({:execute_action, action, payload}, from, state) do
    seq = state.seq + 1
    request = Jason.encode!(%{type: "action", id: seq, action: action, payload: payload || %{}})

    Port.command(state.port, request <> "\n")

    # The pending entry carries what metering needs: who to reply to, and the clock and request
    # size the reply will be measured against.
    entry = %{
      from: from,
      action: action,
      t0: System.monotonic_time(:microsecond),
      bytes_in: byte_size(request)
    }

    {:noreply, %{state | seq: seq, pending: Map.put(state.pending, seq, entry)}}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, %{port: port} = state) do
    {lines, rest} = split_lines(state.buffer <> chunk)

    case run_lines(lines, %{state | buffer: rest}) do
      {:ok, state} -> {:noreply, state}
      {:stop, reason, state} -> {:stop, reason, state}
    end
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
    # A process that dies without a hello most often cannot start at all: the runtime it was built
    # against is not in this image, or the binary is not what the manifest says. Say so, because
    # the exit status alone sends the reader looking in the wrong place.
    if is_nil(state.handshake) do
      Logger.error(
        "[NativePluginRunner] #{state.manifest.id} exited before the protocol handshake. " <>
          "If it was built for a newer .NET, this image may not carry that runtime."
      )
    end

    Logger.warning("[NativePluginRunner] Plugin #{state.manifest.id} exited with status #{status}")

    Enum.each(state.pending, fn {_id, entry} ->
      record_call(state.manifest.id, entry, :exited, 0)
      GenServer.reply(entry.from, {:error, {:plugin_exited, status}})
    end)

    {:stop, {:plugin_exited, status}, %{state | pending: %{}}}
  end

  def handle_info(:handshake_timeout, %{handshake: nil} = state), do: refuse(state, :no_handshake)
  def handle_info(:handshake_timeout, state), do: {:noreply, state}

  def handle_info(:sample_os, state) do
    case Port.info(state.port, :os_pid) do
      {:os_pid, os_pid} -> Exoforge.Metering.sample_os(state.manifest.id, os_pid)
      _ -> :ok
    end

    schedule_os_sample()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_os_sample, do: Process.send_after(self(), :sample_os, @os_sample_ms)

  defp run_lines(lines, state) do
    Enum.reduce_while(lines, {:ok, state}, fn line, {:ok, state} ->
      case handle_line(line, state) do
        {:stop, reason, state} -> {:halt, {:stop, reason, state}}
        state -> {:cont, {:ok, state}}
      end
    end)
  end

  defp send_event(state, event_key, payload) do
    frame = Jason.encode!(%{type: "event", event: to_string(event_key), payload: sanitize(payload)})
    Port.command(state.port, frame <> "\n")
    Exoforge.Metering.record_event(state.manifest.id, event_key)
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
      {:ok, %{"type" => "hello"} = msg} ->
        handle_hello(msg, state)

      {:ok, %{"type" => "action_result"} = msg} ->
        reply_action_result(msg, byte_size(line), state)

      {:ok, %{"type" => "host_call"} = msg} ->
        answer_host_call(msg, state)
        state

      # A plugin's own logs, including the exception trace the SDK now sends. Dropped until now,
      # which meant a plugin that threw said nothing anywhere: the caller got a message, and the
      # file and line that would fix it went into the void.
      {:ok, %{"type" => "host_log"} = msg} ->
        log_from_plugin(msg, state)
        state

      {:ok, _other} ->
        state

      {:error, reason} ->
        Logger.warning("[NativePluginRunner] Bad frame from #{state.manifest.id}: #{inspect(reason)}")
        state
    end
  end

  # The handshake. The plugin states its protocol and the frames it handles; the host decides
  # whether it can run the pair, and says what is wrong when it cannot.
  defp handle_hello(_msg, %{handshake: %{}} = state), do: state

  defp handle_hello(msg, state) do
    if state.handshake_timer, do: Process.cancel_timer(state.handshake_timer)

    case PluginProtocol.accept_hello(msg) do
      {:ok, handshake} ->
        Logger.info(
          "[NativePluginRunner] #{state.manifest.id} speaks protocol #{handshake.protocol} " <>
            "(#{Enum.join(handshake.capabilities, ", ")})"
        )

        %{state | handshake: handshake, handshake_timer: nil}

      {:refuse, reason} ->
        refuse(state, reason)
    end
  end

  defp refuse(state, reason) do
    Logger.error(
      "[NativePluginRunner] Refusing #{state.manifest.id}: #{PluginProtocol.refusal(reason)}. " <>
        "Rebuild the plugin against the current SDK, or update the image."
    )

    Enum.each(state.pending, fn {_id, entry} ->
      GenServer.reply(entry.from, {:error, {:plugin_incompatible, reason}})
    end)

    {:stop, {:shutdown, {:plugin_incompatible, reason}}, %{state | pending: %{}}}
  end

  # The plugin's own log and exception channel. The same line goes to the server log and to the
  # developer-facing buffer: `exo plugin logs` reads the buffer, and an exception trace is exactly
  # what a developer is looking for there.
  defp log_from_plugin(msg, state) do
    record_log(state.manifest.id, Map.get(msg, "level", 1), Map.get(msg, "message", ""))
  end

  defp record_log(plugin_id, level, message) do
    # Keep it where the developer can see it: the server log alone is invisible from Unity. A
    # rate-limited line does not reach here at all, so a flood cannot fill the operator's log either.
    if Exoforge.PluginLogs.append(plugin_id, level, message) == :ok do
      case level do
        0 -> Logger.debug("[#{plugin_id}] #{message}")
        2 -> Logger.warning("[#{plugin_id}] #{message}")
        3 -> Logger.error("[#{plugin_id}] #{message}")
        _ -> Logger.info("[#{plugin_id}] #{message}")
      end
    end
  end

  defp reply_action_result(msg, bytes_out, state) do
    id = Map.get(msg, "id")

    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        state

      {entry, pending} ->
        status = Map.get(msg, "status")

        reply =
          case status do
            "ok" -> {:ok, Map.get(msg, "data")}
            _ -> {:error, normalize_error(Map.get(msg, "error"))}
          end

        record_call(state.manifest.id, entry, if(status == "ok", do: :ok, else: :error), bytes_out)
        GenServer.reply(entry.from, reply)
        %{state | pending: pending}
    end
  end

  # Metered where the wire bytes are known: the request size at send, the reply size here. `:exited`
  # is a call the plugin never answered because its process died.
  defp record_call(plugin_id, entry, status, bytes_out) do
    duration_us = System.monotonic_time(:microsecond) - entry.t0

    Exoforge.Metering.record_invocation(
      plugin_id,
      entry.action,
      duration_us,
      status,
      entry.bytes_in,
      bytes_out
    )
  end

  defp answer_host_call(%{"id" => id, "op" => op, "args" => args}, state) do
    result = run_host_call(op, args || %{}, state.manifest)
    Exoforge.Metering.record_host_call(state.manifest.id, op)
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

  defp run_host_call("call_action", args, manifest) do
    service = Map.get(args, "service", "")
    action = Map.get(args, "action", "")
    payload = Map.get(args, "payload")

    cond do
      not Manifest.allows_service?(manifest, service) ->
        # Same rule as the WASM runner: a plugin calls what it declared, nothing else.
        Logger.warning("[NativePluginRunner] #{manifest.id} called undeclared service #{service}")
        %{error: "service_not_declared"}

      self_call?(manifest, service) ->
        # Dispatching here would GenServer.call this very process, which is busy answering this
        # host call, so the plugin would block until the timeout and take the runner with it.
        %{error: "cannot_call_own_service"}

      true ->
        case ActionDispatcher.dispatch(
               Exoforge.Atoms.existing(service, service),
               Exoforge.Atoms.existing(action, action),
               payload
             ) do
          {:ok, result} -> result
          :ok -> true
          {:error, reason} -> %{error: inspect(reason)}
        end
    end
  end

  defp run_host_call("log", args, manifest) do
    record_log(manifest.id, Map.get(args, "level", 1), Map.get(args, "message", ""))
    true
  end

  defp run_host_call("clock_now", _args, _manifest), do: System.system_time(:millisecond)

  defp run_host_call(_op, _args, _manifest), do: false

  defp self_call?(manifest, service) do
    svc = to_string(service)
    owned = (manifest.provides || []) ++ (manifest.services || [])
    Enum.any?(owned, &(Manifest.service_name(&1) == svc))
  end

  # Key-value helpers exposed by the :database plugin (same shape the WASM host bridge uses).
  # Resolved dynamically so the kernel never links against a plugin module.
  defp db_put(manifest, table, key, value) do
    case db_call(:put, [manifest.id, table, key, value]) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp db_get(manifest, table, key), do: db_call(:get, [manifest.id, table, key])

  defp db_all(manifest, table), do: db_call(:all, [manifest.id, table])

  defp db_delete(manifest, table, key) do
    case db_call(:delete, [manifest.id, table, key]) do
      {:ok, _} -> true
      _ -> false
    end
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
    # always named after the plugin id. `.exoforge/` is where `exo plugin build` stages it; the
    # plugin root is the older layout, kept so an already-deployed plugin still loads.
    staged = Path.join(dir, ".exoforge")

    candidates =
      [
        Path.join(staged, to_string(manifest.id)),
        Path.join(dir, to_string(manifest.id)),
        if(is_binary(manifest.entry_point), do: Path.join(staged, manifest.entry_point)),
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
