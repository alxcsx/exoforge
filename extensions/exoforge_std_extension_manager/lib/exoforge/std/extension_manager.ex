defmodule Exoforge.Std.ExtensionManager do
  @moduledoc """
  Standard Extension Manager for Exoforge.
  Provides the :extension_manager service contract for runtime inspection,
  hot-loading of Elixir and native C# extensions, lifecycle restarts,
  and CLI/SDK synchronization.
  """
  use Exoforge.Extension, provides: [:extension_manager]

  alias Exoforge.ExtensionRegistry
  alias Exoforge.ExtensionBootstrapper
  alias Exoforge.Drivers.Loaders.ManifestLoader

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
    manifests = ExtensionRegistry.all_manifests()

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
          "entry_point" => to_string(m.entry_point),
          "category" => m.category || "Extension",
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
            "category" => m.category || "Extension",
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
    upload_extension_internal(payload)
  end

  @impl true
  defaction remove_extension(payload), scope: Exoforge.Auth.Roles.admin() do
    remove_extension_internal(payload)
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
    reload_extension_internal(payload)
  end

  @impl true
  defaction export_extension_info, scope: Exoforge.Auth.Roles.studio() do
    export_info_internal()
  end

  @impl true
  defaction csharp_attributes do
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

      true ->
        # Re-deploying a running extension: stop the old instance first, otherwise its binary is busy
        # (ETXTBSY on Linux) and booting again would start a duplicate runner.
        _ = ExtensionBootstrapper.unload_extension(name_str)

        case ext_type do
          :native -> handle_upload_native(name_str, raw_binary, manifest_param, files_map)
          :elixir -> handle_upload_elixir(name_str, elixir_code, files_map, manifest_param)
        end
    end
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

        {:ok, %{status: status}} = load_and_boot_extension(m.physical_path, to_string(m.id), m.type)
        {:ok, %{extension_id: to_string(m.id), status: status}}
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
    patterns = [
      "extensions/*/{csharp,unity}/**/*.cs",
      "extensions/*/{csharp,unity}/*.cs",
      "extensions_csharp/*/{csharp,unity}/**/*.cs",
      "extensions_csharp/*/{csharp,unity}/*.cs"
    ]

    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
    |> Enum.map(fn file_path ->
      ext_name =
        file_path
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
      ExtensionRegistry.fetch_manifest(Exoforge.Atoms.existing(id_str, id_str))
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

  defp handle_upload_native(name_str, raw_binary, manifest_param, files_map) do
    if is_nil(raw_binary) or raw_binary == "" do
      {:error, :invalid_package}
    else
      clean_name = sanitize_name(name_str)
      binary = decode_binary(raw_binary)

      target_dir = upload_target_dir(clean_name)
      binary_path = Path.join(target_dir, clean_name)
      staged_path = binary_path <> ".new"
      manifest_path = Path.join(target_dir, "manifest.json")

      with :ok <- File.mkdir_p(target_dir),
           :ok <- File.write(staged_path, binary),
           :ok <- File.chmod(staged_path, 0o755),
           :ok <- File.rename(staged_path, binary_path),
           :ok <- write_extension_files(target_dir, files_map),
           :ok <- write_manifest_file(manifest_path, clean_name, manifest_param, :native) do
        load_and_boot_extension(target_dir, clean_name, :native)
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :write_failed}
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

  defp handle_upload_elixir(name_str, elixir_code, files_map, manifest_param) do
    has_code = (is_binary(elixir_code) and String.trim(elixir_code) != "") or (is_map(files_map) and map_size(files_map) > 0)

    if not has_code do
      {:error, :invalid_package}
    else
      clean_name = sanitize_name(name_str)
      target_dir = upload_target_dir(clean_name)
      lib_dir = Path.join([target_dir, "lib"])
      manifest_path = Path.join(target_dir, "manifest.json")

      with :ok <- File.mkdir_p(lib_dir),
           :ok <- write_elixir_files(target_dir, clean_name, elixir_code, files_map),
           :ok <- write_manifest_file(manifest_path, clean_name, manifest_param, :elixir),
           :ok <- compile_elixir_extension(target_dir, elixir_code) do
        load_and_boot_extension(target_dir, clean_name, :elixir)
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :write_failed}
      end
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

  defp load_and_boot_extension(target_dir, clean_name, type) do
    case ManifestLoader.load_extensions(target_dir) do
      [loaded_manifest | _] ->
        ExtensionRegistry.register(loaded_manifest)

        if Process.whereis(Exoforge.ExtensionSupervisor) != nil do
          ExtensionBootstrapper.boot_extension(loaded_manifest)
          {:ok, %{extension_id: clean_name, type: to_string(type), status: "installed"}}
        else
          {:ok, %{extension_id: clean_name, type: to_string(type), status: "installed"}}
        end

      _ ->
        {:ok, %{extension_id: clean_name, type: to_string(type), status: "saved_pending_restart"}}
    end
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
          %{
            "id" => name,
            "version" => "0.1.0",
            "type" => to_string(default_type),
            "entry_point" => "Elixir." <> Macro.camelize(name),
            "provides" => [name],
            "dependencies" => []
          }
          |> Jason.encode!(pretty: true)
      end

    File.write(manifest_path, content <> "\n")
  end

  defp upload_target_dir(clean_name) do
    base =
      Application.get_env(
        :exoforge_std_extension_manager,
        :upload_dir,
        "priv/data/uploaded_extensions"
      )

    Path.join(base, clean_name)
  end

  defp clean_delete_directory(dir_path) do
    norm = Path.expand(dir_path)
    root_extensions = Path.expand("extensions")
    root_plugins = Path.expand("plugins")
    root_extensions_csharp = Path.expand("extensions_csharp")
    root_csharp = Path.expand("plugins_csharp")
    root_uploaded = Path.expand(Application.get_env(:exoforge_std_extension_manager, :upload_dir, "priv/data/uploaded_extensions"))

    if (String.starts_with?(norm, root_extensions) and norm != root_extensions) or
         (String.starts_with?(norm, root_plugins) and norm != root_plugins) or
         (String.starts_with?(norm, root_extensions_csharp) and norm != root_extensions_csharp) or
         (String.starts_with?(norm, root_csharp) and norm != root_csharp) or
         (String.starts_with?(norm, root_uploaded) and norm != root_uploaded) do
      File.rm_rf(norm)
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
      {:unix, :linux} -> "linux"
      {:unix, :darwin} -> "osx"
      {:win32, _} -> "win"
      {family, name} -> "#{family}-#{name}"
    end
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
    "#{cluster_os()}-#{cluster_arch()}"
  end
end
