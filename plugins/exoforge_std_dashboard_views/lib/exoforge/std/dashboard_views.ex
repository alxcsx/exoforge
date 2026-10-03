defmodule Exoforge.Std.DashboardViews do
  @moduledoc """
  Standard Dashboard Views plugin for Exoforge.
  Provides the :dashboard_view contract, implementing specialized Producer Studio
  visual controls for core services (player_data, plugin_manager, auth)
  strictly via service contracts without depending on concrete plugin implementations.
  """
  use Exoforge.Plugin, provides: [:dashboard_view]

  alias Exoforge.Std.DashboardViews.PlayerDataView
  alias Exoforge.Std.DashboardViews.PluginManagerView
  alias Exoforge.Std.DashboardViews.AuthView

  @manifest %{
    dependencies: [Exoforge.Std.Services.Dashboard],
    category: "Studio",
    dashboard_view: nil
  }

  @view_registry %{
    "player_data" => PlayerDataView,
    :player_data => PlayerDataView,
    "plugin_manager" => PluginManagerView,
    :plugin_manager => PluginManagerView,
    "auth" => AuthView,
    :auth => AuthView
  }

  @doc "Returns the registered view module for a given service or extension id."
  def view_for(id) do
    Map.get(@view_registry, id) || Map.get(@view_registry, to_string(id))
  end

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction resolve_view(payload) do
    id = Map.get(payload, :id) || Map.get(payload, "id")
    view_mod = view_for(id)

    if view_mod && Code.ensure_loaded?(view_mod) do
      {:ok, %{module: view_mod}}
    else
      {:error, :not_found}
    end
  end

  @impl true
  defaction list_views do
    views =
      Enum.map(@view_registry, fn {key, mod} ->
        %{
          "id" => to_string(key),
          "module" => inspect(mod)
        }
      end)
      |> Enum.uniq_by(& &1["id"])

    {:ok, %{views: views, count: length(views)}}
  end

  @impl true
  defaction get_dashboard_mount(_payload) do
    {:ok, %{views: @view_registry}}
  end

  @impl true
  defaction get_dashboard_data(_payload) do
    {:ok, %{status: "ok", views_count: map_size(@view_registry)}}
  end
end
