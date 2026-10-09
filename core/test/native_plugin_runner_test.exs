defmodule Exoforge.NativePluginRunnerTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.NativePluginRunner

  # A stub "plugin": any executable that speaks the JSON line protocol works, which is the
  # point of the runtime — no WASM toolchain, no C# toolchain needed to exercise the host side.
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

  setup do
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
    {:ok, pid} = NativePluginRunner.start_link({manifest, binary, name})
    pid
  end

  defp start_runner(manifest, binary, handshake_timeout_ms) do
    name = :"stub_runner_#{System.unique_integer([:positive])}"
    {:ok, pid} = NativePluginRunner.start_link({manifest, binary, name, handshake_timeout_ms})
    pid
  end

  defp write_variant(manifest, body) do
    path = Path.join(manifest.physical_path, "variant_#{System.unique_integer([:positive])}")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    path
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

    refute error == "service_not_declared", "a declared service was refused"

    GenServer.stop(pid)
  end

  test "a plugin may not call a service it never declared", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    # The WASM runner always enforced this; the native runner dispatched anything, so a native
    # plugin could reach every service in the cluster while claiming none of them.
    assert {:ok, %{"result" => %{"error" => "service_not_declared"}}} =
             GenServer.call(pid, {:execute_action, "call_undeclared", %{}}, 5_000)

    GenServer.stop(pid)
  end

  test "calling its own service fails fast instead of deadlocking", %{manifest: manifest, binary: binary} do
    pid = start_runner(manifest, binary)

    # Dispatching to itself would GenServer.call the runner that is busy answering the host call,
    # so without the guard this blocks the runner for the full action timeout.
    assert {:ok, %{"result" => %{"error" => "cannot_call_own_service"}}} =
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

    assert {:ok, %{"result" => %{"error" => "cannot_call_own_service"}}} =
             GenServer.call(pid, {:execute_action, "call_self", %{}}, 5_000)

    # And a declared dependency is still allowed through to the dispatcher.
    assert {:ok, %{"result" => %{"error" => error}}} =
             GenServer.call(pid, {:execute_action, "call_declared", %{}}, 5_000)

    refute error == "service_not_declared", "a declared dependency was refused"

    GenServer.stop(pid)
  end

  test "a plugin that dies mid-call answers its caller instead of leaving it waiting", %{
    manifest: manifest,
    binary: binary
  } do
    # The runner is linked to this process and stops when the plugin dies, which is the point.
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, binary)

    assert {:error, {:plugin_exited, status}} =
             GenServer.call(pid, {:execute_action, "die", %{}}, 5_000)

    assert is_integer(status)

    # And it stops with that reason, which is the contract the supervisor rests on. A runner left
    # holding a dead port would answer every later call with a timeout and nothing would restart it.
    #
    # The restart itself is not asserted here: doing so means starting the application's own registry
    # and supervisor inside a unit test, and ExUnit tears down what a test supervises, taking the rest
    # of the suite with it. It was verified by hand - kill -9, new pid, calls still answered.
    assert_receive {:EXIT, ^pid, {:plugin_exited, ^status}}, 1_000
  end

  test "a plugin's own log and exception lines reach `exo plugin logs`", %{
    manifest: manifest,
    binary: binary
  } do
    Exoforge.PluginLogs.clear(manifest.id)
    on_exit(fn -> Exoforge.PluginLogs.clear(manifest.id) end)

    pid = start_runner(manifest, binary)

    # The frame is written before the result, so by the time the call returns the buffer holds it.
    assert {:ok, 7} = GenServer.call(pid, {:execute_action, "log_trace", %{}}, 5_000)

    assert [%{level: 3, level_name: "error", message: "boom at Stub.cs:line 100"}] =
             Exoforge.PluginLogs.list(manifest.id)

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

  test "refuses a plugin that speaks a different protocol", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @wrong_protocol))

    assert_receive {:EXIT, ^pid, {:plugin_incompatible, {:protocol_mismatch, 2}}}, 1_000
  end

  test "refuses a plugin that cannot handle the frames the host sends", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @no_capabilities))

    assert_receive {:EXIT, ^pid, {:plugin_incompatible, {:missing_capabilities, ["action", "event"]}}},
                   1_000
  end

  test "refuses a plugin that never completes the handshake", %{manifest: manifest} do
    Process.flag(:trap_exit, true)
    pid = start_runner(manifest, write_variant(manifest, @no_handshake), 100)

    assert_receive {:EXIT, ^pid, {:plugin_incompatible, :no_handshake}}, 1_000
  end

  test "fails loudly when the binary is missing", %{manifest: manifest} do
    missing = %{manifest | physical_path: Path.join(System.tmp_dir!(), "exo_native_missing")}
    assert {:error, {:binary_not_found, _}} = NativePluginRunner.load(missing)
  end
end
