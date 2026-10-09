defmodule Exoforge.Std.FileBucketTest do
  use ExUnit.Case, async: false
  alias Exoforge.ActionDispatcher

  setup do
    Exoforge.PluginCase.register_plugin(Exoforge.Std.FileBucket,
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

    assert {:ok, %{file: file}} = ActionDispatcher.dispatch(:file_bucket, :upload_file, payload)
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

    assert {:ok, %{file: file}} = ActionDispatcher.dispatch(:file_bucket, :upload_file, payload)
    assert file["filename"] == "data.bin"
    assert file["size_bytes"] == byte_size(raw)

    # Read back and verify content
    assert {:ok, %{content: content, file: read_file}} =
             ActionDispatcher.dispatch(:file_bucket, :read_file, %{"id" => file["id"], "bucket" => "unity_assets"})

    assert content == raw
    assert read_file["id"] == file["id"]
  end

  test "get_file_info and list_files" do
    for i <- 1..3 do
      ActionDispatcher.dispatch(:file_bucket, :upload_file, %{
        "bucket" => "avatars",
        "filename" => "avatar_#{i}.png",
        "content" => "fake png content #{i}"
      })
    end

    assert {:ok, %{files: files, count: 3}} =
             ActionDispatcher.dispatch(:file_bucket, :list_files, %{"bucket" => "avatars"})

    assert length(files) == 3

    first = hd(files)
    assert {:ok, %{file: fetched}} =
             ActionDispatcher.dispatch(:file_bucket, :get_file_info, %{"id" => first["id"], "bucket" => "avatars"})

    assert fetched["id"] == first["id"]
    assert fetched["filename"] == first["filename"]
  end

  test "delete_file removes metadata and file from disk" do
    assert {:ok, %{file: file}} = ActionDispatcher.dispatch(:file_bucket, :upload_file, %{
      "bucket" => "temp",
      "filename" => "temp.txt",
      "content" => "delete me"
    })

    assert File.exists?(file["disk_path"])

    assert {:ok, %{deleted: true}} =
             ActionDispatcher.dispatch(:file_bucket, :delete_file, %{"id" => file["id"], "bucket" => "temp"})

    refute File.exists?(file["disk_path"])

    assert {:error, :not_found} =
             ActionDispatcher.dispatch(:file_bucket, :get_file_info, %{"id" => file["id"], "bucket" => "temp"})
  end
end
