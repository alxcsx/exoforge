defmodule Exoforge.ActionTraceTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionTrace
  alias Exoforge.ActionDispatcher

  setup do
    ActionTrace.enable()
    Exoforge.ExtensionCase.reset_action_trace()
  end

  test "samples carry a capped, credential-masked preview of both directions" do
    request = %{email: "a@b.c", password: "hunter2", blob: String.duplicate("x", 2_000)}

    ActionTrace.record(:auth, :login, "player_1", request, {:ok, %{player_id: "p1"}}, 12)

    assert %{samples: [sample], total: 1} = ActionTrace.samples("auth.login")
    assert sample.key == "auth.login"
    assert sample.caller == "player_1"
    assert sample.status == "ok"
    assert sample.duration_ms == 12
    assert sample.request[:password] == "•••"
    assert sample.response == %{player_id: "p1"}
    assert byte_size(sample.request[:blob]) < 600
  end

  test "a failed call is counted as an error, per minute, per action, per caller" do
    ActionTrace.record(:player_data, :get_player, "alice", %{}, {:ok, %{}}, 1)
    ActionTrace.record(:player_data, :get_player, "alice", %{}, {:error, :not_found}, 1)
    ActionTrace.record(:player_data, :get_player, "bob", %{}, {:ok, %{}}, 1)

    %{buckets: buckets} = ActionTrace.snapshot()

    counts = for {_minute, "player_data.get_player", caller, :count, n} <- buckets, do: {caller, n}
    errors = for {_minute, "player_data.get_player", caller, :error, n} <- buckets, do: {caller, n}

    assert {"alice", 2} in counts
    assert {"bob", 1} in counts
    assert {"alice", 1} in errors
    refute Enum.any?(errors, fn {caller, _n} -> caller == "bob" end)
  end

  test "the error status names the reason, so the console can show what came back" do
    ActionTrace.record(:file_bucket, :list_files, "webhook", %{}, {:error, :unauthorized}, 0)

    assert %{samples: [sample]} = ActionTrace.samples("file_bucket.list_files")
    assert sample.status == "error: :unauthorized"
    assert sample.response == :unauthorized
  end

  test "errors are retained even after successful traffic fills the samples ring" do
    ActionTrace.record(:resource_store, :get, "alice", %{}, {:error, :not_found}, 1)

    for _ <- 1..60 do
      ActionTrace.record(:resource_store, :get, "alice", %{}, {:ok, %{}}, 1)
    end

    # The per-action ring keeps only the newest samples, but the error bucket survives long enough
    # to be unfolded: "7 errors" and an empty list is the bug this pins.
    %{samples: samples, total: total} = ActionTrace.samples("resource_store.get", errors_only: true)
    assert total >= 1
    assert Enum.all?(samples, &String.starts_with?(&1.status, "error"))
  end

  test "samples page and filter by caller" do
    for i <- 1..12 do
      caller = if rem(i, 2) == 0, do: "alice", else: "bob"
      ActionTrace.record(:auth, :register, caller, %{"n" => i}, {:ok, %{}}, i)
    end

    first = ActionTrace.samples("auth.register", per_page: 5)
    assert first.page == 1
    assert length(first.samples) == 5
    assert first.pages == 3
    assert hd(first.samples).request == %{"n" => 12}

    third = ActionTrace.samples("auth.register", per_page: 5, page: 3)
    assert length(third.samples) == 2

    alice = ActionTrace.samples("auth.register", caller: "alice", per_page: 10)
    assert alice.total == 6
    assert Enum.all?(alice.samples, &(&1.caller == "alice"))
  end

  test "a nested internal dispatch inherits the request and its origin" do
    parent = %{origin: "player_7", rid: "r_parent", depth: 0, capture: :off}
    previous = Exoforge.RequestContext.enter(parent)

    assert {:error, :service_not_found} = ActionDispatcher.dispatch_internal(:nobody, :nothing, %{})

    Exoforge.RequestContext.restore(previous)

    assert %{samples: [sample]} = ActionTrace.samples("nobody.nothing")
    assert sample.caller == "player_7"
    assert sample.internal == true
    assert sample.rid == "r_parent"
    assert sample.depth == 1
  end

  test "an explicit caller wins over an inherited origin" do
    parent = %{origin: "player_7", rid: "r_parent", depth: 0, capture: :off}
    previous = Exoforge.RequestContext.enter(parent)

    assert {:error, :service_not_found} =
             ActionDispatcher.dispatch(:nobody, :nothing, %{}, caller: "admin_1")

    Exoforge.RequestContext.restore(previous)

    assert %{samples: [sample]} = ActionTrace.samples("nobody.nothing")
    assert sample.caller == "admin_1"
    assert sample.internal == false
    assert sample.rid == "r_parent"
  end

  test "a top-level dispatch starts its own request" do
    assert {:error, :service_not_found} = ActionDispatcher.dispatch(:nobody, :nothing, %{})

    assert %{samples: [sample]} = ActionTrace.samples("nobody.nothing")
    assert sample.rid =~ ~r/^r_/
    assert sample.depth == 0
    assert sample.caller == "client"
  end

  test "for_rid returns only the samples of one request" do
    alice = %{origin: "alice", rid: "r_one", depth: 0, capture: :off}
    previous = Exoforge.RequestContext.enter(alice)
    ActionTrace.record(:auth, :login, "alice", %{}, {:ok, %{}}, 1)
    Exoforge.RequestContext.restore(previous)

    previous = Exoforge.RequestContext.enter(%{alice | rid: "r_two"})
    ActionTrace.record(:auth, :login, "alice", %{}, {:error, :nope}, 1)
    Exoforge.RequestContext.restore(previous)

    assert [%{rid: "r_one", status: "ok"}] = ActionTrace.for_rid("r_one")
    assert [%{rid: "r_two", status: "error: :nope"}] = ActionTrace.for_rid("r_two")
    assert ActionTrace.for_rid("r_missing") == []
  end
end
