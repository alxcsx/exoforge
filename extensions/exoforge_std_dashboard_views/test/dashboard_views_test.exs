defmodule Exoforge.Std.DashboardViewsTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.DashboardViews
  alias Exoforge.Std.DashboardViews.PlayerDataView
  alias Exoforge.Std.DashboardViews.ExtensionManagerView
  alias Exoforge.Std.DashboardViews.AuthView

  setup do
    Exoforge.ExtensionCase.start_kernel()

    Exoforge.ExtensionCase.register_extension(DashboardViews,
      id: :exoforge_std_dashboard_views,
      name: "ExoforgeStdDashboardViews",
      version: Version.parse!("0.1.0"),
      type: :elixir,
      provides: [:dashboard_view]
    )

    :ok
  end

  test "view_for resolves PlayerDataView, ExtensionManagerView, and AuthView" do
    assert DashboardViews.view_for("player_data") == PlayerDataView
    assert DashboardViews.view_for(:player_data) == PlayerDataView
    assert DashboardViews.view_for(:exoforge_std_player_data) == PlayerDataView
    assert DashboardViews.view_for("extension_manager") == ExtensionManagerView
    assert DashboardViews.view_for(:extension_manager) == ExtensionManagerView
    assert DashboardViews.view_for(:exoforge_std_extension_manager) == ExtensionManagerView
    assert DashboardViews.view_for("auth") == AuthView
    assert DashboardViews.view_for(:auth) == AuthView
    assert DashboardViews.view_for(:exoforge_std_auth) == AuthView
  end

  test "resolve_view action resolves module over ActionDispatcher" do
    assert {:ok, result} =
             ActionDispatcher.dispatch(:dashboard_view, :resolve_view, %{id: "player_data"})

    assert result.module == PlayerDataView
    assert result.found == true

    assert {:ok, em_result} =
             ActionDispatcher.dispatch(:dashboard_view, :resolve_view, %{id: "extension_manager"})

    assert em_result.module == ExtensionManagerView
    assert em_result.found == true

    assert {:ok, none_result} =
             ActionDispatcher.dispatch(:dashboard_view, :resolve_view, %{id: "nonexistent_view"})

    assert none_result.module == nil
    assert none_result.found == false
  end

  test "list_views returns registered views" do
    assert {:ok, result} = ActionDispatcher.dispatch(:dashboard_view, :list_views, %{})
    assert is_list(result.views)
    assert result.count >= 3
    ids = Enum.map(result.views, & &1["id"])
    assert "player_data" in ids
    assert "extension_manager" in ids
    assert "auth" in ids
  end
end
