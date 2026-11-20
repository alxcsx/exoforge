defmodule Exoforge.Std.ResourcesViewTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Exoforge.Std.DashboardViews
  alias Exoforge.Std.DashboardViews.ResourcesView

  @wallet %{name: "wallets", extension: "wallet", service: "wallet", columns: ["id", "player_id", "coins"], rows: 12}
  @items %{name: "items", extension: "items", service: "items", columns: ~w(id a b c d e f g), rows: 1}
  @empty %{name: "levels", extension: "level_share", service: "level_share", columns: ["id"], rows: nil}

  defp html(resources, search \\ "") do
    assigns = %{id: "data", resources: resources, search: search, myself: %Phoenix.LiveComponent.CID{cid: 1}, __changed__: %{}}
    rendered_to_string(ResourcesView.render(assigns))
  end

  test "the studio resolves the view by convention" do
    assert DashboardViews.view_for(:resources) == ResourcesView
    assert DashboardViews.view_for(:exoforge_std_resources) == ResourcesView
  end

  test "each table links to the row browser and says how many rows it has" do
    html = html([@wallet, @items, @empty])

    assert html =~ ~s(href="/resources/wallets")
    assert html =~ "12 rows"
    assert html =~ "1 row<"
    assert html =~ "wallet"
    # a long column list is cut, with the rest counted
    assert html =~ "and 2 more"
    # a table that cannot be counted does not claim zero
    refute html =~ "0 rows"
  end

  test "an empty project says how to get a table" do
    html = html([])
    assert html =~ "No extension declares a table yet"
    assert html =~ "[ExoResource]"
  end

  test "search matches a table, its owner or a column, and says when nothing matches" do
    all = [@wallet, @items, @empty]

    assert ResourcesView.filter(all, "") == all
    assert Enum.map(ResourcesView.filter(all, "coins"), & &1.name) == ["wallets"]
    assert Enum.map(ResourcesView.filter(all, "LEVEL_SHARE"), & &1.name) == ["levels"]

    assert html(all, "nothing-like-this") =~ ~s(Nothing matches "nothing-like-this")
  end

  test "row counts read like a person would" do
    assert ResourcesView.rows_text(nil) == "-"
    assert ResourcesView.rows_text(0) == "0 rows"
    assert ResourcesView.rows_text(1) == "1 row"
    assert ResourcesView.rows_text(40) == "40 rows"
  end
end
