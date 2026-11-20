defmodule Exoforge.TableOwnerTest do
  use ExUnit.Case, async: false

  # A table dies with the process that made it. The first caller of the failure groups, the action trace and the
  # log buffer is usually a request that ends a moment later, so these tables must belong to a process that does not.
  test "what a short-lived process records survives the process" do
    if pid = Process.whereis(Exoforge.TableOwner), do: GenServer.stop(pid)

    task =
      Task.async(fn ->
        Exoforge.ErrorGroups.record("svc", "act", "alice", "r_owner_1", %{a: 1}, :boom)
        Exoforge.ActionTrace.enable()
        Exoforge.ExtensionLogs.append("owner_test_ext", 1, "from a short-lived process")
        :done
      end)

    assert Task.await(task) == :done
    refute Process.alive?(task.pid)

    assert [%{service: "svc", action: "act"}] = Exoforge.ErrorGroups.list(%{service: "svc"})
    assert Exoforge.ErrorGroups.count() >= 1
    assert Enum.any?(Exoforge.ExtensionLogs.list("owner_test_ext"), &(&1.message == "from a short-lived process"))

    Exoforge.ErrorGroups.clear()
    Exoforge.ExtensionCase.reset_action_trace()
    Exoforge.ExtensionLogs.clear("owner_test_ext")
  end
end
