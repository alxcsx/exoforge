defmodule Exoforge.RequestContextTest do
  use ExUnit.Case, async: true

  alias Exoforge.RequestContext

  test "a fresh request id is prefixed, url-safe and unique" do
    rid = RequestContext.new_rid()

    assert rid =~ ~r/^r_[A-Za-z0-9_-]{12}$/
    assert rid != RequestContext.new_rid()
  end

  test "an untrusted id is kept only when well-formed" do
    assert RequestContext.sanitize_rid("r_client-1") == "r_client-1"
    assert RequestContext.sanitize_rid("r_client-1") != RequestContext.new_rid()
    assert RequestContext.sanitize_rid("has spaces") =~ ~r/^r_/
    assert RequestContext.sanitize_rid(String.duplicate("a", 100)) =~ ~r/^r_/
    assert RequestContext.sanitize_rid(nil) =~ ~r/^r_/
  end

  test "enter scopes the context and restore pops it, including nesting" do
    assert RequestContext.current() == nil

    outer = %{origin: "alice", rid: "r_outer", depth: 0, capture: :off}
    previous = RequestContext.enter(outer)

    assert RequestContext.origin() == "alice"
    assert RequestContext.rid() == "r_outer"
    assert RequestContext.depth() == 0
    refute RequestContext.capturing?()

    inner = %{outer | depth: 1, capture: :deep}
    previous_inner = RequestContext.enter(inner)

    assert RequestContext.depth() == 1
    assert RequestContext.capturing?()

    RequestContext.restore(previous_inner)
    assert RequestContext.depth() == 0

    RequestContext.restore(previous)
    assert RequestContext.current() == nil
    assert RequestContext.rid() == nil
  end

  test "entering nil clears the context" do
    previous = RequestContext.enter(%{origin: "alice", rid: "r_x", depth: 0, capture: :off})
    _ = RequestContext.enter(nil)

    assert RequestContext.current() == nil

    RequestContext.restore(previous)
  end
end
