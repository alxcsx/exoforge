defmodule Exoforge.Resource do
  @moduledoc """
  Defines an Exoforge Resource module.

  Provides a clean, typed struct, schema introspection, and metadata for Studio integration.

  ## Example

      defmodule MyPlugin.Player do
        use Exoforge.Resource,
          primary_key: :player_id,
          drawer: [:overview, :attributes, :inventory]

        column :player_id, :string, sortable: true
        column :name, :string, filterable: true
        column :level, :integer, default: 1, sortable: true
        column :status, :string, default: "active", badge: true
      end

  The resulting module provides:
  - `%MyPlugin.Player{player_id: nil, name: nil, level: 1, status: "active"}`
  - `MyPlugin.Player.__resource_metadata__/0`
  - `MyPlugin.Player.new/1`
  - `MyPlugin.Player.to_map/1`
  """

  defmacro __using__(opts) do
    quote location: :keep do
      import Exoforge.Resource,
        only: [column: 2, column: 3, primary_key: 1, drawer: 1, doc: 1, actions: 1]

      Module.register_attribute(__MODULE__, :exo_columns, accumulate: true)
      @exo_primary_key Keyword.get(unquote(opts), :primary_key, :id)
      @exo_drawer Keyword.get(unquote(opts), :drawer, [:overview, :attributes])
      @exo_resource_name Keyword.get(unquote(opts), :name, nil)
      @exo_actions Keyword.get(unquote(opts), :actions, [])

      @before_compile Exoforge.Resource
    end
  end

  defmacro primary_key(key) do
    quote do
      @exo_primary_key unquote(key)
    end
  end

  defmacro drawer(tabs) do
    quote do
      @exo_drawer unquote(tabs)
    end
  end

  defmacro actions(acts) do
    quote do
      @exo_actions unquote(acts)
    end
  end

  defmacro doc(str) do
    quote do
      @doc unquote(str)
    end
  end

  defmacro column(name, type, opts \\ []) do
    quote do
      col = %{
        name: unquote(name),
        type: unquote(type),
        label: Keyword.get(unquote(opts), :label, Exoforge.Resource.default_label(unquote(name))),
        sortable: Keyword.get(unquote(opts), :sortable, false),
        filterable: Keyword.get(unquote(opts), :filterable, false),
        badge: Keyword.get(unquote(opts), :badge, false),
        default: Keyword.get(unquote(opts), :default, nil)
      }

      @exo_columns col
    end
  end

  defmacro __before_compile__(env) do
    columns =
      Module.get_attribute(env.module, :exo_columns, [])
      |> Enum.reverse()

    primary_key = Module.get_attribute(env.module, :exo_primary_key) || :id
    drawer = Module.get_attribute(env.module, :exo_drawer) || [:overview, :attributes]
    actions = Module.get_attribute(env.module, :exo_actions) || []

    explicit_name = Module.get_attribute(env.module, :exo_resource_name)
    resource_name = explicit_name || default_resource_name(env.module)

    struct_fields =
      Enum.map(columns, fn col ->
        {col.name, col.default}
      end)

    quote do
      defstruct unquote(Macro.escape(struct_fields))

      @doc "Returns the metadata for this resource."
      def __resource_metadata__ do
        %{
          name: unquote(resource_name),
          primary_key: unquote(primary_key),
          drawer: unquote(drawer),
          actions: unquote(actions),
          columns: unquote(Macro.escape(columns))
        }
      end

      @doc "Constructs a new struct from a map or keyword list."
      def new(attrs \\ %{})

      def new(%__MODULE__{} = struct), do: struct

      def new(attrs) when is_map(attrs) do
        fields =
          Enum.reduce(attrs, %{}, fn {k, v}, acc ->
            key = Enum.find(Map.keys(%__MODULE__{}), &(to_string(&1) == to_string(k)))
            if key, do: Map.put(acc, key, v), else: acc
          end)

        struct(__MODULE__, fields)
      end

      def new(attrs) when is_list(attrs) do
        struct(__MODULE__, attrs)
      end

      @doc "Converts the struct into a plain map."
      def to_map(%__MODULE__{} = s) do
        Map.from_struct(s)
      end
    end
  end

  @doc false
  def default_label(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @doc false
  def default_resource_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
