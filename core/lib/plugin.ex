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
    {name, meta, args, guard} = extract_call_signature(call)

    if length(args) > 1 do
      raise CompileError,
        file: __CALLER__.file,
        line: Keyword.get(meta, :line, __CALLER__.line),
        description: "defaction #{name} must accept zero or one argument"
    end

    arity = length(args)
    line = Keyword.get(meta, :line, __CALLER__.line)
    mode = Keyword.get(opts, :mode, :sync)
    scope = Keyword.get(opts, :scope, :global)

    # ignore payload case no argument was passed to the defaction
    inner_args = if arity == 1, do: args, else: [quote(do: _payload)]
    clean_call = {:__execute_action__, meta, [name | inner_args]}

    inner_def =
      if guard do
        quote do: def(unquote(clean_call) when unquote(guard), do: unquote(block))
      else
        quote do: def(unquote(clean_call), do: unquote(block))
      end

    quote line: line do
      existing_actions = Module.get_attribute(__MODULE__, :exo_actions) || []
      is_first_clause? = not Enum.any?(existing_actions, &(&1.name == unquote(name)))

      if is_first_clause? do
        existing_map = Module.get_attribute(__MODULE__, :exo_actions_map)
        action_map = if is_map(existing_map) do
          existing_map
        else
          %{}
        end
        action_map = Map.put(action_map, unquote(name), %{
          name: unquote(name),
          mode: unquote(mode),
          scope: unquote(scope),
          arity: unquote(arity)
        })
        Module.put_attribute(__MODULE__, :exo_actions_map, action_map)
        @exo_actions MapSet.new(Map.values(action_map))

        # 1. Statically generate the public facade exactly once
        if unquote(arity) == 1 do
          def unquote(name)(payload) do
            Exoforge.ActionDispatcher.dispatch(__MODULE__, unquote(name), payload)
          end
        else
          def unquote(name)() do
            Exoforge.ActionDispatcher.dispatch(__MODULE__, unquote(name), %{})
          end
        end
      end

      @doc false
      unquote(inner_def)
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
    {event_id, meta, args, guard} = extract_event_signature(call, __CALLER__)
    line = Keyword.get(meta, :line, __CALLER__.line)

    if length(args) > 2 do
      raise CompileError,
        file: __CALLER__.file,
        line: line,
        description: "handle_event must accept zero, one, or two arguments"
    end

    payload_arg = if args == [], do: quote(do: _payload), else: hd(args)
    context_arg = if length(args) == 2, do: Enum.at(args, 1), else: quote(do: _context)

    clause = {:handle_inbound_event, meta, [event_id, payload_arg, context_arg]}
    clause = if guard, do: {:when, meta, [clause, guard]}, else: clause

    quote line: line do
      @exo_handlers unquote(event_id)

      @doc false
      def unquote(clause) do
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
      def handled_events, do: Enum.uniq(@exo_handlers)

      @doc false
      @impl Exoforge.Contracts.Plugin
      def init(manifest) do
        on_init(manifest)
      end

      @spec handle_inbound_event(atom(), map() | keyword(), map()) :: :ignored | term()
      def handle_inbound_event(_event, _payload, _context), do: :ignored

      @doc false
      def manifest do
        Exoforge.PluginRegistry.fetch_by_module(__MODULE__)
      end

      @doc false
      def __execute_action__(action, _payload) do
        {:error, {:action_not_found, action}}
      end

      # DEBUG UTILITIES
      @doc "Returns a list of all action names provided by this plugin."
      def __actions__, do: Module.get_attribute(__MODULE__, :exo_actions_map) || %{}
      @doc "Returns a list of all events emitted by this plugin."
      def __events__, do: Enum.map(@exo_events, & &1.name)
    end
  end

  ## ---- HELPER FUNCTIONS -----

  # ---- __using__

  ## ---- handle_event resolution ----

  # handle_event service.event(payload) when guard do ... end
  defp extract_event_signature({:when, meta, [call, guard]}, caller) do
    {event_id, call_meta, args, nil} = extract_event_signature(call, caller)
    {event_id, Keyword.merge(call_meta, meta), args, guard}
  end

  # handle_event Some.Alias do ... end
  defp extract_event_signature({:__aliases__, meta, _} = alias_ast, caller) do
    {Macro.expand(alias_ast, caller), meta, [], nil}
  end

  # handle_event service.event(payload) do ... end
  defp extract_event_signature({{:., _, [svc_ast, event]}, meta, args}, caller) when is_atom(event) do
    contract = expand_service!(svc_ast, caller)

    unless Enum.any?(contract_events(contract), fn e -> e.name == event end) do
      raise CompileError,
        file: caller.file,
        line: Keyword.get(meta, :line, caller.line),
        description: "Event #{event} is not defined in service #{inspect(contract)}"
    end

    {Module.concat([contract, Macro.camelize(to_string(event))]), meta, args || [], nil}
  end

  # handle_event event_name(payload) do ... end
  defp extract_event_signature({name, meta, args}, caller) when is_atom(name) do
    {resolve_event_id!(name, caller), meta, args || [], nil}
  end

  defp extract_event_signature(other, caller) do
    raise CompileError,
      file: caller.file,
      description: "Invalid handle_event target: #{Macro.to_string(other)}"
  end

  defp resolve_event_id!(name, caller) do
    case event_ids_for(name, caller) |> Enum.uniq() do
      [event_id] ->
        event_id

      [] ->
        Module.concat([caller.module, Macro.camelize(to_string(name))])

      many ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "Ambiguous event name #{name}. Found multiple event IDs: #{inspect(many)}. Qualify the event with the specific service or module."
    end
  end

  defp event_ids_for(name, caller) do
    for contract <- Module.get_attribute(caller.module, :exo_provides) || [],
        event <- contract_events(contract),
        event.name == name do
      Module.concat([contract, Macro.camelize(to_string(name))])
    end
  end

  defp contract_events(contract) do
    with {:ok, _} <- Code.ensure_compiled(contract) do
      if function_exported?(contract, :__service_metadata__, 0) do
        contract.__service_metadata__().events
      else
        []
      end
    else
      _ -> []
    end
  end

  defp expand_service!({svc, _, ctx}, caller) when is_atom(svc) and is_atom(ctx),
    do: hd(resolve_contract_modules([svc], caller))

  defp expand_service!({:__aliases__, _, _} = alias_ast, caller),
    do: hd(resolve_contract_modules([alias_ast], caller))

  defp resolve_contract_modules(provides_list, caller) do
    Enum.map(provides_list, fn
      {:__aliases__, _, _} = alias_ast ->
        Macro.expand(alias_ast, caller)

      {:{}, _, [:beam, beam_module]} when is_atom(beam_module) ->
        beam_module

      shorthand when is_atom(shorthand) ->
        Module.concat([Exoforge, Std, Services, Macro.camelize(to_string(shorthand))])
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
      Module.register_attribute(__MODULE__, :exo_actions_map, accumulate: true)
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
