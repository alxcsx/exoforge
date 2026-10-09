defmodule Exoforge.Std.DashboardViews do
  @moduledoc """
  Standard Dashboard Views plugin for Exoforge.
  Provides the :dashboard_view contract, implementing specialized Producer Studio
  visual controls for core services (player_data, plugin_manager, auth)
  strictly via service contracts without depending on concrete plugin implementations.
  """
  use Exoforge.Plugin, provides: [:dashboard_view]

  @manifest %{
    dependencies: [Exoforge.Std.Services.Dashboard],
    title: "Studio Views",
    icon: "🎨",
    category: "Studio",
    dashboard_view: nil
  }

  # Custom views are resolved by convention: <ServiceId>View in this namespace.
  @view_ids [:player_data, :plugin_manager, :auth, :file_bucket]

  @doc "Returns the registered view module for a given service or extension id."
  def view_for(id) when is_atom(id) or is_binary(id) do
    clean_id =
      id
      |> to_string()
      |> String.replace_prefix("exoforge_std_", "")

    mod = Module.concat([Exoforge.Std.DashboardViews, Macro.camelize(clean_id) <> "View"])
    if Code.ensure_loaded?(mod), do: mod, else: nil
  end

  def view_for(_), do: nil

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction resolve_view(payload) do
    id = Map.get(payload, :id) || Map.get(payload, "id")
    view_mod = view_for(id)

    if view_mod && Code.ensure_loaded?(view_mod) do
      {:ok, %{module: view_mod, found: true}}
    else
      {:ok, %{module: nil, found: false}}
    end
  end

  @impl true
  defaction list_views do
    views =
      Enum.map(@view_ids, fn id ->
        %{"id" => to_string(id), "module" => inspect(view_for(id))}
      end)

    {:ok, %{views: views, count: length(views)}}
  end

  @impl true
  defaction get_dashboard_mount(_payload) do
    {:ok, %{views: Map.new(@view_ids, fn id -> {id, view_for(id)} end)}}
  end

  @impl true
  defaction get_dashboard_data(_payload) do
    {:ok, %{status: "ok", views_count: length(@view_ids)}}
  end
end
