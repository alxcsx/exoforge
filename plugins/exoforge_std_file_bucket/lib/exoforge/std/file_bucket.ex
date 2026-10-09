defmodule Exoforge.Std.FileBucket do
  @moduledoc """
  Exoforge Standard File Bucket plugin.
  Provides a pluggable file storage engine for binary assets, media, game saves, and blobs.
  Operates on the local filesystem by default, and can be swapped with alternative implementations
  (such as s3_file_bucket) satisfying the `:file_bucket` service contract.
  """
  use Exoforge.Plugin, provides: [:file_bucket]


  @manifest %{
    system: true,
    category: "Storage",
    title: "File Bucket",
    icon: "🗂️",
    dashboard_view: %{id: :file_bucket, title: "File Bucket", icon: "🗂️"}
  }

  @meta_table :exo_file_bucket_meta

  def on_init(_manifest) do
    ensure_meta_table()
    ensure_storage_dir()
    :ok
  end

  # ---- ACTION IMPLEMENTATIONS ----

  @impl true
  defaction upload_file(payload) do
    bucket = sanitize_bucket(payload[:bucket] || payload["bucket"] || "default")
    filename = payload[:filename] || payload["filename"]
    content_param = payload[:content] || payload["content"]
    path_param = payload[:path] || payload["path"]
    explicit_content_type = payload[:content_type] || payload["content_type"]
    user_metadata = payload[:metadata] || payload["metadata"] || %{}

    cond do
      is_nil(filename) or filename == "" ->
        {:error, :invalid_payload}

      is_nil(content_param) and is_nil(path_param) ->
        {:error, :invalid_payload}

      true ->
        case resolve_binary_data(content_param, path_param) do
          {:ok, binary} ->
            store_binary(bucket, filename, binary, explicit_content_type, user_metadata)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  defaction get_file_info(payload) do
    id = payload[:id] || payload["id"]
    bucket = sanitize_bucket(payload[:bucket] || payload["bucket"] || "default")

    case lookup_file(bucket, id) do
      nil -> {:error, :not_found}
      file -> {:ok, %{file: file}}
    end
  end

  @impl true
  defaction read_file(payload) do
    id = payload[:id] || payload["id"]
    bucket = sanitize_bucket(payload[:bucket] || payload["bucket"] || "default")

    case lookup_file(bucket, id) do
      nil ->
        {:error, :not_found}

      file ->
        disk_path = file["disk_path"] || file[:disk_path]

        case File.read(disk_path) do
          {:ok, binary} ->
            {:ok, %{content: binary, file: file}}

          {:error, _} ->
            {:error, :read_failed}
        end
    end
  end

  @impl true
  defaction list_files(payload) do
    bucket = sanitize_bucket(payload[:bucket] || payload["bucket"] || "default")
    limit = Map.get(payload, :limit, Map.get(payload, "limit", 50))
    offset = Map.get(payload, :offset, Map.get(payload, "offset", 0))

    files =
      list_bucket_files(bucket)
      |> Enum.sort_by(& &1["created_at"], :desc)
      |> Enum.drop(offset)
      |> Enum.take(limit)

    {:ok, %{files: files, count: length(files)}}
  end

  @impl true
  defaction delete_file(payload) do
    id = payload[:id] || payload["id"]
    bucket = sanitize_bucket(payload[:bucket] || payload["bucket"] || "default")

    case lookup_file(bucket, id) do
      nil ->
        {:error, :not_found}

      file ->
        disk_path = file["disk_path"] || file[:disk_path]
        _ = File.rm(disk_path)
        delete_meta(bucket, id)
        {:ok, %{deleted: true}}
    end
  end

  # ---- STORAGE HELPERS ----

  defp resolve_binary_data(content, path) do
    cond do
      is_binary(content) ->
        case Base.decode64(content) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:ok, content}
        end

      is_binary(path) and File.exists?(path) ->
        File.read(path)

      true ->
        {:error, :invalid_payload}
    end
  end

  defp store_binary(bucket, filename, binary, explicit_type, user_metadata) do
    id = generate_id()
    clean_filename = Path.basename(filename)
    size_bytes = byte_size(binary)
    sha256 = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
    content_type = explicit_type || detect_content_type(clean_filename)

    bucket_dir = Path.join(storage_base_dir(), bucket)
    disk_path = Path.join(bucket_dir, "#{id}_#{clean_filename}")

    with :ok <- File.mkdir_p(bucket_dir),
         :ok <- File.write(disk_path, binary) do
      file_record = %{
        "id" => id,
        "bucket" => bucket,
        "filename" => clean_filename,
        "size_bytes" => size_bytes,
        "sha256" => sha256,
        "content_type" => content_type,
        "disk_path" => disk_path,
        "url" => "/api/files/#{bucket}/#{id}/#{URI.encode(clean_filename)}",
        "metadata" => user_metadata,
        "created_at" => System.system_time(:second)
      }

      save_meta(bucket, id, file_record)
      {:ok, %{file: file_record}}
    else
      _ -> {:error, :write_failed}
    end
  end

  def storage_base_dir do
    Application.get_env(:exoforge_std_file_bucket, :storage_dir, "priv/data/file_bucket")
  end

  defp ensure_storage_dir do
    File.mkdir_p(storage_base_dir())
  end

  defp ensure_meta_table do
    if :ets.whereis(@meta_table) == :undefined do
      :ets.new(@meta_table, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  defp save_meta(bucket, id, record) do
    ensure_meta_table()
    :ets.insert(@meta_table, {{bucket, id}, record})
  end

  defp lookup_file(bucket, id) do
    ensure_meta_table()

    case :ets.lookup(@meta_table, {bucket, to_string(id)}) do
      [{{^bucket, _id}, record}] -> record
      [] -> nil
    end
  end

  defp list_bucket_files(bucket) do
    ensure_meta_table()

    :ets.tab2list(@meta_table)
    |> Enum.filter(fn {{b, _id}, _rec} -> b == bucket end)
    |> Enum.map(fn {_key, rec} -> rec end)
  end

  defp delete_meta(bucket, id) do
    ensure_meta_table()
    :ets.delete(@meta_table, {bucket, to_string(id)})
  end

  defp sanitize_bucket(bucket) when is_binary(bucket) do
    sanitized =
      bucket
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]/, "_")

    if sanitized == "", do: "default", else: sanitized
  end

  defp sanitize_bucket(_), do: "default"

  defp generate_id do
    "fl_" <> (:crypto.strong_rand_bytes(10) |> Base.url_encode64(padding: false))
  end

  defp detect_content_type(filename) do
    ext = Path.extname(filename) |> String.downcase()

    case ext do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".json" -> "application/json"
      ".txt" -> "text/plain"
      ".csv" -> "text/csv"
      ".pdf" -> "application/pdf"
      ".zip" -> "application/zip"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".mp4" -> "video/mp4"
      ".bin" -> "application/octet-stream"
      _ -> "application/octet-stream"
    end
  end
end
