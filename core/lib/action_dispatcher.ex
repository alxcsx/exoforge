defmodule Exoforge.ActionDispatcher do
  require Logger
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  def dispatch(service, action, payload, opts \\ []) do
    context = Keyword.get(opts, :context, :global)
    service_atom = to_atom_safe(service)
    action_atom = to_atom_safe(action)
    resolved_mod = resolve_module(service_atom, context)

    case check_scope(resolved_mod, action_atom, payload, opts) do
      :ok ->
        case run_action(resolved_mod, action_atom, payload) do
          {:error, reason} = err ->
            case resolved_mod do
              nil -> Logger.warning("[Action] service not found: #{inspect(service)}, action: #{action}")
              mod -> Logger.warning("[Action] failed in #{inspect(mod)}.#{action}: #{inspect(reason)}")
            end

            err

          {:ok, _} = ok ->
            ok

          :ok ->
            :ok

          other ->
            {:ok, other}
        end

      {:error, reason} = auth_err ->
        Logger.warning("[Action] auth failed for #{inspect(resolved_mod)}.#{action}: #{inspect(reason)}")
        auth_err
    end
  end

  defp run_action(nil, _action, _payload), do: {:error, :service_not_found}

  defp run_action(mod, action, payload) do
    try do
      apply(mod, :__execute_action__, [action, payload])
    rescue
      e in MatchError ->
        {:error, {:plugin_error, "Invalid function call: #{Exception.message(e)}"}}

      _e in FunctionClauseError ->
        {:error, {:plugin_error, "No matching clause found"}}

      e in ArgumentError ->
        {:error, {:plugin_error, "Invalid arguments: #{Exception.message(e)}"}}

      e ->
        {:error, {:framework_error, Exception.message(e)}}
    catch
      :exit, reason ->
        {:error, {:plugin_exited, reason}}
    end
  end

  defp resolve_module(target, ctx, depth \\ 0)

  defp resolve_module(%Manifest{entry_point: mod}, ctx, depth), do: resolve_module(mod, ctx, depth)

  defp resolve_module(mod_str, ctx, depth) when is_binary(mod_str) do
    mod_atom =
      mod_str
      |> Path.rootname()
      |> Path.basename()
      |> Macro.camelize()
      |> then(&Module.concat([Exoforge, Plugins, &1]))

    resolve_module(mod_atom, ctx, depth + 1)
  end

  defp resolve_module(mod, ctx, depth) when is_atom(mod) do
    if function_exported?(mod, :__exoforge_plugin__?, 0) do
      mod
    else
      case PluginRegistry.fetch_service(mod, ctx) || PluginRegistry.fetch_manifest(mod) do
        nil ->
          nil

        %Manifest{entry_point: entry_point} ->
          if depth > 10 do
            Logger.warning("[Action] service resolution depth exceeded for #{inspect(mod)}, defaulting to #{inspect(entry_point)}")
            entry_point
          else
            resolve_module(entry_point, ctx, depth + 1)
          end

        next_mod when is_atom(next_mod) ->
          if depth > 10 do
            Logger.warning("[Action] service resolution depth exceeded for #{inspect(mod)}, defaulting to #{inspect(next_mod)}")
            resolve_module(next_mod, ctx)
          else
            resolve_module(next_mod, ctx, depth + 1)
          end
      end
    end
  end

  defp to_atom_safe(val) when is_atom(val), do: val
  defp to_atom_safe(val) when is_binary(val), do: String.to_atom(val)
  defp to_atom_safe(val), do: val

  defp check_scope(nil, _action, _payload, _opts), do: :ok

  defp check_scope(mod, action, payload, opts) do
    declared_scope = fetch_action_scope(mod, action)
    caller_scopes = extract_caller_scopes(payload, opts)
    authorize_scope(declared_scope, caller_scopes)
  end

  defp fetch_action_scope(mod, action) do
    cond do
      function_exported?(mod, :__actions__, 0) ->
        actions = mod.__actions__()

        action_info =
          cond do
            is_map(actions) ->
              Map.get(actions, action)

            is_list(actions) ->
              Enum.find_value(actions, fn
                item when is_map(item) ->
                  Map.get(item, action) || (if item[:name] == action, do: item, else: nil)

                _ ->
                  nil
              end)

            true ->
              nil
          end

        case action_info do
          %{scope: scope} when not is_nil(scope) -> scope
          _ -> check_contract_scopes(mod, action)
        end

      function_exported?(mod, :__service_metadata__, 0) ->
        meta = mod.__service_metadata__()
        find_scope_in_actions(Map.get(meta, :actions, []), action)

      true ->
        check_contract_scopes(mod, action)
    end
  end

  defp check_contract_scopes(mod, action) do
    if function_exported?(mod, :provides_contracts, 0) do
      Enum.find_value(mod.provides_contracts(), :global, fn contract ->
        if function_exported?(contract, :__service_metadata__, 0) do
          case find_scope_in_actions(contract.__service_metadata__().actions || [], action) do
            :global -> nil
            scope -> scope
          end
        end
      end) || :global
    else
      :global
    end
  end

  defp find_scope_in_actions(actions, action) do
    case Enum.find(actions, fn a -> a.name == action end) do
      %{scope: scope} when not is_nil(scope) -> scope
      _ -> :global
    end
  end

  defp extract_caller_scopes(payload, opts) do
    cond do
      Keyword.has_key?(opts, :caller_scopes) ->
        Keyword.get(opts, :caller_scopes)

      Keyword.has_key?(opts, :scopes) ->
        Keyword.get(opts, :scopes)

      is_map(payload) and (Map.has_key?(payload, "_auth") or Map.has_key?(payload, :_auth)) ->
        auth = Map.get(payload, "_auth") || Map.get(payload, :_auth)

        if is_map(auth) do
          Map.get(auth, "scopes") || Map.get(auth, :scopes) || []
        else
          []
        end

      true ->
        :internal
    end
  end

  defp authorize_scope(scope, _caller_scopes) when scope in [:global, nil], do: :ok
  defp authorize_scope(_declared, :internal), do: :ok

  defp authorize_scope(:server, _caller_scopes) do
    {:error, :forbidden_scope}
  end

  defp authorize_scope(declared, caller_scopes) do
    scopes_list =
      cond do
        is_list(caller_scopes) -> caller_scopes
        is_binary(caller_scopes) or is_atom(caller_scopes) -> [caller_scopes]
        true -> []
      end

    if scopes_list == [] do
      {:error, :unauthorized}
    else
      declared_str = to_string(declared)
      scopes_str = Enum.map(scopes_list, &to_string/1)

      if "admin" in scopes_str or declared_str in scopes_str do
        :ok
      else
        {:error, :forbidden_scope}
      end
    end
  end
end
