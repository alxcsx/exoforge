defmodule Exoforge.Drivers.Runtime.WasmPluginRunner do
  @moduledoc """
  Plugin Runner responsible for loading, sandboxing, and executing WebAssembly (WASM) plugins.
  Supports both Core WebAssembly modules and WebAssembly Components (WASI P2).
  """

  @behaviour Exoforge.Contracts.PluginRunner
  use GenServer
  require Logger

  alias Exoforge.Domain.Manifest
  alias Exoforge.EventDispatcher
  alias Exoforge.ActionDispatcher
  alias Exoforge.PluginRegistry

  @wasm_core_magic <<0, 97, 115, 109, 1, 0, 0, 0>>
  @wasm_component_magic <<0, 97, 115, 109, 13, 0, 1, 0>>
  @default_memory_limit 64 * 1024 * 1024

  # -- Public PluginRunner API --

  @doc """
  Prepares the manifest by ensuring the proxy module is created and set as entry_point.
  """
  def prepare_manifest(%Manifest{} = manifest) do
    proxy_mod = ensure_proxy_module(manifest)
    %{manifest | entry_point: proxy_mod}
  end

  @impl true
  def load(%Manifest{} = manifest) do
    case find_wasm_path(manifest) do
      {:ok, wasm_path} ->
        proxy_mod = ensure_proxy_module(manifest)
        # Register manifest with proxy module as entry point so nothing special-cases :wasm
        updated_manifest = %{manifest | entry_point: proxy_mod}
        PluginRegistry.register(updated_manifest)

        sup_name = Module.concat([Exoforge, Plugins, wasm_module_name(manifest), Supervisor])
        runner_name = via_name(manifest.id)

        child_spec = %{
          id: sup_name,
          start: {
            Supervisor,
            :start_link,
            [
              [
                %{
                  id: __MODULE__,
                  start: {__MODULE__, :start_link, [{updated_manifest, wasm_path, runner_name}]}
                }
              ],
              [name: sup_name, strategy: :one_for_one]
            ]
          },
          type: :supervisor
        }

        DynamicSupervisor.start_child(Exoforge.PluginSupervisor, child_spec)

      {:error, reason} ->
        Logger.error("[WasmPluginRunner] Failed to find WASM file for #{manifest.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def start_link({%Manifest{} = manifest, wasm_path, name}) do
    GenServer.start_link(__MODULE__, {manifest, wasm_path}, name: name)
  end

  @doc """
  Returns or generates the proxy module for a WASM manifest.
  """
  def proxy_module(%Manifest{} = manifest) do
    ensure_proxy_module(manifest)
  end

  @doc """
  Executes an action on a loaded WASM plugin.
  """
  def execute_action(plugin_id, action, payload, timeout \\ 5000) do
    case Exoforge.WorkerRegistry.lookup(plugin_id, :wasm_runner) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, {:execute_action, to_string(action), payload}, timeout)
        catch
          :exit, {:timeout, _} ->
            {:error, :timeout}

          :exit, reason ->
            record_trap(plugin_id, reason)
            {:error, {:wasm_trap, reason}}
        end

      {:error, :not_found} ->
        {:error, {:wasm_plugin_not_running, plugin_id}}
    end
  end

  @doc """
  Dispatches an inbound BEAM event to the running WASM plugin process.
  """
  def dispatch_event(plugin_id, event_key, payload, context \\ %{}) do
    case Exoforge.WorkerRegistry.lookup(plugin_id, :wasm_runner) do
      {:ok, pid} ->
        send(pid, {:exo_event, event_key, payload, context})
        :ok

      _ ->
        :ignored
    end
  end

  # -- GenServer Callbacks --

  @impl true
  def init({manifest, wasm_path}) do
    Logger.info("[WasmPluginRunner] Initializing WASM plugin #{manifest.id} from #{wasm_path}")
    ensure_tables()

    case File.read(wasm_path) do
      {:ok, bytes} ->
        case detect_wasm_type(bytes) do
          :component ->
            init_component(manifest, wasm_path, bytes)

          :core ->
            init_core(manifest, wasm_path, bytes)

          :unknown ->
            {:stop, {:unrecognized_wasm_format, wasm_path}}
        end

      {:error, reason} ->
        {:stop, {:cannot_read_wasm_file, wasm_path, reason}}
    end
  end

  defp init_core(manifest, wasm_path, bytes) do
    imports = build_core_imports(manifest)
    limits = %Wasmex.StoreLimits{memory_size: @default_memory_limit}

    case Wasmex.start_link(%{bytes: bytes, imports: imports, wasi: true, store_limits: limits}) do
      {:ok, instance_pid} ->
        # 1. Subscribe to handled events
        events = Map.get(manifest, :events, [])
        Enum.each(events, fn evt ->
          event_name =
            case evt do
              %{name: n} -> n
              n when is_atom(n) or is_binary(n) -> n
            end

          event_key = if is_binary(event_name), do: safe_to_atom(event_name) || String.to_atom(event_name), else: event_name
          EventDispatcher.subscribe(event_key)
        end)

        # 2. Call __init or init in guest if exported
        cond do
          Wasmex.function_exists(instance_pid, "__init") ->
            _ = Wasmex.call_function(instance_pid, "__init", [])

          Wasmex.function_exists(instance_pid, "init") ->
            _ = Wasmex.call_function(instance_pid, "init", [])

          true ->
            :ok
        end

        state = %{
          manifest: manifest,
          wasm_path: wasm_path,
          type: :core,
          pid: instance_pid,
          bytes: bytes
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("[WasmPluginRunner] Failed to start Core WASM instance: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp init_component(manifest, wasm_path, bytes) do
    case Wasmex.Components.start_link(%{
           bytes: bytes,
           wasi: %Wasmex.Wasi.WasiP2Options{allow_http: true}
         }) do
      {:ok, instance_pid} ->
        state = %{
          manifest: manifest,
          wasm_path: wasm_path,
          type: :component,
          pid: instance_pid,
          bytes: bytes
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("[WasmPluginRunner] Failed to start Component WASM instance: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:execute_action, action_name, payload}, _from, state) do
    result =
      case state.type do
        :core ->
          execute_core_action(state, action_name, payload)

        :component ->
          execute_component_action(state, action_name, payload)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:exo_event, event_key, payload, _context}, state) do
    event_str = to_string(event_key)

    cond do
      Wasmex.function_exists(state.pid, event_str) ->
        _ = execute_core_action(state, event_str, payload)

      Wasmex.function_exists(state.pid, "handle_event") ->
        _ = execute_core_action(state, "handle_event", %{event: event_str, payload: payload})

      Wasmex.function_exists(state.pid, "on_event") ->
        _ = execute_core_action(state, "on_event", %{event: event_str, payload: payload})

      true ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # -- Action Dispatch Execution --

  defp execute_core_action(%{manifest: manifest} = state, action_name, payload) do
    action_atom = safe_to_atom(action_name) || action_name
    action_meta = find_action_meta(manifest, action_atom)

    if action_meta && Map.get(action_meta, :mode) == :cast do
      Task.start(fn -> do_execute_core_action(state, action_name, payload, action_meta) end)
      :ok
    else
      do_execute_core_action(state, action_name, payload, action_meta)
    end
  end

  defp do_execute_core_action(%{pid: pid} = state, action_name, payload, action_meta) do
    cond do
      Wasmex.function_exists(pid, action_name) ->
        call_core_function(state, action_name, payload, action_meta)

      Wasmex.function_exists(pid, "execute_action") ->
        call_core_dispatcher(pid, "execute_action", action_name, payload)

      Wasmex.function_exists(pid, "run_action") ->
        call_core_dispatcher(pid, "run_action", action_name, payload)

      true ->
        {:error, {:action_not_exported, action_name}}
    end
  end

  defp call_core_function(%{pid: pid, manifest: manifest}, action_name, payload, action_meta) do
    args = extract_action_args(manifest, action_name, payload)

    try do
      case Wasmex.call_function(pid, action_name, args) do
        {:ok, []} ->
          :ok

        {:ok, [single_result]} ->
          normalize_result(single_result, action_meta)

        {:ok, results} when is_list(results) ->
          {:ok, results}

        {:error, reason} ->
          record_trap(manifest.id, reason)
          {:error, {:wasm_call_error, reason}}
      end
    rescue
      e ->
        record_trap(manifest.id, Exception.message(e))
        {:error, {:wasm_trap, Exception.message(e)}}
    end
  end

  defp normalize_result(result, _action_meta) when is_binary(result) do
    case Jason.decode(result) do
      {:ok, %{"error" => reason}} when is_binary(reason) ->
        {:error, safe_to_atom(reason) || String.to_atom(reason)}

      {:ok, %{error: reason}} when is_atom(reason) ->
        {:error, reason}

      {:ok, %{"ok" => value}} ->
        {:ok, value}

      {:ok, %{ok: value}} ->
        {:ok, value}

      {:ok, json_map} ->
        {:ok, json_map}

      _ ->
        {:ok, result}
    end
  end

  defp normalize_result(result, _action_meta), do: {:ok, result}

  defp extract_action_args(manifest, action_name, payload) do
    case payload do
      nil -> []
      map when is_map(map) and map_size(map) == 0 -> []
      list when is_list(list) -> list
      num when is_number(num) -> [num]
      map when is_map(map) ->
        action_atom = if is_binary(action_name), do: safe_to_atom(action_name) || action_name, else: action_name

        case find_action_params(manifest, action_atom) do
          {:ok, param_keys} when param_keys != [] ->
            Enum.map(param_keys, fn key ->
              Map.get(map, key) || Map.get(map, to_string(key))
            end)

          _ ->
            Map.values(map)
        end

      other -> [other]
    end
  end

  defp find_action_meta(%Manifest{services: services, provides: provides}, action_atom) do
    found =
      Enum.find_value(services || [], fn svc ->
        Enum.find(svc.actions || [], fn a -> a.name == action_atom end)
      end)

    if found do
      found
    else
      Enum.find_value(provides || [], fn contract_ref ->
        mod = resolve_contract_module(contract_ref)

        if is_atom(mod) and Code.ensure_loaded?(mod) and function_exported?(mod, :__service_metadata__, 0) do
          Enum.find(mod.__service_metadata__().actions || [], fn a -> a.name == action_atom end)
        end
      end)
    end
  end

  defp find_action_params(manifest, action_atom) do
    case find_action_meta(manifest, action_atom) do
      %{params: params} when is_list(params) ->
        param_names =
          Enum.map(params, fn
            {k, _v} -> k
            k when is_atom(k) -> k
          end)

        {:ok, param_names}

      _ ->
        :error
    end
  end

  defp resolve_contract_module(contract_ref) when is_atom(contract_ref) do
    str = to_string(contract_ref)

    if String.starts_with?(str, "Elixir.Exoforge.Std.Services.") do
      contract_ref
    else
      shorthand_mod = Module.concat([Exoforge, Std, Services, Macro.camelize(str)])
      if Code.ensure_loaded?(shorthand_mod), do: shorthand_mod, else: contract_ref
    end
  end

  defp resolve_contract_module(other), do: other

  defp call_core_dispatcher(_pid, dispatcher_fn, action_name, _payload) do
    {:error, {:core_wasm_dispatcher_not_implemented, dispatcher_fn, action_name}}
  end

  defp execute_component_action(%{pid: pid}, action_name, payload) do
    args =
      case payload do
        nil -> []
        map when is_map(map) and map_size(map) == 0 -> []
        list when is_list(list) -> list
        num when is_number(num) -> [num]
        str when is_binary(str) -> [str]
        other -> [Jason.encode!(other)]
      end

    try do
      case Wasmex.Components.call_function(pid, action_name, args) do
        {:ok, result} ->
          decoded =
            if is_binary(result) do
              case Jason.decode(result) do
                {:ok, json} -> json
                _ -> result
              end
            else
              result
            end

          {:ok, decoded}

        {:error, reason} ->
          {:error, {:wasm_component_error, reason}}
      end
    rescue
      e -> {:error, {:wasm_trap, Exception.message(e)}}
    end
  end

  # -- Host Capability ABI v1 Imports for Core WASM --

  defp build_core_imports(manifest) do
    manifest_id = manifest.id

    %{
      "env" => %{
        # Clock ABI: host_clock_now() -> i64
        "host_clock_now" =>
          {:fn, [], [:i64], fn _context -> System.system_time(:millisecond) end},

        # Event ABI: host_emit_event(topic_ptr, topic_len, event_ptr, event_len, payload_ptr, payload_len) -> i32
        "host_emit_event" =>
          {:fn, [:i32, :i32, :i32, :i32, :i32, :i32], [:i32],
           fn context, topic_ptr, topic_len, event_ptr, event_len, payload_ptr, payload_len ->
             try do
               topic = read_string(context, topic_ptr, topic_len)
               event = read_string(context, event_ptr, event_len)
               payload_str = read_string(context, payload_ptr, payload_len)
               payload = decode_payload(payload_str)

               case safe_to_atom(event) do
                 nil ->
                   Logger.warning("[WasmHost:#{manifest_id}] host_emit_event rejected undeclared event #{inspect(event)}")
                   -1

                 event_atom ->
                   opts = if topic != "", do: [topic: topic], else: []
                   EventDispatcher.broadcast(event_atom, payload, opts)
                   0
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # Action ABI: host_call_action(svc_ptr, svc_len, act_ptr, act_len, pay_ptr, pay_len) -> i32
        "host_call_action" =>
          {:fn, [:i32, :i32, :i32, :i32, :i32, :i32], [:i32],
           fn context, svc_ptr, svc_len, act_ptr, act_len, pay_ptr, pay_len ->
             try do
               service = read_string(context, svc_ptr, svc_len)
               action = read_string(context, act_ptr, act_len)
               payload_str = read_string(context, pay_ptr, pay_len)
               payload = decode_payload(payload_str)

               with service_atom when not is_nil(service_atom) <- safe_to_atom(service),
                    action_atom when not is_nil(action_atom) <- safe_to_atom(action),
                    true <- has_capability?(manifest, service_atom),
                    {:ok, _} <- ActionDispatcher.dispatch(service_atom, action_atom, payload) do
                 0
               else
                 :ok -> 0
                 false ->
                   Logger.warning("[WasmHost:#{manifest_id}] host_call_action denied: #{service} not in dependencies")
                   -1
                 _ -> -1
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # Action ABI with response: host_call_action_json(svc_ptr, svc_len, act_ptr, act_len, pay_ptr, pay_len, out_ptr, out_max_len) -> i32
        "host_call_action_json" =>
          {:fn, [:i32, :i32, :i32, :i32, :i32, :i32, :i32, :i32], [:i32],
           fn context, svc_ptr, svc_len, act_ptr, act_len, pay_ptr, pay_len, out_ptr, out_max_len ->
             try do
               service = read_string(context, svc_ptr, svc_len)
               action = read_string(context, act_ptr, act_len)
               payload_str = read_string(context, pay_ptr, pay_len)
               payload = decode_payload(payload_str)

               with service_atom when not is_nil(service_atom) <- safe_to_atom(service),
                    action_atom when not is_nil(action_atom) <- safe_to_atom(action),
                    true <- has_capability?(manifest, service_atom) do
                 case ActionDispatcher.dispatch(service_atom, action_atom, payload) do
                   {:ok, res} ->
                     write_to_guest_memory(context, Jason.encode!(res), out_ptr, out_max_len)

                   :ok ->
                     write_to_guest_memory(context, "{\"status\":\"ok\"}", out_ptr, out_max_len)

                   {:error, reason} ->
                     err_json = Jason.encode!(%{error: to_string(reason)})
                     write_to_guest_memory(context, err_json, out_ptr, out_max_len)
                     -1
                 end
               else
                 false ->
                   Logger.warning("[WasmHost:#{manifest_id}] host_call_action denied: #{service} not in dependencies")
                   -1

                 _ ->
                   -1
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # Log ABI: host_log(level, msg_ptr, msg_len) -> i32
        "host_log" =>
          {:fn, [:i32, :i32, :i32], [:i32],
           fn context, level, msg_ptr, msg_len ->
             try do
               msg = read_string(context, msg_ptr, msg_len)

               case level do
                 0 -> Logger.debug("[WASM:#{manifest_id}] #{msg}")
                 1 -> Logger.info("[WASM:#{manifest_id}] #{msg}")
                 2 -> Logger.warning("[WASM:#{manifest_id}] #{msg}")
                 3 -> Logger.error("[WASM:#{manifest_id}] #{msg}")
                 _ -> Logger.info("[WASM:#{manifest_id}] #{msg}")
               end

               0
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # Database ABI: host_db_get(tbl_ptr, tbl_len, key_ptr, key_len, out_ptr, out_max_len) -> i32
        "host_db_get" =>
          {:fn, [:i32, :i32, :i32, :i32, :i32, :i32], [:i32],
           fn context, tbl_ptr, tbl_len, key_ptr, key_len, out_ptr, out_max_len ->
             try do
               if has_capability?(manifest, :database) do
                 table = read_string(context, tbl_ptr, tbl_len)
                 key = read_string(context, key_ptr, key_len)

                 case apply_db(:get, [manifest_id, table, key]) do
                   {:ok, record} ->
                     write_to_guest_memory(context, Jason.encode!(record), out_ptr, out_max_len)

                   {:error, :not_found} ->
                     0

                   _ ->
                     -1
                 end
               else
                 Logger.warning("[WasmHost:#{manifest_id}] host_db_get denied: :database not in dependencies")
                 -1
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # Database ABI: host_db_put(tbl_ptr, tbl_len, key_ptr, key_len, val_ptr, val_len) -> i32
        "host_db_put" =>
          {:fn, [:i32, :i32, :i32, :i32, :i32, :i32], [:i32],
           fn context, tbl_ptr, tbl_len, key_ptr, key_len, val_ptr, val_len ->
             try do
               if has_capability?(manifest, :database) do
                 table = read_string(context, tbl_ptr, tbl_len)
                 key = read_string(context, key_ptr, key_len)
                 val_str = read_string(context, val_ptr, val_len)
                 val = decode_payload(val_str)

                 case apply_db(:put, [manifest_id, table, key, val]) do
                   {:ok, _} -> 0
                   :ok -> 0
                   _ -> -1
                 end
               else
                 Logger.warning("[WasmHost:#{manifest_id}] host_db_put denied: :database not in dependencies")
                 -1
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # Database ABI: host_db_delete(tbl_ptr, tbl_len, key_ptr, key_len) -> i32
        "host_db_delete" =>
          {:fn, [:i32, :i32, :i32, :i32], [:i32],
           fn context, tbl_ptr, tbl_len, key_ptr, key_len ->
             try do
               if has_capability?(manifest, :database) do
                 table = read_string(context, tbl_ptr, tbl_len)
                 key = read_string(context, key_ptr, key_len)

                 case apply_db(:delete, [manifest_id, table, key]) do
                   {:ok, _} -> 0
                   :ok -> 0
                   _ -> -1
                 end
               else
                 -1
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # State ABI: host_get_state(key_ptr, key_len, out_ptr, out_max_len) -> i32
        "host_get_state" =>
          {:fn, [:i32, :i32, :i32, :i32], [:i32],
           fn context, key_ptr, key_len, out_ptr, out_max_len ->
             try do
               key = read_string(context, key_ptr, key_len)
               ensure_tables()

               case :ets.lookup(:exo_guest_state, {manifest_id, key}) do
                 [{{^manifest_id, ^key}, val}] ->
                   json = if is_binary(val), do: val, else: Jason.encode!(val)
                   write_to_guest_memory(context, json, out_ptr, out_max_len)

                 [] ->
                   0
               end
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end},

        # State ABI: host_set_state(key_ptr, key_len, val_ptr, val_len) -> i32
        "host_set_state" =>
          {:fn, [:i32, :i32, :i32, :i32], [:i32],
           fn context, key_ptr, key_len, val_ptr, val_len ->
             try do
               key = read_string(context, key_ptr, key_len)
               val_str = read_string(context, val_ptr, val_len)
               val = decode_payload(val_str)
               ensure_tables()

               :ets.insert(:exo_guest_state, {{manifest_id, key}, val})
               0
             rescue
               e ->
                 record_trap(manifest_id, Exception.message(e))
                 -1
             end
           end}
      }
    }
  end

  defp read_string(%{caller: caller, memory: memory}, offset, length) do
    if length <= 0 do
      ""
    else
      Wasmex.Memory.read_string(caller, memory, offset, length)
    end
  end

  defp write_to_guest_memory(%{caller: caller, memory: memory}, binary, out_ptr, out_max_len)
       when is_binary(binary) do
    if out_ptr > 0 and out_max_len > 0 do
      bytes_to_write = min(byte_size(binary), out_max_len)
      chunk = binary_part(binary, 0, bytes_to_write)
      Wasmex.Memory.write_binary(caller, memory, out_ptr, chunk)
      bytes_to_write
    else
      0
    end
  end

  defp decode_payload(payload_str) do
    case Jason.decode(payload_str) do
      {:ok, data} -> data
      _ -> payload_str
    end
  end

  # -- Helpers --

  defp detect_wasm_type(bytes) when byte_size(bytes) >= 8 do
    case binary_part(bytes, 0, 8) do
      @wasm_component_magic -> :component
      @wasm_core_magic -> :core
      _ -> :unknown
    end
  end

  defp detect_wasm_type(_), do: :unknown

  defp via_name(plugin_id) do
    Exoforge.WorkerRegistry.via_tuple(plugin_id, :wasm_runner)
  end

  defp wasm_module_name(manifest) do
    if is_atom(manifest.entry_point) and manifest.entry_point != nil do
      manifest.entry_point
    else
      manifest.id
      |> to_string()
      |> Macro.camelize()
      |> then(&Module.concat([Exoforge, Plugins, &1]))
    end
  end

  defp ensure_proxy_module(manifest) do
    mod = wasm_module_name(manifest)
    manifest_id = manifest.id
    provides = Map.get(manifest, :provides, [])
    events = Map.get(manifest, :events, [])
    services = Map.get(manifest, :services, [])

    service_metadata =
      case services do
        [first_svc | _] -> first_svc
        _ -> %{name: hd(provides || [manifest_id]), actions: [], events: [], resources: []}
      end

    unless Code.ensure_loaded?(mod) do
      contents =
        quote do
          defmodule unquote(mod) do
            @moduledoc false
            def __exoforge_plugin__?, do: true
            def manifest, do: unquote(Macro.escape(manifest))
            def provides_contracts, do: unquote(Macro.escape(provides))
            def handled_events, do: unquote(Macro.escape(events))
            def __service_metadata__, do: unquote(Macro.escape(service_metadata))
            def __services_metadata__, do: unquote(Macro.escape(services))
            def children, do: []
            def init(_manifest), do: :ok

            def handle_inbound_event(event_key, payload, context) do
              Exoforge.Drivers.Runtime.WasmPluginRunner.dispatch_event(
                unquote(manifest_id),
                event_key,
                payload,
                context
              )
            end

            def __execute_action__(action, payload) do
              Exoforge.Drivers.Runtime.WasmPluginRunner.execute_action(
                unquote(manifest_id),
                action,
                payload
              )
            end
          end
        end

      Code.eval_quoted(contents)
    end

    mod
  end

  defp has_capability?(%Manifest{dependencies: deps, provides: provides}, service) do
    svc_str = to_string(service)
    allowed = (deps || []) ++ (provides || [])

    Enum.any?(allowed, fn item ->
      to_string(item) == svc_str or
        to_string(item) == Macro.underscore(svc_str) or
        Macro.underscore(to_string(item)) == svc_str
    end)
  end

  defp safe_to_atom(nil), do: nil
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when is_binary(val) do
    try do
      String.to_existing_atom(val)
    rescue
      ArgumentError -> nil
    end
  end
  defp safe_to_atom(_), do: nil

  defp ensure_tables do
    case :ets.info(:exo_guest_state) do
      :undefined ->
        :ets.new(:exo_guest_state, [:set, :named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end

    case :ets.info(:exo_wasm_stats) do
      :undefined ->
        :ets.new(:exo_wasm_stats, [:set, :named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end
  end

  def record_trap(plugin_id, reason) do
    ensure_tables()
    stats = get_stats(plugin_id)

    new_stats = %{
      stats
      | traps_count: stats.traps_count + 1,
        last_trap: to_string(reason),
        last_trap_at: System.system_time(:second)
    }

    :ets.insert(:exo_wasm_stats, {plugin_id, new_stats})
  end

  def get_stats(plugin_id) do
    ensure_tables()

    case :ets.lookup(:exo_wasm_stats, plugin_id) do
      [{^plugin_id, stats}] -> stats
      [] -> %{traps_count: 0, last_trap: nil, last_trap_at: nil}
    end
  end

  defp apply_db(func, args) do
    db_mod = Module.concat([Exoforge, Std, Database])
    apply(db_mod, func, args)
  end

  defp find_wasm_path(%Manifest{physical_path: path, entry_point: entry_point, id: id}) do
    candidates = [
      if(is_binary(entry_point) and String.ends_with?(entry_point, ".wasm"), do: Path.join(path, entry_point)),
      if(is_binary(path) and String.ends_with?(path, ".wasm"), do: path),
      Path.join(path, "#{id}.wasm"),
      Path.join([path, "bin", "Release", "net10.0", "wasi-wasm", "#{id}.wasm"]),
      Path.join([path, "bin", "Release", "net10.0", "wasi-wasm", "wasm", "for-publish", "#{id}.wasm"]),
      Path.join([path, "bin", "Release", "net10.0", "wasi-wasm", "dotnet.wasm"]),
      Path.join([path, "bin", "Debug", "net10.0", "wasi-wasm", "#{id}.wasm"]),
      Path.join([path, "bin", "Debug", "net10.0", "wasi-wasm", "dotnet.wasm"])
    ]
    |> Enum.reject(&is_nil/1)

    case Enum.find(candidates, fn c -> File.regular?(c) and String.ends_with?(c, ".wasm") end) do
      nil ->
        wildcard_pattern = Path.join([path, "**", "*.wasm"])
        case Path.wildcard(wildcard_pattern) do
          [first | _] -> {:ok, first}
          [] -> {:error, :wasm_file_not_found}
        end

      found ->
        {:ok, found}
    end
  end
end
