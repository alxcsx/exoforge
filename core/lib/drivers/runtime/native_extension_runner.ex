defmodule Exoforge.Drivers.Runtime.NativeExtensionRunner do
  @moduledoc """
  Runs a C# extension as an OS process: a framework-dependent .NET binary, spawned over stdio.

  The binary is spawned as an OS process and speaks newline-delimited JSON over stdio. The frames
  and the handshake are `Exoforge.Drivers.Runtime.ExtensionProtocol`; an extension that does not speak the
  host's protocol or cannot handle what the host sends is refused with a reason rather than fed
  frames it cannot parse. Host calls are synchronous: the extension blocks reading the reply, so the
  runner answers them inline while waiting for the action result. This keeps the extension free of any
  toolchain beyond `dotnet publish` while preserving the same manifest/contract surface.
  """
  @behaviour Exoforge.Contracts.ExtensionRunner
  use GenServer
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.ExtensionProtocol
  alias Exoforge.EventDispatcher
  alias Exoforge.ExtensionRegistry
  alias Exoforge.WorkerRegistry

  @runner_key :native_runner

  # The OS already accounts for a process's CPU and peak memory, so metering samples it instead of
  # instrumenting the extension. Five seconds is often enough for a billing-quality number and cheap
  # enough to leave on; `VmHWM` is a high-water mark, so a peak between samples is never lost.
  @os_sample_ms 5_000

  @doc "Prepares the manifest by ensuring the proxy module is created and set as entry_point."
  def prepare_manifest(%Manifest{} = manifest) do
    Exoforge.Drivers.Runtime.ExtensionProxy.prepare(manifest, __MODULE__, native_module_name(manifest))
  end

  @impl true
  def load(%Manifest{} = manifest) do
    case find_binary_path(manifest) do
      {:ok, binary_path} ->
        updated_manifest = prepare_manifest(manifest)
        Exoforge.ExtensionRegistry.register(updated_manifest)

        sup_name = Module.concat([Exoforge, Extensions, module_name(manifest), Supervisor])

        pool_size = Application.get_env(:exoforge, :native_extension_pool_size, 1)

        children =
          Enum.map(1..pool_size, fn idx ->
            runner_name = via_name(manifest.id, idx)

            %{
              id: {__MODULE__, idx},
              restart: :transient,
              start: {
                __MODULE__,
                :start_link,
                [{updated_manifest, binary_path, runner_name, idx, ExtensionProtocol.handshake_timeout_ms()}]
              }
            }
          end)

        child_spec = %{
          id: sup_name,
          restart: :temporary,
          start: {
            Supervisor,
            :start_link,
            [children, [name: sup_name, strategy: :one_for_one, max_restarts: 3, max_seconds: 5]]
          },
          type: :supervisor
        }

        DynamicSupervisor.start_child(Exoforge.ExtensionSupervisor, child_spec)

      {:error, reason} ->
        Logger.error("[NativeExtensionRunner] No binary for #{manifest.id}: #{inspect(reason)}")
        ExtensionRegistry.mark_crashed(manifest.id, reason)
        {:error, reason}
    end
  end

  def start_link({%Manifest{} = manifest, binary_path, name}) do
    start_link({manifest, binary_path, name, 1, ExtensionProtocol.handshake_timeout_ms()})
  end

  def start_link({%Manifest{} = manifest, binary_path, name, handshake_timeout_ms})
      when is_integer(handshake_timeout_ms) do
    start_link({manifest, binary_path, name, 1, handshake_timeout_ms})
  end

  def start_link({%Manifest{} = manifest, binary_path, name, idx, handshake_timeout_ms}) do
    GenServer.start_link(__MODULE__, {manifest, binary_path, idx, handshake_timeout_ms}, name: name)
  end

  @doc "Forwards an inbound BEAM event to the extension process as an `event` frame."
  def dispatch_event(extension_id, event_key, payload, _context) do
    case WorkerRegistry.lookup(extension_id, {@runner_key, 1}) do
      {:ok, pid} ->
        send(pid, {:forward_event, event_key, payload})
        :ok

      _ ->
        :ignored
    end
  end

  @doc """
  The operating-system pid of the extension process.

  The only handle on an extension from outside the BEAM. The OS accounts for the process's CPU and memory
  there, so this is what usage metering reads, and what makes a kill test a real one rather than a
  test of the runner's own protocol.
  """
  def os_pid(pid) when is_pid(pid), do: GenServer.call(pid, :os_pid)

  @doc "Executes an action on a running native extension."
  def execute_action(extension_id, action, payload, timeout \\ 5000) do
    pool_size = Application.get_env(:exoforge, :native_extension_pool_size, 1)
    idx = :erlang.phash2(make_ref(), pool_size) + 1

    case WorkerRegistry.lookup(extension_id, {@runner_key, idx}) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, {:execute_action, to_string(action), payload}, timeout)
        catch
          :exit, {:timeout, _} -> {:error, :timeout}
          :exit, reason -> {:error, {:extension_crashed, reason}}
        end

      {:error, :not_found} ->
        case ExtensionRegistry.get_crash_info(extension_id) do
          {:crashed, reason} ->
            {:error, {:extension_crashed, reason}}

          _ ->
            {:error, {:extension_not_running, extension_id}}
        end
    end
  end

  @impl true
  def init({manifest, binary_path, handshake_timeout_ms}) when is_integer(handshake_timeout_ms) do
    init({manifest, binary_path, 1, handshake_timeout_ms})
  end

  def init({manifest, binary_path, idx, handshake_timeout_ms}) do
    Process.flag(:trap_exit, true)
    Logger.debug("[NativeExtensionRunner] Starting native extension #{manifest.id} (worker #{idx}) from #{binary_path}")

    port =
      Port.open({:spawn_executable, binary_path}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide
      ])

    # Only worker 1 subscribes to events and records start metrics to prevent duplicate broadcasts/metering
    if idx == 1 do
      Enum.each(declared_events(manifest), fn
        {event, topic} when is_binary(topic) and topic != "" -> EventDispatcher.subscribe(event, topic: topic)
        {event, _topic} -> EventDispatcher.subscribe(event)
      end)

      # Metering is on from the first start: the first start is the uptime origin, later ones are restarts.
      Exoforge.Metering.record_start(manifest.id)
    end

    Port.command(port, ExtensionProtocol.hello_frame() <> "\n")
    handshake_timer = Process.send_after(self(), :handshake_timeout, handshake_timeout_ms)

    schedule_os_sample()

    {:ok,
     %{
       manifest: manifest,
       port: port,
       buffer: "",
       pending: %{},
       seq: 0,
       handshake: nil,
       handshake_timer: handshake_timer,
       worker_idx: idx
     }}
  end

  @impl true
  def handle_call(:os_pid, _from, state) do
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
    if is_nil(state.handshake) do
      Logger.error(
        "[NativeExtensionRunner] #{state.manifest.id} exited before the protocol handshake (exit status #{status}). " <>
          "This usually indicates: 1) LIBC/RID MISMATCH: The binary was compiled for glibc (e.g. linux-x64) instead of musl (e.g. linux-musl-x64) for Alpine Linux; " <>
          "2) RUNTIME PACK: The required .NET runtime is missing from the container image; or 3) MISSING DEPENDENCY. " <>
          "The extension has been marked as crashed and isolated to protect the cluster supervision tree."
      )

      ExtensionRegistry.mark_crashed(state.manifest.id, {:exit_before_handshake, status})

      Enum.each(state.pending, fn {_id, entry} ->
        record_call(state.manifest.id, entry, :exited, 0)
        GenServer.reply(entry.from, {:error, {:extension_crashed, {:exit_before_handshake, status}}})
      end)

      {:stop, {:shutdown, {:extension_exited, status}}, %{state | pending: %{}}}
    else
      Logger.warning("[NativeExtensionRunner] Extension #{state.manifest.id} exited with status #{status}")

      ExtensionRegistry.mark_crashed(state.manifest.id, {:extension_exited, status})

      Enum.each(state.pending, fn {_id, entry} ->
        record_call(state.manifest.id, entry, :exited, 0)
        GenServer.reply(entry.from, {:error, {:extension_exited, status}})
      end)

      {:stop, {:extension_exited, status}, %{state | pending: %{}}}
    end
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

  @impl true
  def terminate(_reason, %{port: port} = _state) do
    try do
      case Port.info(port, :os_pid) do
        {:os_pid, pid} when is_integer(pid) and pid > 0 ->
          kill_os_process(pid)

        _ ->
          :ok
      end
    catch
      _, _ -> :ok
    end

    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp kill_os_process(pid) do
    case :os.type() do
      {:win32, _} ->
        System.cmd("taskkill", ["/F", "/T", "/PID", to_string(pid)], stderr_to_stdout: true)

      _ ->
        System.cmd("kill", ["-9", to_string(pid)], stderr_to_stdout: true)
    end
  rescue
    _ -> :ok
  end

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
    |> Exoforge.ExtensionRegistry.manifest_services()
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

      {:ok, %{"type" => "host_log"} = msg} ->
        log_from_extension(msg, state)
        state

      {:ok, _other} ->
        state

      {:error, reason} ->
        Logger.warning("[NativeExtensionRunner] Bad frame from #{state.manifest.id}: #{inspect(reason)}")
        state
    end
  end

  defp handle_hello(_msg, %{handshake: %{}} = state), do: state

  defp handle_hello(msg, state) do
    if state.handshake_timer, do: Process.cancel_timer(state.handshake_timer)

    case ExtensionProtocol.accept_hello(msg) do
      {:ok, handshake} ->
        Logger.debug(
          "[NativeExtensionRunner] #{state.manifest.id} speaks protocol #{handshake.protocol} " <>
            "(#{Enum.join(handshake.capabilities, ", ")})"
        )

        %{state | handshake: handshake, handshake_timer: nil}

      {:refuse, reason} ->
        refuse(state, reason)
    end
  end

  defp refuse(state, reason) do
    Logger.error(
      "[NativeExtensionRunner] Refusing #{state.manifest.id}: #{ExtensionProtocol.refusal(reason)}. " <>
        "Rebuild the extension against the current SDK, or update the image."
    )

    ExtensionRegistry.mark_crashed(state.manifest.id, {:handshake_refused, reason})

    Enum.each(state.pending, fn {_id, entry} ->
      GenServer.reply(entry.from, {:error, {:extension_incompatible, reason}})
    end)

    {:stop, {:shutdown, {:extension_incompatible, reason}}, %{state | pending: %{}}}
  end

  defp log_from_extension(msg, state) do
    record_log(state.manifest.id, Map.get(msg, "level", 1), Map.get(msg, "message", ""))
  end

  defp record_log(extension_id, level, message) do
    if Exoforge.ExtensionLogs.append(extension_id, level, message) == :ok do
      case level do
        0 -> Logger.debug("[#{extension_id}] #{message}")
        2 -> Logger.warning("[#{extension_id}] #{message}")
        3 -> Logger.error("[#{extension_id}] #{message}")
        _ -> Logger.info("[#{extension_id}] #{message}")
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

  defp record_call(extension_id, entry, status, bytes_out) do
    duration_us = System.monotonic_time(:microsecond) - entry.t0

    Exoforge.Metering.record_invocation(
      extension_id,
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
        Logger.warning("[NativeExtensionRunner] #{manifest.id} called undeclared service #{service}")
        %{error: "service_not_declared"}

      self_call?(manifest, service) ->
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

  defp db_put(manifest, table, key, value) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           extension: manifest.id,
           operation: %{action: :put, table: table, id: key, data: value}
         }) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp db_get(manifest, table, key) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           extension: manifest.id,
           operation: %{action: :get, table: table, id: key}
         }) do
      {:ok, %{rows: [record]}} -> {:ok, record}
      {:ok, %{"rows" => [record]}} -> {:ok, record}
      _ -> {:error, :not_found}
    end
  end

  defp db_all(manifest, table) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           extension: manifest.id,
           operation: %{action: :all, table: table}
         }) do
      {:ok, %{rows: rows}} when is_list(rows) -> {:ok, rows}
      {:ok, %{"rows" => rows}} when is_list(rows) -> {:ok, rows}
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      error -> error
    end
  end

  defp db_delete(manifest, table, key) do
    case ActionDispatcher.dispatch(:database, :execute, %{
           extension: manifest.id,
           operation: %{action: :delete, table: table, id: key}
         }) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # -- Helpers --

  defp sanitize(result), do: Exoforge.ExtensionRegistry.sanitize_for_json(result)

  defp normalize_error(nil), do: "unknown_error"
  defp normalize_error(%{"code" => code, "message" => msg}), do: {String.to_atom(code), msg}
  defp normalize_error(error) when is_binary(error), do: error
  defp normalize_error(error), do: inspect(error)

  defp split_lines(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp find_binary_path(manifest) do
    dir = manifest.physical_path || ""
    staged = Path.join(dir, ".exoforge")
    id_str = to_string(manifest.id)
    ep_str = if is_binary(manifest.entry_point), do: manifest.entry_point, else: nil

    candidates =
      [
        Path.join(staged, id_str),
        Path.join(staged, id_str <> ".exe"),
        Path.join(dir, id_str),
        Path.join(dir, id_str <> ".exe"),
        if(ep_str, do: Path.join(staged, ep_str)),
        if(ep_str, do: Path.join(staged, ep_str <> ".exe")),
        if(ep_str, do: Path.join(dir, ep_str)),
        if(ep_str, do: Path.join(dir, ep_str <> ".exe"))
      ]
      |> Enum.reject(&is_nil/1)

    case Enum.find(candidates, &File.regular?/1) do
      nil -> {:error, {:binary_not_found, candidates}}
      path -> {:ok, path}
    end
  end

  defp native_module_name(manifest), do: Module.concat([Exoforge, Extensions, manifest.id, Native])

  defp via_name(extension_id, idx) do
    WorkerRegistry.via_tuple(extension_id, {@runner_key, idx})
  end

  defp module_name(manifest) do
    if is_atom(manifest.entry_point) and manifest.entry_point != nil do
      manifest.entry_point
    else
      manifest.id
    end
  end
end
