defmodule Exoforge.Std.VersioningTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Lldb.Manager, as: DbManager
  alias Exoforge.Std.Versioning.Serializer

  setup do
    Exoforge.ExtensionCase.start_kernel()
    unless Process.whereis(DbManager), do: start_supervised!(DbManager)
    unless Process.whereis(Serializer), do: start_supervised!(Serializer)

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)

    Exoforge.ExtensionCase.register_extension(Exoforge.Std.Versioning,
      id: :exoforge_std_versioning,
      provides: [Exoforge.Std.Services.Versioning],
      dependencies: [Exoforge.Std.Services.Database]
    )

    Exoforge.Std.Versioning.init_schema()
    ActionDispatcher.dispatch_internal(:database, :execute, %{plugin: :versioning, operation: "DELETE FROM game_versions"})
    :ok
  end

  defp call(action, payload), do: ActionDispatcher.dispatch_internal(:versioning, action, payload)
  defp statuses, do: with({:ok, %{versions: v}} <- call(:list, %{}), do: Map.new(v, &{&1.version, &1.status}))

  test "a registered version starts in dev and resolves with its locks" do
    assert {:ok, %{status: "dev"}} = call(:register, %{version: "1.0", locks: %{"inventory" => "2.1.0"}})
    assert {:ok, %{status: "dev", locks: %{"inventory" => "2.1.0"}}} = call(:resolve, %{version: "1.0"})
    assert {:error, :already_exists} = call(:register, %{version: "1.0"})
    assert {:error, :not_found} = call(:resolve, %{version: "9.9"})
  end

  test "promoting moves the live one to outdated, and a fourth version blocks the oldest outdated" do
    for v <- ["1.0", "1.1", "1.2"] do
      assert {:ok, _} = call(:register, %{version: v})
      assert {:ok, %{status: "live"}} = call(:promote, %{version: v})
    end

    assert statuses() == %{"1.0" => "outdated", "1.1" => "outdated", "1.2" => "live"}

    assert {:ok, %{blocked: ["1.0"]}} = call(:register, %{version: "1.3"})
    assert statuses() == %{"1.0" => "blocked", "1.1" => "outdated", "1.2" => "live", "1.3" => "dev"}
    assert {:ok, %{status: "blocked"}} = call(:resolve, %{version: "1.0"})
  end

  test "only a dev version can be promoted, and block is idempotent" do
    assert {:ok, _} = call(:register, %{version: "1.0"})
    assert {:ok, _} = call(:promote, %{version: "1.0"})
    assert {:error, :invalid_transition} = call(:promote, %{version: "1.0"})
    assert {:error, :not_found} = call(:promote, %{version: "nope"})

    assert {:ok, %{status: "blocked"}} = call(:block, %{version: "1.0"})
    assert {:ok, %{status: "blocked"}} = call(:block, %{version: "1.0"})
    assert {:error, :not_found} = call(:block, %{version: "nope"})
  end
end
