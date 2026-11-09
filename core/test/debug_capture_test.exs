defmodule Exoforge.DebugCaptureTest do
  use ExUnit.Case, async: false

  alias Exoforge.DebugCapture

  setup do
    DebugCapture.stop_all()
    on_exit(fn -> DebugCapture.stop_all() end)
  end

  test "a player rule matches that origin and no other" do
    assert %{kind: "player", value: "alice", seconds: 60} =
             DebugCapture.capture("player", "alice", 60)

    assert [%{kind: "player", value: "alice", remaining_s: remaining}] = DebugCapture.list()
    assert remaining in [59, 60]
    assert DebugCapture.capture_for("alice", "svc.act") == :deep
    assert DebugCapture.capture_for("bob", "svc.act") == :off
    assert DebugCapture.active?()
  end

  test "an action rule matches the dispatched key; a global rule matches anything" do
    DebugCapture.capture("action", "file_bucket.list_files", 60)

    assert DebugCapture.capture_for("anyone", "file_bucket.list_files") == :deep
    assert DebugCapture.capture_for("anyone", "file_bucket.list_buckets") == :off

    DebugCapture.capture("global", "*", 60)

    assert DebugCapture.capture_for("nobody", "whatever.action") == :deep
  end

  test "an expired rule no longer matches and is dropped from the list" do
    rule = DebugCapture.capture("player", "alice", 1)

    :persistent_term.put(
      {{DebugCapture, :rule}, "player", "alice"},
      %{rule | until_ms: System.system_time(:millisecond) - 1}
    )

    assert DebugCapture.capture_for("alice", "a.b") == :off
    assert DebugCapture.list() == []
  end

  test "stop removes one rule and stop_all removes every rule" do
    DebugCapture.capture("player", "alice", 60)
    DebugCapture.capture("action", "a.b", 60)

    DebugCapture.stop("player", "alice")

    assert DebugCapture.capture_for("alice", "other.action") == :off
    assert DebugCapture.capture_for("x", "a.b") == :deep

    DebugCapture.stop_all()
    assert DebugCapture.list() == []
  end
end
