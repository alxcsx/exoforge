defmodule Exoforge.Std.ResourcesTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.Std.Resources
  alias Exoforge.ActionDispatcher
  alias Exoforge.PluginRegistry

  defmodule WidgetsContract do
    import Exoforge.Contracts.Service

    defservice widgets do
      action :ping do
        returns(ok: :boolean)
      end

      resource :widget do
        source({:table, "widgets"})
        primary_key(:id)

        column(:id, :string, sortable: true)
        column(:name, :string, filterable: true, sortable: true)
        column(:score, :integer, filterable: true, sortable: true)
      end
    end
  end

  setup do
    PluginRegistry.initialize_ets()
    start_supervised!({DbManager, [driver: :sqlite]})

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_resources,
      name: "exoforge_std_resources",
      version: "0.1.0",
      entry_point: Resources,
      provides: [:resource_store]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :widgets_plugin,
      name: "widgets_plugin",
      version: "0.1.0",
      entry_point: Resources,
      provides: [WidgetsContract.Widgets]
    })

    Resources.run_migrations()
    :ok
  end

  defp dispatch(action, payload), do: ActionDispatcher.dispatch(:resource_store, action, payload)

  test "migrate creates the backing table" do
    assert {:ok, %{migrated: n}} = dispatch(:migrate, %{})
    assert n >= 1
  end

  test "create, get, update, delete round-trip" do
    assert {:ok, %{row: row}} =
             dispatch(:create, %{
               resource: "widget",
               attributes: %{"id" => "w1", "name" => "Gear", "score" => 10}
             })

    assert row["name"] == "Gear"

    assert {:ok, %{row: fetched}} = dispatch(:get, %{resource: "widget", id: "w1"})
    assert fetched["score"] == 10

    assert {:ok, %{row: updated}} =
             dispatch(:update, %{resource: "widget", id: "w1", attributes: %{"score" => 42}})

    assert updated["score"] == 42

    assert {:ok, %{deleted: true}} = dispatch(:delete, %{resource: "widget", id: "w1"})
    assert {:error, :not_found} = dispatch(:get, %{resource: "widget", id: "w1"})
  end

  test "list supports filter, search, sort and pagination" do
    for {id, name, score} <- [{"a", "Alpha", 5}, {"b", "Beta", 30}, {"c", "Gamma", 20}] do
      dispatch(:create, %{
        resource: "widget",
        attributes: %{"id" => id, "name" => name, "score" => score}
      })
    end

    assert {:ok, %{rows: rows, total: 3}} = dispatch(:list, %{resource: "widget"})
    assert length(rows) == 3

    assert {:ok, %{rows: [top]}} =
             dispatch(:list, %{resource: "widget", sort: "score:desc", limit: 1})

    assert top["id"] == "b"

    assert {:ok, %{rows: filtered}} =
             dispatch(:list, %{resource: "widget", filter: %{"score" => 20}})

    assert Enum.map(filtered, & &1["id"]) == ["c"]

    assert {:ok, %{rows: searched}} = dispatch(:list, %{resource: "widget", search: "amm"})
    assert Enum.map(searched, & &1["id"]) == ["c"]
  end

  test "upsert inserts then updates on conflict" do
    assert {:ok, %{row: r1}} =
             dispatch(:upsert, %{
               resource: "widget",
               attributes: %{"id" => "u1", "name" => "One", "score" => 1}
             })

    assert r1["score"] == 1

    assert {:ok, %{row: r2}} =
             dispatch(:upsert, %{
               resource: "widget",
               attributes: %{"id" => "u1", "name" => "One", "score" => 9}
             })

    assert r2["score"] == 9
  end

  test "rejects attributes outside the resource schema" do
    assert {:error, :invalid_attributes} =
             dispatch(:create, %{resource: "widget", attributes: %{"nope" => 1}})
  end

  test "resource_store actions reject callers below studio scope" do
    assert {:error, :forbidden_scope} =
             ActionDispatcher.dispatch(:resource_store, :list, %{resource: "widget"},
               caller_scopes: ["guest"]
             )

    assert {:ok, _} =
             ActionDispatcher.dispatch(:resource_store, :list, %{resource: "widget"},
               caller_scopes: ["studio"]
             )
  end
end
