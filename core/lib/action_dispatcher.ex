defmodule Exoforge.ActionDispatcher do
  @alias Exoforge.PluginRegistry

  def dispatch(service, action, payload, opts \\ []) do
    resolved_mod = resolve_module(service)

    result = run_action(resolved_mod, action, payload)

    result
  end

  defp run_action(nil, _action, _payload), do: {:error, :service_not_found}

  defp run_action(mod, action, payload) do
    try do
      apply(mod, :__execute_action__, [action, payload])
    rescue
      e -> {:error, {:plugin_crashed, Exception.message(e)}}
    catch
      :exit, reason -> {:error, {:plugin_exited, reason}}
    end
  end

  defp resolve_module(%Manifest{entry_point: mod}), do: mod

  defp resolve_module(mod) when is_atom(mod) do
    if function_exported?(mod, :__exoforge_plugin__?, 0) do
      mod
    else
      resolve_module(PluginRegistry.fetch_service(mod))
    end
  end

  defp resolve_module(_), do: nil
end
