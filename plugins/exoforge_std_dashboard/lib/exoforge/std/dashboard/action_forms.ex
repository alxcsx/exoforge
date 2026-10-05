defmodule Exoforge.Std.Dashboard.ActionForms do
  @moduledoc """
  What the Studio's action console needs to know about a service contract: the catalog of callable
  actions, the form defaults for each, and how submitted form strings become a typed payload.

  This is pure — no socket, no LiveView — so it can be tested directly. It used to live inside
  `StudioLive`, where the only way to exercise the type coercion was to drive the UI.
  """

  alias Exoforge.Auth.Roles
  alias Exoforge.PluginRegistry
  alias Exoforge.Std.Dashboard.Extensions

  @type service :: %{name: String.t(), actions: [map()]}
  @type action :: map()

  @doc """
  Every callable action across all extensions, grouped by service and sorted by name.

  Read from the live extension manifests, so a plugin that is unloaded disappears from the console.
  """
  def catalog do
    from_extensions()
    |> Enum.filter(fn svc -> is_list(actions_of(svc)) and actions_of(svc) != [] end)
    |> Enum.map(&normalize_service/1)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  @doc "The service named `name`, or nil."
  def service(catalog, nil), do: List.first(catalog)

  def service(catalog, name) do
    Enum.find(catalog, &(&1.name == name)) || List.first(catalog)
  end

  @doc "The action named `name` within `service`, or its first action."
  def action(nil, _name), do: nil

  def action(service, nil), do: List.first(service.actions)

  def action(service, name) do
    Enum.find(service.actions, &(&1.name == name)) || List.first(service.actions)
  end

  @doc "Form defaults for an action — the strings the modal opens with."
  def default_params(nil), do: %{}

  def default_params(%{params: params}) do
    Map.new(params, fn param -> {param.name, default_value(param.type)} end)
  end

  @doc """
  Turns submitted form values into a typed payload.

  Values arrive as strings from the form; each is coerced to the type the contract declares, so a
  service receives `%{count: 3}` rather than `%{count: "3"}`.
  """
  def build_payload(nil, _form_values), do: %{}

  def build_payload(%{params: params}, form_values) do
    Map.new(params, fn param ->
      key = Exoforge.Atoms.existing(param.name, param.name)
      {key, cast(Map.get(form_values, param.name, ""), param.type)}
    end)
  end

  @doc "Coerces one form string to `type`. Unparseable values become the type's zero value."
  def cast(value, type) when is_binary(value) do
    trimmed = String.trim(value)

    case type do
      :integer -> parse_integer(trimmed)
      :float -> parse_float(trimmed)
      :boolean -> String.downcase(trimmed) in ["true", "1", "yes"]
      :map -> parse_map(value)
      _ -> value
    end
  end

  def cast(value, _type), do: value

  @doc """
  Parses the console's comma-separated scope list.

  Empty means admin: the console is already behind an authenticated Studio session, and an empty
  list would otherwise be rejected as unauthorized before the action ever runs.
  """
  def parse_scopes(nil), do: [Roles.admin()]

  def parse_scopes(raw) do
    case raw |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [] -> [Roles.admin()]
      scopes -> scopes
    end
  end

  # ---- internals ---------------------------------------------------------------------

  defp from_extensions do
    Extensions.dashboard_extensions()
    |> Enum.flat_map(fn ext -> Map.get(ext, :services, []) end)
  rescue
    _ -> []
  end

  defp normalize_service(svc) do
    %{
      name: PluginRegistry.clean_service_name(svc[:name] || svc["name"]),
      actions: Enum.map(actions_of(svc), &normalize_action/1)
    }
  end

  defp normalize_action(act) do
    %{
      name: to_string(act[:name] || act["name"]),
      doc: act[:doc] || act["doc"] || "No description provided.",
      mode: to_string(act[:mode] || act["mode"] || "sync"),
      params: Extensions.normalize_action_params(act[:params] || act["params"] || [])
    }
  end

  defp actions_of(svc), do: svc[:actions] || svc["actions"] || []

  defp default_value(:integer), do: "1"
  defp default_value(:float), do: "1.0"
  defp default_value(:boolean), do: "true"
  defp default_value(:map), do: "{}"
  defp default_value(_), do: ""

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp parse_map(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
end
