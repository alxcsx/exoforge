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
      *'"action":"ping"'*)
        printf '{"type":"action_result","id":%s,"status":"ok","data":42}\\n' "$id" ;;
      *'"action":"emit"'*)
        printf '{"type":"host_call","id":1,"op":"emit_event","args":{"topic":"stub:events","event":"stub_emitted","payload":{"n":1}}}\\n'
        IFS= read -r _reply
        printf '{"type":"action_result","id":%s,"status":"ok","data":1}\\n' "$id" ;;
      *'"action":"boom"'*)
        printf '{"type":"action_result","id":%s,"status":"error","error":"exploded"}\\n' "$id" ;;
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

  test "fails loudly when the binary is missing", %{manifest: manifest} do
    missing = %{manifest | physical_path: Path.join(System.tmp_dir!(), "exo_native_missing")}
    assert {:error, {:binary_not_found, _}} = NativePluginRunner.load(missing)
  end
end
