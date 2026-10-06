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
      item = to_string(item)
      item == svc or item == Macro.underscore(svc) or Macro.underscore(item) == svc
    end)
  end

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
    entities: [],
    dashboard_view: nil,
    title: nil,
    icon: nil,
    ui_hooks: %{},
    category: "Extension",
    system: false,
    assets_path: "assets"
  ]
end
