defmodule Exoforge.Std.PluginManager do
  @moduledoc """
  Standard Plugin Manager for Exoforge.
  Provides the :plugin_manager service contract for runtime inspection,
  hot-loading of Elixir and native C# plugins, lifecycle restarts,
  and CLI/SDK synchronization.
  """
  use Exoforge.Plugin, provides: [:plugin_manager]

  alias Exoforge.PluginRegistry
  alias Exoforge.PluginBootstrapper
  alias Exoforge.Drivers.Loaders.ManifestLoader

  @manifest %{
    dependencies: [],
    category: "Management",
    system: true,
    dashboard_view: %{
      id: :plugin_manager,
      title: "Plugin Manager",
      icon: "📦"
    }
  }

  @doc "Dashboard visualization specification."
  def dashboard_view, do: @manifest.dashboard_view

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction list_plugins, scope: Exoforge.Auth.Roles.studio() do
    manifests = PluginRegistry.all_manifests()

    plugins =
      Enum.map(manifests, fn m ->
        %{
          "id" => to_string(m.id),
          "name" => to_string(m.name),
          "version" => to_string(m.version),
          "type" => to_string(m.type),
          "entry_point" => to_string(m.entry_point),
          "category" => m.category || "Extension",
          "provides" => Enum.map(m.provides || [], &to_string/1),
          "dependencies" => Enum.map(m.dependencies || [], &to_string/1),
          "services" => PluginRegistry.sanitize_for_json(m.services || []),
          "physical_path" => m.physical_path
        }
      end)
      |> Enum.sort_by(& &1["id"])

    {:ok, %{plugins: plugins, count: length(plugins)}}
  end

  @impl true
  defaction get_plugin(payload), scope: Exoforge.Auth.Roles.studio() do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")

    if is_nil(id_str) or id_str == "" do
      {:error, :not_found}
    else
      manifest =
        find_manifest(id_str)

      case manifest do
        nil ->
          {:error, :not_found}

        m ->
          size_bytes = calculate_plugin_size(m)

          plugin_data = %{
            "id" => to_string(m.id),
            "name" => to_string(m.name),
            "version" => to_string(m.version),
            "type" => to_string(m.type),
            "entry_point" => to_string(m.entry_point),
            "provides" => Enum.map(m.provides || [], &to_string/1),
            "dependencies" => Enum.map(m.dependencies || [], &to_string/1),
            "services" => PluginRegistry.sanitize_for_json(m.services || []),
              "dashboard_view" => m.dashboard_view,
            "physical_path" => m.physical_path,
            "size_bytes" => size_bytes
          }

          {:ok, %{plugin: plugin_data}}
      end
    end
  end

  @impl true
  defaction get_system_info, scope: Exoforge.Auth.Roles.studio() do
    mem_total = :erlang.memory(:total)

    info = %{
      "node" => to_string(node()),
      "uptime_seconds" => div(:erlang.element(1, :erlang.statistics(:wall_clock)), 1000),
      "memory_bytes" => mem_total,
      "memory_mb" => Float.round(mem_total / (1024 * 1024), 2),
      "process_count" => :erlang.system_info(:process_count),
      "elixir_version" => System.version(),
      "otp_release" => System.otp_release(),
      "plugins_count" => length(PluginRegistry.all_manifests())
    }

    {:ok, %{system: info}}
  end

  @impl true
  defaction upload_plugin(payload), scope: Exoforge.Auth.Roles.admin() do
    name_str = Map.get(payload, :name) || Map.get(payload, "name")
    raw_binary = Map.get(payload, :binary) || Map.get(payload, "binary")

    elixir_code =
      Map.get(payload, :elixir_code) || Map.get(payload, "elixir_code") ||
        Map.get(payload, :code) || Map.get(payload, "code")

    files_map = Map.get(payload, :files) || Map.get(payload, "files")
    manifest_param = Map.get(payload, :manifest) || Map.get(payload, "manifest")
    type_param = Map.get(payload, :type) || Map.get(payload, "type")

    plugin_type = detect_plugin_type(type_param, raw_binary, elixir_code, files_map)

    cond do
      is_nil(name_str) or name_str == "" ->
        {:error, :invalid_package}

      is_nil(plugin_type) ->
        {:error, :invalid_package}

      true ->
        # Re-deploying a running plugin: stop the old instance first, otherwise its binary is busy
        # (ETXTBSY on Linux) and booting again would start a duplicate runner.
        _ = PluginBootstrapper.unload_plugin(name_str)

        case plugin_type do
          :native -> handle_upload_native(name_str, raw_binary, manifest_param)
          :elixir -> handle_upload_elixir(name_str, elixir_code, files_map, manifest_param)
        end
    end
  end

  @impl true
  defaction remove_plugin(payload), scope: Exoforge.Auth.Roles.admin() do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")
    delete_files = Map.get(payload, :delete_files) || Map.get(payload, "delete_files") || false

    if is_nil(id_str) or id_str == "" do
      {:error, :not_found}
    else
      atom_id = Exoforge.Atoms.existing(id_str, id_str)

      manifest =
        PluginRegistry.fetch_manifest(id_str) ||
          PluginRegistry.fetch_manifest(atom_id)

      case manifest do
        nil ->
          {:error, :not_found}

        m ->
          PluginBootstrapper.unload_plugin(id_str)
          if atom_id != id_str, do: PluginBootstrapper.unload_plugin(atom_id)

          if m.type == :elixir and is_atom(m.entry_point) do
            :code.purge(m.entry_point)
            :code.delete(m.entry_point)
          end

          Exoforge.PluginLogs.clear(m.id)

          if delete_files and m.physical_path && File.dir?(m.physical_path) do
            clean_delete_directory(m.physical_path)
          end

          {:ok, %{status: "removed", id: to_string(m.id), type: to_string(m.type)}}
      end
    end
  end

  @impl true
  defaction restart_system, scope: Exoforge.Auth.Roles.admin() do
    PluginBootstrapper.reload_all()
    count = length(PluginRegistry.all_manifests())
    {:ok, %{status: "restarted", plugins_count: count}}
  end

  @impl true
  defaction logs(payload), scope: Exoforge.Auth.Roles.studio() do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")
    limit = Map.get(payload, :limit) || Map.get(payload, "limit") || 100

    case find_manifest(id_str) do
      nil ->
        {:error, :not_found}

      m ->
        lines = Exoforge.PluginLogs.list(m.id, limit)
        {:ok, %{plugin_id: to_string(m.id), lines: lines, count: length(lines)}}
    end
  end

  @impl true
  defaction reload_plugin(payload), scope: Exoforge.Auth.Roles.admin() do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")

    case find_manifest(id_str) do
      nil ->
        {:error, :not_found}

      m ->
        # Re-boot from the files already staged on disk — no re-upload, no rebuild.
        PluginBootstrapper.unload_plugin(m.id)

        {:ok, %{status: status}} = load_and_boot_plugin(m.physical_path, to_string(m.id), m.type)
        {:ok, %{plugin_id: to_string(m.id), status: status}}
    end
  end

  @impl true
  defaction export_plugin_info, scope: Exoforge.Auth.Roles.studio() do
    manifests = PluginRegistry.all_manifests()

    exported =
      Enum.map(manifests, fn m ->
        clean_provides = Enum.map(m.provides || [], &PluginRegistry.clean_service_name/1)
        clean_deps = Enum.map(m.dependencies || [], &PluginRegistry.clean_service_name/1)

        %{
          "id" => to_string(m.id),
          "name" => to_string(m.name),
          "version" => to_string(m.version),
          "type" => to_string(m.type),
          "provides" => clean_provides,
          "dependencies" => clean_deps,
          "services" => Enum.map(PluginRegistry.manifest_services(m), &PluginRegistry.sanitize_for_json/1),
        }
      end)

    {:ok,
     %{
       export: %{
         "cluster" => to_string(node()),
         "timestamp" => System.system_time(:second),
         "plugins_count" => length(exported),
         "plugins" => exported
       }
     }}
  end

  ## ---- PRIVATE HELPERS ----

  # Resolves a plugin by id, accepting either the string or the existing atom form.
  defp find_manifest(id_str) when is_binary(id_str) do
    PluginRegistry.fetch_manifest(id_str) ||
      PluginRegistry.fetch_manifest(Exoforge.Atoms.existing(id_str, id_str))
  end

  defp find_manifest(_), do: nil

  # A binary is native, source is Elixir. There was a third kind; it is a runner away, and adding one
  # back means a clause here and a handler beside `handle_upload_native/3`.
  defp detect_plugin_type(type, _raw_binary, elixir_code, files_map) do
    type_str = to_string(type || "") |> String.downcase()

    cond do
      type_str in ["native", "wasm"] -> :native
      type_str == "elixir" -> :elixir
      not is_nil(elixir_code) and elixir_code != "" -> :elixir
      is_map(files_map) and map_size(files_map) > 0 -> :elixir
      true -> nil
    end
  end

  defp handle_upload_native(name_str, raw_binary, manifest_param) do
    if is_nil(raw_binary) or raw_binary == "" do
      {:error, :invalid_package}
    else
      clean_name = sanitize_name(name_str)
      binary = decode_binary(raw_binary)

      target_dir = upload_target_dir(clean_name)
      binary_path = Path.join(target_dir, clean_name)
      staged_path = binary_path <> ".new"
      manifest_path = Path.join(target_dir, "manifest.json")

      # Stage then atomically rename: rename(2) replaces the inode, so an old binary that is still
      # executing can be replaced even if the process has not fully exited yet.
      with :ok <- File.mkdir_p(target_dir),
           :ok <- File.write(staged_path, binary),
           :ok <- File.chmod(staged_path, 0o755),
           :ok <- File.rename(staged_path, binary_path),
           :ok <- write_manifest_file(manifest_path, clean_name, manifest_param, :native) do
        load_and_boot_plugin(target_dir, clean_name, :native)
      else
        _ -> {:error, :write_failed}
      end
    end
  end

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
           :ok <- compile_elixir_plugin(target_dir, elixir_code) do
        load_and_boot_plugin(target_dir, clean_name, :elixir)
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

  defp compile_elixir_plugin(target_dir, elixir_code) do
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

  defp load_and_boot_plugin(target_dir, clean_name, type) do
    case ManifestLoader.load_plugins(target_dir) do
      [loaded_manifest | _] ->
        PluginRegistry.register(loaded_manifest)

        if Process.whereis(Exoforge.PluginSupervisor) != nil do
          PluginBootstrapper.boot_plugin(loaded_manifest)
          {:ok, %{plugin_id: clean_name, type: to_string(type), status: "installed"}}
        else
          {:ok, %{plugin_id: clean_name, type: to_string(type), status: "installed"}}
        end

      _ ->
        {:ok, %{plugin_id: clean_name, type: to_string(type), status: "saved_pending_restart"}}
    end
  end

  defp calculate_plugin_size(m) do
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

  # A payload is either raw bytes or base64 of them. Trying the decode is the whole test: a compiled
  # binary starts with bytes outside the base64 alphabet, so it always fails and comes back untouched.
  # There used to be a WASM magic-header check in front of this, which was redundant for WASM and
  # wrong for anything else.
  defp decode_binary(bin) when is_binary(bin) do
    case Base.decode64(bin) do
      {:ok, decoded} -> decoded
      _ -> bin
    end
  end

  defp decode_binary(_), do: nil

  # JSON, like every other manifest. A caller that sends one is taken at its word; a caller that
  # sends a map gets it encoded; and a caller that sends nothing gets a manifest for an Elixir plugin
  # named after the upload.
  #
  # The format used to be detected by looking for `%{` in the payload, which is a thing a format
  # should not need. Now it is JSON or it is a map, and both end up as JSON.
  defp write_manifest_file(manifest_path, name, manifest_param, default_type) do
    content =
      cond do
        is_binary(manifest_param) ->
          manifest_param

        is_map(manifest_param) ->
          manifest_param |> Exoforge.PluginRegistry.sanitize_for_json() |> Jason.encode!(pretty: true)

        true ->
          %{
            "id" => name,
            "version" => "0.1.0",
            "type" => to_string(default_type),
            # The `Elixir.` prefix is not decoration: as source, `TestPlugin` is the alias for
            # `Elixir.TestPlugin`, and without it the loader builds a different atom than the module
            # it is meant to boot.
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
        :exoforge_std_plugin_manager,
        :upload_dir,
        "priv/data/uploaded_plugins"
      )

    Path.join(base, clean_name)
  end

  defp clean_delete_directory(dir_path) do
    norm = Path.expand(dir_path)
    root_plugins = Path.expand("plugins")
    root_csharp = Path.expand("plugins_csharp")
    root_uploaded = Path.expand(Application.get_env(:exoforge_std_plugin_manager, :upload_dir, "priv/data/uploaded_plugins"))

    if (String.starts_with?(norm, root_plugins) and norm != root_plugins) or
       (String.starts_with?(norm, root_csharp) and norm != root_csharp) or
       (String.starts_with?(norm, root_uploaded) and norm != root_uploaded) do
      File.rm_rf(norm)
    end
  end

  # Joins an uploaded relative path under `base`, refusing anything that escapes it.
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

end
