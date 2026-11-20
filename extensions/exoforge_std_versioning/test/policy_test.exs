defmodule Exoforge.Std.Versioning.PolicyTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.Versioning.Policy

  setup do
    Application.put_env(:exoforge_std_versioning, :max_active_versions, 3)
    on_exit(fn -> Application.delete_env(:exoforge_std_versioning, :max_active_versions) end)
    :ok
  end

  test "register adds version as dev and returns only that change" do
    rows = []
    assert {:ok, %{"1.0" => "dev"}} = Policy.register(rows, "1.0")
  end

  test "register of existing version returns already_exists" do
    rows = [%{version: "1.0", status: "dev", created_at: 1}]
    assert {:error, :already_exists} = Policy.register(rows, "1.0")
  end

  test "promote dev to live turns old live into outdated" do
    rows = [
      %{version: "1.0", status: "live", created_at: 1},
      %{version: "2.0", status: "dev", created_at: 2}
    ]
    assert {:ok, %{"2.0" => "live", "1.0" => "outdated"}} = Policy.promote(rows, "2.0")
  end

  test "promote of unknown returns not_found" do
    rows = [%{version: "1.0", status: "dev", created_at: 1}]
    assert {:error, :not_found} = Policy.promote(rows, "9.9")
  end

  test "promote of non-dev returns invalid_transition" do
    rows = [%{version: "1.0", status: "live", created_at: 1}]
    assert {:error, :invalid_transition} = Policy.promote(rows, "1.0")
  end

  test "registering 4th with 3 non-blocked blocks oldest outdated" do
    rows = [
      %{version: "1.0", status: "outdated", created_at: 1},
      %{version: "2.0", status: "live", created_at: 2},
      %{version: "3.0", status: "dev", created_at: 3}
    ]
    assert {:ok, %{"4.0" => "dev", "1.0" => "blocked"}} = Policy.register(rows, "4.0")
  end

  test "registering over cap with only dev+live+dev returns too_many_active" do
    rows = [
      %{version: "1.0", status: "dev", created_at: 1},
      %{version: "2.0", status: "live", created_at: 2},
      %{version: "3.0", status: "dev", created_at: 3}
    ]
    assert {:error, :too_many_active} = Policy.register(rows, "4.0")
  end

  test "block of unknown returns not_found" do
    rows = [%{version: "1.0", status: "dev", created_at: 1}]
    assert {:error, :not_found} = Policy.block(rows, "9.9")
  end

  test "block of blocked returns ok empty" do
    rows = [%{version: "1.0", status: "blocked", created_at: 1}]
    assert {:ok, %{}} = Policy.block(rows, "1.0")
  end
end