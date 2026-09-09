defmodule Exoforge.ActionDispatcher do
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  def dispatch(service, action, payload, opts \\ []) do
    context = Keyword.get(opts, :context, :global)
    resolved_mod = resolve_module(service, context)

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

  defp resolve_module(%Manifest{entry_point: mod}, _), do: mod

  defp resolve_module(mod, ctx) when is_atom(mod) do
    if function_exported?(mod, :__exoforge_plugin__?, 0) do
      mod
    else
      resolve_module(PluginRegistry.fetch_service(mod, ctx), ctx)
    end
  end

  defp resolve_module(_, _), do: nil
end
