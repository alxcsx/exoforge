defmodule Exoforge.Std.ExtensionManager do
  @moduledoc """
  Standard Extension Manager for Exoforge.
  Provides the :extension_manager service contract for runtime inspection,
  hot-loading of Elixir and native C# extensions, lifecycle restarts,
  and CLI/SDK synchronization.

  Redeploying an extension stops the previous instance before starting the new one
  (one instance by design, to prevent duplicate runners and binary-busy errors),
  creating a brief window where the extension is not running. Lifecycle mutations
  (`upload_extension`, `remove_extension`, `reload_extension`) are serialized through
  `Exoforge.Std.ExtensionManager.Serializer`, and a failed redeploy restores the
  backed-up previous version.
  """
  use Exoforge.Extension, provides: [:extension_manager]

  defmodule Serializer do
    @moduledoc false
    use GenServer
    require Logger

    def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

    def run(fun) when is_function(fun, 0) do
      ensure_started()
      GenServer.call(__MODULE__, {:run, fun}, :infinity)
    end

    defp ensure_started do
      if Process.whereis(__MODULE__) == nil do
        case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
      end
    end

    # Recovery runs after init returns and never raises out of it: a backup that cannot be restored
    # is logged, not a crash loop that takes the extension manager down with it.
    @impl true
    def init(:ok), do: {:ok, %{}, {:continue, :recover}}

    @impl true
    def handle_continue(:recover, state) do
      try do
        Exoforge.Std.ExtensionManager.recover_leftover_backups()
      rescue
        e -> Logger.error("[ExtensionManager] Backup recovery failed: #{Exception.message(e)}")
      catch
        kind, reason -> Logger.error("[ExtensionManager] Backup recovery failed: #{inspect({kind, reason})}")
      end

      {:noreply, state}
    end

    @impl true
    def handle_call({:run, fun}, _from, state) do
      {:reply, fun.(), state}
    end
  end

  def children, do: [Serializer]

  alias Exoforge.ExtensionRegistry
  alias Exoforge.ExtensionBootstrapper
  alias Exoforge.Drivers.Loaders.ManifestLoader
  require Logger

  @manifest %{
    dependencies: [],
    title: "Extension Manager",
    icon: "⚙️",
    category: "System",
    system: true,
    dashboard_view: %{
      id: :extension_manager,
      title: "Extension Manager",
      icon: "⚙️"
    }
  }

  @doc "Dashboard visualization specification."
  def dashboard_view, do: @manifest.dashboard_view

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction list_extensions, scope: Exoforge.Auth.Roles.studio() do
    # Extensions that failed to boot are not registered; they are listed too, so the cluster can say
    # which are down and why.
    failed = Enum.map(ExtensionRegistry.failed_extensions(), fn {manifest, _failure} -> manifest end)
    manifests = ExtensionRegistry.all_manifests() ++ failed

    extensions =
      Enum.map(manifests, fn m ->
        dv = m.dashboard_view
        dv_title = is_map(dv) && (Map.get(dv, :title) || Map.get(dv, "title"))
        dv_icon = is_map(dv) && (Map.get(dv, :icon) || Map.get(dv, "icon"))
        title = m.title || dv_title || to_string(m.name || m.id)
        icon = m.icon || dv_icon || "🧩"

        %{
          "id" => to_string(m.id),
          "name" => to_string(m.name),
          "title" => title,
          "icon" => icon,
          "version" => to_string(m.version),
          "type" => to_string(m.type),
          "status" => extension_status(m.id),
          "failure" => failure_info(m.id),
          "entry_point" => to_string(m.entry_point),
          "category" => m.category || "Extension",
          "system" => m.system == true,
          "provides" => Enum.map(m.provides || [], &ExtensionRegistry.service_alias_or_module/1),
          "dependencies" => Enum.map(m.dependencies || [], &ExtensionRegistry.service_alias_or_module/1),
          "services" => ExtensionRegistry.sanitize_for_json(m.services || []),
          "dashboard_view" => dv,
          "physical_path" => m.physical_path
        }
      end)
      |> Enum.sort_by(& &1["id"])

    {:ok, %{extensions: extensions, count: length(extensions)}}
  end

  @impl true
  defaction get_extension(payload), scope: Exoforge.Auth.Roles.studio() do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")

    if is_nil(id_str) or id_str == "" do
      {:error, :not_found}
    else
      manifest = find_manifest(id_str)

      case manifest do
        nil ->
          {:error, :not_found}

        m ->
          size_bytes = calculate_extension_size(m)

          dv = m.dashboard_view
          dv_title = is_map(dv) && (Map.get(dv, :title) || Map.get(dv, "title"))
          dv_icon = is_map(dv) && (Map.get(dv, :icon) || Map.get(dv, "icon"))
          title = m.title || dv_title || to_string(m.name || m.id)
          icon = m.icon || dv_icon || "🧩"

          ext_data = %{
            "id" => to_string(m.id),
            "name" => to_string(m.name),
            "title" => title,
            "icon" => icon,
            "version" => to_string(m.version),
            "type" => to_string(m.type),
            "status" => extension_status(m.id),
            "failure" => failure_info(m.id),
            "category" => m.category || "Extension",
            "system" => m.system == true,
            "entry_point" => to_string(m.entry_point),
            "provides" => Enum.map(m.provides || [], &ExtensionRegistry.service_alias_or_module/1),
            "dependencies" => Enum.map(m.dependencies || [], &ExtensionRegistry.service_alias_or_module/1),
            "services" => ExtensionRegistry.sanitize_for_json(m.services || []),
            "dashboard_view" => dv,
            "physical_path" => m.physical_path,
            "size_bytes" => size_bytes
          }

          {:ok, %{extension: ext_data}}
      end
    end
  end

  @impl true
  defaction get_system_info, scope: Exoforge.Auth.Roles.studio() do
    mem_total = :erlang.memory(:total)
    count = length(ExtensionRegistry.all_manifests())

    info = %{
      "node" => to_string(node()),
      "uptime_seconds" => div(:erlang.element(1, :erlang.statistics(:wall_clock)), 1000),
      "memory_bytes" => mem_total,
      "memory_mb" => Float.round(mem_total / (1024 * 1024), 2),
      "process_count" => :erlang.system_info(:process_count),
      "elixir_version" => System.version(),
      "otp_release" => System.otp_release(),
      "version" => Exoforge.BuildInfo.version(),
      "commit_hash" => Exoforge.BuildInfo.commit_hash(),
      "build_date" => Exoforge.BuildInfo.build_date(),
      "extensions_count" => count,
      "title_id" => Exoforge.Metering.title_id(),
      "studio_id" => Exoforge.Metering.studio_id(),
      "project_name" => Exoforge.Metering.project_name(),
      "studio_name" => Exoforge.Metering.studio_name(),
      "target_rid" => cluster_target_rid(),
      "os" => cluster_os(),
      "arch" => cluster_arch()
    }

    {:ok, %{system: info}}
  end

  @impl true
  defaction upload_extension(payload), scope: Exoforge.Auth.Roles.admin() do
    Serializer.run(fn -> upload_extension_internal(payload) end)
  end

  @impl true
  defaction remove_extension(payload), scope: Exoforge.Auth.Roles.admin() do
    Serializer.run(fn -> remove_extension_internal(payload) end)
  end

  @doc """
  Wipes the instance. `mode` is "extensions" (remove every non-standard extension with its tables,
  data and file buckets; accounts, tokens and Studio settings stay) or "everything" (also players,
  accounts except admin/studio ones, service tokens, game versions, Studio preferences, file buckets).
  """
  @impl true
  defaction reset_instance(payload), scope: Exoforge.Auth.Roles.admin() do
    Serializer.run(fn -> reset_instance_internal(payload) end)
  end

  @impl true
  defaction restart_system, scope: Exoforge.Auth.Roles.admin() do
    ExtensionBootstrapper.reload_all()
    count = length(ExtensionRegistry.all_manifests())
    {:ok, %{status: "restarted", extensions_count: count}}
  end

  @impl true
  defaction logs(payload), scope: Exoforge.Auth.Roles.studio() do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")
    limit = Map.get(payload, :limit) || Map.get(payload, "limit") || 100

    case find_manifest(id_str) do
      nil ->
        {:error, :not_found}

      m ->
        lines = Exoforge.ExtensionLogs.list(m.id, limit)
        {:ok, %{extension_id: to_string(m.id), lines: lines, count: length(lines)}}
    end
  end

  @impl true
  defaction reload_extension(payload), scope: Exoforge.Auth.Roles.admin() do
    Serializer.run(fn -> reload_extension_internal(payload) end)
  end

  @impl true
  defaction export_extension_info, scope: Exoforge.Auth.Roles.studio() do
    export_info_internal()
  end

  @impl true
  defaction csharp_attributes, scope: Exoforge.Auth.Roles.studio() do
    files = scan_csharp_attributes()
    {:ok, %{files: files, count: length(files)}}
  end

  ## ---- PRIVATE HELPERS ----

  defp upload_extension_internal(payload) do
    name_str = Map.get(payload, :name) || Map.get(payload, "name")
    raw_binary = Map.get(payload, :binary) || Map.get(payload, "binary")

    elixir_code =
      Map.get(payload, :elixir_code) || Map.get(payload, "elixir_code") ||
        Map.get(payload, :code) || Map.get(payload, "code")

    files_map = Map.get(payload, :files) || Map.get(payload, "files")
    manifest_param = Map.get(payload, :manifest) || Map.get(payload, "manifest")
    type_param = Map.get(payload, :type) || Map.get(payload, "type")

    ext_type = detect_extension_type(type_param, raw_binary, elixir_code, files_map)

    cond do
      is_nil(name_str) or name_str == "" ->
        {:error, :invalid_package}

      is_nil(ext_type) ->
        {:error, :invalid_package}

      ext_type == :native and (is_nil(raw_binary) or raw_binary == "") ->
        {:error, :invalid_package}

      # Refused before the running copy is stopped: a binary built for another OS dies on its first byte
      # ("syntax error: unexpected word" from the shell) and takes the working version with it.
      ext_type == :native and wrong_binary_format(raw_binary) != nil ->
        {:error, {:wrong_binary_format, wrong_binary_format(raw_binary)}}

      ext_type == :elixir and not has_elixir_code?(elixir_code, files_map) ->
        {:error, :invalid_package}

      true ->
        clean_name = sanitize_name(name_str)

        case validate_incoming_manifest_resources(clean_name, manifest_param, files_map) do
          {:error, reason} ->
            {:error, {:migration_failed, reason}}

          :ok ->
            # Capture the previous manifest before unloading so a failed redeploy can restore it.
            previous = find_manifest(name_str)

            # Re-deploying a running extension: stop the old instance first, otherwise its binary is busy
            # (ETXTBSY on Linux) and booting again would start a duplicate runner.
            _ = ExtensionBootstrapper.unload_extension(name_str)

            case ext_type do
              :native -> handle_upload_native(name_str, raw_binary, manifest_param, files_map, previous)
              :elixir -> handle_upload_elixir(name_str, elixir_code, files_map, manifest_param, previous)
            end
        end
    end
  end

  # Returns a message when the uploaded executable cannot run on this cluster's OS, nil when it can (or
  # when the format is not one we recognise: the runner's own handshake failure still covers that).
  def wrong_binary_format(raw_binary) when is_binary(raw_binary) do
    head =
      case Base.decode64(binary_part(raw_binary, 0, min(byte_size(raw_binary), 16) |> div(4) |> Kernel.*(4))) do
        {:ok, decoded} -> decoded
        _ -> raw_binary
      end

    built_for =
      case head do
        <<0x7F, "ELF", _::binary>> -> "linux"
        <<"MZ", _::binary>> -> "win"
        <<0xCF, 0xFA, 0xED, 0xFE, _::binary>> -> "osx"
        <<0xCA, 0xFE, 0xBA, 0xBE, _::binary>> -> "osx"
        _ -> nil
      end

    server = cluster_os()

    cond do
      is_nil(built_for) -> nil
      built_for == "linux" and String.starts_with?(server, "linux") -> nil
      built_for == server -> nil
      true ->
        "This extension was built for #{built_for}, but this server runs #{server}. " <>
          "Build it for #{cluster_target_rid()} (exo extension push does this by itself; in Unity set the build target to Auto or #{cluster_target_rid()}) and upload it again. The version that was running is untouched."
    end
  end

  def wrong_binary_format(_), do: nil

  defp has_elixir_code?(elixir_code, files_map) do
    (is_binary(elixir_code) and String.trim(elixir_code) != "") or
      (is_map(files_map) and map_size(files_map) > 0)
  end

  defp reset_instance_internal(payload) do
    mode = to_string(Map.get(payload, :mode) || Map.get(payload, "mode") || "")

    if mode in ["extensions", "everything"] do
      failed = Enum.map(ExtensionRegistry.failed_extensions(), fn {manifest, _} -> manifest end)

      user_manifests =
        (ExtensionRegistry.all_manifests() ++ failed)
        |> Enum.filter(&user_deployed?/1)
        |> Enum.uniq_by(&to_string(&1.id))

      ids = Enum.map(user_manifests, &to_string(&1.id))
      # Only what was uploaded is deleted from disk. A native extension loaded from a checkout (a maintainer's
      # extensions_csharp/ folder, say) is unloaded and its data dropped, but its source files are never touched.
      removed =
        user_manifests
        |> Enum.filter(fn m ->
          match?({:ok, _}, remove_extension_internal(%{"id" => to_string(m.id), "delete_files" => uploaded?(m)}))
        end)
        |> Enum.map(&to_string(&1.id))

      Enum.each(ids, fn id ->
        ExtensionRegistry.clear_failure(id)
        optional(Exoforge.Std.Database, :reset!, [Exoforge.Atoms.existing(id, id)])
        optional(Exoforge.Std.Database, :reset!, [id])
        optional(Exoforge.Std.Resources, :forget_migrated, [Exoforge.Atoms.existing(id, id)])
      end)

      # Extension files live in buckets the extension names itself (level_share: "doodle_levels"), so a
      # reset empties every bucket except the SDK package bucket.
      files = optional(Exoforge.Std.FileBucket, :wipe, [:files]) || 0

      summary = %{mode: mode, extensions_removed: removed, extensions_skipped: ids -- removed, files_removed: files}
      {:ok, if(mode == "everything", do: Map.merge(summary, reset_everything_else()), else: summary)}
    else
      {:error, :invalid_mode}
    end
  end

  # An extension the user deployed: a native (C#) one, or any extension that sits in the uploads folder.
  # Standard extensions are Elixir and live under builtin_extensions/ (or extensions/ in a checkout).
  defp user_deployed?(%{type: :native}), do: true
  defp user_deployed?(manifest), do: uploaded?(manifest)

  # Sits in the uploads folder (or its temp fallback), and is not a built-in.
  defp uploaded?(%{physical_path: path}) when is_binary(path) do
    norm = Path.expand(path)
    uploads = [Path.expand(upload_base_dir()), Path.expand(Path.join(System.tmp_dir!(), "exoforge_uploaded_extensions"))]
    not String.starts_with?(norm, Path.expand("builtin_extensions")) and Enum.any?(uploads, &String.starts_with?(norm, &1))
  end

  defp uploaded?(_), do: false

  # The wipe helpers live in other standard extensions, which a stripped-down server may not have.
  defp optional(module, fun, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, fun, length(args)), do: apply(module, fun, args)
  end

  defp reset_everything_else do
    %{removed: accounts_removed, kept: kept} = optional(Exoforge.Std.Auth, :wipe_accounts, []) || %{removed: 0, kept: []}

    kept = Enum.uniq(["admin" | kept])
    placeholders = kept |> Enum.with_index(1) |> Enum.map_join(", ", fn {_, i} -> "$#{i}" end)

    for table <- ["players", "player_kv"] do
      Exoforge.ActionDispatcher.dispatch_internal(:database, :execute, %{
        plugin: :player_data,
        operation: "DELETE FROM #{table} WHERE player_id NOT IN (#{placeholders})",
        arguments: kept
      })
    end

    versions = optional(Exoforge.Std.Versioning, :wipe, []) || 0
    all_files = optional(Exoforge.Std.FileBucket, :wipe, [:all]) || 0
    optional(Exoforge.Std.Dashboard.ProjectMetadata, :reset, [])

    %{accounts_removed: accounts_removed, accounts_kept: kept, game_versions_removed: versions, bucket_files_removed: all_files, studio_config: "reset"}
  end

  defp remove_extension_internal(payload) do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")
    delete_files = Map.get(payload, :delete_files) || Map.get(payload, "delete_files") || false

    if is_nil(id_str) or id_str == "" do
      {:error, :not_found}
    else
      atom_id = Exoforge.Atoms.existing(id_str, id_str)

      manifest =
        ExtensionRegistry.fetch_manifest(id_str) ||
          ExtensionRegistry.fetch_manifest(atom_id)

      case manifest do
        nil ->
          {:error, :not_found}

        m ->
          ExtensionBootstrapper.unload_extension(id_str)
          if atom_id != id_str, do: ExtensionBootstrapper.unload_extension(atom_id)

          if m.type == :elixir and is_atom(m.entry_point) do
            :code.purge(m.entry_point)
            :code.delete(m.entry_point)
          end

          Exoforge.ExtensionLogs.clear(m.id)

          if (delete_files and m.physical_path) && File.dir?(m.physical_path) do
            clean_delete_directory(m.physical_path)
          end

          {:ok, %{status: "removed", id: to_string(m.id), extension_id: to_string(m.id), type: to_string(m.type)}}
      end
    end
  end

  defp reload_extension_internal(payload) do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")

    case find_manifest(id_str) do
      nil ->
        {:error, :not_found}

      m ->
        ExtensionBootstrapper.unload_extension(m.id)

        case reload_boot(m) do
          :ok -> {:ok, %{extension_id: to_string(m.id), status: "installed"}}
          {:error, reason} -> {:error, %{error: reason}}
        end
    end
  end

  # Boots the files that are already installed. Unlike an install there is no earlier version to go
  # back to, and `rollback_extension/6` deletes the target directory, so a failed reload must not go
  # through it: it leaves the files alone and records the extension as failed, so it stays listed with why.
  defp reload_boot(%{physical_path: path} = manifest) do
    result =
      try do
        case ManifestLoader.load_extensions(path) do
          [loaded | _] ->
            ExtensionRegistry.register(loaded)

            case run_resource_migration(loaded) do
              {:error, reason} -> {:error, {:migration_failed, reason}}
              _ -> safe_boot_extension(loaded)
            end

          [] ->
            {:error, :manifest_not_loaded}
        end
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, reason}
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        _ = ExtensionBootstrapper.unload_extension(manifest.id)
        ExtensionRegistry.unregister(manifest.id)

        ExtensionRegistry.record_failure(manifest, %{
          kind: :boot_failed,
          stage: :reload,
          message: "reload failed: #{inspect(reason)}",
          detail: inspect(reason),
          at: System.system_time(:second)
        })

        {:error, reason}
    end
  end

  defp run_resource_migration(loaded_manifest) do
    if ExtensionRegistry.fetch_service(:resource_store) != nil and declares_resources?(loaded_manifest) do
      Exoforge.ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{
        extension: to_string(loaded_manifest.id)
      })
    else
      {:ok, :noop}
    end
  end

  defp export_info_internal do
    manifests = ExtensionRegistry.all_manifests()

    exported =
      Enum.map(manifests, fn m ->
        clean_provides = Enum.map(m.provides || [], &ExtensionRegistry.clean_service_name/1)
        clean_deps = Enum.map(m.dependencies || [], &ExtensionRegistry.clean_service_name/1)
        dv = m.dashboard_view
        dv_title = is_map(dv) && (Map.get(dv, :title) || Map.get(dv, "title"))
        dv_icon = is_map(dv) && (Map.get(dv, :icon) || Map.get(dv, "icon"))
        title = m.title || dv_title || to_string(m.name || m.id)
        icon = m.icon || dv_icon || "🧩"

        %{
          "id" => to_string(m.id),
          "name" => to_string(m.name),
          "version" => to_string(m.version),
          "type" => to_string(m.type),
          "category" => m.category || "Extension",
          "title" => title,
          "icon" => icon,
          "dashboard_view" => dv,
          "system" => m.system || false,
          "provides" => clean_provides,
          "dependencies" => clean_deps,
          "input_types" => m.input_types || %{},
          "services" => Enum.map(ExtensionRegistry.manifest_services(m), &ExtensionRegistry.sanitize_for_json/1)
        }
      end)

    attrs = scan_csharp_attributes()

    {:ok,
     %{
       export: %{
         "cluster" => to_string(node()),
         "timestamp" => System.system_time(:second),
         "extensions_count" => length(exported),
         "extensions" => exported,
         "csharp_attributes" => attrs
       }
     }}
  end

  defp scan_csharp_attributes do
    base_prefix =
      cond do
        File.dir?("extensions") -> ""
        File.dir?("../../extensions") -> "../../"
        File.dir?("../extensions") -> "../"
        true -> ""
      end

    patterns = [
      Path.join(base_prefix, "extensions/*/{csharp,unity}/**/*.cs"),
      Path.join(base_prefix, "extensions/*/{csharp,unity}/*.cs"),
      Path.join(base_prefix, "extensions_csharp/*/{csharp,unity}/**/*.cs"),
      Path.join(base_prefix, "extensions_csharp/*/{csharp,unity}/*.cs")
    ]

    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
    |> Enum.map(fn file_path ->
      rel =
        if base_prefix != "" and String.starts_with?(file_path, base_prefix) do
          String.replace_prefix(file_path, base_prefix, "")
        else
          file_path
        end

      ext_name =
        rel
        |> Path.split()
        |> Enum.at(1)

      filename = Path.basename(file_path)

      %{
        "filename" => filename,
        "extension" => ext_name,
        "path" => file_path,
        "content" => File.read!(file_path)
      }
    end)
  end

  # Resolves an extension by id, accepting either the string or the existing atom form.
  defp find_manifest(id_str) when is_binary(id_str) do
    ExtensionRegistry.fetch_manifest(id_str) ||
      ExtensionRegistry.fetch_manifest(Exoforge.Atoms.existing(id_str, id_str)) ||
      failed_manifest(id_str)
  end

  defp find_manifest(_), do: nil

  defp detect_extension_type(type, _raw_binary, elixir_code, files_map) do
    type_str = to_string(type || "") |> String.downcase()

    cond do
      type_str in ["native", "wasm"] -> :native
      type_str == "elixir" -> :elixir
      not is_nil(elixir_code) and elixir_code != "" -> :elixir
      is_map(files_map) and map_size(files_map) > 0 -> :elixir
      true -> nil
    end
  end

  defp handle_upload_native(name_str, raw_binary, manifest_param, files_map, previous) do
    clean_name = sanitize_name(name_str)
    binary = decode_binary(raw_binary)

    case ensure_writable_target_dir(clean_name) do
      {:ok, target_dir} ->
        backup_dir = backup_existing_dir(target_dir)

        install_with_rollback(target_dir, clean_name, previous, backup_dir, fn ->
          is_win = match?({:win32, _}, :os.type())
          binary_name = if is_win, do: clean_name <> ".exe", else: clean_name
          binary_path = Path.join(target_dir, binary_name)
          staged_path = binary_path <> ".new"
          manifest_path = Path.join(target_dir, "manifest.json")

          with :ok <- File.write(staged_path, binary),
               :ok <- safe_install_binary(staged_path, binary_path),
               :ok <- write_extension_files(target_dir, files_map),
               :ok <- write_manifest_file(manifest_path, clean_name, manifest_param, :native) do
            load_and_boot_extension(target_dir, clean_name, :native, previous, backup_dir)
          else
            {:error, reason} ->
              Logger.error("[ExtensionManager] Failed to install native extension #{clean_name}: #{inspect(reason)}")
              rollback_extension(target_dir, clean_name, previous, backup_dir, reason)

            _ ->
              rollback_extension(target_dir, clean_name, previous, backup_dir, :write_failed)
          end
        end)

      {:error, reason} ->
        Logger.error("[ExtensionManager] Could not create target directory for #{clean_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp safe_install_binary(staged_path, binary_path, retries \\ 10) do
    _ = File.chmod(staged_path, 0o755)

    if File.exists?(binary_path) do
      case File.rm(binary_path) do
        :ok ->
          :ok

        {:error, :eacces} when retries > 0 ->
          :timer.sleep(100)
          safe_install_binary(staged_path, binary_path, retries - 1)

        {:error, _} ->
          :ok
      end
    end

    case File.rename(staged_path, binary_path) do
      :ok ->
        _ = File.chmod(binary_path, 0o755)
        :ok

      {:error, :eacces} when retries > 0 ->
        :timer.sleep(100)
        safe_install_binary(staged_path, binary_path, retries - 1)

      {:error, _} ->
        case File.copy(staged_path, binary_path) do
          {:ok, _} ->
            _ = File.rm(staged_path)
            _ = File.chmod(binary_path, 0o755)
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp write_extension_files(_target_dir, nil), do: :ok

  defp write_extension_files(target_dir, files_map) when is_map(files_map) do
    try do
      Enum.each(files_map, fn {rel_path, content} ->
        dest = safe_join(target_dir, to_string(rel_path))
        File.mkdir_p!(Path.dirname(dest))

        data =
          case content do
            %{"encoding" => "base64", "content" => b64} -> Base.decode64!(b64)
            %{encoding: "base64", content: b64} -> Base.decode64!(b64)
            %{"content" => raw} -> to_string(raw)
            %{content: raw} -> to_string(raw)
            str when is_binary(str) -> str
            other -> to_string(other)
          end

        File.write!(dest, data)
      end)

      :ok
    rescue
      _ -> {:error, :write_failed}
    end
  end

  defp write_extension_files(_target_dir, _), do: :ok

  defp handle_upload_elixir(name_str, elixir_code, files_map, manifest_param, previous) do
    clean_name = sanitize_name(name_str)

    case ensure_writable_target_dir(clean_name) do
      {:ok, target_dir} ->
        backup_dir = backup_existing_dir(target_dir)

        install_with_rollback(target_dir, clean_name, previous, backup_dir, fn ->
          lib_dir = Path.join([target_dir, "lib"])
          manifest_path = Path.join(target_dir, "manifest.json")

          with :ok <- File.mkdir_p(lib_dir),
               :ok <- write_elixir_files(target_dir, clean_name, elixir_code, files_map),
               :ok <- write_manifest_file(manifest_path, clean_name, manifest_param, :elixir),
               :ok <- compile_elixir_extension(target_dir, elixir_code) do
            load_and_boot_extension(target_dir, clean_name, :elixir, previous, backup_dir)
          else
            {:error, reason} ->
              rollback_extension(target_dir, clean_name, previous, backup_dir, reason)

            _ ->
              rollback_extension(target_dir, clean_name, previous, backup_dir, :write_failed)
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_elixir_files(target_dir, clean_name, elixir_code, files_map) do
    try do
      if is_map(files_map) do
        Enum.each(files_map, fn {rel_path, content} ->
          dest = safe_join(target_dir, rel_path)
          File.mkdir_p!(Path.dirname(dest))
          File.write!(dest, to_string(content))
        end)
      end

      if is_binary(elixir_code) and String.trim(elixir_code) != "" do
        code_dest = Path.join([target_dir, "lib", "#{clean_name}.ex"])
        File.write!(code_dest, elixir_code)
      end

      :ok
    rescue
      _ -> {:error, :write_failed}
    end
  end

  defp compile_elixir_extension(target_dir, elixir_code) do
    ex_files = Path.wildcard(Path.join([target_dir, "**", "*.ex"]))

    try do
      if ex_files != [] do
        Enum.each(ex_files, fn file ->
          Code.compile_file(file)
        end)
      else
        if is_binary(elixir_code) and elixir_code != "" do
          Code.compile_string(elixir_code)
        end
      end

      :ok
    rescue
      e ->
        {:error, {:compilation_failed, Exception.message(e)}}
    end
  end

  defp load_and_boot_extension(target_dir, clean_name, type, previous \\ nil, backup_dir \\ nil) do
    case ManifestLoader.load_extensions(target_dir) do
      [loaded_manifest | _] ->
        previous = previous || ExtensionRegistry.fetch_manifest(loaded_manifest.id)

        ExtensionRegistry.register(loaded_manifest)

        migration_result = run_resource_migration(loaded_manifest)

        case migration_result do
          {:error, reason} ->
            rollback_extension(
              target_dir,
              clean_name,
              previous,
              backup_dir,
              {:migration_failed, reason},
              loaded_manifest
            )

          _ ->
            case safe_boot_extension(loaded_manifest) do
              :ok ->
                case cleanup_backup(backup_dir) do
                  :ok ->
                    {:ok, %{extension_id: clean_name, type: to_string(type), status: "installed"}}

                  {:error, cleanup_err} ->
                    {:ok, %{extension_id: clean_name, type: to_string(type), status: "installed", warning: inspect(cleanup_err)}}
                end

              {:error, reason} ->
                rollback_extension(
                  target_dir,
                  clean_name,
                  previous,
                  backup_dir,
                  {:boot_failed, reason},
                  loaded_manifest
                )
            end
        end

      _ ->
        rollback_extension(target_dir, clean_name, previous, backup_dir, :manifest_not_loaded)
    end
  end

  @doc false
  def backup_existing_dir(target_dir) do
    if File.dir?(target_dir) do
      backup_dir = "#{target_dir}.bak.#{System.unique_integer([:positive])}"
      File.rm_rf(backup_dir)

      case File.rename(target_dir, backup_dir) do
        :ok ->
          File.mkdir_p!(target_dir)
          backup_dir

        {:error, _} ->
          nil
      end
    else
      nil
    end
  end

  defp cleanup_backup(nil), do: :ok

  # Renaming the backup to `.done.` is the commit point: it is atomic, and recovery restores only
  # `.bak.` directories, so a crash after a successful install never brings the old version back.
  defp cleanup_backup(backup_dir) do
    done_dir = String.replace(backup_dir, ~r/\.bak\.(\d+)$/, ".done.\\1")
    backup_dir = if File.rename(backup_dir, done_dir) == :ok, do: done_dir, else: backup_dir

    case File.rm_rf(backup_dir) do
      {:ok, _} ->
        :ok

      {:error, reason, file} ->
        Logger.warning("[ExtensionManager] Failed to remove backup #{backup_dir} at #{file}: #{inspect(reason)}")
        {:error, {:backup_cleanup_failed, backup_dir, file, reason}}
    end
  end

  defp safe_boot_extension(manifest) do
    if Process.whereis(Exoforge.ExtensionSupervisor) == nil do
      :ok
    else
      try do
        case ExtensionBootstrapper.boot_extension(manifest) do
          {:ok, _pid} -> :ok
          {:ok, _pid, _info} -> :ok
          :ok -> :ok
          {:error, reason} -> {:error, reason}
          other -> {:error, other}
        end
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, reason}
      end
    end
  end

  @doc false
  def recover_leftover_backups do
    dirs =
      [upload_base_dir(), Path.join(System.tmp_dir!(), "exoforge_uploaded_extensions")]
      |> Enum.uniq()
      |> Enum.filter(&File.dir?/1)

    Enum.each(dirs, fn base ->
      # Committed installs whose backup removal was interrupted.
      base |> Path.join("*.done.*") |> Path.wildcard() |> Enum.each(&File.rm_rf/1)

      base
      |> Path.join("*.bak.*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.each(fn backup_dir ->
        target_dir = Regex.replace(~r/\.bak\.\d+$/, backup_dir, "")
        clean_name = Path.basename(target_dir)
        Logger.warning("[ExtensionManager] Recovering leftover backup #{backup_dir} -> #{target_dir}")

        unload_id = Exoforge.Atoms.existing(clean_name, clean_name)
        _ = ExtensionBootstrapper.unload_extension(unload_id)
        ExtensionRegistry.unregister(unload_id)

        File.rm_rf(target_dir)

        case File.rename(backup_dir, target_dir) do
          :ok ->
            case ManifestLoader.load_extensions(target_dir) do
              [manifest | _] ->
                if manifest.type == :elixir do
                  _ = compile_elixir_extension(manifest.physical_path || target_dir, nil)
                end

                ExtensionRegistry.register(manifest)

                # At boot the extensions it depends on may not be up yet; then the files are back and the
                # bootstrapper starts it in dependency order on the next start instead.
                boot_res =
                  if Enum.all?(manifest.dependencies || [], &dependency_up?/1),
                    do: safe_boot_extension(manifest),
                    else: :deferred_until_dependencies
                Logger.info("[ExtensionManager] Recovered #{manifest.id} v#{manifest.version} from backup (boot: #{inspect(boot_res)})")

              _ ->
                Logger.warning("[ExtensionManager] Restored backup #{target_dir} but no manifest could be loaded")
            end

          {:error, reason} ->
            Logger.error("[ExtensionManager] Failed to restore backup #{backup_dir} -> #{target_dir}: #{inspect(reason)}")
        end
      end)
    end)

    :ok
  end

  defp dependency_up?(dep) do
    case if(is_atom(dep), do: dep, else: Exoforge.Atoms.existing(to_string(dep), nil)) do
      nil -> false
      service -> ExtensionRegistry.fetch_service(service) != nil
    end
  end

  @doc false
  def install_with_rollback(target_dir, clean_name, previous, backup_dir, install_fun) do
    try do
      install_fun.()
    rescue
      e ->
        Logger.error("[ExtensionManager] Exception during install of #{clean_name}: #{Exception.message(e)}")
        rollback_extension(target_dir, clean_name, previous, backup_dir, {:exception, Exception.message(e)})
    catch
      kind, reason ->
        Logger.error("[ExtensionManager] #{kind} during install of #{clean_name}: #{inspect(reason)}")
        rollback_extension(target_dir, clean_name, previous, backup_dir, {kind, reason})
    end
  end

  defp rollback_extension(target_dir, clean_name, previous, backup_dir, original_error, loaded_manifest \\ nil) do
    unload_id = if loaded_manifest, do: loaded_manifest.id, else: Exoforge.Atoms.existing(clean_name, clean_name)
    _ = ExtensionBootstrapper.unload_extension(unload_id)
    ExtensionRegistry.unregister(unload_id)

    File.rm_rf(target_dir)

    if backup_dir && File.dir?(backup_dir) do
      _ = File.rename(backup_dir, target_dir)
    end

    rollback_status =
      if previous do
        if previous.type == :elixir do
          _ = compile_elixir_extension(previous.physical_path || target_dir, nil)
        end

        ExtensionRegistry.register(previous)

        case safe_boot_extension(previous) do
          :ok -> :restored
          {:error, rb_err} -> {:failed, rb_err}
        end
      else
        ExtensionRegistry.unregister(clean_name)
        :cleaned
      end

    {:error, %{error: original_error, rollback: rollback_status}}
  end

  defp validate_incoming_manifest_resources(clean_name, manifest_param, files_map) do
    manifest_map = parse_manifest_param(manifest_param, files_map)

    if is_map(manifest_map) do
      ext_id_raw = Map.get(manifest_map, :id) || Map.get(manifest_map, "id") || clean_name
      ext_id = Exoforge.Atoms.existing(to_string(ext_id_raw), ext_id_raw)
      resources = extract_manifest_resources(manifest_map)

      Enum.reduce_while(resources, :ok, fn res, :ok ->
        case extract_table_source(res) do
          nil ->
            {:cont, :ok}

          table ->
            case validate_resource_spec(ext_id, table, res) do
              :ok -> {:cont, :ok}
              {:error, _} = err -> {:halt, err}
            end
        end
      end)
    else
      :ok
    end
  end

  defp parse_manifest_param(manifest_param, _files_map) when is_map(manifest_param), do: manifest_param

  defp parse_manifest_param(manifest_param, _files_map) when is_binary(manifest_param) do
    case Jason.decode(manifest_param) do
      {:ok, m} when is_map(m) -> m
      _ -> nil
    end
  end

  defp parse_manifest_param(_, files_map) when is_map(files_map) do
    entry = Map.get(files_map, "manifest.json") || Map.get(files_map, :"manifest.json")

    raw =
      case entry do
        %{"content" => c} -> c
        %{content: c} -> c
        c when is_binary(c) -> c
        m when is_map(m) -> m
        _ -> nil
      end

    cond do
      is_map(raw) -> raw
      is_binary(raw) -> parse_manifest_param(raw, nil)
      true -> nil
    end
  end

  defp parse_manifest_param(_, _), do: nil

  defp extract_manifest_resources(manifest_map) do
    root_res = Map.get(manifest_map, :resources) || Map.get(manifest_map, "resources") || []
    services = Map.get(manifest_map, :services) || Map.get(manifest_map, "services") || []

    service_res =
      if is_list(services) do
        Enum.flat_map(services, fn svc ->
          if is_map(svc), do: Map.get(svc, :resources) || Map.get(svc, "resources") || [], else: []
        end)
      else
        []
      end

    root_res ++ service_res
  end

  defp extract_table_source(res) when is_map(res) do
    case Map.get(res, :source) || Map.get(res, "source") do
      {:table, t} -> to_string(t)
      [:table, t] -> to_string(t)
      ["table", t] -> to_string(t)
      %{table: t} -> to_string(t)
      %{"table" => t} -> to_string(t)
      nil ->
        name = Map.get(res, :name) || Map.get(res, "name")
        if name, do: to_string(name), else: nil
      _ -> nil
    end
  end

  defp extract_table_source(_), do: nil

  defp validate_resource_spec(ext_id, table, res) do
    pk = String.downcase(to_string(Map.get(res, :primary_key) || Map.get(res, "primary_key") || :id))
    cols = Map.get(res, :columns) || Map.get(res, "columns") || []

    names =
      Enum.map(cols, fn c ->
        to_string(Map.get(c, :name) || Map.get(c, "name") || "")
      end)

    down_names = Enum.map(names, &String.downcase/1)

    cond do
      pk != "id" and pk not in down_names ->
        {:error, {:invalid_resource, %{extension: ext_id, table: table, column: pk, reason: :primary_key_not_found}}}

      Enum.uniq(down_names) != down_names ->
        dup = down_names -- Enum.uniq(down_names)
        col = Enum.find(names, fn n -> String.downcase(n) == List.first(dup) end)
        {:error, {:invalid_resource, %{extension: ext_id, table: table, column: col, reason: :duplicate_column}}}

      true ->
        :ok
    end
  end

  defp declares_resources?(manifest) do
    root_res = Map.get(manifest, :resources, []) || Map.get(manifest, "resources", [])
    services = ExtensionRegistry.manifest_services(manifest)

    service_res =
      Enum.flat_map(services, fn svc ->
        Map.get(svc, :resources, []) || Map.get(svc, "resources", [])
      end)

    root_res != [] or service_res != []
  end

  defp calculate_extension_size(m) do
    if m.physical_path && File.dir?(m.physical_path) do
      Path.wildcard(Path.join([m.physical_path, "**", "*"]))
      |> Enum.reduce(0, fn file, acc ->
        if File.regular?(file) do
          acc + (File.stat(file) |> elem(1) |> Map.get(:size, 0))
        else
          acc
        end
      end)
    else
      0
    end
  end

  defp decode_binary(bin) when is_binary(bin) do
    case Base.decode64(bin) do
      {:ok, decoded} -> decoded
      _ -> bin
    end
  end

  defp decode_binary(_), do: nil

  defp write_manifest_file(manifest_path, name, manifest_param, default_type) do
    content =
      cond do
        is_binary(manifest_param) ->
          manifest_param

        is_map(manifest_param) ->
          manifest_param |> ExtensionRegistry.sanitize_for_json() |> Jason.encode!(pretty: true)

        true ->
          title = Macro.camelize(name)

          %{
            "id" => name,
            "title" => title,
            "category" => "Game",
            "icon" => "🧩",
            "version" => "0.1.0",
            "type" => to_string(default_type),
            "entry_point" => "Elixir." <> title,
            "provides" => [name],
            "dependencies" => [],
            "dashboard_view" => %{
              "id" => name,
              "title" => title,
              "icon" => "🧩"
            }
          }
          |> Jason.encode!(pretty: true)
      end

    File.write(manifest_path, content <> "\n")
  end

  defp upload_base_dir do
    cond do
      dir = System.get_env("UPLOADED_EXTENSIONS_PATH") ->
        dir

      dir = System.get_env("EXOFORGE_DATA_DIR") ->
        Path.join(dir, "uploaded_extensions")

      dir = Application.get_env(:exoforge_std_extension_manager, :upload_dir) ->
        dir

      ext_paths = System.get_env("EXTENSIONS_PATH") ->
        paths =
          cond do
            String.contains?(ext_paths, ",") -> String.split(ext_paths, ",", trim: true)
            String.contains?(ext_paths, ";") -> String.split(ext_paths, ";", trim: true)
            true -> [ext_paths]
          end
          |> Enum.map(&String.trim/1)

        Enum.find(paths, fn p -> String.contains?(p, "upload") end) || List.last(paths) || "priv/data/uploaded_extensions"

      true ->
        "priv/data/uploaded_extensions"
    end
  end

  defp upload_target_dir(clean_name) do
    Path.join(upload_base_dir(), clean_name)
  end

  defp ensure_writable_target_dir(clean_name) do
    primary = upload_target_dir(clean_name)

    case File.mkdir_p(primary) do
      :ok ->
        {:ok, primary}

      {:error, :eacces} ->
        fallback_base = Path.join(System.tmp_dir!(), "exoforge_uploaded_extensions")
        fallback = Path.join(fallback_base, clean_name)

        case File.mkdir_p(fallback) do
          :ok ->
            Logger.warning("[ExtensionManager] Primary upload directory #{primary} returned :eacces; using fallback: #{fallback}")
            {:ok, fallback}

          {:error, err} ->
            {:error, err}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clean_delete_directory(dir_path) do
    norm = Path.expand(dir_path)
    root_extensions = Path.expand("extensions")
    root_plugins = Path.expand("plugins")
    root_extensions_csharp = Path.expand("extensions_csharp")
    root_csharp = Path.expand("plugins_csharp")
    root_uploaded = Path.expand(upload_base_dir())
    root_builtin = Path.expand("builtin_extensions")

    # Never delete files inside builtin_extensions
    if String.starts_with?(norm, root_builtin) do
      Logger.warning("[ExtensionManager] Refusing to delete builtin extension files at #{norm}")
    else
      if (String.starts_with?(norm, root_extensions) and norm != root_extensions) or
           (String.starts_with?(norm, root_plugins) and norm != root_plugins) or
           (String.starts_with?(norm, root_extensions_csharp) and norm != root_extensions_csharp) or
           (String.starts_with?(norm, root_csharp) and norm != root_csharp) or
           (String.starts_with?(norm, root_uploaded) and norm != root_uploaded) do
        File.rm_rf(norm)
      end
    end
  end

  defp safe_join(base, rel_path) do
    base = Path.expand(base)
    dest = Path.expand(Path.join(base, to_string(rel_path)))

    if dest == base or String.starts_with?(dest, base <> "/") do
      dest
    else
      raise ArgumentError, "path traversal in uploaded file: #{inspect(rel_path)}"
    end
  end

  defp sanitize_name(name) do
    name
    |> to_string()
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]/, "")
  end

  defp cluster_os do
    case :os.type() do
      {:unix, :linux} ->
        if is_musl_linux?() do
          "linux-musl"
        else
          "linux"
        end

      {:unix, :darwin} ->
        "osx"

      {:win32, _} ->
        "win"

      {family, name} ->
        "#{family}-#{name}"
    end
  end

  defp is_musl_linux? do
    File.exists?("/etc/alpine-release") or
      Path.wildcard("/lib/ld-musl-*.so*") != [] or
      Path.wildcard("/lib64/ld-musl-*.so*") != [] or
      Path.wildcard("/usr/lib/ld-musl-*.so*") != []
  end

  defp cluster_arch do
    arch_str = to_string(:erlang.system_info(:system_architecture))

    cond do
      String.contains?(arch_str, "aarch64") or String.contains?(arch_str, "arm64") -> "arm64"
      String.contains?(arch_str, "x86_64") or String.contains?(arch_str, "amd64") -> "x64"
      String.contains?(arch_str, "arm") -> "arm"
      true -> "x64"
    end
  end

  defp cluster_target_rid do
    case System.get_env("EXOFORGE_TARGET_RID") do
      val when is_binary(val) and val != "" ->
        String.trim(val)

      _ ->
        "#{cluster_os()}-#{cluster_arch()}"
    end
  end

  defp extension_status(manifest_id) do
    case ExtensionRegistry.get_failure(manifest_id) do
      %{kind: :blocked} ->
        "blocked"

      %{} ->
        "failed"

      nil ->
        case ExtensionRegistry.get_crash_info(manifest_id) do
          {:crashed, _reason} -> "crashed"
          _ -> "running"
        end
    end
  end

  # Why an extension is not running, as JSON-safe data; nil for one that is.
  defp failure_info(manifest_id) do
    case ExtensionRegistry.get_failure(manifest_id) do
      %{} = failure ->
        %{
          "kind" => to_string(failure.kind),
          "stage" => to_string(failure.stage),
          "message" => failure.message,
          "detail" => if(failure.detail, do: to_string(inspect(failure.detail, printable_limit: 2000)), else: nil),
          "at" => failure.at
        }

      nil ->
        crash_failure_info(manifest_id)
    end
  end

  # An extension that started and then died is not in the failure table (it did not fail to load), but the developer
  # needs the same answer for it: what happened, in words, with the process's own last output underneath.
  defp crash_failure_info(manifest_id) do
    case ExtensionRegistry.get_crash_info(manifest_id) do
      {:crashed, reason} ->
        {message, detail} = describe_crash(reason)
        %{"kind" => "crashed", "stage" => "run", "message" => message, "detail" => detail, "at" => nil}

      _ ->
        nil
    end
  end

  @doc false
  def describe_crash({:exit_before_handshake, status, tail}) do
    output = tail |> List.wrap() |> Enum.join("\n")

    message =
      cond do
        output =~ ~r/syntax error|Exec format error|cannot execute binary|not found/ ->
          "The server could not run the file: it was built for another operating system or is not a program. Build for #{cluster_target_rid()} and deploy again."

        true ->
          "The process exited with status #{status} before it finished starting."
      end

    {message, if(output == "", do: nil, else: output)}
  end

  def describe_crash({:startup_failed, %{message: message}}), do: {"Its start-up hook failed: #{message}", nil}
  def describe_crash({:startup_failed, other}), do: {"Its start-up hook failed.", inspect(other, printable_limit: 500)}
  def describe_crash({:binary_not_found, _}), do: {"The program file is missing on the server. Deploy the extension again.", nil}
  def describe_crash(%{kind: kind, message: message}), do: {"#{kind}: #{message}", nil}
  def describe_crash(other), do: {"The extension stopped unexpectedly.", inspect(other, printable_limit: 500)}

  defp failed_manifest(id_str) do
    Enum.find_value(ExtensionRegistry.failed_extensions(), fn {manifest, _failure} ->
      if to_string(manifest.id) == id_str, do: manifest
    end)
  end
end
