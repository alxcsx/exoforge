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
        import Exoforge.Contracts.Service,
          only: [
            action: 2,
            event: 2,
            resource: 1,
            resource: 2,
            defresource: 2,
            defresource: 3
          ]

        Module.register_attribute(__MODULE__, :exo_actions_meta, accumulate: true)
        Module.register_attribute(__MODULE__, :exo_events_meta, accumulate: true)
        Module.register_attribute(__MODULE__, :exo_resources_meta, accumulate: true)

        unquote(block)
        @doc false
        def __service_name__, do: unquote(name)
        @doc false
        def __service_metadata__ do
          %{
            name: unquote(name),
            actions: Enum.reverse(@exo_actions_meta),
            events: Enum.reverse(@exo_events_meta),
            resources: Enum.reverse(@exo_resources_meta)
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

  @doc """
  Declares a typed resource struct module inside a service contract and registers it in the service metadata.
  """
  defmacro defresource(name_ast, opts_or_block)

  defmacro defresource(name_ast, do: block) do
    quote location: :keep do
      Exoforge.Contracts.Service.defresource(unquote(name_ast), [], do: unquote(block))
    end
  end

  defmacro defresource(name_ast, opts) when is_list(opts) do
    quote location: :keep do
      doc_tuple = Module.get_attribute(__MODULE__, :doc) || {0, nil}
      Module.delete_attribute(__MODULE__, :doc)

      sub_module = Module.concat(__MODULE__, unquote(name_ast))

      defmodule sub_module do
        use Exoforge.Resource, unquote(opts)
      end

      meta =
        sub_module.__resource_metadata__()
        |> Map.put(:doc, elem(doc_tuple, 1))

      @exo_resources_meta meta
    end
  end

  defmacro defresource(name_ast, opts, do: block) do
    quote location: :keep do
      doc_tuple = Module.get_attribute(__MODULE__, :doc) || {0, nil}
      Module.delete_attribute(__MODULE__, :doc)

      sub_module = Module.concat(__MODULE__, unquote(name_ast))

      defmodule sub_module do
        use Exoforge.Resource, unquote(opts)
        unquote(block)
      end

      meta =
        sub_module.__resource_metadata__()
        |> Map.put(:doc, elem(doc_tuple, 1))

      @exo_resources_meta meta
    end
  end

  @doc """
  Declares a resource either by referencing an existing module implementing `Exoforge.Resource`,
  or using an inline specification block.
  """
  defmacro resource(target, opts_or_block \\ [])

  defmacro resource(name, do: block) do
    parsed = parse_resource_block(block)

    quote location: :keep do
      doc_tuple = Module.get_attribute(__MODULE__, :doc) || {0, nil}
      Module.delete_attribute(__MODULE__, :doc)

      @exo_resources_meta %{
        name: unquote(name),
        doc: elem(doc_tuple, 1) || unquote(parsed[:doc]),
        primary_key: unquote(parsed[:primary_key]),
        columns: unquote(Macro.escape(parsed[:columns])),
        drawer: unquote(Macro.escape(parsed[:drawer])),
        actions: unquote(Macro.escape(parsed[:actions]))
      }
    end
  end

  defmacro resource(target, opts) when is_list(opts) do
    quote location: :keep do
      mod = unquote(target)

      meta =
        cond do
          is_atom(mod) and Code.ensure_loaded?(mod) and
              function_exported?(mod, :__resource_metadata__, 0) ->
            res = mod.__resource_metadata__()
            extra_actions = Keyword.get(unquote(opts), :actions, [])
            actions = if extra_actions != [], do: extra_actions, else: res.actions
            name = Keyword.get(unquote(opts), :name, res.name)
            %{res | name: name, actions: actions}

          true ->
            res_name =
              Keyword.get(
                unquote(opts),
                :name,
                Exoforge.Resource.default_resource_name(mod)
              )

            %{
              name: res_name,
              primary_key: Keyword.get(unquote(opts), :primary_key, :id),
              columns: [],
              drawer: Keyword.get(unquote(opts), :drawer, [:overview, :attributes]),
              actions: Keyword.get(unquote(opts), :actions, [])
            }
        end

      @exo_resources_meta meta
    end
  end

  defp parse_resource_block({:__block__, _, calls}) do
    parse_resource_calls(calls, default_resource_meta())
  end

  defp parse_resource_block(single_call) do
    parse_resource_calls([single_call], default_resource_meta())
  end

  defp default_resource_meta do
    %{
      primary_key: :id,
      columns: [],
      drawer: [:overview, :attributes],
      actions: [],
      doc: nil
    }
  end

  defp parse_resource_calls([], acc) do
    %{acc | columns: Enum.reverse(acc.columns)}
  end

  defp parse_resource_calls([node | rest], acc) do
    acc =
      case node do
        {:primary_key, _, [pk]} when is_atom(pk) ->
          Map.put(acc, :primary_key, pk)

        {:column, _, [col_name, type]} when is_atom(col_name) and is_atom(type) ->
          col = %{
            name: col_name,
            type: type,
            label: default_column_label(col_name),
            sortable: false,
            filterable: false,
            badge: false
          }

          Map.update!(acc, :columns, &[col | &1])

        {:column, _, [col_name, type, opts]} when is_atom(col_name) and is_atom(type) ->
          opts_map = if Keyword.keyword?(opts), do: Map.new(opts), else: %{}

          col = %{
            name: col_name,
            type: type,
            label: Map.get(opts_map, :label, default_column_label(col_name)),
            sortable: Map.get(opts_map, :sortable, false),
            filterable: Map.get(opts_map, :filterable, false),
            badge: Map.get(opts_map, :badge, false)
          }

          col = Map.merge(opts_map, col)
          Map.update!(acc, :columns, &[col | &1])

        {:drawer, _, [tabs]} when is_list(tabs) ->
          Map.put(acc, :drawer, tabs)

        {:drawer_tabs, _, [tabs]} when is_list(tabs) ->
          Map.put(acc, :drawer, tabs)

        {:actions, _, [actions]} when is_list(actions) ->
          Map.put(acc, :actions, actions)

        {:doc, _, [doc_str]} when is_binary(doc_str) ->
          Map.put(acc, :doc, doc_str)

        _other ->
          acc
      end

    parse_resource_calls(rest, acc)
  end

  defp default_column_label(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
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
