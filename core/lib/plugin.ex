defmodule Exoforge.Plugin do
  @moduledoc "Public DSL for creating Exoforge plugins."

  defmacro __using__(opts) do
    implements_ast = Keyword.get(opts, :implements, Keyword.get(opts, :provides, []))
    implements_list = if is_list(implements_ast), do: implements_ast, else: [implements_ast]

    behavior_injections =
      Enum.map(implements_list, fn
        {:__aliases__, _, _} = alias_ast ->
          contract_module = Macro.expand(alias_ast, __CALLER__)
          quote do: @behaviour(unquote(contract_module))

        {:{}, _, [:beam, beam_module]} when is_atom(beam_module) ->
          quote do: @behaviour(unquote(beam_module))

        {:beam, beam_module} when is_atom(beam_module) ->
          quote do: @behaviour(unquote(beam_module))

        shorthand when is_atom(shorthand) ->
          contract_module = Module.concat([Exoforge, Contracts, Services, Macro.camelize(to_string(shorthand))])
          quote do: @behaviour(unquote(contract_module))
      end)

    quote do
      @behaviour Exoforge.Contracts.Plugin
      import Exoforge.Plugin, only: [defaction: 2, defevent: 2]
      Module.register_attribute(__MODULE__, :exo_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :exo_events, accumulate: true)
      Module.register_attribute(__MODULE__, :manifest, accumulate: false)
      Module.register_attribute(__MODULE__, :infra, accumulate: false)

      @exo_provides unquote(implements_list)

      @manifest %{}
      @infra %{}

      def __exoforge_plugin__?, do: true
      def on_init(_manifest), do: :ok
      defoverridable on_init: 1

      unquote(behavior_injections)
      @before_compile Exoforge.Plugin
    end
  end

  defmacro defaction({name, _meta, args}, do: block) do
    quote do
      @exo_actions unquote(name)
      def unquote(name)(unquote_splicing(args)), do: unquote(block)
    end
  end

  defmacro defevent({name, _meta, args}, do: block) do
    quote do
      @exo_events unquote(name)
      def unquote(name)(unquote_splicing(args)), do: unquote(block)
    end
  end

  defmacro __before_compile__(env) do
    manifest = Module.get_attribute(env.module, :manifest)

    quote do
      def manifest_data, do: unquote(Macro.escape(manifest))
      def infra_requirements, do: @infra
      def provides_contracts, do: @exo_provides

      @impl Exoforge.Contracts.Plugin
      def init(manifest) do
        on_init(manifest)

        {:ok,
         %{
           plugin: __MODULE__,
           actions: @exo_actions,
           events: @exo_events,
           provides: @exo_provides
         }}
      end

      def manifest do
        Exoforge.PluginRegistry.fetch_manifest(__MODULE__)
      end
    end
  end
end
