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
        case validate_params(resolved_mod, action_atom, payload, opts) do
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

          {:error, _} = param_err ->
            Logger.warning("[Action] invalid parameters for #{inspect(resolved_mod)}.#{action}: #{inspect(param_err)}")
            param_err
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
    case PluginRegistry.fetch_service(mod_str, ctx) || PluginRegistry.fetch_manifest(mod_str) do
      nil -> nil
      manifest -> resolve_module(manifest, ctx, depth + 1)
    end
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
            Logger.warning(
              "[Action] service resolution depth exceeded for #{inspect(mod)}, defaulting to #{inspect(entry_point)}"
            )

            entry_point
          else
            resolve_module(entry_point, ctx, depth + 1)
          end

        next_mod when is_atom(next_mod) ->
          if depth > 10 do
            Logger.warning(
              "[Action] service resolution depth exceeded for #{inspect(mod)}, defaulting to #{inspect(next_mod)}"
            )

            resolve_module(next_mod, ctx)
          else
            resolve_module(next_mod, ctx, depth + 1)
          end
      end
    end
  end

  # External transports may supply arbitrary names; never create atoms for them.
  defp to_atom_safe(val) when is_binary(val), do: Exoforge.Atoms.existing(val, val)

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
                  Map.get(item, action) || if item[:name] == action, do: item, else: nil

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

  # Role hierarchy: admin > studio > player > guest. A caller may run an action
  # whose declared scope is at or below their own rank.
  defp authorize_scope(declared, caller_scopes) do
    scopes_str = normalize_scopes(caller_scopes)

    if scopes_str == [] do
      {:error, :unauthorized}
    else
      declared_str = to_string(declared)
      known? = Exoforge.Auth.Roles.rank(declared_str) > 0

      cond do
        not known? ->
          if declared_str in scopes_str, do: :ok, else: {:error, :forbidden_scope}

        Exoforge.Auth.Roles.satisfies?(scopes_str, declared_str) ->
          :ok

        true ->
          {:error, :forbidden_scope}
      end
    end
  end

  defp normalize_scopes(scopes) do
    cond do
      is_list(scopes) -> Enum.map(scopes, &to_string/1)
      is_binary(scopes) or is_atom(scopes) -> [to_string(scopes)]
      true -> []
    end
  end

  defp validate_params(mod, action, payload, opts) do
    if Keyword.get(opts, :validate_params, true) and is_map(payload) do
      params_spec = fetch_action_params(mod, action)

      if is_list(params_spec) and params_spec != [] do
        require_all? = Keyword.get(opts, :require_params, false)

        Enum.find_value(params_spec, :ok, fn {param_name, spec} ->
          val = Map.get(payload, param_name, Map.get(payload, to_string(param_name)))

          {type, optional?} =
            case spec do
              t when is_atom(t) ->
                {t, false}

              kw when is_list(kw) ->
                t = Keyword.get(kw, :type, :term)
                opt? = Keyword.get(kw, :optional, false)
                {t, opt?}

              _ ->
                {:term, true}
            end

          cond do
            is_nil(val) and require_all? and not optional? ->
              {:error, {:missing_param, param_name}}

            is_nil(val) ->
              nil

            not valid_type?(val, type) ->
              {:error, {:invalid_param_type, field: param_name, expected: type, received: val}}

            true ->
              nil
          end
        end)
      else
        :ok
      end
    else
      :ok
    end
  end

  defp fetch_action_params(mod, action) do
    cond do
      function_exported?(mod, :__service_metadata__, 0) ->
        meta = mod.__service_metadata__()
        find_params_in_actions(Map.get(meta, :actions, []), action)

      function_exported?(mod, :provides_contracts, 0) ->
        Enum.find_value(mod.provides_contracts(), [], fn contract ->
          if function_exported?(contract, :__service_metadata__, 0) do
            case find_params_in_actions(contract.__service_metadata__().actions || [], action) do
              [] -> nil
              params -> params
            end
          end
        end) || []

      true ->
        []
    end
  end

  defp find_params_in_actions(actions, action) do
    case Enum.find(actions, fn a -> a.name == action end) do
      %{params: params} when is_list(params) -> params
      _ -> []
    end
  end

  defp valid_type?(_val, :term), do: true
  defp valid_type?(val, :integer), do: is_integer(val)
  defp valid_type?(val, :string), do: is_binary(val)
  defp valid_type?(val, :boolean), do: is_boolean(val)
  defp valid_type?(val, :float), do: is_float(val) or is_integer(val)
  defp valid_type?(val, :map), do: is_map(val)
  defp valid_type?(val, :list), do: is_list(val)
  defp valid_type?(val, :atom), do: is_atom(val)
  defp valid_type?(_val, _other), do: true
end
