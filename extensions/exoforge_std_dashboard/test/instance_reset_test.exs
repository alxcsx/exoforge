defmodule Exoforge.Std.Dashboard.InstanceResetTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.{Auth, Database}
  alias Exoforge.Std.Lldb.Manager, as: DbManager

  defmodule GameStub do
    use Exoforge.Extension, provides: [:reset_game_service]
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    unless Process.whereis(DbManager), do: start_supervised!(DbManager)

    Exoforge.ExtensionCase.register_database(Database)
    Exoforge.ExtensionCase.register_auth(Auth)

    Exoforge.ExtensionCase.register_extension(Exoforge.Std.ExtensionManager,
      id: :extension_manager,
      provides: [:extension_manager]
    )

    Exoforge.ExtensionCase.register_extension(GameStub,
      id: :reset_game,
      provides: [:reset_game_service],
      physical_path: Path.join([System.tmp_dir!(), "exoforge_uploaded_extensions", "reset_game"])
    )

    Auth.init_schema()
    {:ok, _} = Auth.upsert_account("admin", "admin@example.com", "pw", ["admin"])
    {:ok, _} = Auth.upsert_account("alice", "alice@example.com", "pw", ["player"])
    {:ok, _} = Database.put(:reset_game, "scores", "1", %{"points" => 5})
    :ok
  end

  defp reset(mode, scopes \\ ["admin"]),
    do: ActionDispatcher.dispatch(:extension_manager, :reset_instance, %{mode: mode}, caller_scopes: scopes)

  defp account_ids do
    {:ok, %{rows: rows}} =
      Database.execute(:auth, "SELECT player_id FROM accounts")

    Enum.map(rows, & &1["player_id"])
  end

  test "a non-admin caller is refused and nothing is removed" do
    assert {:error, _} = reset("everything", ["studio"])
    assert Exoforge.ExtensionRegistry.fetch_manifest(:reset_game)
  end

  test "an unknown mode is refused" do
    assert {:error, :invalid_mode} = reset("nope")
  end

  test "extensions mode removes user extensions and their data but keeps accounts" do
    assert {:ok, summary} = reset("extensions")
    assert "reset_game" in summary.extensions_removed
    refute Exoforge.ExtensionRegistry.fetch_manifest(:reset_game)
    assert {:error, _} = Database.get(:reset_game, "scores", "1")
    assert Exoforge.ExtensionRegistry.fetch_manifest(:extension_manager)
    assert "alice" in account_ids()
    assert "admin" in account_ids()
  end

  test "everything mode also removes players but the admin account survives" do
    assert {:ok, summary} = reset("everything")
    assert "reset_game" in summary.extensions_removed
    assert summary.accounts_removed >= 1
    ids = account_ids()
    refute "alice" in ids
    assert "admin" in ids
  end

  test "extensions mode never deletes source files outside the uploads folder" do
    dir = Path.join(System.tmp_dir!(), "reset_checkout_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "Source.cs"), "// checked in")
    on_exit(fn -> File.rm_rf(dir) end)

    Exoforge.ExtensionCase.register_extension(GameStub,
      id: :reset_checkout,
      provides: [:reset_checkout_service],
      type: :native,
      physical_path: dir
    )

    assert {:ok, summary} = reset("extensions")
    assert "reset_checkout" in summary.extensions_removed
    assert File.exists?(Path.join(dir, "Source.cs"))
  end
end
