defmodule Exoforge.Contracts.Service do
  @moduledoc "Provides a DSL for service specification"

  @valid_keys [:params, :returns, :errors, :payload, :mode, :scope, :topic]

  defmacro defservice(name_ast, do: block) do
    name = extract_name!(name_ast)
    service_alias = Macro.camelize(to_string(name))

    quote location: :keep do
      contract_module = Module.concat([__MODULE__, unquote(service_alias)])

      defmodule contract_module do
        @moduledoc "Contract definition for the #{unquote(name)} service."
        import Exoforge.Contracts.Service, only: [action: 2, event: 2]

        Module.register_attribute(__MODULE__, :exo_actions_meta, accumulate: true)
        Module.register_attribute(__MODULE__, :exo_events_meta, accumulate: true)

        unquote(block)
        @doc false
        def __service_name__, do: unquote(name)
        @doc false
        def __service_metadata__ do
          %{
            name: unquote(name),
            actions: @exo_actions_meta,
            events: @exo_events_meta
          }
        end
      end
    end
  end

  defmacro action(name, do: block) do
    meta = parse_block(block)

    mode = Map.get(meta, :mode) || :sync
    scope = Map.get(meta, :scope) || :global
    params = Map.get(meta, :params) || []
    returns = Map.get(meta, :returns)
    errors = Map.get(meta, :errors) || []

    success_type = if returns, do: quote(do: map()), else: quote(do: term())

    callback_return_type =
      case mode do
        :sync -> quote(do: {:ok, unquote(success_type)} | {:error, term()})
        :async -> quote(do: {:ok, Task.t()} | {:error, term()})
        :cast -> quote(do: :ok)
        _ -> raise CompileError, description: "Invalid action mode: #{mode}"
      end

    callback_ast =
      if params == [] do
        quote do: @callback(unquote(name)() :: unquote(callback_return_type))
      else
        quote do: @callback(unquote(name)(payload :: map()) :: unquote(callback_return_type))
      end

    quote location: :keep do
      doc_tuple = Module.get_attribute(__MODULE__, :doc) || {0, nil}
      Module.delete_attribute(__MODULE__, :doc)

      @exo_actions_meta %{
        name: unquote(name),
        doc: elem(doc_tuple, 1),
        mode: unquote(mode),
        scope: unquote(scope),
        params: unquote(Macro.escape(params)),
        returns: unquote(Macro.escape(returns)),
        errors: unquote(Macro.escape(errors))
      }

      unquote(callback_ast)
    end
  end

  defmacro event(name, do: block) do
    meta = parse_block(block)

    quote location: :keep do
      doc_tuple = Module.get_attribute(__MODULE__, :doc) || {0, nil}
      Module.delete_attribute(__MODULE__, :doc)

      @exo_events_meta %{
        name: unquote(name),
        doc: elem(doc_tuple, 1),
        payload: unquote(Macro.escape(meta.payload)),
        scope: unquote(meta.scope),
        topic: unquote(meta.topic)
      }
    end
  end

  defp extract_name!({identifier, _, context}) when is_atom(identifier) and is_atom(context), do: identifier
  defp extract_name!(atom) when is_atom(atom), do: atom
  defp extract_name!(_), do: raise(ArgumentError, "defservice expects a bare word or atom (e.g., database)")

  defp parse_block({:__block__, _, calls}), do: parse_block(calls)
  defp parse_block(calls) when not is_list(calls), do: parse_block([calls])

  defp parse_block(nodes) do
    defaults = %{params: [], mode: :sync, returns: nil, errors: [], payload: [], scope: :global, topic: nil}

    Enum.reduce(nodes, defaults, fn
      {key, _meta, [value]}, acc when key in @valid_keys -> Map.put(acc, key, value)
      _invalid_node, acc -> acc
    end)
  end
end
