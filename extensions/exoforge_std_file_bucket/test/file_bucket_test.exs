defmodule Exoforge.Std.FileBucketTest do
  use ExUnit.Case, async: false
  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database.Manager, as: DbManager

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!(DbManager)
    end

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)

    Exoforge.ExtensionCase.register_extension(Exoforge.Std.FileBucket,
      id: :exoforge_std_file_bucket,
      provides: [:file_bucket]
    )

    storage_dir = "priv/data/test_file_bucket_#{System.unique_integer([:positive])}"
    Application.put_env(:exoforge_std_file_bucket, :storage_dir, storage_dir)
    Exoforge.Std.FileBucket.on_init(%{})

    on_exit(fn ->
      File.rm_rf(storage_dir)
    end)

    %{storage_dir: storage_dir}
  end

  test "upload_file with raw binary content" do
    payload = %{
      "bucket" => "test_bucket",
      "filename" => "hello.txt",
      "content" => "Hello Exoforge File Bucket!",
      "content_type" => "text/plain"
    }

    assert {:ok, %{file: file}} = ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, payload)
    assert file["filename"] == "hello.txt"
    assert file["bucket"] == "test_bucket"
    assert file["size_bytes"] == 27
    assert file["content_type"] == "text/plain"
    assert is_binary(file["sha256"])
    assert File.exists?(file["disk_path"])
  end

  test "upload_file with base64 encoded content" do
    raw = "Binary payload from Unity or web"
    b64 = Base.encode64(raw)

    payload = %{
      "bucket" => "unity_assets",
      "filename" => "data.bin",
      "content" => b64
    }

    assert {:ok, %{file: file}} = ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, payload)
    assert file["filename"] == "data.bin"
    assert file["size_bytes"] == byte_size(raw)

    # Read back and verify content
    assert {:ok, %{content: content, file: read_file}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :read_file, %{"id" => file["id"], "bucket" => "unity_assets"})

    assert content == raw
    assert read_file["id"] == file["id"]
  end

  test "get_file_info and list_files with search" do
    for i <- 1..3 do
      ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
        "bucket" => "avatars",
        "filename" => "avatar_#{i}.png",
        "content" => "fake png content #{i}"
      })
    end

    assert {:ok, %{files: files, count: 3}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :list_files, %{"bucket" => "avatars"})

    assert length(files) == 3

    first = hd(files)
    # Lookup by id without specifying bucket
    assert {:ok, %{file: fetched}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :get_file_info, %{"id" => first["id"]})

    assert fetched["id"] == first["id"]
    assert fetched["filename"] == first["filename"]

    # Search filter
    assert {:ok, %{files: search_res, count: 1}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :list_files, %{"search" => "avatar_2"})
    assert hd(search_res)["filename"] == "avatar_2.png"
  end

  test "list_buckets lists all active buckets" do
    ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
      "bucket" => "bucket_alpha",
      "filename" => "alpha.txt",
      "content" => "alpha"
    })

    ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
      "bucket" => "bucket_beta",
      "filename" => "beta.txt",
      "content" => "beta"
    })

    assert {:ok, %{buckets: buckets}} = ActionDispatcher.dispatch_internal(:file_bucket, :list_buckets, %{})
    names = Enum.map(buckets, & &1["bucket"])
    assert "bucket_alpha" in names
    assert "bucket_beta" in names
    assert "default" in names

    assert %{"bucket" => "default", "visibility" => "private"} =
             Enum.find(buckets, &(&1["bucket"] == "default"))

    assert %{"bucket" => "bucket_alpha", "visibility" => "private"} =
             Enum.find(buckets, &(&1["bucket"] == "bucket_alpha"))
  end

  test "update_file modifies filename and replaces content while keeping id" do
    assert {:ok, %{file: file}} = ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
      "bucket" => "docs",
      "filename" => "old_name.txt",
      "content" => "old content"
    })

    id = file["id"]

    assert {:ok, %{file: updated}} = ActionDispatcher.dispatch_internal(:file_bucket, :update_file, %{
      "id" => id,
      "bucket" => "docs",
      "filename" => "new_name.txt",
      "content" => "new replaced content!"
    })

    assert updated["id"] == id
    assert updated["filename"] == "new_name.txt"
    assert updated["size_bytes"] == byte_size("new replaced content!")

    assert {:ok, %{content: read_content}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :read_file, %{"id" => id, "bucket" => "docs"})
    assert read_content == "new replaced content!"
  end

  test "delete_file removes metadata and file from disk" do
    assert {:ok, %{file: file}} = ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
      "bucket" => "temp",
      "filename" => "temp.txt",
      "content" => "delete me"
    })

    assert File.exists?(file["disk_path"])

    assert {:ok, %{deleted: true}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :delete_file, %{"id" => file["id"], "bucket" => "temp"})

    refute File.exists?(file["disk_path"])

    assert {:error, :not_found} =
             ActionDispatcher.dispatch_internal(:file_bucket, :get_file_info, %{"id" => file["id"], "bucket" => "temp"})
  end

  test "lookup by filename and .bundle content type detection" do
    assert {:ok, %{file: file}} = ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
      "bucket" => "addressables",
      "filename" => "scene_all_123.bundle",
      "content" => "bundle_binary_content",
      "metadata" => %{"tag" => "addressables"}
    })

    assert file["content_type"] == "application/octet-stream"

    # Lookup using filename instead of id
    assert {:ok, %{file: by_name}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :get_file_info, %{
               "bucket" => "addressables",
               "id" => "scene_all_123.bundle"
             })

    assert by_name["id"] == file["id"]
    assert by_name["filename"] == "scene_all_123.bundle"
  end

  test "seeds SDK archives from dist into sdk bucket and resolves by engine alias", %{storage_dir: storage_dir} do
    File.rm_rf!(Path.join(storage_dir, "sdk"))
    dist_dir = "priv/data/test_dist_#{System.unique_integer([:positive])}"
    File.mkdir_p!(dist_dir)
    on_exit(fn -> File.rm_rf(dist_dir) end)

    File.write!(Path.join(dist_dir, "com.exoforge.sdk-0.1.0.tgz"), "fake_tgz_payload")
    Application.put_env(:exoforge_std_file_bucket, :sdk_dist_dir, dist_dir)
    on_exit(fn -> Application.delete_env(:exoforge_std_file_bucket, :sdk_dist_dir) end)

    Exoforge.Std.FileBucket.on_init(%{})

    assert {:ok, %{file: sdk_file}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :get_file_info, %{
               "bucket" => "sdk",
               "id" => "unity"
             })

    assert sdk_file["filename"] == "com.exoforge.sdk-0.1.0.tgz"
    assert sdk_file["content_type"] == "application/gzip"
    assert sdk_file["metadata"]["engine"] == "unity"
  end

  test "seeds multiple SDK versions and resolves engine query to latest version", %{storage_dir: storage_dir} do
    File.rm_rf!(Path.join(storage_dir, "sdk"))
    dist_dir = "priv/data/test_dist_multi_#{System.unique_integer([:positive])}"
    File.mkdir_p!(dist_dir)
    on_exit(fn -> File.rm_rf(dist_dir) end)

    File.write!(Path.join(dist_dir, "com.exoforge.sdk-0.1.15.tgz"), "older_payload")
    File.write!(Path.join(dist_dir, "com.exoforge.sdk-0.1.31.tgz"), "newer_payload")
    Application.put_env(:exoforge_std_file_bucket, :sdk_dist_dir, dist_dir)
    on_exit(fn -> Application.delete_env(:exoforge_std_file_bucket, :sdk_dist_dir) end)

    Exoforge.Std.FileBucket.on_init(%{})

    assert {:ok, %{file: sdk_file}} =
             ActionDispatcher.dispatch_internal(:file_bucket, :get_file_info, %{
               "bucket" => "sdk",
               "id" => "unity"
             })

    assert sdk_file["filename"] == "com.exoforge.sdk-0.1.31.tgz"
    assert sdk_file["metadata"]["version"] == "0.1.31"
  end

  describe "access" do
    test "players cannot call raw file actions; staff can" do
      payload = %{"bucket" => "b", "filename" => "a.txt", "content" => "x"}

      for action <- [
            :upload_file,
            :list_files,
            :list_buckets,
            :set_bucket_visibility,
            :read_file,
            :get_file_info,
            :update_file,
            :delete_file
          ] do
        assert {:error, {:forbidden_scope, _}} =
                 ActionDispatcher.dispatch(:file_bucket, action, payload, caller_scopes: ["player"])
      end

      assert {:ok, %{file: _}} =
               ActionDispatcher.dispatch(:file_bucket, :upload_file, payload, caller_scopes: ["studio"])
    end

    test "signed_url and authorize_download are server-only, even for admins" do
      for action <- [:signed_url, :authorize_download] do
        assert {:error, {:forbidden_scope, _}} =
                 ActionDispatcher.dispatch(:file_bucket, action, %{}, caller_scopes: ["admin"])
      end
    end

    test "upload_file never reads a server path" do
      secret = Path.join(System.tmp_dir!(), "exo_bucket_secret_#{System.unique_integer([:positive])}")
      File.write!(secret, "do not leak")

      assert {:error, :invalid_payload} =
               ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{
                 "bucket" => "x",
                 "filename" => "h.txt",
                 "path" => secret
               })

      File.rm(secret)
    end

    test "a signed URL authorizes one file until it expires" do
      {:ok, %{file: file}} =
        ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, %{"bucket" => "levels", "filename" => "l.png", "content" => "png"})

      {:ok, %{url: url}} =
        ActionDispatcher.dispatch_internal(:file_bucket, :signed_url, %{"bucket" => "levels", "id" => file["id"], "ttl_seconds" => 60})

      %{"exp" => exp, "sig" => sig} = url |> URI.parse() |> Map.get(:query) |> URI.decode_query()
      grant = %{"bucket" => "levels", "id" => file["id"], "exp" => exp, "sig" => sig}

      assert {:ok, %{allowed: true}} = ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, grant)
      assert {:ok, %{allowed: false}} = ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{grant | "id" => "other"})
      assert {:ok, %{allowed: false}} = ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{grant | "exp" => "1"})
      assert {:ok, %{allowed: false}} = ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, Map.delete(grant, "sig"))
    end

    test "the config seeds sdk as public; every other bucket is private" do
      assert {:ok, %{allowed: true}} = ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{"bucket" => "sdk", "id" => "any"})
      assert {:ok, %{allowed: false}} = ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{"bucket" => "levels", "id" => "any"})
    end

    test "staff set a bucket's visibility and the stored value decides the download" do
      bucket = "levels_#{System.unique_integer([:positive])}"

      assert {:ok, %{allowed: false}} =
               ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{"bucket" => bucket, "id" => "any"})

      assert {:ok, %{bucket: ^bucket, visibility: "public"}} =
               ActionDispatcher.dispatch(
                 :file_bucket,
                 :set_bucket_visibility,
                 %{
                   "bucket" => bucket,
                   "visibility" => "public"
                 },
                 caller_scopes: ["studio"]
               )

      assert {:ok, %{allowed: true}} =
               ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{"bucket" => bucket, "id" => "any"})

      assert {:ok, %{visibility: "private"}} =
               ActionDispatcher.dispatch_internal(:file_bucket, :set_bucket_visibility, %{
                 "bucket" => bucket,
                 "visibility" => "private"
               })

      assert {:ok, %{allowed: false}} =
               ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{"bucket" => bucket, "id" => "any"})
    end

    test "a visibility only accepts public or private" do
      assert {:error, :invalid_payload} =
               ActionDispatcher.dispatch_internal(:file_bucket, :set_bucket_visibility, %{
                 "bucket" => "levels",
                 "visibility" => "everyone"
               })
    end

    test "visibility survives an extension restart, and the config does not undo it" do
      try do
        assert {:ok, %{visibility: "private"}} =
                 ActionDispatcher.dispatch_internal(:file_bucket, :set_bucket_visibility, %{
                   "bucket" => "sdk",
                   "visibility" => "private"
                 })

        Exoforge.Std.FileBucket.on_init(%{})

        assert {:ok, %{allowed: false}} =
                 ActionDispatcher.dispatch_internal(:file_bucket, :authorize_download, %{"bucket" => "sdk", "id" => "any"})
      after
        # The stored value outlives the test; put the seeded default back for the tests that follow.
        ActionDispatcher.dispatch_internal(:file_bucket, :set_bucket_visibility, %{
          "bucket" => "sdk",
          "visibility" => "public"
        })
      end
    end
  end
end
