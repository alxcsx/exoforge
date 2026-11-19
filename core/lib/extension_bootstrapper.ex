defmodule Exoforge.ExtensionBootstrapper do
  require Logger
  alias Exoforge.Domain.Manifest
  alias Exoforge.ExtensionRegistry
  alias Exoforge.Drivers.Runtime.ElixirExtensionRunner

  def boot do
    t0 = System.monotonic_time(:millisecond)
    loader_config = Application.get_env(:exoforge, :module_loader, [])
    driver = Keyword.get(loader_config, :driver, Exoforge.Drivers.Loaders.ManifestLoader)
    path =
      case Keyword.get(loader_config, :scan_path) do
        nil ->
          cond do
            File.dir?("builtin_extensions") and File.dir?("uploaded_extensions") ->
              ["builtin_extensions", "uploaded_extensions"]

            File.dir?("extensions") ->
              "extensions"

            true ->
              "_build/dev/lib"
          end

        custom ->
          custom
      end

    ExtensionRegistry.initialize_ets()

    case run(driver, path) do
      [] ->
        if ExtensionRegistry.failed_extensions() == [] do
          formatted = if is_list(path), do: Enum.join(path, ", "), else: to_string(path)
          Logger.warning("[Exoforge] no extensions found at #{formatted}")
        end

      loaded ->
        total_ms = System.monotonic_time(:millisecond) - t0
        print_startup_banner(loaded, total_ms)
    end

    :ok
  end

  defmodule StartError do
    @moduledoc "Raised when an extension's runner reports that it could not start."
    defexception [:id, :reason]

    @impl true
    def message(%{id: id, reason: reason}), do: "extension #{id} failed to start: #{inspect(reason)}"
  end

  @doc "Re-runs discovery, topological sort, and boots all extensions."
  def reload_all do
    boot()
  end

  @doc "Boots and registers an individual manifest directly."
  def boot_extension(%Manifest{} = manifest) do
    initialize_and_register(manifest)
  end

  @doc "Unloads an extension from registry and runners."
  def unload_extension(extension_id) do
    manifest =
      ExtensionRegistry.fetch_manifest(extension_id) ||
        (is_binary(extension_id) && ExtensionRegistry.fetch_manifest(Exoforge.Atoms.existing(extension_id)))

    if manifest do
      terminate_extension_processes(manifest)
      if manifest.type == :native do
        Process.sleep(100)
      end
    end

    ExtensionRegistry.unregister(extension_id)
  end

  @doc """
  Discovers, orders and boots every extension, one at a time, each in isolation.

  An extension that fails to start (or whose dependencies cannot be satisfied) is recorded as failed
  in `ExtensionRegistry` and boot carries on with the rest. An extension that depends on a failed one is
  not started either: it is recorded as blocked. Returns the manifests that booted.
  """
  def run(driver, path) do
    {manifests, problems} = driver.load_extensions(path) |> sort_isolated()
    total = length(manifests) + length(problems)
    Logger.info("[Boot] Discovered #{total} extension manifests. Initializing dependency tree...")

    providers = provider_index(manifests ++ Enum.map(problems, &elem(&1, 0)))

    failed =
      Enum.reduce(problems, MapSet.new(), fn {manifest, failure}, acc ->
        fail_extension(manifest, Map.put(failure, :kind, :boot_failed))
        MapSet.put(acc, manifest.id)
      end)

    {loaded, _failed} =
      manifests
      |> Enum.with_index(length(problems) + 1)
      |> Enum.reduce({[], failed}, fn {manifest, idx}, {loaded, failed} ->
        case blocked_by(manifest, providers, failed) do
          [] ->
            t_start = System.monotonic_time(:millisecond)

            case isolated_load(manifest) do
              :ok ->
                t_elapsed = System.monotonic_time(:millisecond) - t_start
                log_loaded(manifest, idx, total, t_elapsed)
                {[manifest | loaded], failed}

              {:error, failure} ->
                fail_extension(manifest, Map.put(failure, :kind, :boot_failed))
                {loaded, MapSet.put(failed, manifest.id)}
            end

          blockers ->
            names = blockers |> Enum.map(&to_string/1) |> Enum.join(", ")

            fail_extension(manifest, %{
              kind: :blocked,
              stage: :dependencies,
              message: "dependency #{names} failed",
              detail: %{dependencies: Enum.map(blockers, &to_string/1)}
            })

            {loaded, MapSet.put(failed, manifest.id)}
        end
      end)

    Enum.reverse(loaded)
  end

  defp log_loaded(manifest, idx, total, t_elapsed) do
    type_label = if manifest.type == :native, do: "Native", else: "Elixir"

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

          other ->
            ":#{other}"
        end
      end)
      |> Enum.join(", ")

    Logger.info(
      "[Boot] [#{idx}/#{total}] #{manifest.id} (#{type_label}) -> provides [#{provides_str}] in #{t_elapsed}ms"
    )
  end

  # Loads one extension and turns every way that can go wrong into a value. Nothing a single
  # extension does may stop the rest of the cluster from booting.
  defp isolated_load(manifest) do
    initialize_and_register(manifest)
    :ok
  rescue
    e in StartError -> {:error, %{stage: :start, message: Exception.message(e), detail: inspect(e.reason)}}
    e -> {:error, %{stage: :load, message: Exception.message(e), detail: Exception.format(:error, e, __STACKTRACE__)}}
  catch
    :exit, reason -> {:error, %{stage: :load, message: "exited: #{inspect(reason)}", detail: inspect(reason)}}
    kind, value -> {:error, %{stage: :load, message: "#{kind}: #{inspect(value)}", detail: inspect(value)}}
  end

  defp fail_extension(%Manifest{} = manifest, failure) do
    failure = Map.merge(%{detail: nil, at: System.system_time(:second)}, failure)

    # What did start is torn down and the manifest unregistered, so the extension provides nothing
    # and a half-started one cannot answer calls.
    try do
      terminate_extension_processes(manifest)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    ExtensionRegistry.unregister(manifest.id)
    ExtensionRegistry.record_failure(manifest, failure)

    Logger.error("[Boot] FAILED #{manifest.id} (#{failure.kind}, #{failure.stage}): #{failure.message}")

    try do
      Exoforge.ExtensionLogs.append(to_string(manifest.id), :error, "#{failure.kind}: #{failure.message}")

      Exoforge.EventDispatcher.broadcast(
        "extension.boot_failed",
        %{id: to_string(manifest.id), kind: failure.kind, stage: failure.stage, message: failure.message},
        source: :kernel
      )
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
  end

  # service key => provider ids, over every discovered extension (failed ones included).
  defp provider_index(manifests) do
    manifests
    |> Enum.flat_map(fn m ->
      Enum.flat_map(m.provides || [], fn p -> Enum.map(service_keys(p), &{&1, m.id}) end)
    end)
    |> Enum.group_by(fn {service, _id} -> service end, fn {_service, id} -> id end)
  end

  # The providers that make this extension unstartable: for each declared dependency whose providers
  # have all failed. A dependency with a healthy provider does not block.
  defp blocked_by(manifest, providers, failed) do
    manifest.dependencies
    |> Enum.flat_map(fn req ->
      case find_providers(providers, req) do
        {:ok, ids} -> if Enum.all?(ids, &MapSet.member?(failed, &1)), do: ids, else: []
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  defp initialize_and_register(%Manifest{} = manifest) do
    runner = runner_for(manifest.type)

    manifest =
      if function_exported?(runner, :prepare_manifest, 1) do
        runner.prepare_manifest(manifest)
      else
        manifest
      end

    ExtensionRegistry.register(manifest)

    case runner.load(manifest) do
      {:error, reason} -> raise StartError, id: manifest.id, reason: reason
      result -> result
    end
  end

  # One clause per runtime. A runtime added later adds a clause here and a runner module, and
  # nothing else in the kernel changes.
  defp runner_for(:elixir), do: ElixirExtensionRunner
  defp runner_for(:native), do: Exoforge.Drivers.Runtime.NativeExtensionRunner
  defp runner_for(mod) when is_atom(mod), do: mod

  @spec sort!([%Manifest{}]) :: [%Manifest{}]
  def sort!(manifests) do
    case sort_isolated(manifests) do
      {sorted, []} -> sorted
      {_sorted, [{_manifest, %{message: message}} | _]} -> raise message
    end
  end

  @doc """
  Orders manifests so providers come before dependents, without letting one bad manifest stop the
  rest. Returns `{sorted, problems}`: `problems` lists `{manifest, failure}` for each extension that
  requires a service nobody provides or sits in a dependency cycle; those are left out of `sorted`.
  """
  @spec sort_isolated([%Manifest{}]) :: {[%Manifest{}], [{%Manifest{}, map()}]}
  def sort_isolated(manifests) do
    graph = :digraph.new()

    try do
      Enum.each(manifests, &:digraph.add_vertex(graph, &1.id, &1))

      service_providers = provider_index(manifests)
      by_id = Map.new(manifests, &{&1.id, &1})

      missing =
        for m <- manifests, req <- m.dependencies, reduce: [] do
          acc ->
            case find_providers(service_providers, req) do
              {:ok, providers} ->
                Enum.each(providers, &:digraph.add_edge(graph, &1, m.id))
                acc

              :error ->
                message = "[Missing Dependency]: Extension `#{m.id}` requires service `#{req}`, which is not provided."
                [{m, %{stage: :dependencies, message: message, detail: inspect(req)}} | acc]
            end
        end
        |> Enum.reverse()

      {sorted_ids, cyclic} =
        case :digraph_utils.topsort(graph) do
          false ->
            cycles = :digraph_utils.cyclic_strong_components(graph)
            members = List.flatten(cycles)
            :digraph.del_vertices(graph, members)

            problems =
              Enum.flat_map(cycles, fn component ->
                message = "[Failed To Register Dependencies]: Circular dependency detected: #{inspect([component])}"

                Enum.map(component, fn id ->
                  {Map.fetch!(by_id, id), %{stage: :dependencies, message: message, detail: inspect(component)}}
                end)
              end)

            {:digraph_utils.topsort(graph), problems}

          ids ->
            {ids, []}
        end

      problem_ids = MapSet.new(Enum.map(missing ++ cyclic, fn {m, _} -> m.id end))

      sorted =
        sorted_ids
        |> Enum.reject(&MapSet.member?(problem_ids, &1))
        |> Enum.map(fn id -> elem(:digraph.vertex(graph, id), 1) end)

      {sorted, missing ++ cyclic}
    after
      :digraph.delete(graph)
    end
  end

  defp service_keys(service), do: ExtensionRegistry.service_keys(service)

  defp find_providers(service_providers, req) do
    Enum.find_value(service_keys(req), :error, fn key ->
      case Map.fetch(service_providers, key) do
        {:ok, providers} -> {:ok, providers}
        :error -> nil
      end
    end)
  end

  defp terminate_extension_processes(%Manifest{type: :elixir, entry_point: ext_mod}) when is_atom(ext_mod) do
    ext_sup_name = Module.concat(ext_mod, Supervisor)
    stop_child_supervisor(ext_sup_name)
  end

  defp terminate_extension_processes(%Manifest{type: :native} = manifest) do
    mod = if is_atom(manifest.entry_point) and manifest.entry_point != nil, do: manifest.entry_point, else: manifest.id
    sup_name = Module.concat([Exoforge, Extensions, mod, Supervisor])
    stop_child_supervisor(sup_name)
  end

  defp terminate_extension_processes(_), do: :ok

  defp stop_child_supervisor(sup_name) do
    case Process.whereis(sup_name) do
      pid when is_pid(pid) ->
        if Process.whereis(Exoforge.ExtensionSupervisor) != nil do
          DynamicSupervisor.terminate_child(Exoforge.ExtensionSupervisor, pid)
        else
          Process.exit(pid, :shutdown)
        end

      _ ->
        :ok
    end
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

            other ->
              ":#{other}"
          end
        end)
        |> Enum.uniq()
        |> Enum.join(", ")

      banner = """

      ==============================================================================
        🚀 EXOFORGE CLUSTER RUNTIME (v#{Exoforge.BuildInfo.version()} [#{env}])
      ==============================================================================
        • Exoforge Dashboard:   http://localhost:#{dash_port}
        • REST API Gateway:  http://localhost:#{http_port} (Docs: /api/docs)
        • WebSocket Gateway: ws://localhost:#{ws_port}/ws (Game Client SDK)
      ------------------------------------------------------------------------------
        • Active Extensions (#{length(manifests)}): #{Enum.map_join(manifests, ", ", & &1.id)}
        • Services Exposed:    #{services}
        • Cluster Node:        #{node()}
        • Status:              ONLINE and responsive (ready in #{total_ms}ms)
      ==============================================================================
      """

      IO.puts(banner)
    end

    Logger.info("[Exoforge] All #{length(manifests)} extensions loaded. System online in #{total_ms}ms")
  end

  defp current_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      Application.get_env(:exoforge, :env, :prod)
    end
  end
end
