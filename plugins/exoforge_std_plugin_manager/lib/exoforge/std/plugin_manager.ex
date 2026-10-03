defmodule Exoforge.Std.PluginManager do
  @moduledoc """
  Standard Plugin Manager for Exoforge.
  Provides the :plugin_manager service contract for runtime inspection,
  hot-loading of both Elixir and WebAssembly (WASM) plugins, lifecycle restarts,
  and CLI/SDK synchronization.
  """
  use Exoforge.Plugin, provides: [:plugin_manager]

  alias Exoforge.PluginRegistry
  alias Exoforge.PluginBootstrapper
  alias Exoforge.Drivers.Loaders.ManifestLoader

  @manifest %{
    dependencies: [],
    category: "Management",
    dashboard_view: %{
      id: :plugin_manager,
      title: "Plugin Manager",
      icon: "📦"
    }
  }

  @wasm_magic <<0, 97, 115, 109>>

  @doc "Dashboard visualization specification."
  def dashboard_view, do: @manifest.dashboard_view

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction list_plugins, scope: "studio" do
    manifests = PluginRegistry.all_manifests()

    plugins =
      Enum.map(manifests, fn m ->
        %{
          "id" => to_string(m.id),
          "name" => to_string(m.name),
          "version" => to_string(m.version),
          "type" => to_string(m.type),
          "entry_point" => to_string(m.entry_point),
          "provides" => Enum.map(m.provides || [], &to_string/1),
          "dependencies" => Enum.map(m.dependencies || [], &to_string/1),
          "services" => m.services || [],
          "entities" => m.entities || [],
          "physical_path" => m.physical_path
        }
      end)
      |> Enum.sort_by(& &1["id"])

    {:ok, %{plugins: plugins, count: length(plugins)}}
  end

  @impl true
  defaction get_plugin(payload), scope: "studio" do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")

    if is_nil(id_str) or id_str == "" do
      {:error, :not_found}
    else
      manifest =
        PluginRegistry.fetch_manifest(id_str) ||
          PluginRegistry.fetch_manifest(existing_atom(id_str))

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
            "services" => m.services || [],
            "entities" => m.entities || [],
            "dashboard_view" => m.dashboard_view,
            "physical_path" => m.physical_path,
            "size_bytes" => size_bytes,
            "wasm_size_bytes" => size_bytes
          }

          {:ok, %{plugin: plugin_data}}
      end
    end
  end

  @impl true
  defaction get_system_info, scope: "studio" do
    active_ents =
      if Code.ensure_loaded?(Exoforge.Entities) and
           function_exported?(Exoforge.Entities, :list_active, 0) do
        try do
          length(Exoforge.Entities.list_active())
        rescue
          _ -> 0
        end
      else
        0
      end

    mem_total = :erlang.memory(:total)

    info = %{
      "node" => to_string(node()),
      "uptime_seconds" => div(:erlang.element(1, :erlang.statistics(:wall_clock)), 1000),
      "memory_bytes" => mem_total,
      "memory_mb" => Float.round(mem_total / (1024 * 1024), 2),
      "process_count" => :erlang.system_info(:process_count),
      "elixir_version" => System.version(),
      "otp_release" => System.otp_release(),
      "plugins_count" => length(PluginRegistry.all_manifests()),
      "active_entities_count" => active_ents
    }

    {:ok, %{system: info}}
  end

  @impl true
  defaction upload_plugin(payload), scope: "admin" do
    name_str = Map.get(payload, :name) || Map.get(payload, "name")
    raw_wasm = Map.get(payload, :wasm_binary) || Map.get(payload, "wasm_binary")

    elixir_code =
      Map.get(payload, :elixir_code) || Map.get(payload, "elixir_code") ||
        Map.get(payload, :code) || Map.get(payload, "code")

    files_map = Map.get(payload, :files) || Map.get(payload, "files")
    manifest_param = Map.get(payload, :manifest) || Map.get(payload, "manifest")
    type_param = Map.get(payload, :type) || Map.get(payload, "type")

    plugin_type = detect_plugin_type(type_param, raw_wasm, elixir_code, files_map)

    cond do
      is_nil(name_str) or name_str == "" ->
        {:error, :invalid_package}

      is_nil(plugin_type) ->
        {:error, :invalid_package}

      plugin_type == :wasm ->
        handle_upload_wasm(name_str, raw_wasm, manifest_param)

      plugin_type == :elixir ->
        handle_upload_elixir(name_str, elixir_code, files_map, manifest_param)
    end
  end

  @impl true
  defaction remove_plugin(payload), scope: "admin" do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")
    delete_files = Map.get(payload, :delete_files) || Map.get(payload, "delete_files") || false

    if is_nil(id_str) or id_str == "" do
      {:error, :not_found}
    else
      atom_id = existing_atom(id_str)

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

          if delete_files and m.physical_path && File.dir?(m.physical_path) do
            clean_delete_directory(m.physical_path)
          end

          {:ok, %{status: "removed", id: to_string(m.id), type: to_string(m.type)}}
      end
    end
  end

  @impl true
  defaction restart_system, scope: "admin" do
    PluginBootstrapper.reload_all()
    count = length(PluginRegistry.all_manifests())
    {:ok, %{status: "restarted", plugins_count: count}}
  end

  @impl true
  defaction export_plugin_info, scope: "studio" do
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
          "services" => m.services || [],
          "entities" => m.entities || []
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

  defp detect_plugin_type(type, raw_wasm, elixir_code, files_map) do
    type_str = to_string(type || "") |> String.downcase()

    cond do
      type_str == "wasm" -> :wasm
      type_str == "elixir" -> :elixir
      not is_nil(raw_wasm) and raw_wasm != "" -> :wasm
      not is_nil(elixir_code) and elixir_code != "" -> :elixir
      is_map(files_map) and map_size(files_map) > 0 -> :elixir
      true -> nil
    end
  end

  defp handle_upload_wasm(name_str, raw_wasm, manifest_param) do
    if is_nil(raw_wasm) or raw_wasm == "" do
      {:error, :invalid_package}
    else
      clean_name = sanitize_name(name_str)
      wasm_bytes = decode_wasm_binary(raw_wasm)

      case wasm_bytes do
        <<0, 97, 115, 109, _rest::binary>> ->
          target_dir = Path.join(["plugins_csharp", clean_name])
          wasm_path = Path.join(target_dir, "#{clean_name}.wasm")
          manifest_path = Path.join(target_dir, "manifest.exs")

          with :ok <- File.mkdir_p(target_dir),
               :ok <- File.write(wasm_path, wasm_bytes),
               :ok <- write_manifest_file(manifest_path, clean_name, manifest_param, :wasm) do
            load_and_boot_plugin(target_dir, clean_name, :wasm)
          else
            _ -> {:error, :write_failed}
          end

        _invalid ->
          {:error, :invalid_package}
      end
    end
  end

  defp handle_upload_elixir(name_str, elixir_code, files_map, manifest_param) do
    has_code = (is_binary(elixir_code) and String.trim(elixir_code) != "") or (is_map(files_map) and map_size(files_map) > 0)

    if not has_code do
      {:error, :invalid_package}
    else
      clean_name = sanitize_name(name_str)
      target_dir = Path.join(["plugins", clean_name])
      lib_dir = Path.join([target_dir, "lib"])
      manifest_path = Path.join(target_dir, "manifest.exs")

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
          dest = Path.join(target_dir, to_string(rel_path))
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
      pattern =
        case m.type do
          :wasm -> Path.join(m.physical_path, "*.wasm")
          _ -> Path.join([m.physical_path, "**", "*"])
        end

      Path.wildcard(pattern)
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

  defp decode_wasm_binary(bin) when is_binary(bin) do
    if String.starts_with?(bin, @wasm_magic) do
      bin
    else
      case Base.decode64(bin) do
        {:ok, decoded} -> decoded
        _ -> bin
      end
    end
  end

  defp decode_wasm_binary(_), do: nil

  defp write_manifest_file(manifest_path, name, manifest_param, default_type) do
    content =
      cond do
        is_binary(manifest_param) and String.contains?(manifest_param, "%{") ->
          manifest_param

        is_map(manifest_param) ->
          inspect(manifest_param, pretty: true)

        true ->
          """
          %{
            id: :#{name},
            name: "#{Macro.camelize(name)}",
            version: "0.1.0",
            type: :#{default_type},
            entry_point: #{Macro.camelize(name)},
            provides: [:#{name}],
            dependencies: []
          }
          """
      end

    File.write(manifest_path, content)
  end

  defp clean_delete_directory(dir_path) do
    norm = Path.expand(dir_path)
    root_plugins = Path.expand("plugins")
    root_csharp = Path.expand("plugins_csharp")

    if (String.starts_with?(norm, root_plugins) and norm != root_plugins) or
       (String.starts_with?(norm, root_csharp) and norm != root_csharp) do
      File.rm_rf(norm)
    end
  end

  defp sanitize_name(name) do
    name
    |> to_string()
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]/, "")
  end

  defp existing_atom(val) when is_atom(val), do: val

  defp existing_atom(val) do
    String.to_existing_atom(to_string(val))
  rescue
    ArgumentError -> val
  end
end
