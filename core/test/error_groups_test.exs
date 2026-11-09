defmodule Exoforge.ErrorGroupsTest do
  use ExUnit.Case, async: false

  alias Exoforge.ErrorGroups

  setup do
    ErrorGroups.clear()
    :ok
  end

  test "groups identical reasons and keeps counts, first/last, callers and a masked sample" do
    ErrorGroups.record(:file_bucket, :list_files, "alice", "r_1", %{"bucket" => "a"}, :unauthorized)
    ErrorGroups.record(:file_bucket, :list_files, "bob", "r_2", %{"bucket" => "b"}, :unauthorized)
    ErrorGroups.record(:auth, :login, "alice", "r_3", %{}, :unauthorized)

    assert [login, group] = ErrorGroups.list()

    assert group.service == "file_bucket"
    assert group.action == "list_files"
    assert group.reason == ":unauthorized"
    assert group.count == 2
    assert group.rid == "r_2"
    assert group.caller == "bob"
    assert Enum.sort(group.callers) == ["alice", "bob"]
    assert group.request["bucket"] == "b"
    assert group.first_seen <= group.last_seen

    assert login.action == "login"
    assert login.count == 1
  end

  test "the sample request is masked before it is kept" do
    ErrorGroups.record(:auth, :login, "alice", "r_1", %{"email" => "a@b.c", "password" => "hunter2"}, :invalid)

    assert [group] = ErrorGroups.list()
    assert group.request["password"] == "•••"
    assert group.request["email"] == "a@b.c"
  end

  test "filters narrow by service, action, caller and rid" do
    ErrorGroups.record(:file_bucket, :list_files, "alice", "r_1", %{}, :unauthorized)
    ErrorGroups.record(:player_data, :get_player, "bob", "r_2", %{}, :not_found)

    assert [%{action: "list_files"}] = ErrorGroups.list(%{service: "file_bucket"})
    assert [%{action: "list_files"}] = ErrorGroups.list(action: "list_files")
    assert [%{action: "list_files"}] = ErrorGroups.list(%{caller: "alice"})
    assert [%{action: "get_player"}] = ErrorGroups.list(%{"rid" => "r_2"})
    assert ErrorGroups.list(%{service: "nobody"}) == []
  end

  test "the table is capped, dropping the least recently seen groups" do
    for i <- 1..210 do
      ErrorGroups.record(:svc, :act, "u", "r_#{i}", %{}, {:boom, i})
    end

    assert ErrorGroups.count() == 200
    assert ErrorGroups.list(%{rid: "r_1"}) == []
    assert [%{rid: "r_210"}] = ErrorGroups.list(%{rid: "r_210"})
  end
end
