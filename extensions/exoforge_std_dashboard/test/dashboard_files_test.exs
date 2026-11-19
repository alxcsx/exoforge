defmodule Exoforge.DashboardFilesTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Dashboard.Router
  alias Exoforge.Std.Database.Manager, as: DbManager

  @opts Router.init([])

  setup do
    Exoforge.ExtensionCase.allow_dev_tokens()
    Application.put_env(:exoforge, :require_admin_auth, true)
    on_exit(fn -> Application.delete_env(:exoforge, :require_admin_auth) end)

    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!(DbManager)
    end

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)
    Exoforge.ExtensionCase.register_auth(Exoforge.Std.Auth)

    Exoforge.ExtensionCase.register_extension(Exoforge.Std.FileBucket,
      id: :exoforge_std_file_bucket,
      provides: [Exoforge.Std.Services.FileBucket]
    )

    storage_dir = "priv/data/test_dashboard_files_#{System.unique_integer([:positive])}"
    Application.put_env(:exoforge_std_file_bucket, :storage_dir, storage_dir)
    Exoforge.Std.FileBucket.on_init(%{})
    on_exit(fn -> File.rm_rf(storage_dir) end)

    {:ok, %{file: file}} =
      ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{"bucket" => "levels", "filename" => "l.png", "content" => "png"})

    {:ok, player} = Exoforge.Std.Auth.issue_token("ply_studio_files", ["player"])
    {:ok, studio} = Exoforge.Std.Auth.issue_token("stu_studio_files", ["studio"])

    %{stored: file, player: player, studio: studio}
  end

  defp get(path, token \\ nil) do
    conn = conn(:get, path)
    conn = if token, do: put_req_header(conn, "authorization", "Bearer #{token}"), else: conn
    Router.call(conn, @opts)
  end

  test "the Studio's file route refuses anonymous and player requests", %{stored: file, player: player} do
    assert get(file["url"]).status == 403
    assert get(file["url"], player).status == 403
  end

  test "staff and signed URLs are served", %{stored: file, studio: studio} do
    assert get(file["url"], studio).status == 200

    {:ok, %{url: url}} = ActionDispatcher.dispatch_internal(:file_bucket, :signed_url, %{"bucket" => "levels", "id" => file["id"]})
    assert get(url).status == 200
  end

  test "a player reaches a bucket only while staff have it public", %{stored: file, player: player} do
    assert get(file["url"], player).status == 403

    {:ok, %{visibility: "public"}} =
      ActionDispatcher.dispatch(
        :file_bucket,
        :set_bucket_visibility,
        %{
          "bucket" => "levels",
          "visibility" => "public"
        },
        caller_scopes: ["studio"]
      )

    assert get(file["url"]).status == 200
    assert get(file["url"], player).status == 200

    {:ok, %{visibility: "private"}} =
      ActionDispatcher.dispatch(
        :file_bucket,
        :set_bucket_visibility,
        %{
          "bucket" => "levels",
          "visibility" => "private"
        },
        caller_scopes: ["studio"]
      )

    assert get(file["url"]).status == 403
    assert get(file["url"], player).status == 403
  end
end
