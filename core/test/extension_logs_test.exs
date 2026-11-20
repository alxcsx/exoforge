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

    # The same second stays closed, the next one opens, and its first line says what was dropped.
    assert ExtensionLogs.append(extension, 1, "late", now + 999) == :rate_limited
    assert ExtensionLogs.append(extension, 1, "next second", now + 1_000) == :ok
    assert ExtensionLogs.count(extension) == limit + 2

    assert Enum.any?(ExtensionLogs.list(extension, 500), fn entry ->
             entry.level == 2 and entry.message =~ "6 log lines were dropped"
           end)
  end

  test "a flood cannot hide a warning or an error", %{extension: extension} do
    now = 5_000
    for _ <- 1..ExtensionLogs.rate_limit(), do: ExtensionLogs.append(extension, 1, "chatter", now)

    assert ExtensionLogs.append(extension, 1, "more chatter", now) == :rate_limited
    assert ExtensionLogs.append(extension, 2, "the warning", now) == :ok
    assert ExtensionLogs.append(extension, 3, "the error", now) == :ok

    messages = Enum.map(ExtensionLogs.list(extension, 500), & &1.message)
    assert "the warning" in messages and "the error" in messages
    refute "more chatter" in messages
  end

  describe "history" do
    defp entry(at, message), do: %{at: at, level: 1, level_name: "info", message: message, rid: nil}

    test "older persisted lines fill what memory does not hold, so one new line does not hide the history" do
      cached = [entry(1_000, "after restart")]
      history = fn before_ms, count -> send(self(), {:asked, before_ms, count}); [entry(100, "before 1"), entry(200, "before 2")] end

      lines = ExtensionLogs.merge_history(cached, 10, history)

      assert Enum.map(lines, & &1.message) == ["before 1", "before 2", "after restart"]
      # it asked only for what is older than the oldest line in memory, and only as many as were missing
      assert_received {:asked, 1_000, 9}
    end

    test "when memory already holds the limit the database is not asked" do
      cached = for i <- 1..3, do: entry(i, "line #{i}")
      history = fn _, _ -> flunk("the history must not be read") end

      assert ExtensionLogs.merge_history(cached, 3, history) |> Enum.map(& &1.message) == ["line 1", "line 2", "line 3"]
    end

    test "with nothing in memory the newest persisted lines are returned" do
      history = fn nil, 2 -> [entry(5, "five"), entry(6, "six")] end
      assert ExtensionLogs.merge_history([], 2, history) |> Enum.map(& &1.message) == ["five", "six"]
    end
  end

  test "a busy action does not push an extension's own lines out of its log", %{extension: extension} do
    defmodule Busy do
      use Exoforge.Extension
      defaction(ping(_p), scope: :server) do
        {:ok, %{}}
      end
    end

    Exoforge.ExtensionCase.start_kernel()
    Exoforge.ExtensionCase.register_extension(Busy, id: extension, provides: [:busy_logs_svc])
    ExtensionLogs.append(extension, 1, "my own line")

    for _ <- 1..250, do: Exoforge.ActionDispatcher.dispatch_internal(:busy_logs_svc, :ping, %{})

    assert Enum.map(ExtensionLogs.list(extension), & &1.message) == ["my own line"]
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
