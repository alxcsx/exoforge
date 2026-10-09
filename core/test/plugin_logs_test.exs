defmodule Exoforge.PluginLogsTest do
  use ExUnit.Case, async: false

  alias Exoforge.PluginLogs

  setup do
    plugin = "logs_test_#{System.unique_integer([:positive])}"
    PluginLogs.clear(plugin)
    on_exit(fn -> PluginLogs.clear(plugin) end)
    %{plugin: plugin}
  end

  test "keeps lines in the order they were emitted", %{plugin: plugin} do
    PluginLogs.append(plugin, 1, "first")
    PluginLogs.append(plugin, 2, "second")
    PluginLogs.append(plugin, 3, "third")

    assert Enum.map(PluginLogs.list(plugin), & &1.message) == ["first", "second", "third"]
    assert PluginLogs.count(plugin) == 3
  end

  test "maps numeric levels to names", %{plugin: plugin} do
    for level <- 0..3, do: PluginLogs.append(plugin, level, "l#{level}")

    assert Enum.map(PluginLogs.list(plugin), & &1.level_name) ==
             ["debug", "info", "warning", "error"]
  end

  test "caps how many lines a single plugin can hold", %{plugin: plugin} do
    # One per second: the line cap is what this tests, not the rate cap.
    for i <- 1..250, do: PluginLogs.append(plugin, 1, "line #{i}", i * 1_000)

    assert PluginLogs.count(plugin) == 200
    # The oldest were dropped, the newest kept.
    assert List.last(PluginLogs.list(plugin)).message == "line 250"
    refute Enum.any?(PluginLogs.list(plugin), &(&1.message == "line 1"))
  end

  test "caps how many lines a plugin can emit per second", %{plugin: plugin} do
    limit = PluginLogs.rate_limit()
    now = 1_000

    results = for _ <- 1..(limit + 5), do: PluginLogs.append(plugin, 1, "flood", now)
    assert Enum.count(results, &(&1 == :ok)) == limit
    assert PluginLogs.count(plugin) == limit

    # The same second stays closed, the next one opens.
    assert PluginLogs.append(plugin, 1, "late", now + 999) == :rate_limited
    assert PluginLogs.append(plugin, 1, "next second", now + 1_000) == :ok
    assert PluginLogs.count(plugin) == limit + 1
  end

  test "limit returns the newest lines", %{plugin: plugin} do
    for i <- 1..10, do: PluginLogs.append(plugin, 1, "line #{i}")

    assert Enum.map(PluginLogs.list(plugin, 3), & &1.message) == ["line 8", "line 9", "line 10"]
  end

  test "keeps plugins separate", %{plugin: plugin} do
    PluginLogs.append(plugin, 1, "mine")
    PluginLogs.append("someone_else", 1, "theirs")

    assert Enum.map(PluginLogs.list(plugin), & &1.message) == ["mine"]
  end

  test "an unknown plugin has no lines", %{plugin: plugin} do
    assert PluginLogs.list(plugin) == []
    assert PluginLogs.count(plugin) == 0
  end

  test "clear drops a plugin's lines", %{plugin: plugin} do
    PluginLogs.append(plugin, 1, "gone")
    PluginLogs.clear(plugin)

    assert PluginLogs.list(plugin) == []
  end

  test "ignores a non-binary message rather than raising", %{plugin: plugin} do
    assert PluginLogs.append(plugin, 1, nil) == :ok
    assert PluginLogs.append(plugin, 1, %{not: "a string"}) == :ok
    assert PluginLogs.count(plugin) == 0
  end
end
