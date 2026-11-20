defmodule Exoforge.Drivers.Runtime.NativeExtensionRunner do
  @moduledoc """
  Runs a C# extension as an OS process: a framework-dependent .NET binary, spawned over stdio.

  The binary is spawned as an OS process and speaks newline-delimited JSON over stdio. The frames
  and the handshake are `Exoforge.Drivers.Runtime.ExtensionProtocol`; an extension that does not speak the
  host's protocol or cannot handle what the host sends is refused with a reason rather than fed
  frames it cannot parse. Host calls are multiplexed by id: the extension may have several in
  flight, so the runner answers each as it arrives while the action result is still pending. This
  keeps the extension free of any toolchain beyond `dotnet publish` while preserving the same
  manifest/contract surface.
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

  # OS sample interval and stderr tail capture limits
  @os_sample_ms 5_000
  @max_stderr_bytes 64 * 1024
  @max_stderr_lines 20
  # How often what the process writes to stderr is copied into the extension's logs, and how much per pass.
  @stderr_poll_ms 2_000
  @stderr_lines_per_pass 100

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
          # The request context rides along: the extension may call other services or log from
          # inside this action, and those must still answer "who asked, and in which request".
          GenServer.call(
            pid,
            {:execute_action, to_string(action), payload, Exoforge.RequestContext.current()},
            timeout
          )
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

    stderr_path =
      Path.join(
        System.tmp_dir!(),
        "exoforge_ext_stderr_#{manifest.id}_#{idx}_#{System.unique_integer([:positive])}.log"
      )

    _ = File.touch(stderr_path)

    {spawn_exec, spawn_args} =
      case :os.type() do
        {:win32, _} ->
          cmd = System.find_executable("cmd.exe") || "cmd.exe"
          {cmd, ["/c", "\"#{binary_path}\" 2>\"#{stderr_path}\""]}

        _ ->
          sh = System.find_executable("sh") || "/bin/sh"
          {sh, ["-c", "exec \"$0\" 2>\"$1\"", binary_path, stderr_path]}
      end

    port =
      Port.open({:spawn_executable, spawn_exec}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        {:args, spawn_args}
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

    Port.command(port, ExtensionProtocol.hello_frame(dialect: active_db_dialect(manifest)) <> "\n")
    handshake_timer = Process.send_after(self(), :handshake_timeout, handshake_timeout_ms)

    schedule_os_sample()
    Process.send_after(self(), :poll_stderr, @stderr_poll_ms)

    {:ok,
     %{
       manifest: manifest,
       port: port,
       buffer: "",
       pending: %{},
       seq: 0,
       current_context: nil,
       handshake: nil,
       handshake_timer: handshake_timer,
       lifecycle: nil,
       lifecycle_timer: nil,
       worker_idx: idx,
       stderr_path: stderr_path,
       stderr_offset: 0
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

  # An extension that is still running its startup hook is not ready for gameplay. Refuse the
  # action instead of racing the hook; the caller can retry after the extension reports ready.
  def handle_call({:execute_action, _action, _payload}, _from, %{lifecycle: :pending} = state) do
    {:reply, {:error, {:extension_starting, state.manifest.id}}, state}
  end

  def handle_call({:execute_action, _action, _payload, _context}, _from, %{lifecycle: :pending} = state) do
    {:reply, {:error, {:extension_starting, state.manifest.id}}, state}
  end

  def handle_call({:execute_action, action, payload}, from, state) do
    handle_call({:execute_action, action, payload, nil}, from, state)
  end

  def handle_call({:execute_action, action, payload, context}, from, state) do
    seq = state.seq + 1
    request = Jason.encode!(%{type: "action", id: seq, action: action, payload: payload || %{}})

    Port.command(state.port, request <> "\n")

    # The pending entry carries what metering needs: who to reply to, and the clock and request
    # size the reply will be measured against. The context is what a host call or a log line made
    # while this action runs is attributed to.
    entry = %{
      from: from,
      action: action,
      context: context,
      t0: System.monotonic_time(:microsecond),
      bytes_in: byte_size(request)
    }

    {:noreply, %{state | seq: seq, pending: Map.put(state.pending, seq, entry), current_context: context}}
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
    # What it printed on its way out is the reason, so it goes into its logs before anything else.
    state = flush_stderr(state)
    record_log(state.manifest.id, 3, "The process exited with status #{status}.")

    if is_nil(state.handshake) do
      stderr_tail = read_stderr_tail(state.stderr_path)
      stderr_msg = format_stderr_msg(stderr_tail, " (no stderr captured)")

      Logger.error(
        "[NativeExtensionRunner] #{state.manifest.id} exited before the protocol handshake (exit status #{status}). " <>
          "This usually indicates: 1) LIBC/RID MISMATCH: The binary was compiled for glibc (e.g. linux-x64) instead of musl (e.g. linux-musl-x64) for Alpine Linux; " <>
          "2) RUNTIME PACK: The required .NET runtime is missing from the container image; or 3) MISSING DEPENDENCY. " <>
          "The extension has been marked as crashed and isolated to protect the cluster supervision tree. " <>
          stderr_msg <> "\nRun: exo extension logs #{state.manifest.id}"
      )

      ExtensionRegistry.mark_crashed(state.manifest.id, {:exit_before_handshake, status, stderr_tail})

      Enum.each(state.pending, fn {_id, entry} ->
        record_call(state.manifest.id, entry, :exited, 0)
        GenServer.reply(entry.from, {:error, {:extension_crashed, {:exit_before_handshake, status, stderr_tail}}})
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

  def handle_info(:lifecycle_timeout, %{lifecycle: :pending} = state) do
    fail_lifecycle(state, "timeout", "the startup hook did not finish")
  end

  def handle_info(:lifecycle_timeout, state), do: {:noreply, state}

  def handle_info(:poll_stderr, state) do
    state = flush_stderr(state)
    Process.send_after(self(), :poll_stderr, @stderr_poll_ms)
    {:noreply, state}
  end

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
  def terminate(_reason, state) do
    if timer = Map.get(state, :lifecycle_timer), do: Process.cancel_timer(timer)
    port = Map.get(state, :port)

    if port do
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
    end

    cleanup_stderr(state)

    :ok
  end

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

      {:ok, %{"type" => "lifecycle_result"} = msg} ->
        handle_lifecycle_result(msg, state)

      {:ok, _other} ->
        state

      {:error, _reason} ->
        # stdout is the wire, so a plain `Console.WriteLine` lands here. It is still the extension talking: it goes
        # into its logs instead of vanishing into the server console.
        if state.handshake, do: record_log(state.manifest.id, 1, "[stdout] " <> String.slice(line, 0, 2_000))
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

        state
        |> Map.put(:handshake, handshake)
        |> Map.put(:handshake_timer, nil)
        |> start_lifecycle()

      {:refuse, reason} ->
        refuse(state, reason)
    end
  end

  # Optional and negotiated: only an extension that declared `lifecycle` receives the frame.
  # Extensions that did not declare it keep the pre-hook behavior and are immediately ready.
  defp start_lifecycle(%{handshake: %{lifecycle: true}} = state) do
    Port.command(state.port, ExtensionProtocol.lifecycle_frame() <> "\n")
    timer = Process.send_after(self(), :lifecycle_timeout, ExtensionProtocol.lifecycle_timeout_ms())
    %{state | lifecycle: :pending, lifecycle_timer: timer}
  end

  defp start_lifecycle(state), do: %{state | lifecycle: :ready}

  defp handle_lifecycle_result(_msg, %{lifecycle: lifecycle} = state) when lifecycle != :pending do
    state
  end

  defp handle_lifecycle_result(msg, state) do
    if state.lifecycle_timer, do: Process.cancel_timer(state.lifecycle_timer)

    case ExtensionProtocol.accept_lifecycle_result(msg) do
      :ok ->
        %{state | lifecycle: :ready, lifecycle_timer: nil}

      {:error, %{code: code, message: message}} ->
        fail_lifecycle(state, code, message)
    end
  end

  defp fail_lifecycle(state, code, message) do
    Logger.error(
      "[NativeExtensionRunner] #{state.manifest.id} failed its startup hook (#{code}): #{message}. " <>
        "The extension has been marked as crashed; fix OnExtensionStart and redeploy."
    )

    ExtensionRegistry.mark_crashed(state.manifest.id, {:startup_failed, %{code: code, message: message}})

    Enum.each(state.pending, fn {_id, entry} ->
      GenServer.reply(entry.from, {:error, {:extension_crashed, {:startup_failed, code}}})
    end)

    {:stop, {:shutdown, {:startup_failed, code}}, %{state | pending: %{}, lifecycle: {:error, code}}}
  end

  defp refuse(state, reason) do
    stderr_tail = read_stderr_tail(state.stderr_path)
    stderr_msg = format_stderr_msg(stderr_tail, "")

    Logger.error(
      "[NativeExtensionRunner] Refusing #{state.manifest.id}: #{ExtensionProtocol.refusal(reason)}. " <>
        "Rebuild the extension against the current SDK, or update the image." <> stderr_msg
    )

    ExtensionRegistry.mark_crashed(state.manifest.id, {:handshake_refused, reason})

    Enum.each(state.pending, fn {_id, entry} ->
      GenServer.reply(entry.from, {:error, {:extension_incompatible, reason}})
    end)

    {:stop, {:shutdown, {:extension_incompatible, reason}}, %{state | pending: %{}}}
  end

  defp log_from_extension(msg, state) do
    # A log line belongs to the request that is running: enter it so the line carries its rid.
    previous = Exoforge.RequestContext.enter(state.current_context)

    try do
      record_log(state.manifest.id, Map.get(msg, "level", 1), Map.get(msg, "message", ""))
    after
      Exoforge.RequestContext.restore(previous)
    end
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

        # Attribute outgoing host calls to the most recent action still in flight.
        current_context =
          case pending |> Map.values() |> Enum.max_by(& &1.t0, fn -> nil end) do
            nil -> nil
            newest -> newest.context
          end

        %{state | pending: pending, current_context: current_context}
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
    previous = Exoforge.RequestContext.enter(state.current_context)

    try do
      result = run_host_call(op, args || %{}, state.manifest)

      # A captured request keeps the boundary crossing: the extension asked the host for this.
      if Exoforge.RequestContext.capturing?() do
        Exoforge.ActionTrace.record(
          state.manifest.id,
          op,
          Exoforge.RequestContext.origin(),
          args || %{},
          result,
          0,
          true,
          :host_call
        )
      end

      Exoforge.Metering.record_host_call(state.manifest.id, op)
      response = Jason.encode!(%{type: "host_call_result", id: id, result: sanitize(result)})
      Port.command(state.port, response <> "\n")
    after
      Exoforge.RequestContext.restore(previous)
    end
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
    case db_put(manifest, Map.get(args, "table"), Map.get(args, "key"), Map.get(args, "value")) do
      {:ok, _} -> true
      {:error, reason} -> %{ok: false, error: inspect(reason)}
    end
  end

  defp run_host_call("db_get", args, manifest) do
    case db_get(manifest, Map.get(args, "table"), Map.get(args, "key")) do
      {:ok, record} -> record
      {:error, :not_found} -> nil
      {:error, reason} -> %{ok: false, error: inspect(reason)}
    end
  end

  defp run_host_call("db_all", args, manifest) do
    case db_all(manifest, Map.get(args, "table")) do
      {:ok, rows} when is_list(rows) -> rows
      {:error, reason} -> %{ok: false, error: inspect(reason)}
    end
  end

  defp run_host_call("db_delete", args, manifest) do
    case db_delete(manifest, Map.get(args, "table"), Map.get(args, "key")) do
      {:ok, _} -> true
      {:error, reason} -> %{ok: false, error: inspect(reason)}
    end
  end

  defp run_host_call("db_batch", args, manifest) do
    if not Manifest.allows_service?(manifest, "database") do
      Logger.warning("[NativeExtensionRunner] #{manifest.id} called undeclared service database")

      %{
        ok: false,
        error: %{
          code: "service_not_declared",
          message: "Service 'database' is not declared in this extension's dependencies."
        }
      }
    else
      operations = extract_batch_operations(args)

      if not is_list(operations) do
        %{
          ok: false,
          error: %{
            code: "invalid_batch",
            message: "db_batch requires an 'operations' list."
          }
        }
      else
        case db_batch(manifest, operations) do
          {:ok, _} ->
            true

          {:error, %{index: idx} = err} when is_integer(idx) ->
            reason = Map.get(err, :reason)
            code = Map.get(err, :code) || batch_error_code(reason)
            message = Map.get(err, :message) || format_batch_error(reason)

            %{
              ok: false,
              index: idx,
              error: %{
                code: to_string(code),
                index: idx,
                message: to_string(message)
              }
            }

          {:error, {:batch_error, idx, reason}} when is_integer(idx) ->
            %{
              ok: false,
              index: idx,
              error: %{
                code: batch_error_code(reason),
                index: idx,
                message: format_batch_error(reason)
              }
            }

          {:error, reason} ->
            %{
              ok: false,
              error: %{
                code: batch_error_code(reason),
                message: format_batch_error(reason)
              }
            }
        end
      end
    end
  end

  defp run_host_call("call_action", args, manifest) do
    service = Map.get(args, "service", "")
    action = Map.get(args, "action", "")
    payload = Map.get(args, "payload")

    cond do
      not Manifest.allows_service?(manifest, service) ->
        Logger.warning("[NativeExtensionRunner] #{manifest.id} called undeclared service #{service}")

        %{
          error: %{
            code: "service_not_declared",
            message: "Service '#{service}' is not declared in this extension's dependencies."
          }
        }

      self_call?(manifest, service) ->
        %{
          error: %{
            code: "cannot_call_own_service",
            message: "An extension cannot call its own service '#{service}'."
          }
        }

      true ->
        case ActionDispatcher.dispatch_internal(
               Exoforge.Atoms.existing(service, service),
               Exoforge.Atoms.existing(action, action),
               payload
             ) do
          {:ok, result} -> result
          :ok -> true
          {:error, reason} -> %{error: describe_action_error(reason)}
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
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: manifest.id,
           extension: manifest.id,
           operation: %{action: :put, table: table, id: key, data: value}
         }) do
      {:ok, res} -> {:ok, res}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp db_get(manifest, table, key) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: manifest.id,
           extension: manifest.id,
           operation: %{action: :get, table: table, id: key}
         }) do
      {:ok, %{rows: [record]}} -> {:ok, record}
      {:ok, %{"rows" => [record]}} -> {:ok, record}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:ok, %{"rows" => []}} -> {:error, :not_found}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  defp db_all(manifest, table) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: manifest.id,
           extension: manifest.id,
           operation: %{action: :all, table: table}
         }) do
      {:ok, %{rows: rows}} when is_list(rows) -> {:ok, rows}
      {:ok, %{"rows" => rows}} when is_list(rows) -> {:ok, rows}
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp db_delete(manifest, table, key) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: manifest.id,
           extension: manifest.id,
           operation: %{action: :delete, table: table, id: key}
         }) do
      {:ok, res} -> {:ok, res}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp db_batch(manifest, operations) when is_list(operations) do
    case ActionDispatcher.dispatch_internal(:database, :execute, %{
           plugin: manifest.id,
           extension: manifest.id,
           operation: %{action: :batch, operations: operations}
         }) do
      {:ok, res} -> {:ok, res}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp extract_batch_operations(ops) when is_list(ops), do: ops

  defp extract_batch_operations(args) when is_map(args) do
    cond do
      Map.has_key?(args, "operations") -> Map.get(args, "operations")
      Map.has_key?(args, :operations) -> Map.get(args, :operations)
      true -> nil
    end
  end

  defp extract_batch_operations(_), do: nil

  defp batch_error_code({:postgres_error, _}), do: "postgres_error"
  defp batch_error_code({:invalid_value, _, _}), do: "invalid_value"
  defp batch_error_code({:missing_resource_table, _}), do: "missing_resource_table"
  defp batch_error_code({:unsupported_batch_action, _}), do: "unsupported_batch_action"
  defp batch_error_code(:positional_args_must_be_list), do: "invalid_arguments"
  defp batch_error_code({code, _}) when is_atom(code) or is_binary(code), do: to_string(code)
  defp batch_error_code(code) when is_atom(code) and not is_nil(code), do: to_string(code)
  defp batch_error_code(_), do: "batch_failed"

  defp format_batch_error({:postgres_error, msg}) when is_binary(msg), do: msg

  defp format_batch_error({:invalid_value, col, type}),
    do: "Invalid value for column '#{col}' (expected #{type})"

  defp format_batch_error({:missing_resource_table, tbl}),
    do: "Missing declared resource table '#{tbl}'"

  defp format_batch_error({:unsupported_batch_action, action}),
    do: "Unsupported batch operation '#{action}'; only execute, put, and delete are allowed"

  defp format_batch_error({_, msg}) when is_binary(msg), do: msg
  defp format_batch_error(msg) when is_binary(msg), do: msg
  defp format_batch_error(other), do: inspect(other)

  # -- Helpers --

  defp sanitize(result), do: Exoforge.ExtensionRegistry.sanitize_for_json(result)

  defp active_db_dialect(manifest) do
    if ExtensionRegistry.fetch_service(:lldb) do
      try do
        case ActionDispatcher.dispatch_internal(:lldb, :connection_config, %{namespace: to_string(manifest.id)}) do
          {:ok, %{driver: driver}} -> driver
          {:ok, %{"driver" => driver}} -> driver
          _ -> nil
        end
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end
  end

  defp normalize_error(nil), do: "unknown_error"
  defp normalize_error(%{"code" => code, "message" => msg}), do: {String.to_atom(code), msg}
  defp normalize_error(error) when is_binary(error), do: error
  defp normalize_error(error), do: inspect(error)

  # A failed extension-to-extension call keeps a code and a message: the SDK throws an
  # ExoActionException with the code the callee threw, so a caller can branch on it.
  defp describe_action_error({code, message}) when is_atom(code) or is_binary(code) do
    %{code: to_string(code), message: error_message(message)}
  end

  defp describe_action_error(code) when is_atom(code) or is_binary(code) do
    %{code: to_string(code), message: to_string(code)}
  end

  defp describe_action_error(other), do: %{code: "action_failed", message: inspect(other)}

  defp error_message(message) when is_binary(message), do: message
  defp error_message(message), do: inspect(message)

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

  defp cleanup_stderr(%{stderr_path: stderr_path}) when is_binary(stderr_path) do
    _ = File.rm(stderr_path)
    :ok
  rescue
    _ -> :ok
  end

  defp cleanup_stderr(_state), do: :ok

  # Copies what the process has written to stderr since the last pass into the extension's logs (as warnings), so a
  # `Console.Error.WriteLine` or an unhandled exception shows up while the extension runs, not only after it died.
  defp flush_stderr(%{stderr_path: path} = state) when is_binary(path) do
    offset = Map.get(state, :stderr_offset, 0)

    with {:ok, %{size: size}} when size > offset <- File.stat(path),
         {:ok, file} <- :file.open(to_charlist(path), [:read, :binary]) do
      try do
        case :file.pread(file, offset, min(size - offset, @max_stderr_bytes)) do
          {:ok, chunk} ->
            lines = chunk |> String.split(~r/\r?\n/, trim: true) |> Enum.reject(&(String.trim(&1) == ""))
            {shown, extra} = Enum.split(lines, @stderr_lines_per_pass)

            Enum.each(shown, &record_log(state.manifest.id, 2, "[stderr] " <> String.slice(&1, 0, 2_000)))

            if extra != [],
              do: record_log(state.manifest.id, 2, "[stderr] ... #{length(extra)} more lines were written to stderr")

            %{state | stderr_offset: offset + byte_size(chunk)}

          _ ->
            state
        end
      after
        :file.close(file)
      end
    else
      _ -> state
    end
  end

  defp flush_stderr(state), do: state

  defp read_stderr_tail(nil), do: []

  defp read_stderr_tail(stderr_path) do
    case File.stat(stderr_path) do
      {:ok, %{size: size}} when size > 0 ->
        offset = max(0, size - @max_stderr_bytes)
        bytes_to_read = min(size, @max_stderr_bytes)

        case :file.open(to_charlist(stderr_path), [:read, :binary]) do
          {:ok, file} ->
            try do
              case :file.pread(file, offset, bytes_to_read) do
                {:ok, content} ->
                  content
                  |> String.trim_trailing()
                  |> case do
                    "" ->
                      []

                    trimmed ->
                      trimmed
                      |> String.split(~r/\r?\n/)
                      |> Enum.take(-@max_stderr_lines)
                  end

                _ ->
                  []
              end
            after
              :file.close(file)
            end

          _ ->
            []
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp format_stderr_msg([], fallback), do: fallback

  defp format_stderr_msg(stderr_tail, _fallback) when is_list(stderr_tail) and stderr_tail != [] do
    "\nCaptured stderr (last #{length(stderr_tail)} lines):\n" <> Enum.join(stderr_tail, "\n")
  end

  defp format_stderr_msg(_tail, fallback), do: fallback
end
