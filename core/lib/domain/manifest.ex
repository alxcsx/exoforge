defmodule Exoforge.Domain.Manifest do
  @moduledoc """
  Represents an Plugin metadata
  """

  @enforce_keys [:id, :name, :version, :entry_point]

  @doc """
  Whether a plugin may call a service: it must declare it as a dependency or provide it.

  Both runtimes gate `call_action` on this. It lives here because the WASM runner had it and the
  native runner did not, which is not the kind of difference two implementations should be free to
  develop on their own.
  """
  def allows_service?(%__MODULE__{dependencies: deps, provides: provides}, service) do
    svc = to_string(service)

    Enum.any?((deps || []) ++ (provides || []), fn item ->
      item = service_name(item)
      item == svc or item == Macro.underscore(svc) or Macro.underscore(item) == svc
    end)
  end

  @doc """
  The name of a service entry, as a string.

  A hand-written manifest lists `provides: [:database]`, but `PluginRegistry` shapes those entries
  into the service metadata maps before anything dispatches. `to_string/1` on one of those maps
  raises `Protocol.UndefinedError`, so every reader of this field has to go through here.
  """
  def service_name(%{name: name}), do: to_string(name)
  def service_name(%{"name" => name}), do: to_string(name)
  def service_name(other), do: to_string(other)

  defstruct [
    :id,
    :name,
    :version,
    :entry_point,
    type: :elixir,
    context: :global,
    # automatically set by the loader.
    physical_path: "",
    dependencies: [],
    provides: [],
    services: [],
    events: [],
    dashboard_view: nil,
    title: nil,
    icon: nil,
    ui_hooks: %{},
    category: "Extension",
    system: false,
    assets_path: "assets"
  ]
end
