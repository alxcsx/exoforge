defmodule Exoforge.Std.Dashboard.ResourceForms do
  @moduledoc """
  What the Studio's Data tab needs to know about a resource: its columns, the form defaults for
  them, and how submitted form strings become a typed row.

  Pure — no socket, no LiveView — for the same reason `ActionForms` is: the interesting part is the
  type coercion, and testing it should not mean driving a UI.

  A resource's schema comes from the manifest, so the form a developer sees is the contract their
  plugin declared. Adding a column to a record changes the form, and nothing here has to know what
  the column means.
  """

  alias Exoforge.Std.Dashboard.ActionForms

  @type column :: %{
          key: atom() | String.t(),
          label: String.t(),
          type: atom(),
          badge: boolean(),
          role: String.t() | nil,
          primary_key: boolean()
        }

  @doc """
  The columns of a resource, in the order the plugin declared them.

  The primary key is marked rather than removed: it is what identifies the row, so the form shows it
  and disables it when editing.
  """
  def columns(nil), do: []

  def columns(resource) do
    primary = to_string(resource[:primary_key] || resource["primary_key"] || :id)
    declared = resource[:columns] || resource["columns"] || []

    declared
    |> Enum.map(fn column ->
      key = column[:name] || column["name"]

      %{
        key: key,
        label: column[:label] || column["label"] || Phoenix.Naming.humanize(to_string(key)),
        type: column[:type] || column["type"] || :string,
        badge: column[:badge] || column["badge"] || false,
        role: column[:role] || column["role"],
        default: column[:default] || column["default"],
        choices: column[:choices] || column["choices"] || [],
        primary_key: to_string(key) == primary
      }
    end)
    |> Enum.uniq_by(& &1.key)
  end

  @doc """
  Form defaults for a set of columns, as strings — what the inputs start from.

  A column's declared default wins over the type's placeholder: it is what the plugin said the value
  should be, and it is the reason a column with one is not simply absent from every row the Studio
  writes.
  """
  def defaults(columns) do
    Map.new(columns, fn column ->
      {to_string(column.key), column[:default] || default(column.type)}
    end)
  end

  @doc "Form defaults for a row being edited: its own values, as the strings the inputs expect."
  def values_for(row, columns) when is_map(row) do
    Map.new(columns, fn column ->
      key = to_string(column.key)
      {key, stringify(row[key] || row[String.to_atom(key)], column.type)}
    end)
  end

  def values_for(_row, columns), do: defaults(columns)

  @doc """
  The typed attributes for `resource_store.create`/`update`, from submitted form strings.

  Blank inputs are dropped rather than sent as empty strings, so a column the author left alone is
  left to the store's own default. The primary key is never dropped: it is what identifies the row.
  """
  def attributes(values, columns) do
    Enum.reduce(columns, %{}, fn column, acc ->
      key = to_string(column.key)
      raw = Map.get(values, key)

      cond do
        column.type == :boolean -> Map.put(acc, key, truthy?(raw))
        is_nil(raw) or (is_binary(raw) and String.trim(raw) == "") -> acc
        true -> Map.put(acc, key, ActionForms.cast(raw, column.type))
      end
    end)
  end

  @doc """
  Which columns are missing something they need. Only the primary key is required: every other
  column is the plugin's to default, and a resource with no key cannot be created or updated.
  """
  def errors(values, columns) do
    columns
    |> Enum.filter(& &1.primary_key)
    |> Enum.filter(fn column ->
      value = Map.get(values, to_string(column.key))
      is_nil(value) or (is_binary(value) and String.trim(value) == "")
    end)
    |> Map.new(fn column -> {to_string(column.key), "#{column.label} is required"} end)
  end

  defp default(:integer), do: "1"
  defp default(:float), do: "1.0"
  defp default(:boolean), do: "false"
  defp default(:map), do: "{}"
  defp default(:list), do: "[]"
  defp default(_), do: ""

  defp stringify(nil, _type), do: ""
  defp stringify(value, :boolean), do: to_string(value in [true, "true", 1])
  defp stringify(value, _type) when is_binary(value), do: value
  defp stringify(value, _type), do: to_string(value)

  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(value) when is_binary(value), do: String.trim(value) in ["true", "1", "on"]
  defp truthy?(value), do: value in [1, true]
end
