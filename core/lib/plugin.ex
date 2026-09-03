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

        shorthand when is_atom(shorthand) ->
          contract_module = Module.concat([Exoforge, Contracts, Services, Macro.camelize(to_string(shorthand))])
          quote do: @behaviour(unquote(contract_module))
      end)

    quote location: :keep do
      @behaviour Exoforge.Contracts.Plugin
      import Exoforge.Plugin, only: [defaction: 2, defevent: 2]

      Module.register_attribute(__MODULE__, :exo_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :exo_events, accumulate: true)
      Module.register_attribute(__MODULE__, :manifest, accumulate: false)
      Module.register_attribute(__MODULE__, :infra, accumulate: false)

      @exo_provides unquote(implements_list)

      @manifest %{}
      @infra %{}
      @doc false
      def __exoforge_plugin__?, do: true
      @doc "lifecycle hook: callend when the plugin is first loaded"
      def on_init(_manifest), do: :ok
      defoverridable on_init: 1

      unquote(behavior_injections)
      @before_compile Exoforge.Plugin
    end
  end

  defmacro defaction({name, meta, args}, do: block) do
    spec_args = if args, do: Enum.map(args, fn _ -> quote do: term() end), else: []
    line = Keyword.get(meta, :line, __CALLER__.line)

    quote line: line do
      @exo_actions unquote(name)
      @spec unquote(name)(unquote_splicing(spec_args)) :: term()
      def unquote(name)(unquote_splicing(args)), do: unquote(block)
    end
  end

  defmacro defevent({name, meta, args}, do: block) do
    spec_args = if args, do: Enum.map(args, fn _ -> quote do: term() end), else: []
    line = Keyword.get(meta, :line, __CALLER__.line)

    quote line: line do
      @exo_events unquote(name)
      @spec unquote(name)(unquote_splicing(spec_args)) :: term()
      def unquote(name)(unquote_splicing(args)), do: unquote(block)
    end
  end

  defmacro __before_compile__(env) do
    manifest = Module.get_attribute(env.module, :manifest) || %{}
    infra = Module.get_attribute(env.module, :infra) || %{}

    # Manifest Validation
    valid_keys = Map.keys(struct(Exoforge.Domain.Manifest)) -- [:__struct__]
    provided_keys = Map.keys(manifest)
    invalid_keys = provided_keys -- valid_keys

    if invalid_keys != [] do
      raise CompileError,
        file: env.file,
        description: "Invalid keys in @manifest: #{inspect(invalid_keys)}. Allowed keys are: #{inspect(valid_keys)}"
    end

    if not is_map(infra) do
      raise CompileError,
        file: env.file,
        description: "@infra must be a map. Got: #{inspect(infra)}"
    end

    quote location: :keep do
      @doc false
      def manifest_data, do: unquote(Macro.escape(manifest))
      @doc false
      def infra_requirements, do: @infra
      @doc false
      def provides_contracts, do: @exo_provides

      @doc false
      @impl Exoforge.Contracts.Plugin
      def init(manifest) do
        on_init(manifest)

        {:ok,
         %{
           plugin: __MODULE__,
           actions: Enum.reverse(@exo_actions),
           events: Enum.reverse(@exo_events),
           provides: @exo_provides
         }}
      end

      @doc false
      def manifest do
        Exoforge.PluginRegistry.fetch_manifest(__MODULE__)
      end
    end
  end
end
