defmodule Exoforge.Plugin do
  @moduledoc "Public DSL for creating Exoforge plugins."

  defmacro __using__(opts) do
    provides_ast = Keyword.get(opts, :provides, [])
    provides_list = if is_list(provides_ast), do: provides_ast, else: [provides_ast]
    contract_modules = resolve_contract_modules(provides_list, __CALLER__)

    quote location: :keep do
      @behaviour Exoforge.Contracts.Plugin
      import Exoforge.Plugin,
        only: [
          defaction: 2,
          defaction: 3,
          defevent: 1,
          defevent: 2,
          handle_event: 2
        ]

      unquote(setup_attributes(contract_modules))
      unquote(inject_behaviors(contract_modules))
      unquote(inject_events(contract_modules))
      unquote(setup_lifecycle())

      @before_compile Exoforge.Plugin
    end
  end

  defmacro defaction(call, opts \\ [], do: block) do
    {name, meta, args, _guard} = extract_call_signature(call)
    param_names = extract_param_names(args)

    line = Keyword.get(meta, :line, __CALLER__.line)
    mode = Keyword.get(opts, :mode, :sync)
    scope = Keyword.get(opts, :scope, :global)
    arity = length(args)
    spec_args = Enum.map(args, fn _ -> quote do: term() end)

    quote line: line do
      existing_actions = Module.get_attribute(__MODULE__, :exo_actions) || []

      is_first_clause? =
        not Enum.any?(existing_actions, fn a -> a.name == unquote(name) and a.arity == unquote(arity) end)

      if is_first_clause? do
        @exo_actions %{
          name: unquote(name),
          mode: unquote(mode),
          scope: unquote(scope),
          params: unquote(param_names),
          arity: unquote(arity)
        }

        @spec unquote(name)(unquote_splicing(spec_args)) :: term()
      end

      def unquote(call), do: unquote(block)
    end
  end

  defmacro defevent(call, opts \\ []) do
    {name, meta, args, guard} = extract_call_signature(call)
    param_names = extract_param_names(args)
    line = Keyword.get(meta, :line, __CALLER__.line)

    base_module_ast = Keyword.get(opts, :module, __CALLER__.module)
    base_module = Macro.expand(base_module_ast, __CALLER__)
    event_alias = Macro.camelize(to_string(name))
    event_full_id = Module.concat([base_module, event_alias])

    scope = Keyword.get(opts, :scope, :server)
    topic_key = Keyword.get(opts, :topic)

    topic_val_ast =
      if topic_key in param_names, do: Macro.var(topic_key, nil), else: :global

    payload_ast = {:%{}, [], Enum.map(param_names, fn key -> {key, Macro.var(key, nil)} end)}
    spec_args = Enum.map(args, fn _ -> quote do: term() end)
    clean_call = {name, meta, args}

    body_ast =
      quote do
        payload = unquote(payload_ast)
        dispatch_opts = [topic: unquote(topic_val_ast), scope: unquote(scope), source: __MODULE__]

        Exoforge.EventDispatcher.broadcast(unquote(event_full_id), payload, dispatch_opts)
        {:ok, unquote(event_full_id)}
      end

    def_ast =
      if guard do
        quote do: def(unquote(clean_call) when unquote(guard), do: unquote(body_ast))
      else
        quote do: def(unquote(clean_call), do: unquote(body_ast))
      end

    quote line: line do
      @exo_events %{
        id: unquote(event_full_id),
        name: unquote(name),
        arity: unquote(length(args)),
        scope: unquote(scope),
        topic_key: unquote(topic_key)
      }

      @spec unquote(name)(unquote_splicing(spec_args)) :: {:ok, unquote(event_full_id)}
      @doc false
      unquote(def_ast)
    end
  end

  defmacro handle_event(call, do: block) do
    {name, meta, args, guard} = extract_call_signature(call)
    line = Keyword.get(meta, :line, __CALLER__.line)
    event_id = Macro.expand(name, __CALLER__)

    safe_payload_arg =
      case args do
        [] -> quote do: _payload
        [payload_ast] -> payload_ast
        _ -> raise CompileError, description: "handle_event #{name} must accept exactly zero or one argument"
      end

    clean_handler_call = {:handle_inbound_event, meta, [name, safe_payload_arg]}

    handler_call =
      if guard do
        {:when, meta, [clean_handler_call, guard]}
      else
        clean_handler_call
      end

    quote line: line do
      @exo_handlers unquote(event_id)

      @doc false
      def unquote(handler_call) do
        unquote(block)
      end
    end
  end

  defmacro __before_compile__(env) do
    manifest = Module.get_attribute(env.module, :manifest) || %{}
    infra = Module.get_attribute(env.module, :infra) || %{}

    if not is_map(infra) do
      raise CompileError,
        file: env.file,
        description: "@infra must be a map. Got: #{inspect(infra)}"
    end

    quote location: :keep do
      @doc false
      def manifest_overrides, do: unquote(Macro.escape(manifest))
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

      @spec handle_inbound_event(atom(), map() | keyword()) :: :ignored | term()
      def handle_inbound_event(_event, _payload), do: :ignored

      @doc false
      def manifest do
        Exoforge.PluginRegistry.fetch_manifest(__MODULE__)
      end

      # DEBUG UTILITIES
      @doc "Returns a list of all action names provided by this plugin."
      def __actions__, do: Enum.map(@exo_actions, & &1.name)
      @doc "Returns a list of all events emitted by this plugin."
      def __events__, do: Enum.map(@exo_events, & &1.name)
      @doc "Returns a list of all events this plugin handles."
      def __handlers__, do: @exo_handlers
    end
  end

  ## ---- HELPER FUNCTIONS -----

  # ---- __using__

  defp resolve_contract_modules(provides_list, caller) do
    Enum.map(provides_list, fn
      {:__aliases__, _, _} = alias_ast ->
        Macro.expand(alias_ast, caller)

      {:{}, _, [:beam, beam_module]} when is_atom(beam_module) ->
        beam_module

      shorthand when is_atom(shorthand) ->
        Module.concat([Exoforge, Contracts, Services, Macro.camelize(to_string(shorthand))])
    end)
  end

  defp inject_behaviors(contract_modules) do
    Enum.map(contract_modules, fn mod -> quote do: @behaviour(unquote(mod)) end)
  end

  defp inject_events(contract_modules) do
    Enum.flat_map(contract_modules, fn contract_module ->
      Code.ensure_compiled(contract_module)

      if function_exported?(contract_module, :__service_metadata__, 0) do
        metadata = contract_module.__service_metadata__()

        Enum.map(metadata.events, fn event ->
          param_vars = Enum.map(event.payload, fn {key, _type} -> Macro.var(key, nil) end)
          call_ast = {event.name, [], param_vars}

          final_ast =
            quote do
              Exoforge.Plugin.defevent(
                unquote(call_ast),
                module: unquote(contract_module),
                scope: unquote(event.scope || :server),
                topic: unquote(event.topic)
              )
            end

          final_ast
        end)
      else
        []
      end
    end)
  end

  defp setup_attributes(contract_modules) do
    quote do
      Module.register_attribute(__MODULE__, :exo_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :exo_events, accumulate: true)
      Module.register_attribute(__MODULE__, :exo_handlers, accumulate: true)

      Module.register_attribute(__MODULE__, :manifest, accumulate: false)
      Module.register_attribute(__MODULE__, :infra, accumulate: false)

      @exo_provides unquote(contract_modules)
      @manifest %{}
      @infra %{}
    end
  end

  defp setup_lifecycle do
    quote do
      @doc false
      def __exoforge_plugin__?, do: true
      @doc "Returns the name of the supervisor module for this plugin."
      def supervisor(), do: Module.concat([__MODULE__, Supervisor])
      @doc "Lifecycle hook: called when the plugin is first loaded."
      def on_init(_manifest), do: :ok
      @doc "Lifecycle hook: inject custom children into the plugin supervision tree."
      def children(), do: []

      defoverridable on_init: 1, children: 0
    end
  end

  # ---- defaction / defevent

  defp extract_call_signature({:when, _, [call, guard]}) do
    {name, meta, args, _nil_guard} = extract_call_signature(call)
    {name, meta, args, guard}
  end

  defp extract_call_signature({name, meta, args}) do
    {name, meta, args || [], nil}
  end

  defp extract_param_names(args) do
    Enum.map(args, fn
      {:\\, _, [{var_name, _, _}, _default]} when is_atom(var_name) -> var_name
      {var_name, _, _} when is_atom(var_name) -> var_name
      _ -> :arg
    end)
  end
end
