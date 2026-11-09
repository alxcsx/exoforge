defmodule Exoforge.ActionTraceTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionTrace

  setup do
    ActionTrace.enable()

    for table <- [:exo_action_trace, :exo_action_trace_buckets] do
      try do
        :ets.delete_all_objects(table)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  test "samples carry a capped, credential-masked preview of both directions" do
    request = %{email: "a@b.c", password: "hunter2", blob: String.duplicate("x", 2_000)}

    ActionTrace.record(:auth, :login, "player_1", request, {:ok, %{player_id: "p1"}}, 12)

    assert %{samples: [sample]} = ActionTrace.snapshot()
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

    assert %{samples: [sample]} = ActionTrace.snapshot()
    assert sample.status == "error: :unauthorized"
    assert sample.response == :unauthorized
  end
end
