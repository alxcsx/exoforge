defmodule Exoforge.Std.FileBucket do
  @moduledoc """
  Exoforge Standard File Bucket plugin.
  Provides a pluggable file storage engine for binary assets, media, game saves, and blobs.
  Operates on the local filesystem by default, and can be swapped with alternative implementations
  (such as s3_file_bucket) satisfying the `:file_bucket` service contract.
  """
  use Exoforge.Plugin, provides: [:file_bucket]

  @manifest %{
    category: "Storage",
    title: "File Bucket",
    icon: "🗂️",
    dashboard_view: %{id: :file_bucket, title: "File Bucket", icon: "🗂️"}
  }

  @meta_table :exo_file_bucket_meta

  def on_init(_manifest) do
    ensure_meta_table()
    ensure_storage_dir()
    sync_disk_to_meta()
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
    bucket = payload[:bucket] || payload["bucket"]
    sanitized = if is_binary(bucket) and bucket != "", do: sanitize_bucket(bucket), else: nil

    case lookup_file(sanitized, id) do
      nil -> {:error, :not_found}
      file -> {:ok, %{file: file}}
    end
  end

  @impl true
  defaction read_file(payload) do
    id = payload[:id] || payload["id"]
    bucket = payload[:bucket] || payload["bucket"]
    sanitized = if is_binary(bucket) and bucket != "", do: sanitize_bucket(bucket), else: nil

    case lookup_file(sanitized, id) do
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
    raw_bucket = payload[:bucket] || payload["bucket"]
    limit = Map.get(payload, :limit, Map.get(payload, "limit", 100))
    offset = Map.get(payload, :offset, Map.get(payload, "offset", 0))
    search = Map.get(payload, :search, Map.get(payload, "search", ""))

    all_files =
      cond do
        is_nil(raw_bucket) or raw_bucket in ["", "all", :all] ->
          list_all_files()

        true ->
          list_bucket_files(sanitize_bucket(raw_bucket))
      end

    filtered_files =
      if is_binary(search) and search != "" do
        q = String.downcase(search)

        Enum.filter(all_files, fn f ->
          String.contains?(String.downcase(to_string(f["filename"] || "")), q) or
            String.contains?(String.downcase(to_string(f["id"] || "")), q) or
            String.contains?(String.downcase(to_string(f["bucket"] || "")), q) or
            String.contains?(String.downcase(to_string(f["content_type"] || "")), q)
        end)
      else
        all_files
      end

    sorted =
      filtered_files
      |> Enum.sort_by(&(&1["created_at"] || 0), :desc)

    paged =
      sorted
      |> Enum.drop(offset)
      |> Enum.take(limit)

    {:ok, %{files: paged, count: length(paged), total: length(sorted)}}
  end

  @impl true
  defaction list_buckets do
    ensure_meta_table()

    buckets_from_meta =
      :ets.tab2list(@meta_table)
      |> Enum.map(fn {{b, _id}, _rec} -> b end)

    buckets_from_disk =
      case File.ls(storage_base_dir()) do
        {:ok, entries} ->
          Enum.filter(entries, fn entry ->
            File.dir?(Path.join(storage_base_dir(), entry))
          end)

        _ ->
          []
      end

    all_buckets =
      ["default" | buckets_from_meta ++ buckets_from_disk]
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, %{buckets: all_buckets}}
  end

  @impl true
  defaction update_file(payload) do
    id = payload[:id] || payload["id"]
    bucket = payload[:bucket] || payload["bucket"]
    sanitized = if is_binary(bucket) and bucket != "", do: sanitize_bucket(bucket), else: nil

    case lookup_file(sanitized, id) do
      nil ->
        {:error, :not_found}

      existing_file ->
        file_bucket = existing_file["bucket"]
        old_disk_path = existing_file["disk_path"]

        new_filename =
          case payload[:filename] || payload["filename"] do
            name when is_binary(name) and name != "" -> Path.basename(name)
            _ -> existing_file["filename"]
          end

        user_metadata =
          case payload[:metadata] || payload["metadata"] do
            meta when is_map(meta) -> Map.merge(existing_file["metadata"] || %{}, meta)
            _ -> existing_file["metadata"] || %{}
          end

        content_param = payload[:content] || payload["content"]

        new_binary =
          if is_binary(content_param) do
            case Base.decode64(content_param) do
              {:ok, decoded} -> decoded
              :error -> content_param
            end
          else
            nil
          end

        bucket_dir = Path.join(storage_base_dir(), file_bucket)
        new_disk_path = Path.join(bucket_dir, "#{id}_#{new_filename}")

        result =
          cond do
            # Updating content
            new_binary != nil ->
              if old_disk_path != new_disk_path and File.exists?(old_disk_path) do
                _ = File.rm(old_disk_path)
                _ = File.rm(old_disk_path <> ".meta.json")
              end

              size_bytes = byte_size(new_binary)
              sha256 = :crypto.hash(:sha256, new_binary) |> Base.encode16(case: :lower)

              content_type =
                payload[:content_type] || payload["content_type"] ||
                  detect_content_type(new_filename)

              with :ok <- File.write(new_disk_path, new_binary) do
                {:ok, size_bytes, sha256, content_type, new_disk_path}
              end

            # Only renaming or updating metadata
            old_disk_path != new_disk_path and File.exists?(old_disk_path) ->
              with :ok <- File.rename(old_disk_path, new_disk_path) do
                _ = File.rm(old_disk_path <> ".meta.json")

                content_type =
                  payload[:content_type] || payload["content_type"] ||
                    detect_content_type(new_filename)

                {:ok, existing_file["size_bytes"], existing_file["sha256"], content_type,
                 new_disk_path}
              end

            true ->
              content_type =
                payload[:content_type] || payload["content_type"] || existing_file["content_type"]

              {:ok, existing_file["size_bytes"], existing_file["sha256"], content_type,
               old_disk_path}
          end

        case result do
          {:ok, size_bytes, sha256, content_type, disk_path} ->
            updated_record =
              existing_file
              |> Map.merge(%{
                "filename" => new_filename,
                "size_bytes" => size_bytes,
                "sha256" => sha256,
                "content_type" => content_type,
                "disk_path" => disk_path,
                "url" => "/api/files/#{file_bucket}/#{id}/#{URI.encode(new_filename)}",
                "metadata" => user_metadata,
                "updated_at" => System.system_time(:second)
              })

            save_meta(file_bucket, id, updated_record)
            write_meta_sidecar(disk_path, updated_record)
            {:ok, %{file: updated_record}}

          _ ->
            {:error, :write_failed}
        end
    end
  end

  @impl true
  defaction delete_file(payload) do
    id = payload[:id] || payload["id"]
    bucket = payload[:bucket] || payload["bucket"]
    sanitized = if is_binary(bucket) and bucket != "", do: sanitize_bucket(bucket), else: nil

    case lookup_file(sanitized, id) do
      nil ->
        {:error, :not_found}

      file ->
        file_bucket = file["bucket"]
        disk_path = file["disk_path"] || file[:disk_path]
        _ = File.rm(disk_path)
        _ = File.rm(disk_path <> ".meta.json")
        delete_meta(file_bucket, id)
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
      write_meta_sidecar(disk_path, file_record)
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
    :ets.insert(@meta_table, {{bucket, to_string(id)}, record})
  end

  defp write_meta_sidecar(disk_path, record) do
    try do
      File.write(disk_path <> ".meta.json", Jason.encode!(record))
    rescue
      _ -> :ok
    end
  end

  defp lookup_file(nil, id), do: lookup_by_id(id)

  defp lookup_file(bucket, id) do
    ensure_meta_table()

    case :ets.lookup(@meta_table, {bucket, to_string(id)}) do
      [{{^bucket, _id}, record}] -> record
      [] -> lookup_by_id(id)
    end
  end

  defp lookup_by_id(id) do
    ensure_meta_table()
    id_str = to_string(id)

    case :ets.tab2list(@meta_table) |> Enum.find(fn {{_b, i}, _rec} -> i == id_str end) do
      {_key, rec} -> rec
      nil -> nil
    end
  end

  defp list_bucket_files(bucket) do
    ensure_meta_table()

    :ets.tab2list(@meta_table)
    |> Enum.filter(fn {{b, _id}, _rec} -> b == bucket end)
    |> Enum.map(fn {_key, rec} -> rec end)
  end

  defp list_all_files do
    ensure_meta_table()

    :ets.tab2list(@meta_table)
    |> Enum.map(fn {_key, rec} -> rec end)
  end

  defp delete_meta(bucket, id) do
    ensure_meta_table()
    :ets.delete(@meta_table, {bucket, to_string(id)})
  end

  defp sync_disk_to_meta do
    base = storage_base_dir()

    if File.dir?(base) do
      case File.ls(base) do
        {:ok, buckets} ->
          Enum.each(buckets, fn bucket ->
            bucket_path = Path.join(base, bucket)

            if File.dir?(bucket_path) do
              case File.ls(bucket_path) do
                {:ok, files} ->
                  Enum.each(files, fn file ->
                    file_path = Path.join(bucket_path, file)

                    if String.ends_with?(file, ".meta.json") do
                      try do
                        case File.read(file_path) do
                          {:ok, json} ->
                            case Jason.decode(json) do
                              {:ok, rec} ->
                                save_meta(rec["bucket"] || bucket, rec["id"], rec)

                              _ ->
                                :ok
                            end

                          _ ->
                            :ok
                        end
                      rescue
                        _ -> :ok
                      end
                    else
                      # Non-meta file: check if sidecar exists, if not index it
                      meta_path = file_path <> ".meta.json"

                      unless File.exists?(meta_path) do
                        index_loose_file(bucket, file, file_path)
                      end
                    end
                  end)

                _ ->
                  :ok
              end
            end
          end)

        _ ->
          :ok
      end
    end
  end

  defp index_loose_file(bucket, file, file_path) do
    case String.split(file, "_", parts: 2) do
      [id, name] when byte_size(id) > 4 ->
        stat = File.stat!(file_path)
        content_type = detect_content_type(name)

        rec = %{
          "id" => id,
          "bucket" => bucket,
          "filename" => name,
          "size_bytes" => stat.size,
          "sha256" => "",
          "content_type" => content_type,
          "disk_path" => file_path,
          "url" => "/api/files/#{bucket}/#{id}/#{URI.encode(name)}",
          "metadata" => %{},
          "created_at" => DateTime.to_unix(stat.mtime)
        }

        save_meta(bucket, id, rec)
        write_meta_sidecar(file_path, rec)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
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
      ".ogg" -> "audio/ogg"
      ".mp4" -> "video/mp4"
      ".webm" -> "video/webm"
      ".bin" -> "application/octet-stream"
      _ -> "application/octet-stream"
    end
  end
end
