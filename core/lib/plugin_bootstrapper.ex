defmodule Exoforge.PluginBootstrapper do
  require Logger
  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.Drivers.Runtime.ElixirPluginRunner

  def boot do
    t0 = System.monotonic_time(:millisecond)
    loader_config = Application.get_env(:exoforge, :module_loader, [])
    driver = Keyword.get(loader_config, :driver, Exoforge.Drivers.Loaders.ManifestLoader)
    path = Keyword.get(loader_config, :scan_path, "plugins")

    PluginRegistry.initialize_ets()

    case run(driver, path) do
      [] ->
        Logger.warning("[Exoforge] no plugins found at #{path}")

      loaded ->
        total_ms = System.monotonic_time(:millisecond) - t0
        print_startup_banner(loaded, total_ms)
    end

    :ok
  end

  @doc "Re-runs discovery, topological sort, and boots all plugins."
  def reload_all do
    boot()
  end

  @doc "Boots and registers an individual manifest directly."
  def boot_plugin(%Manifest{} = manifest) do
    initialize_and_register(manifest)
  end

  @doc "Unloads a plugin from registry and runners."
  def unload_plugin(plugin_id) do
    manifest =
      PluginRegistry.fetch_manifest(plugin_id) ||
        (is_binary(plugin_id) && PluginRegistry.fetch_manifest(existing_atom_safe(plugin_id)))

    if manifest do
      terminate_plugin_processes(manifest)
    end

    PluginRegistry.unregister(plugin_id)
  end

  def run(driver, path) do
    manifests = driver.load_plugins(path) |> sort!()
    total = length(manifests)
    Logger.info("[Boot] Discovered #{total} plugin manifests. Initializing dependency tree...")

    Enum.with_index(manifests, 1)
    |> Enum.each(fn {manifest, idx} ->
      t_start = System.monotonic_time(:millisecond)
      initialize_and_register(manifest)
      t_elapsed = System.monotonic_time(:millisecond) - t_start
      type_label = if manifest.type == :wasm, do: "WASM", else: "Elixir"
      provides_str =
        (manifest.provides || [])
        |> Enum.map(fn p ->
          case p do
            mod when is_atom(mod) ->
              str = to_string(mod)
              if String.starts_with?(str, "Elixir.Exoforge.Std.Services.") do
                ":#{Macro.underscore(Module.split(mod) |> List.last())}"
              else
                ":#{mod}"
              end
            other -> ":#{other}"
          end
        end)
        |> Enum.join(", ")

      Logger.info("[Boot] [#{idx}/#{total}] #{manifest.id} (#{type_label}) -> provides [#{provides_str}] in #{t_elapsed}ms")
    end)

    manifests
  end

  defp initialize_and_register(%Manifest{} = manifest) do
    runner = runner_for(manifest.type)

    manifest =
      if function_exported?(runner, :prepare_manifest, 1) do
        runner.prepare_manifest(manifest)
      else
        manifest
      end

    PluginRegistry.register(manifest)
    runner.load(manifest)
  end

  defp runner_for(:elixir), do: ElixirPluginRunner
  defp runner_for(:wasm), do: Exoforge.Drivers.Runtime.WasmPluginRunner
  defp runner_for(mod) when is_atom(mod), do: mod

  @spec sort!([%Manifest{}]) :: [%Manifest{}]
  def sort!(manifests) do
    graph = :digraph.new()

    try do
      # Create Nodes
      Enum.each(manifests, &:digraph.add_vertex(graph, &1.id, &1))

      service_providers =
        manifests
        |> Enum.flat_map(fn m ->
          Enum.flat_map(m.provides, fn p ->
            Enum.map(service_keys(p), &{&1, m.id})
          end)
        end)
        |> Enum.group_by(fn {service, _id} -> service end, fn {_service, id} -> id end)

      # Create Links
      for m <- manifests, req <- m.dependencies do
        case find_providers(service_providers, req) do
          {:ok, providers} -> Enum.each(providers, &:digraph.add_edge(graph, &1, m.id))
          :error -> raise "[Missing Dependency]: Plugin `#{m.id}` requires service `#{req}`, which is not provided."
        end
      end

      # Sort
      case :digraph_utils.topsort(graph) do
        false ->
          cycles = :digraph_utils.cyclic_strong_components(graph)
          raise "[Failed To Register Dependencies]: Circular dependency detected: #{inspect(cycles)}"

        sorted_ids ->
          Enum.map(sorted_ids, fn id -> elem(:digraph.vertex(graph, id), 1) end)
      end
    after
      :digraph.delete(graph)
    end
  end

  defp service_keys(service), do: PluginRegistry.service_keys(service)

  defp find_providers(service_providers, req) do
    Enum.find_value(service_keys(req), :error, fn key ->
      case Map.fetch(service_providers, key) do
        {:ok, providers} -> {:ok, providers}
        :error -> nil
      end
    end)
  end

  defp terminate_plugin_processes(%Manifest{type: :elixir, entry_point: plugin_mod}) when is_atom(plugin_mod) do
    plugin_sup_name = Module.concat(plugin_mod, Supervisor)
    stop_child_supervisor(plugin_sup_name)
  end

  defp terminate_plugin_processes(%Manifest{type: :wasm} = manifest) do
    mod_name =
      if is_atom(manifest.entry_point) and manifest.entry_point != nil do
        manifest.entry_point
      else
        manifest.id
        |> to_string()
        |> Macro.camelize()
        |> then(&Module.concat([Exoforge, Plugins, &1]))
      end

    sup_name = Module.concat([Exoforge, Plugins, mod_name, Supervisor])
    stop_child_supervisor(sup_name)
  end

  defp terminate_plugin_processes(_), do: :ok

  defp stop_child_supervisor(sup_name) do
    case Process.whereis(sup_name) do
      pid when is_pid(pid) ->
        if Process.whereis(Exoforge.PluginSupervisor) != nil do
          DynamicSupervisor.terminate_child(Exoforge.PluginSupervisor, pid)
        else
          Process.exit(pid, :shutdown)
        end

      _ ->
        :ok
    end
  end

  defp existing_atom_safe(val) do
    String.to_existing_atom(to_string(val))
  rescue
    ArgumentError -> nil
  end

  defp print_startup_banner(manifests, total_ms) do
    env = current_env()

    if env != :test do
      dash_port = Exoforge.Endpoints.dashboard_port()
      http_port = Exoforge.Endpoints.http_port()
      ws_port = Exoforge.Endpoints.ws_port()

      services =
        manifests
        |> Enum.flat_map(fn m -> m.provides || [] end)
        |> Enum.map(fn p ->
          case p do
            mod when is_atom(mod) ->
              str = to_string(mod)
              if String.starts_with?(str, "Elixir.Exoforge.Std.Services.") do
                ":#{Macro.underscore(Module.split(mod) |> List.last())}"
              else
                ":#{mod}"
              end
            other -> ":#{other}"
          end
        end)
        |> Enum.uniq()
        |> Enum.join(", ")

      banner = """

==============================================================================
  🚀 EXOFORGE CLUSTER RUNTIME (v1.0.0 [#{env}])
==============================================================================
  • Producer Studio:   http://localhost:#{dash_port}
  • REST API Gateway:  http://localhost:#{http_port} (Docs: /api/docs)
  • WebSocket Gateway: ws://localhost:#{ws_port}/ws (Game Client SDK)
------------------------------------------------------------------------------
  • Active Plugins (#{length(manifests)}): #{Enum.map_join(manifests, ", ", & &1.id)}
  • Services Exposed:  #{services}
  • Cluster Node:      #{node()}
  • Status:            ONLINE and responsive (ready in #{total_ms}ms)
==============================================================================
"""

      IO.puts(banner)
    end

    Logger.info("[Exoforge] All #{length(manifests)} plugins loaded. System online in #{total_ms}ms")
  end

  defp current_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      Application.get_env(:exoforge, :env, :prod)
    end
  end
end
