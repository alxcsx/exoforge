defmodule Exoforge.Std.PluginManager do
  @moduledoc """
  Standard Plugin Manager for Exoforge.
  Provides the :plugin_manager service contract for runtime inspection,
  hot-loading of WASM plugins, lifecycle restarts, and CLI/SDK synchronization.
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
          size_bytes =
            if m.physical_path && File.dir?(m.physical_path) do
              Path.wildcard(Path.join(m.physical_path, "*.wasm"))
              |> Enum.reduce(0, fn file, acc ->
                acc + (File.stat(file) |> elem(1) |> Map.get(:size, 0))
              end)
            else
              0
            end

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
    manifest_param = Map.get(payload, :manifest) || Map.get(payload, "manifest")

    if is_nil(name_str) or name_str == "" or is_nil(raw_wasm) do
      {:error, :invalid_package}
    else
      clean_name =
        name_str
        |> to_string()
        |> Macro.underscore()
        |> String.replace(~r/[^a-z0-9_]/, "")

      wasm_bytes = decode_wasm_binary(raw_wasm)

      case wasm_bytes do
        <<0, 97, 115, 109, _rest::binary>> ->
          target_dir = Path.join(["plugins_csharp", clean_name])
          wasm_path = Path.join(target_dir, "#{clean_name}.wasm")
          manifest_path = Path.join(target_dir, "manifest.exs")

          case File.mkdir_p(target_dir) do
            :ok ->
              case File.write(wasm_path, wasm_bytes) do
                :ok ->
                  write_manifest_file(manifest_path, clean_name, manifest_param)

                  # Hot-load manifest and boot plugin if supervisor is alive
                  if Process.whereis(Exoforge.PluginSupervisor) != nil do
                    case ManifestLoader.load_plugins(target_dir) do
                      [loaded_manifest | _] ->
                        PluginBootstrapper.boot_plugin(loaded_manifest)
                        {:ok, %{plugin_id: clean_name, status: "installed"}}

                      _ ->
                        {:ok, %{plugin_id: clean_name, status: "saved_pending_restart"}}
                    end
                  else
                    {:ok, %{plugin_id: clean_name, status: "saved_pending_restart"}}
                  end

                {:error, _} ->
                  {:error, :write_failed}
              end

            {:error, _} ->
              {:error, :write_failed}
          end

        _invalid ->
          {:error, :invalid_package}
      end
    end
  end

  @impl true
  defaction remove_plugin(payload), scope: "admin" do
    id_str = Map.get(payload, :id) || Map.get(payload, "id")

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

        _m ->
          PluginBootstrapper.unload_plugin(id_str)
          if atom_id != id_str, do: PluginBootstrapper.unload_plugin(atom_id)
          {:ok, %{status: "removed"}}
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

  defp write_manifest_file(manifest_path, name, manifest_param) do
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
            type: :wasm,
            entry_point: #{Macro.camelize(name)},
            provides: [:#{name}],
            dependencies: []
          }
          """
      end

    File.write(manifest_path, content)
  end

  defp existing_atom(val) when is_atom(val), do: val

  defp existing_atom(val) do
    String.to_existing_atom(to_string(val))
  rescue
    ArgumentError -> val
  end
end
