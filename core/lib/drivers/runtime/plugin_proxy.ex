defmodule Exoforge.Drivers.Runtime.PluginProxy do
  @moduledoc """
  Generates the module the kernel calls into for a non-Elixir plugin.

  Both the WASM reactor runner and the native (AOT process) runner register a generated proxy
  module as the manifest's `entry_point`, so `ActionDispatcher` stays runtime-agnostic and calls
  `__execute_action__/2` without knowing where the plugin actually runs.
  """
  alias Exoforge.Domain.Manifest

  @doc "Ensures the proxy module exists and returns it."
  def ensure(%Manifest{} = manifest, runner, module_name) do
    manifest_id = manifest.id
    provides = Map.get(manifest, :provides, [])
    events = Map.get(manifest, :events, [])
    services = Map.get(manifest, :services, [])

    service_metadata =
      case services do
        [first_svc | _] -> first_svc
        _ -> %{name: hd(provides || [manifest_id]), actions: [], events: [], resources: []}
      end

    unless Code.ensure_loaded?(module_name) do
      contents =
        quote do
          defmodule unquote(module_name) do
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
              unquote(runner).dispatch_event(unquote(manifest_id), event_key, payload, context)
            end

            def __execute_action__(action, payload) do
              unquote(runner).execute_action(unquote(manifest_id), action, payload)
            end
          end
        end

      Code.eval_quoted(contents)
    end

    module_name
  end
end
