defmodule Exoforge.ActionDispatcher do
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  def dispatch(service, action, payload, opts \\ []) do
    context = Keyword.get(opts, :context, :global)
    resolved_mod = resolve_module(service, context)

    case run_action(resolved_mod, action, payload) do
      {:ok, result} -> result
      {:error, reason} ->
        case resolved_mod do
          nil -> IO.puts("[Action] service not found: #{inspect(service)}, action: #{action}")
          mod -> IO.puts("[Action] failed in #{inspect(mod)}.#{action}/0: #{inspect(reason)}")
        end

        {:error, reason}
    end
  end

  defp run_action(nil, _action, _payload), do: {:error, :service_not_found}

  defp run_action(mod, action, payload) do
    result =
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

    result
  end

  defp resolve_module(%Manifest{entry_point: mod}, _), do: mod

  defp resolve_module(mod, ctx, depth \\ 0) when is_atom(mod) do
    if function_exported?(mod, :__exoforge_plugin__?, 0) do
      mod
    else
      PluginRegistry.fetch_service(mod, ctx)
      |> case do
        nil -> nil
        next_mod when is_atom(next_mod) ->
          if depth > 10 do
            IO.puts("[Action] service resolution depth exceeded for #{inspect(mod)}, defaulting to #{inspect(next_mod)}")
            resolve_module(next_mod, ctx)
          else
            resolve_module(next_mod, ctx, depth + 1)
          end
      end
    end
  end
end
