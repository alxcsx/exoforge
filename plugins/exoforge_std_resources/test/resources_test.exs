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
        column(:tier, :string, choices: ~w(bronze silver))
      end
    end
  end

  # A resource nothing else touches, so the SQL assertion below cannot depend on which test ran first.
  defmodule TiersContract do
    import Exoforge.Contracts.Service

    defservice tiers do
      resource :tier do
        source({:table, "tiers"})
        primary_key(:id)

        column(:id, :string)
        column(:level, :string, choices: ~w(bronze silver))
      end
    end
  end

  defmodule ScoresContract do
    import Exoforge.Contracts.Service

    defservice scores do
      # No `source`: the plugin stores rows through the host KV bridge.
      resource :snake_score do
        primary_key(:player_id)

        column(:player_id, :string, sortable: true)
        column(:name, :string, filterable: true)
        column(:score, :integer, sortable: true)
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
      id: :tiers_plugin,
      name: "tiers_plugin",
      version: "0.1.0",
      entry_point: Resources,
      provides: [TiersContract.Tiers]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :widgets_plugin,
      name: "widgets_plugin",
      version: "0.1.0",
      entry_point: Resources,
      provides: [WidgetsContract.Widgets]
    })

    Resources.run_migrations()

    # One SQLite file for the whole suite, so a row written by one test is visible to the next: the
    # test that asserts `total: 3` saw four whenever the upsert test ran first, which is a coin flip
    # on the seed. Each test starts from an empty table instead.
    dispatch(:clear, %{resource: "widget"})
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

  test "lists rows stored through the host KV bridge when the resource has no table source" do
    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :snake_plugin,
      name: "snake_plugin",
      version: "0.1.0",
      entry_point: Resources,
      provides: [ScoresContract.Scores]
    })

    assert {:ok, _} =
             Exoforge.Std.Database.put(:snake_plugin, "snake_score", "p1", %{
               "player_id" => "p1",
               "name" => "Viper",
               "score" => 42
             })

    assert {:ok, %{rows: rows, total: 1}} = dispatch(:list, %{resource: "snake_score"})
    assert [%{"score" => 42, "name" => "Viper"}] = rows

    # The bridge stores the row under a key and injects it as `id`. Here the resource's key is
    # `player_id`, so that `id` is the same value a second time, as a string - it is not a field of
    # this resource and should not be shown as one.
    assert [row] = rows
    refute Map.has_key?(row, "id")
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

  # A table created before the resource declared a primary key has none, and `CREATE TABLE IF NOT
  # EXISTS` never repairs it. Every upsert against it then failed forever with "ON CONFLICT clause
  # does not match any PRIMARY KEY or UNIQUE constraint" - silently, because the one caller that
  # mattered threw the result away.
  test "migration repairs a table that predates the primary key" do
    # The resource's table lives in the database of the plugin that declared it, which is not the
    # plugin serving the store. Getting this wrong makes the test pass without testing anything.
    sql = fn statement ->
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :widgets_plugin,
        operation: statement,
        arguments: []
      })
    end

    # Prove the setup is real before relying on it.
    assert {:ok, _} = sql.("DROP TABLE IF EXISTS widgets")
    assert {:ok, _} = sql.("CREATE TABLE widgets (id text, name text, score integer)")
    assert {:error, _} = sql.("INSERT INTO widgets (id, name, score) VALUES ('d', 'dup', 1) ON CONFLICT(id) DO NOTHING")

    Resources.run_migrations("widget")

    assert {:ok, %{row: row}} =
             dispatch(:upsert, %{
               resource: "widget",
               attributes: %{"id" => "w9", "name" => "Repaired", "score" => 1}
             })

    assert row["name"] == "Repaired"

    # The point of the key: the second write updates in place rather than inserting a duplicate.
    assert {:ok, %{row: again}} =
             dispatch(:upsert, %{
               resource: "widget",
               attributes: %{"id" => "w9", "name" => "Repaired", "score" => 2}
             })

    assert again["score"] == 2
    assert {:ok, %{rows: rows}} = dispatch(:list, %{resource: "widget"})
    assert length(rows) == 1
  end

  # The same closed set a C# enum produces. Both spell it as a list of values in the manifest, so one
  # check covers both - and the database gets the same constraint.
  test "rejects a value outside a column's choices" do
    assert {:error, {:not_a_choice, "tier", "gold"}} =
             dispatch(:create, %{
               resource: "widget",
               attributes: %{"id" => "w1", "name" => "Gear", "score" => 1, "tier" => "gold"}
             })

    assert {:ok, _} =
             dispatch(:create, %{
               resource: "widget",
               attributes: %{"id" => "w1", "name" => "Gear", "score" => 1, "tier" => "bronze"}
             })
  end

  test "the choices are a database constraint too" do
    {:ok, %{rows: rows}} =
      ActionDispatcher.dispatch(:database, :execute, %{
        plugin: :tiers_plugin,
        operation: "SELECT sql FROM sqlite_master WHERE name = 'tiers'"
      })

    assert [%{"sql" => sql}] = rows
    assert sql =~ "CHECK (level IN ('bronze', 'silver'))"
  end

  test "rejects attributes outside the resource schema" do
    assert {:error, :invalid_attributes} =
             dispatch(:create, %{resource: "widget", attributes: %{"nope" => 1}})
  end

  test "clear deletes every row of a resource" do
    for {id, name, score} <- [{"ca", "Alpha", 5}, {"cb", "Beta", 30}] do
      dispatch(:create, %{
        resource: "widget",
        attributes: %{"id" => id, "name" => name, "score" => score}
      })
    end

    assert {:ok, %{cleared: true}} = dispatch(:clear, %{resource: "widget"})
    assert {:ok, %{rows: []}} = dispatch(:list, %{resource: "widget"})
  end

  test "clear empties a KV-backed resource" do
    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :snake_plugin,
      name: "snake_plugin",
      version: "0.1.0",
      entry_point: Resources,
      provides: [ScoresContract.Scores]
    })

    Exoforge.Std.Database.put(:snake_plugin, "snake_score", "clear_p1", %{
      "player_id" => "clear_p1",
      "name" => "Clear Me",
      "score" => 1
    })

    assert {:ok, %{cleared: true}} = dispatch(:clear, %{resource: "snake_score"})
    assert {:ok, %{rows: []}} = dispatch(:list, %{resource: "snake_score"})
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
