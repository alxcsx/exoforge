defmodule Exoforge.Std.Dashboard.InputTypes do
  @moduledoc """
  Form input types the Studio renders from metadata instead of from code.

  A contract parameter or resource column says what it wants to be edited with; the Studio
  resolves the widget in this order:

    1. an inline `input:` spec on the parameter/column,
    2. an id registered in any manifest's `input_types` — a plugin contributing its own,
    3. the builtin set (the ids the Studio always knows: `color`, `textarea`, `checkbox`,
       `select`, `range`, `email`, `url`, `tel`, `password`, `date`, `time`, `datetime_local`,
       `json`, `list`),
    4. nothing — the standard rendering for `:integer/:boolean/:map/...` applies, unchanged.

  A spec is declarative — pure data — which is what makes it usable from any plugin, including a
  native C# one whose manifest any language can author:

      %{type: "input", attributes: %{"type" => "color"}}
      %{type: "select", options: ["easy", "medium", "hard"]}
      %{type: "textarea", attributes: %{"rows" => "3"}}

  An in-process plugin may instead contribute a widget component:

      @manifest %{input_types: %{vertex_colour: MyApp.VertexColourPicker}}

  where `MyApp.VertexColourPicker` is an HEEx functional component implementing
  `Exoforge.Std.Dashboard.Input`: `render/1` — the widget, given
  `%{name:, value:, class:, readonly:}` — and `cast/2` — the submitted form string to
  `{:ok, value} | {:error, message}`.

  Attribute conventions: `[type: :string, input: :color]` — the `input:` id selects the widget
  while the `type` stays the contract's own; a non-scalar `type` alone
  (`params(team_colour: :color)`) also resolves, so a plugin's domain vocabulary can be its input
  vocabulary.
  """
  use Phoenix.Component
  alias Exoforge.PluginRegistry

  # The widgets the Studio always ships. Data only: every one is a plain HTML input — the
  # browser is the engine, no JavaScript required.
  @builtin [
    {"text", %{type: "input", attributes: %{"type" => "text"}, parse: :none, options: []}},
    {"color", %{type: "input", attributes: %{"type" => "color"}, parse: :none, options: []}},
    {"email", %{type: "input", attributes: %{"type" => "email"}, parse: :none, options: []}},
    {"url", %{type: "input", attributes: %{"type" => "url"}, parse: :none, options: []}},
    {"tel", %{type: "input", attributes: %{"type" => "tel"}, parse: :none, options: []}},
    {"password", %{type: "input", attributes: %{"type" => "password"}, parse: :none, options: []}},
    {"range", %{type: "input", attributes: %{"type" => "range"}, parse: :none, options: []}},
    {"date", %{type: "input", attributes: %{"type" => "date"}, parse: :none, options: []}},
    {"time", %{type: "input", attributes: %{"type" => "time"}, parse: :none, options: []}},
    {"datetime_local", %{type: "input", attributes: %{"type" => "datetime-local"}, parse: :none, options: []}},
    {"textarea", %{type: "textarea", attributes: %{"rows" => "3", "type" => "textarea"}, parse: :none, options: []}},
    {"json", %{type: "textarea", attributes: %{"rows" => "3"}, parse: :json, options: []}},
    {"list", %{type: "textarea", attributes: %{"rows" => "2"}, parse: :list, options: []}},
    {"checkbox", %{type: "checkbox", attributes: %{"type" => "checkbox"}, parse: :boolean, options: []}},
    {"select", %{type: "select", attributes: %{}, parse: :none, options: []}}
  ]
  |> Map.new()

  # The scalar types with standard widgets. Anything a contract declares outside this set is
  # treated as an input-type id.
  @scalar_types ~w(integer float boolean map string term list atom)a
  @scalar_strings Enum.map(@scalar_types, &to_string/1)

  ## ---- resolution ---------------------------------------------------------------

  @doc """
  Resolves the custom input spec for a parameter or column definition, or nil when the standard
  rendering applies. Order: an inline `input:` spec, then an id — the declared `type` when it is
  not a scalar.
  """
  def resolve(meta) when is_map(meta) do
    cond do
      inline = fetch(meta, :input) -> normalize(inline)
      id = self_named_id(meta) -> registered_spec(id)
      true -> nil
    end
  end

  defp self_named_id(meta) do
    case fetch(meta, :type) do
      nil -> nil
      type when type in @scalar_types -> nil
      type when is_binary(type) and type in @scalar_strings -> nil
      other -> to_string(other)
    end
  end

  @doc "The spec registered for `id` across every manifest's `input_types`, or that id's builtin."
  def registered_spec(id) do
    id = to_string(id)

    from_manifests(id) || Map.get(@builtin, id)
  end

  defp from_manifests(id) do
    PluginRegistry.all_manifests()
    |> Enum.flat_map(fn manifest ->
      manifest
      |> Map.get(:input_types, %{})
      |> Enum.filter(fn {key, _} -> to_string(key) == id end)
      |> Enum.map(fn {_, spec_or_module} -> normalize(spec_or_module) end)
    end)
    |> List.first()
  end

  @doc """
  Normalizes one spec, in any shape a plugin may write it: a data map, a widget module (in
  process, or its `"Elixir.MyApp.Widget"` manifest encoding), or an input id (`:color`) — which
  becomes that id's spec, or a bare HTML input element of that type.
  """
  def normalize(spec) when is_map(spec) do
    cond do
      module = module_in_spec(spec) ->
        %{type: "module", module: module, parse: :none, options: [], attributes: %{}}

      true ->
        %{
          type: to_string(fetch(spec, :type) || fetch(spec, :widget) || fetch(spec, :element, "input")),
          parse: safe_parse(fetch(spec, :parse)),
          options: to_strings(fetch(spec, :options) || fetch(spec, :choices) || []),
          attributes: attributes_of(spec)
        }
    end
  end

  def normalize(spec) when is_atom(spec) do
    if module_widget?(spec) do
      %{type: "module", module: spec, parse: :none, options: [], attributes: %{}}
    else
      builtin_or_element(spec)
    end
  end

  # A manifest frowns at module atoms: sanitize turned them into "Elixir.MyApp.Widget" strings.
  def normalize("Elixir." <> _ = encoded),
    do: %{type: "module", module: module_from_string(encoded), parse: :none, options: [], attributes: %{}}

  def normalize(spec) when is_binary(spec), do: builtin_or_element(spec)

  def normalize(_), do: nil

  defp module_in_spec(spec) do
    # `module_widget?/1` cannot run inside a guard, so the candidates are matched loosely and
    # the check happens after.
    candidates = [fetch(spec, :module), fetch(spec, :widget), fetch(spec, :type)]

    Enum.find(candidates, fn candidate -> module_widget?(candidate) end)
  end

  defp module_widget?(atom) when is_atom(atom), do: function_exported?(atom, :render, 1)

  defp module_widget?(_), do: false

  defp module_from_string(encoded) do
    String.to_existing_atom(encoded)
  rescue
    _ -> nil
  end

  defp builtin_or_element(id) do
    id = to_string(id)
    Map.get(@builtin, id) || %{type: "input", attributes: %{"type" => id}, parse: :none, options: []}
  end

  defp attributes_of(spec) do
    attrs = fetch(spec, :attributes) || fetch(spec, :attrs) || %{}

    Map.new(attrs, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  @parse_hints [:none, :integer, :float, :boolean, :json, :list]
  defp safe_parse(nil), do: :none
  defp safe_parse(hint) when hint in @parse_hints, do: hint

  # Manifests may hand anything; an unknown atom name never becomes one.
  defp safe_parse(hint) when is_binary(hint) do
    case String.to_existing_atom(hint) do
      existing when existing in @parse_hints -> existing
      _ -> :none
    end
  rescue
    _ -> :none
  end

  defp safe_parse(_), do: :none

  defp to_strings(options) when is_list(options), do: Enum.map(options, &to_string/1)
  defp to_strings(_), do: []

  defp fetch(map, key), do: fetch(map, key, nil)

  defp fetch(map, key, default) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key)) || default
  end

  defp fetch(_, _, default), do: default

  ## ---- casting ---------------------------------------------------------------

  @doc "Turns a submitted form string into the value a resolved `spec` declares."
  def cast(value, %{module: module}) when is_atom(module) do
    module.cast(value, %{})
  rescue
    e -> {:error, "widget cast failed: #{Exception.message(e)}"}
  end

  def cast(value, %{parse: :json}), do: parse_json(value)
  def cast(value, %{parse: :list}), do: {:ok, to_list(value)}
  def cast(value, %{parse: :integer}), do: {:ok, parse_integer(value)}
  def cast(value, %{parse: :float}), do: {:ok, parse_float(value)}
  def cast(value, %{parse: :boolean}), do: {:ok, to_string(value) in ["true", "1", "on", "yes"]}
  def cast(value, _spec), do: {:ok, value}

  ## ---- rendering ---------------------------------------------------------------

  attr :spec, :map, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :class, :string, default: nil
  attr :readonly, :boolean, default: false

  @doc "Renders one custom input from a resolved spec. The sites render the standard types themselves."
  def widget(assigns) do
    case assigns.spec do
      %{type: "module", module: module} when is_atom(module) ->
        module.render(%{
          name: assigns.name,
          value: assigns.value,
          class: input_class(assigns.class),
          readonly: assigns.readonly
        })

      %{type: "textarea"} = spec ->
        assigns
        |> assign(:attrs, attributes(assigns, spec, keep_value?: false))
        |> render_textarea()

      %{type: "select"} = spec ->
        assigns
        |> assign(:attrs, attributes(assigns, spec, keep_value?: true))
        |> assign(:options, Map.get(spec, :options, []))
        |> render_select()

      %{type: "checkbox"} ->
        assigns
        |> assign(:checked, assigns.value in ["true", "1", "on", true])
        |> render_checkbox()

      spec ->
        assigns
        |> assign(:attrs, attributes(assigns, spec, keep_value?: true))
        |> render_input()
    end
  end

  defp render_input(assigns) do
    ~H"""
    <input {@attrs} />
    """
  end

  defp render_textarea(assigns) do
    ~H"""
    <textarea {@attrs}><%= @value %></textarea>
    """
  end

  defp render_select(assigns) do
    ~H"""
    <select {@attrs}>
      <%= for option <- @options do %>
        <option value={option} selected={to_string(@value) == option}><%= option %></option>
      <% end %>
    </select>
    """
  end

  defp render_checkbox(assigns) do
    # The hidden false keeps an unchecked box posting the falsy value, as booleans do elsewhere.
    ~H"""
    <input type="hidden" name={@name} value="false" />
    <input type="checkbox" name={@name} value="true" checked={@checked} class={@class} />
    """
  end

  # The frame's identity (name, value) and the site's CSS win over anything a spec declares, so a
  # widget cannot silently drop its value or break out of the form's styling.
  defp attributes(assigns, spec, keep_value?: keep_value?) do
    (spec[:attributes] || %{})
    |> Map.merge(%{"class" => input_class(assigns.class)})
    |> Map.put("name", assigns.name)
    |> then(fn attrs -> if keep_value?, do: Map.put(attrs, "value", assigns.value), else: attrs end)
    |> map_put("readonly", if(assigns.readonly, do: "readonly"))
  end

  defp map_put(map, _key, nil), do: map
  defp map_put(map, key, value), do: Map.put(map, key, to_string(value))

  defp input_class(nil),
    do:
      "rounded-xl border border-gray-200 bg-gray-50 text-xs font-mono text-gray-800 px-2 py-1.5 focus:border-purple-400 focus:bg-white focus:outline-none"

  defp input_class(class), do: class

  ## ---- casting helpers ---------------------------------------------------------

  defp parse_json(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, parsed} -> {:ok, parsed}
      _ -> {:error, "not valid JSON"}
    end
  end

  defp parse_json(value), do: {:ok, value}

  defp to_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> list
      _ -> value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp to_list(value) when is_list(value), do: value
  defp to_list(value), do: [value]

  defp parse_integer(value) do
    case Integer.parse(String.trim(to_string(value))) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_float(value) do
    case Float.parse(String.trim(to_string(value))) do
      {float, _} -> float
      :error -> 0.0
    end
  end
end
