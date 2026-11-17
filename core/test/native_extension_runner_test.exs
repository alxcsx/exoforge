defmodule Exoforge.NativeExtensionRunnerTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.NativeExtensionRunner
  alias Exoforge.ExtensionLogs

  # A service the stub plugin calls; it fails the way a real extension does, with a code the caller
  # can act on, so the host-side shape of a failed call is observable end to end.
  defmodule WalletPlug do
    use Exoforge.Extension, provides: [:wallet]

    @impl true
    defaction debit(_payload), do: {:error, {:insufficient_funds, "You need 10 coins"}}
  end

  # A stub "plugin": any executable that speaks the JSON line protocol works, which is the
  # point of the runtime — no C# toolchain needed to exercise the host side.
  @stub """
  #!/usr/bin/env bash
  while IFS= read -r line; do
    id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
    case "$line" in
      *'"type":"hello"'*)
        printf '{"type":"hello","protocol":1,"plugin":"stub_plugin","capabilities":["action","event","host_call_result"]}\\n' ;;
      *'"action":"ping"'*)
        printf '{"type":"action_result","id":%s,"status":"ok","data":42}\\n' "$id" ;;
      *'"action":"emit"'*)
        printf '{"type":"host_call","id":1,"op":"emit_event","args":{"topic":"stub:events","event":"stub_emitted","payload":{"n":1}}}\\n'
        IFS= read -r _reply
        printf '{"type":"action_result","id":%s,"status":"ok","data":1}\\n' "$id" ;;
      *'"action":"boom"'*)
        printf '{"type":"action_result","id":%s,"status":"error","error":"exploded"}\\n' "$id" ;;
      *'"action":"log_trace"'*)
        # The SDK's unhandled-exception path: a fire-and-forget `host_log` frame, then the result.
        printf '{"type":"host_log","level":3,"message":"boom at Stub.cs:line 100"}\n'
        printf '{"type":"action_result","id":%s,"status":"ok","data":7}\n' "$id" ;;
      *'"action":"die"'*)
        # No reply at all: the process goes away without saying anything, which is what a segfault,
        # an OOM kill or an Environment.Exit looks like from the host's side.
        exit 1 ;;
      *'"action":"stderr_noise"'*)
        echo "debug noise from native extension" >&2
        printf '{"type":"action_result","id":%s,"status":"ok","data":"clean_result"}\\n' "$id"
        echo "more debug noise on stderr" >&2 ;;
      *'"action":"call_declared"'*)
        printf '{"type":"host_call","id":1,"op":"call_action","args":{"service":"database","action":"ping","payload":{}}}\\n'
        IFS= read -r reply
        printf '{"type":"action_result","id":%s,"status":"ok","data":%s}\\n' "$id" "$reply" ;;
      *'"action":"call_undeclared"'*)
        printf '{"type":"host_call","id":1,"op":"call_action","args":{"service":"auth","action":"ping","payload":{}}}\\n'
        IFS= read -r reply
        printf '{"type":"action_result","id":%s,"status":"ok","data":%s}\\n' "$id" "$reply" ;;
      *'"action":"call_self"'*)
        printf '{"type":"host_call","id":1,"op":"call_action","args":{"service":"stub_plugin","action":"ping","payload":{}}}\\n'
        IFS= read -r reply
        printf '{"type":"action_result","id":%s,"status":"ok","data":%s}\\n' "$id" "$reply" ;;
      *'"action":"call_failing"'*)
        printf '{"type":"host_call","id":1,"op":"call_action","args":{"service":"wallet","action":"debit","payload":{}}}\\n'
        IFS= read -r reply
        printf '{"type":"action_result","id":%s,"status":"ok","data":%s}\\n' "$id" "$reply" ;;
    esac
  done
  """

  # Variants for the handshake refusal tests: each answers the host's hello differently, or not at
  # all, and none of them need the action protocol.
  @no_handshake """
  #!/usr/bin/env bash
  while IFS= read -r _line; do :; done
  """

  @wrong_protocol """
  #!/usr/bin/env bash
  read -r _hello
  printf '{"type":"hello","protocol":2,"plugin":"stub_plugin","capabilities":["action","event"]}\\n'
  while IFS= read -r _line; do :; done
  """

  @no_capabilities """
  #!/usr/bin/env bash
  read -r _hello
  printf '{"type":"hello","protocol":1,"plugin":"stub_plugin","capabilities":[]}\\n'
  while IFS= read -r _line; do :; done
  """

  @lifecycle_stub """
  #!/usr/bin/env bash
  while IFS= read -r line; do
    id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
    case "$line" in
      *'"type":"hello"'*)
        printf '{"type":"hello","protocol":1,"plugin":"stub_plugin","capabilities":["action","event","host_call_result","lifecycle"]}\\n' ;;
      *'"type":"lifecycle"'*)
        printf '{"type":"lifecycle_result","id":1,"status":"ok"}\\n' ;;
      *'"action":"ping"'*)
        printf '{"type":"action_result","id":%s,"status":"ok","data":42}\\n' "$id" ;;
    esac
  done
  """

  @lifecycle_error_stub """
  #!/usr/bin/env bash
  while IFS= read -r line; do
    case "$line" in
      *'"type":"hello"'*)
        printf '{"type":"hello","protocol":1,"plugin":"stub_plugin","capabilities":["action","event","host_call_result","lifecycle"]}\\n' ;;
      *'"type":"lifecycle"'*)
        printf '{"type":"lifecycle_result","id":1,"status":"error","error":{"code":"startup_failed","message":"seed failed"}}\\n'
        exit 0 ;;
    esac
  done
  """

  setup do
    unless Process.whereis(Exoforge.ExtensionRegistry) do
      start_supervised!(Exoforge.ExtensionRegistry)
    end

    unless Process.whereis(Exoforge.WorkerRegistry.Registry) do
      start_supervised!(Exoforge.WorkerRegistry)
    end

    unless Process.whereis(Exoforge.EventDispatcher.registry_name()) do
      start_supervised!(Exoforge.EventDispatcher)
    end

    dir = Path.join(System.tmp_dir!(), "exo_native_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    binary = Path.join(dir, "stub_plugin")
    File.write!(binary, @stub)
    File.chmod!(binary, 0o755)

    manifest = %Manifest{
      id: :stub_plugin,
      name: "stub_plugin",
      version: "1.0.0",
      entry_point: :stub_plugin,
      physical_path: dir,
      type: :native,
      dependencies: [:database],
      provides: [:stub_plugin]
    }

    {:ok, binary: binary, manifest: manifest}
  end

  defp start_runner(manifest, binary) do
    name = :"stub_runner_#{System.unique_integer([:positive])}"
    {:ok, pid} = NativeExtensionRunner.start_link({manifest, binary, name})
    pid
  end

  defp start_runner(manifest, binary, handshake_timeout_ms) do
    name = :"stub_runner_#{System.unique_integer([:positive])}"
    {:ok, pid} = NativeExtensionRunner.start_link({manifest, binary, name, handshake_timeout_ms})
    pid
  end

  defp write_variant(manifest, body) do
    path = Path.join(manifest.physical_path, "variant_#{System.unique_integer([:positive])}")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    path
  end

  defp wait_until(fun, attempts \\ 100) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition did not become true")
      true -> Process.sleep(10) && wait_until(fun, attempts - 1)
    end
  end

  test "executes an action and returns its result", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    assert {:ok, 42} = GenServer.call(pid, {:execute_action, "ping", %{}}, 5_000)
    GenServer.stop(pid)
  end

  test "surfaces action errors from the plugin", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    assert {:error, "exploded"} = GenServer.call(pid, {:execute_action, "boom", %{}}, 5_000)
    GenServer.stop(pid)
  end

  test "answers host calls inline and keeps the action result", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    # The plugin blocks on host_call until the runner replies; if that handshake is wrong the
    # action never returns.
    assert {:ok, 1} = GenServer.call(pid, {:execute_action, "emit", %{}}, 5_000)
    GenServer.stop(pid)
  end

  test "a plugin may call a service it declared", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    # No database is running in this test, so the dispatch itself fails. The point is that it got
    # that far: a declared service passes the gate, an undeclared one never reaches the dispatcher.
    assert {:ok, %{"result" => %{"error" => error}}} =
             GenServer.call(pid, {:execute_action, "call_declared", %{}}, 5_000)

    refute error["code"] == "service_not_declared", "a declared service was refused"

    GenServer.stop(pid)
  end

  test "a failed extension-to-extension call keeps the callee's code and message", %{
    manifest: manifest,
    binary: binary
  } do
    Exoforge.ExtensionRegistry.register(%Manifest{
      id: :wallet_plug,
      name: "wallet_plug",
      version: "1.0.0",
      entry_point: WalletPlug,
      provides: [:wallet]
    })

    pid = start_runner(%{manifest | dependencies: [:database, :wallet]}, binary)

    # The SDK throws an ExoActionException with this code; a caller must not mistake a failed debit
    # for an empty balance.
    assert {:ok,
            %{
              "result" => %{
                "error" => %{"code" => "insufficient_funds", "message" => "You need 10 coins"}
              }
            }} = GenServer.call(pid, {:execute_action, "call_failing", %{}}, 5_000)

    GenServer.stop(pid)
  end

  test "a plugin may not call a service it never declared", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    # The capability check is not optional: the native runner used to dispatch anything, so a native
    # plugin could reach every service in the cluster while claiming none of them.
    assert {:ok, %{"result" => %{"error" => %{"code" => "service_not_declared"}}}} =
             GenServer.call(pid, {:execute_action, "call_undeclared", %{}}, 5_000)

    GenServer.stop(pid)
  end

  test "calling its own service fails fast instead of deadlocking", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    # Dispatching to itself would GenServer.call the runner that is busy answering the host call,
    # so without the guard this blocks the runner for the full action timeout.
    assert {:ok, %{"result" => %{"error" => %{"code" => "cannot_call_own_service"}}}} =
             GenServer.call(pid, {:execute_action, "call_self", %{}}, 5_000)

    GenServer.stop(pid)
  end

  test "a shaped manifest does not crash the capability checks", %{binary: binary} do
    # PluginRegistry shapes `provides` from [:name] into the service metadata maps before anything
    # dispatches, so this is what a running plugin actually carries. The checks used to_string/1 on
    # those entries, which raises Protocol.UndefinedError on a map - every native plugin that called
    # another service crashed. The earlier tests passed because they used an unshaped atom list.
    shaped = %Manifest{
      id: :stub_plugin,
      name: "stub_plugin",
      version: "1.0.0",
      entry_point: :stub_plugin,
      physical_path: Path.dirname(binary),
      type: :native,
      dependencies: [%{name: :database, actions: [], events: [], resources: []}],
      provides: [%{name: :stub_plugin, actions: [], events: [], resources: []}]
    }

    pid = start_runner(shaped, binary)

    assert {:ok, %{"result" => %{"error" => %{"code" => "cannot_call_own_service"}}}} =
             GenServer.call(pid, {:execute_action, "call_self", %{}}, 5_000)

    # And a declared dependency is still allowed through to the dispatcher.
    assert {:ok, %{"result" => %{"error" => error}}} =
             GenServer.call(pid, {:execute_action, "call_declared", %{}}, 5_000)

    refute error["code"] == "service_not_declared", "a declared dependency was refused"

    GenServer.stop(pid)
  end

  test "a plugin that dies mid-call answers its caller instead of leaving it waiting", %{
    manifest: manifest,
    binary: binary
  } do
    # The runner is linked to this process and stops when the plugin dies, which is the point.
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, binary)

    assert {:error, {:extension_exited, status}} =
             GenServer.call(pid, {:execute_action, "die", %{}}, 5_000)

    assert is_integer(status)

    # And it stops with that reason, which is the contract the supervisor rests on. A runner left
    # holding a dead port would answer every later call with a timeout and nothing would restart it.
    #
    # The restart itself is not asserted here: doing so means starting the application's own registry
    # and supervisor inside a unit test, and ExUnit tears down what a test supervises, taking the rest
    # of the suite with it. It was verified by hand - kill -9, new pid, calls still answered.
    assert_receive {:EXIT, ^pid, {:extension_exited, ^status}}, 1_000
  end

  test "an extension's own log and exception lines reach `exo extension logs`", %{
    manifest: manifest,
    binary: binary
  } do
    ExtensionLogs.clear(manifest.id)
    on_exit(fn -> ExtensionLogs.clear(manifest.id) end)

    pid = start_runner(manifest, binary)

    # The frame is written before the result, so by the time the call returns the buffer holds it.
    assert {:ok, 7} = GenServer.call(pid, {:execute_action, "log_trace", %{}}, 5_000)

    assert [%{level: 3, level_name: "error", message: "boom at Stub.cs:line 100"}] =
             ExtensionLogs.list(manifest.id)

    GenServer.stop(pid)
  end

  test "meters the calls the runner sees", %{manifest: manifest, binary: binary} do
    metered = %{manifest | id: :metered_stub}
    pid = start_runner(metered, binary)

    assert {:ok, 42} = GenServer.call(pid, {:execute_action, "ping", %{}}, 5_000)
    assert {:ok, 1} = GenServer.call(pid, {:execute_action, "emit", %{}}, 5_000)
    GenServer.stop(pid)

    assert %{plugins: [usage]} = Exoforge.Metering.snapshot(:metered_stub)
    assert usage.plugin.starts == 1
    assert usage.plugin.host_calls == 1

    # Sorted by action name, and each call carries the bytes the runner put on the wire.
    assert [%{action: "emit", invocations: 1}, %{action: "ping", invocations: 1}] =
             Enum.map(usage.actions, &%{action: &1.action, invocations: &1.invocations})

    assert Enum.all?(usage.actions, &(&1.bytes_in > 0 and &1.bytes_out > 0))
  end

  # The refusals stop with `{:shutdown, ...}`: the runner child is `:transient`, so an incompatible
  # plugin is refused once and not restarted, while a plugin the OS killed is.
  test "refuses an extension that speaks a different protocol", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @wrong_protocol))

    assert_receive {:EXIT, ^pid, {:shutdown, {:extension_incompatible, {:protocol_mismatch, 2}}}},
                   1_000
  end

  test "refuses an extension that cannot handle the frames the host sends", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @no_capabilities))

    assert_receive {:EXIT, ^pid, {:shutdown, {:extension_incompatible, {:missing_capabilities, ["action", "event"]}}}},
                   1_000
  end

  test "refuses an extension that never completes the handshake", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @no_handshake), 100)

    assert_receive {:EXIT, ^pid, {:shutdown, {:extension_incompatible, :no_handshake}}}, 1_000
  end

  test "runs the optional startup hook before the first action", %{manifest: manifest} do
    pid = start_runner(manifest, write_variant(manifest, @lifecycle_stub))
    wait_until(fn -> :sys.get_state(pid).lifecycle == :ready end)

    assert {:ok, 42} = GenServer.call(pid, {:execute_action, "ping", %{}}, 5_000)
    GenServer.stop(pid)
  end

  test "a failed startup hook marks the extension crashed and stops it", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @lifecycle_error_stub))

    assert_receive {:EXIT, ^pid, {:shutdown, {:startup_failed, "startup_failed"}}}, 1_000

    assert {:crashed, {:startup_failed, %{code: "startup_failed", message: "seed failed"}}} =
             Exoforge.ExtensionRegistry.get_crash_info(manifest.id)
  end

  test "fails loudly when the binary is missing", %{manifest: manifest} do
    missing = %{manifest | physical_path: Path.join(System.tmp_dir!(), "exo_native_missing")}
    assert {:error, {:binary_not_found, _}} = NativeExtensionRunner.load(missing)
    assert {:crashed, {:binary_not_found, _}} = Exoforge.ExtensionRegistry.get_crash_info(missing.id)
  end

  test "isolates pre-handshake exit and marks extension as crashed", %{manifest: manifest} do
    # Simulates an immediate process exit (e.g. exit 2 due to missing glibc/musl ld-linux interpreter)
    exit_immediately = """
    #!/usr/bin/env bash
    exit 2
    """

    variant = write_variant(manifest, exit_immediately)

    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, variant)

    # Shuts down with {:shutdown, {:extension_exited, 2}} so OTP supervisor does NOT restart it
    assert_receive {:EXIT, ^pid, {:shutdown, {:extension_exited, 2}}}, 1_000

    # Extension status is recorded in ExtensionRegistry
    assert {:crashed, {:exit_before_handshake, 2, _}} = Exoforge.ExtensionRegistry.get_crash_info(manifest.id)

    # Action invocation returns the crash error immediately
    assert {:error, {:extension_crashed, {:exit_before_handshake, 2, _}}} =
             NativeExtensionRunner.execute_action(manifest.id, "ping", %{})
  end

  test "captures stderr on pre-handshake exit and includes it in crash info", %{manifest: manifest} do
    crash_script = """
    #!/usr/bin/env bash
    echo "Fatal error: missing dependency libhostfxr.so" >&2
    echo "Stack trace: at System.Runtime.Loader.AssemblyLoadContext" >&2
    exit 134
    """

    variant = write_variant(manifest, crash_script)

    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, variant)

    assert_receive {:EXIT, ^pid, {:shutdown, {:extension_exited, 134}}}, 1_000

    assert {:crashed, {:exit_before_handshake, 134, stderr_tail}} =
             Exoforge.ExtensionRegistry.get_crash_info(manifest.id)

    assert is_list(stderr_tail)
    assert Enum.any?(stderr_tail, &(&1 =~ "missing dependency libhostfxr.so"))
    assert Enum.any?(stderr_tail, &(&1 =~ "Stack trace: at System.Runtime.Loader"))
  end

  test "an extension writing to stderr after handshake does not corrupt NDJSON protocol", %{
    manifest: manifest,
    binary: binary
  } do
    pid = start_runner(manifest, binary)

    # The action emits lines to stderr before and after the NDJSON action_result frame
    assert {:ok, "clean_result"} =
             GenServer.call(pid, {:execute_action, "stderr_noise", %{}}, 5_000)

    # Subsequent actions continue to succeed without protocol stream corruption
    assert {:ok, 42} = GenServer.call(pid, {:execute_action, "ping", %{}}, 5_000)

    GenServer.stop(pid)
  end

  test "cleans up temporary stderr file on termination", %{manifest: manifest, binary: binary} do
    test_manifest = %{manifest | id: :"cleanup_test_#{System.unique_integer([:positive])}"}
    pid = start_runner(test_manifest, binary)

    # Temporary stderr file must exist while process is running
    temp_pattern = Path.join(System.tmp_dir!(), "exoforge_ext_stderr_#{test_manifest.id}_*")
    matching_files = Path.wildcard(temp_pattern)
    assert length(matching_files) == 1
    [stderr_file] = matching_files
    assert File.exists?(stderr_file)

    # Stop runner
    GenServer.stop(pid)

    # Temporary stderr file must be removed
    refute File.exists?(stderr_file)
    assert Path.wildcard(temp_pattern) == []
  end

  test "cleans up temporary stderr file on handshake timeout", %{manifest: manifest} do
    test_manifest = %{manifest | id: :"timeout_cleanup_#{System.unique_integer([:positive])}"}

    script = """
    #!/usr/bin/env bash
    echo "Extension started, hanging before hello..." >&2
    while IFS= read -r _line; do :; done
    """

    variant = write_variant(test_manifest, script)

    Process.flag(:trap_exit, true)
    pid = start_runner(test_manifest, variant, 100)

    # Temporary stderr file exists while running
    temp_pattern = Path.join(System.tmp_dir!(), "exoforge_ext_stderr_#{test_manifest.id}_*")
    matching_files = Path.wildcard(temp_pattern)
    assert length(matching_files) == 1
    [stderr_file] = matching_files
    assert File.exists?(stderr_file)

    # Wait for handshake refusal shutdown
    assert_receive {:EXIT, ^pid, {:shutdown, {:extension_incompatible, :no_handshake}}}, 1_000

    # Temporary stderr file must be cleaned up
    refute File.exists?(stderr_file)
    assert Path.wildcard(temp_pattern) == []
  end
end
