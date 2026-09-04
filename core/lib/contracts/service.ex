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
          doc_data = Module.get_attribute(__MODULE__, :moduledoc)
          doc_string = if is_tuple(doc_data), do: elem(doc_data, 1), else: nil

          %{
            name: unquote(name),
            doc: doc_string,
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

    callback_return_type =
      case mode do
        :sync -> quote(do: {:ok, term()} | {:error, term()})
        :async -> quote(do: {:ok, Task.t()} | {:error, term()})
        :cast -> quote(do: :ok)
        _ -> raise CompileError, description: "Invalid action mode: #{mode}"
      end

    quote location: :keep do
      doc_tuple = Module.get_attribute(__MODULE__, :doc) || {0, nil}
      Module.delete_attribute(__MODULE__, :doc)

      @exo_actions_meta %{
        name: unquote(name),
        doc: elem(doc_tuple, 1),
        mode: unquote(mode),
        params: unquote(Macro.escape(meta.params)),
        returns: unquote(Macro.escape(meta.returns)),
        errors: unquote(Macro.escape(meta.errors))
      }

      @callback unquote(name)(payload :: map() | keyword()) :: unquote(callback_return_type)
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
    defaults = %{params: [], mode: :sync, returns: nil, errors: [], payload: [], scope: :server, topic: nil}

    Enum.reduce(nodes, defaults, fn
      {key, _meta, [value]}, acc when key in @valid_keys -> Map.put(acc, key, value)
      _invalid_node, acc -> acc
    end)
  end
end
