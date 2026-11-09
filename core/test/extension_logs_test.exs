defmodule Exoforge.ExtensionLogsTest do
  use ExUnit.Case, async: false

  alias Exoforge.ExtensionLogs

  setup do
    extension = "logs_test_#{System.unique_integer([:positive])}"
    ExtensionLogs.clear(extension)
    on_exit(fn -> ExtensionLogs.clear(extension) end)
    %{extension: extension}
  end

  test "keeps lines in the order they were emitted", %{extension: extension} do
    ExtensionLogs.append(extension, 1, "first")
    ExtensionLogs.append(extension, 2, "second")
    ExtensionLogs.append(extension, 3, "third")

    assert Enum.map(ExtensionLogs.list(extension), & &1.message) == ["first", "second", "third"]
    assert ExtensionLogs.count(extension) == 3
  end

  test "maps numeric levels to names", %{extension: extension} do
    for level <- 0..3, do: ExtensionLogs.append(extension, level, "l#{level}")

    assert Enum.map(ExtensionLogs.list(extension), & &1.level_name) ==
             ["debug", "info", "warning", "error"]
  end

  test "caps how many lines a single extension can hold", %{extension: extension} do
    # One per second: the line cap is what this tests, not the rate cap.
    for i <- 1..250, do: ExtensionLogs.append(extension, 1, "line #{i}", i * 1_000)

    assert ExtensionLogs.count(extension) == 200
    # The oldest were dropped, the newest kept.
    assert List.last(ExtensionLogs.list(extension)).message == "line 250"
    refute Enum.any?(ExtensionLogs.list(extension), &(&1.message == "line 1"))
  end

  test "caps how many lines an extension can emit per second", %{extension: extension} do
    limit = ExtensionLogs.rate_limit()
    now = 1_000

    results = for _ <- 1..(limit + 5), do: ExtensionLogs.append(extension, 1, "flood", now)
    assert Enum.count(results, &(&1 == :ok)) == limit
    assert ExtensionLogs.count(extension) == limit

    # The same second stays closed, the next one opens.
    assert ExtensionLogs.append(extension, 1, "late", now + 999) == :rate_limited
    assert ExtensionLogs.append(extension, 1, "next second", now + 1_000) == :ok
    assert ExtensionLogs.count(extension) == limit + 1
  end

  test "limit returns the newest lines", %{extension: extension} do
    for i <- 1..10, do: ExtensionLogs.append(extension, 1, "line #{i}")

    assert Enum.map(ExtensionLogs.list(extension, 3), & &1.message) == ["line 8", "line 9", "line 10"]
  end

  test "keeps extensions separate", %{extension: extension} do
    ExtensionLogs.append(extension, 1, "mine")
    ExtensionLogs.append("someone_else", 1, "theirs")

    assert Enum.map(ExtensionLogs.list(extension), & &1.message) == ["mine"]
  end

  test "an unknown extension has no lines", %{extension: extension} do
    assert ExtensionLogs.list(extension) == []
    assert ExtensionLogs.count(extension) == 0
  end

  test "clear drops an extension's lines", %{extension: extension} do
    ExtensionLogs.append(extension, 1, "gone")
    ExtensionLogs.clear(extension)

    assert ExtensionLogs.list(extension) == []
  end

  test "ignores a non-binary message rather than raising", %{extension: extension} do
    assert ExtensionLogs.append(extension, 1, nil) == :ok
    assert ExtensionLogs.append(extension, 1, %{not: "a string"}) == :ok
    assert ExtensionLogs.count(extension) == 0
  end

  test "for_rid returns only the lines of one request, oldest first" do
    context = %{origin: "alice", rid: "r_logs_1", depth: 0, capture: :off}
    previous = Exoforge.RequestContext.enter(context)
    :ok = Exoforge.ExtensionLogs.append(:rid_plugin, 1, "inside the request")
    Exoforge.RequestContext.restore(previous)

    :ok = Exoforge.ExtensionLogs.append(:rid_plugin, 1, "outside any request")

    assert ["[INFO] inside the request"] = Exoforge.ExtensionLogs.for_rid("r_logs_1")
    assert Exoforge.ExtensionLogs.for_rid("r_missing") == []
  end
end
