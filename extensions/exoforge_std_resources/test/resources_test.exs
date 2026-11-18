defmodule Exoforge.Std.ResourcesTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database.Manager, as: DbManager
  alias Exoforge.Std.Resources
  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry

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

  # A resource with structured columns: they are stored as text, so the store owns the JSON.
  defmodule ConfigContract do
    import Exoforge.Contracts.Service

    defservice game_config do
      resource :game_config do
        source({:table, "game_config"})
        primary_key(:id)

        column(:id, :string)
        column(:settings, :map)
        column(:tags, :list)
      end
    end
  end

  # SQLite has no boolean type: exqlite binds `true` as the text "true", and a `DEFAULT false`
  # column holds the integer 0. Reads decode by the declared column type.
  defmodule TogglesContract do
    import Exoforge.Contracts.Service

    defservice toggles do
      resource :toggle do
        source({:table, "toggles"})
        primary_key(:id)

        column(:id, :string)
        column(:color_blind, :boolean)
        column(:beta, :boolean, default: false)
        column(:volume, :integer)
        column(:scale, :float)
      end
    end
  end

  defmodule PublicCatalogContract do
    import Exoforge.Contracts.Service

    defservice public_catalog do
      resource :public_item do
        source({:table, "public_items"})
        primary_key(:id)
        allow_player_read(true)

        column(:id, :string, sortable: true)
        column(:name, :string, filterable: true)
      end

      resource :private_item do
        source({:table, "private_items"})
        primary_key(:id)

        column(:id, :string)
        column(:secret, :string)
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
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    Exoforge.ExtensionCase.register_database(Exoforge.Std.Database)

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :exoforge_std_resources,
      provides: [:resource_store]
    )

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :tiers_plugin,
      provides: [TiersContract.Tiers]
    )

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :widgets_plugin,
      provides: [WidgetsContract.Widgets]
    )

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :config_plugin,
      provides: [ConfigContract.GameConfig]
    )

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :public_catalog_plugin,
      provides: [PublicCatalogContract.PublicCatalog]
    )

    Exoforge.ExtensionCase.register_extension(Resources,
      id: :toggles_plugin,
      provides: [TogglesContract.Toggles]
    )

    Resources.run_migrations()

    # One SQLite file for the whole suite, so a row written by one test is visible to the next: the
    # test that asserts `total: 3` saw four whenever the upsert test ran first, which is a coin flip
    # on the seed. Each test starts from an empty table instead.
    dispatch(:clear, %{resource: "widget"})
    :ok
  end

  defp dispatch(action, payload), do: ActionDispatcher.dispatch_internal(:resource_store, action, payload)

  test "structured values are written as JSON text instead of failing at the adapter" do
    assert {:ok, %{row: row}} =
             dispatch(:create, %{
               resource: "game_config",
               attributes: %{"id" => "cfg", "settings" => %{"volume" => 3}, "tags" => ["a", "b"]}
             })

    # These columns are text (`sql_type/1`); binding a map or a list is what raised inside the
    # database manager before, surfacing to callers as {:extension_exited, ...}.
    assert Jason.decode!(row["settings"]) == %{"volume" => 3}
    assert Jason.decode!(row["tags"]) == ["a", "b"]

    assert {:ok, %{row: fetched}} = dispatch(:get, %{resource: "game_config", id: "cfg"})
    assert Jason.decode!(fetched["settings"]) == %{"volume" => 3}
  end

  test "boolean columns read back as booleans through the resource store" do
    assert {:ok, %{row: row}} =
             dispatch(:create, %{
               resource: "toggle",
               attributes: %{
                 "id" => "bool_1",
                 "color_blind" => true,
                 "volume" => 5,
                 "scale" => 1.5
               }
             })

    assert row["color_blind"] == true
    assert row["volume"] == 5
    assert row["scale"] == 1.5

    assert {:ok, %{row: fetched}} = dispatch(:get, %{resource: "toggle", id: "bool_1"})
    assert fetched["color_blind"] == true
    assert is_integer(fetched["volume"])
    assert is_float(fetched["scale"])

    assert {:ok, %{row: updated}} =
             dispatch(:update, %{
               resource: "toggle",
               id: "bool_1",
               attributes: %{"color_blind" => false}
             })

    assert updated["color_blind"] == false

    assert {:ok, %{rows: rows}} = dispatch(:list, %{resource: "toggle"})
    assert Enum.any?(rows, &(&1["id"] == "bool_1" and &1["color_blind"] == false))
  end

  test "boolean columns read back as booleans through the host KV bridge" do
    assert {:ok, _} =
             Exoforge.Std.Database.put(:toggles_plugin, "toggles", "bool_2", %{
               "id" => "bool_2",
               "color_blind" => true,
               "volume" => 7
             })

    assert {:ok, row} = Exoforge.Std.Database.get(:toggles_plugin, "toggles", "bool_2")
    assert row["color_blind"] == true
    assert row["volume"] == 7

    assert {:ok, rows} = Exoforge.Std.Database.all(:toggles_plugin, "toggles")
    assert Enum.any?(rows, &(&1["id"] == "bool_2" and &1["color_blind"] == true))
  end

  test "booleans stored as SQLite text or left at a SQL default still read back as booleans" do
    # Rows written before the fix hold the text "true"; a bare `DEFAULT false` holds the integer 0.
    assert {:ok, _} =
             Exoforge.Std.Database.execute(
               :toggles_plugin,
               "INSERT INTO toggles (id, color_blind) VALUES ($1, $2)",
               ["bool_text", "true"]
             )

    assert {:ok, _} =
             Exoforge.Std.Database.execute(
               :toggles_plugin,
               "INSERT INTO toggles (id) VALUES ($1)",
               ["bool_default"]
             )

    assert {:ok, text_row} = Exoforge.Std.Database.get(:toggles_plugin, "toggles", "bool_text")
    assert text_row["color_blind"] == true

    assert {:ok, default_row} =
             Exoforge.Std.Database.get(:toggles_plugin, "toggles", "bool_default")

    assert default_row["beta"] == false
  end

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

    # A caller that is allowed to miss asks for it: the same lookup answers with an empty row
    # instead of an error, so a preference read on first boot is not a failure.
    assert {:ok, %{row: nil}} =
             dispatch(:get, %{resource: "widget", id: "w1", optional: true})
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
    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
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
      ActionDispatcher.dispatch_internal(:database, :execute, %{
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
      ActionDispatcher.dispatch_internal(:database, :execute, %{
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
    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
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
    assert {:error, {:forbidden_scope, _}} =
             ActionDispatcher.dispatch(:resource_store, :list, %{resource: "widget"}, caller_scopes: ["guest"])

    assert {:ok, _} =
             ActionDispatcher.dispatch(
               :resource_store,
               :list,
               %{resource: "widget", _auth: %{scopes: ["studio"]}},
               caller_scopes: ["studio"]
             )
  end

  test "allow_player_read exposes only opted-in resources to player reads" do
    dispatch(:clear, %{resource: "public_item"})
    dispatch(:clear, %{resource: "private_item"})

    assert {:ok, _} =
             dispatch(:create, %{
               resource: "public_item",
               attributes: %{"id" => "pub_1", "name" => "Public"}
             })

    assert {:ok, _} =
             dispatch(:create, %{
               resource: "private_item",
               attributes: %{"id" => "priv_1", "secret" => "hidden"}
             })

    # Player can read the opted-in resource.
    assert {:ok, %{rows: rows}} =
             ActionDispatcher.dispatch(
               :resource_store,
               :list,
               %{resource: "public_item", _auth: %{scopes: ["player"]}},
               caller_scopes: ["player"]
             )

    assert Enum.any?(rows, &(&1["id"] == "pub_1"))

    assert {:ok, %{row: row}} =
             ActionDispatcher.dispatch(
               :resource_store,
               :get,
               %{resource: "public_item", id: "pub_1", _auth: %{scopes: ["player"]}},
               caller_scopes: ["player"]
             )

    assert row["name"] == "Public"

    # Player cannot read a resource that did not opt in.
    assert {:error, :forbidden_scope} =
             ActionDispatcher.dispatch(
               :resource_store,
               :list,
               %{resource: "private_item", _auth: %{scopes: ["player"]}},
               caller_scopes: ["player"]
             )

    # Staff can read it.
    assert {:ok, _} =
             ActionDispatcher.dispatch(
               :resource_store,
               :list,
               %{resource: "private_item", _auth: %{scopes: ["studio"]}},
               caller_scopes: ["studio"]
             )

    # Internal callers can read it.
    assert {:ok, _} = dispatch(:list, %{resource: "private_item"})

    # Writes stay studio-scoped even for a public resource.
    assert {:error, {:forbidden_scope, %{required: "studio"}}} =
             ActionDispatcher.dispatch(
               :resource_store,
               :create,
               %{resource: "public_item", attributes: %{"id" => "pub_2"}, _auth: %{scopes: ["player"]}},
               caller_scopes: ["player"]
             )
  end

  defp register_native_manifest(id, json_map) do
    dir = Path.join(System.tmp_dir!(), "exo_res_test_#{id}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "manifest.json"), Jason.encode!(json_map))
    [manifest] = Exoforge.Drivers.Loaders.ManifestLoader.load_extensions(dir)
    Exoforge.ExtensionRegistry.register(manifest)

    on_exit(fn ->
      if :ets.whereis(:exo_extensions_mem) != :undefined do
        Exoforge.ExtensionRegistry.unregister(manifest.id)
      end

      File.rm_rf!(dir)
    end)

    manifest
  end

  test "loja_itens manifest with PrimaryKey 'Id' and column 'id' migrates twice and stores rows" do
    register_native_manifest("loja_itens", %{
      "id" => "loja_itens",
      "name" => "LojaItens",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "loja_itens",
      "services" => [
        %{
          "name" => "loja_itens",
          "resources" => [
            %{
              "name" => "itens",
              "source" => %{"table" => "itens"},
              "primary_key" => "Id",
              "columns" => [
                %{"name" => "id", "type" => "string"},
                %{"name" => "nome", "type" => "string"},
                %{"name" => "tipo", "type" => "string"},
                %{"name" => "preco", "type" => "integer"}
              ]
            },
            %{
              "name" => "inventario",
              "source" => %{"table" => "inventario"},
              "primary_key" => "Id",
              "columns" => [
                %{"name" => "id", "type" => "string"},
                %{"name" => "ouro", "type" => "integer"},
                %{"name" => "itens", "type" => "map"}
              ]
            }
          ]
        }
      ]
    })

    assert {:ok, %{migrated: 2}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "loja_itens"})

    # Redeploy / second migrate succeeds cleanly without duplicate-column errors.
    assert {:ok, %{migrated: 2}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "loja_itens"})

    assert {:ok, %{row: item}} =
             dispatch(:create, %{
               resource: "itens",
               attributes: %{"id" => "espada", "nome" => "Espada", "tipo" => "arma", "preco" => 50}
             })

    assert item["nome"] == "Espada"
  end

  test "refuses duplicate columns differing only by case before running any DDL" do
    register_native_manifest("dup_ext", %{
      "id" => "dup_ext",
      "name" => "DupExt",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "dup_ext",
      "services" => [
        %{
          "name" => "dup_svc",
          "resources" => [
            %{
              "name" => "dup_items",
              "source" => %{"table" => "dup_items"},
              "primary_key" => "id",
              "columns" => [
                %{"name" => "id", "type" => "string"},
                %{"name" => "Name", "type" => "string"},
                %{"name" => "name", "type" => "string"}
              ]
            }
          ]
        }
      ]
    })

    assert {:error, {:invalid_resource, %{extension: :dup_ext, table: "dup_items", column: col, reason: :duplicate_column}}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "dup_ext"})

    assert String.downcase(col) == "name"

    assert {:ok, %{rows: []}} =
             Exoforge.Std.Database.execute(
               :dup_ext,
               "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'dup_items'"
             )
  end

  test "refuses primary_key naming no column before running any DDL" do
    register_native_manifest("bad_pk_ext", %{
      "id" => "bad_pk_ext",
      "name" => "BadPkExt",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "bad_pk_ext",
      "services" => [
        %{
          "name" => "bad_pk_svc",
          "resources" => [
            %{
              "name" => "bad_pks",
              "source" => %{"table" => "bad_pks"},
              "primary_key" => "missing_id",
              "columns" => [
                %{"name" => "id", "type" => "string"},
                %{"name" => "label", "type" => "string"}
              ]
            }
          ]
        }
      ]
    })

    assert {:error, {:invalid_resource, %{extension: :bad_pk_ext, table: "bad_pks", column: "missing_id", reason: :primary_key_not_found}}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "bad_pk_ext"})

    assert {:ok, %{rows: []}} =
             Exoforge.Std.Database.execute(
               :bad_pk_ext,
               "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'bad_pks'"
             )
  end

  test "scoped migrate ignores a broken resource in another extension" do
    register_native_manifest("broken_other", %{
      "id" => "broken_other",
      "name" => "BrokenOther",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "broken_other",
      "services" => [
        %{
          "name" => "broken_other",
          "resources" => [
            %{
              "name" => "broken_rows",
              "source" => %{"table" => "broken_rows"},
              "primary_key" => "missing_id",
              "columns" => [%{"name" => "id", "type" => "string"}]
            }
          ]
        }
      ]
    })

    register_native_manifest("healthy_ext", %{
      "id" => "healthy_ext",
      "name" => "HealthyExt",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "healthy_ext",
      "services" => [
        %{
          "name" => "healthy_ext",
          "resources" => [
            %{
              "name" => "healthy_rows",
              "source" => %{"table" => "healthy_rows"},
              "primary_key" => "id",
              "columns" => [%{"name" => "id", "type" => "string"}]
            }
          ]
        }
      ]
    })

    assert {:ok, %{migrated: 1}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "healthy_ext"})
  end

  test "validates all resources of an extension before running DDL for any of them" do
    register_native_manifest("multi_res_ext", %{
      "id" => "multi_res_ext",
      "name" => "MultiResExt",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "multi_res_ext",
      "services" => [
        %{
          "name" => "multi_res_ext",
          "resources" => [
            %{
              "name" => "first_valid",
              "source" => %{"table" => "first_valid"},
              "primary_key" => "id",
              "columns" => [%{"name" => "id", "type" => "string"}]
            },
            %{
              "name" => "second_invalid",
              "source" => %{"table" => "second_invalid"},
              "primary_key" => "id",
              "columns" => [
                %{"name" => "id", "type" => "string"},
                %{"name" => "Id", "type" => "string"}
              ]
            }
          ]
        }
      ]
    })

    assert {:error, {:invalid_resource, %{extension: :multi_res_ext, table: "second_invalid", reason: :duplicate_column}}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "multi_res_ext"})

    assert {:ok, %{rows: []}} =
             Exoforge.Std.Database.execute(
               :multi_res_ext,
               "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'first_valid'"
             )
  end

  test "compares existing table columns case-insensitively in reconcile_columns and repair_primary_key" do
    assert {:ok, _} =
             Exoforge.Std.Database.execute(
               :mixed_cols_ext,
               "CREATE TABLE mixed_cols (Id text, Nome text)"
             )

    register_native_manifest("mixed_cols_ext", %{
      "id" => "mixed_cols_ext",
      "name" => "MixedColsExt",
      "version" => "0.1.0",
      "type" => "native",
      "entry_point" => "mixed_cols_ext",
      "services" => [
        %{
          "name" => "mixed_cols_ext",
          "resources" => [
            %{
              "name" => "mixed_cols",
              "source" => %{"table" => "mixed_cols"},
              "primary_key" => "id",
              "columns" => [
                %{"name" => "id", "type" => "string"},
                %{"name" => "nome", "type" => "string"},
                %{"name" => "score", "type" => "integer"}
              ]
            }
          ]
        }
      ]
    })

    assert {:ok, %{migrated: 1}} =
             ActionDispatcher.dispatch_internal(:resource_store, :migrate, %{extension: "mixed_cols_ext"})

    {:ok, %{columns: cols}} =
      ActionDispatcher.dispatch_internal(:database, :table_columns, %{
        plugin: :mixed_cols_ext,
        table: "mixed_cols"
      })

    assert Enum.map(cols, &String.downcase/1) == ["id", "nome", "score"]

    assert {:ok, %{row: row}} =
             dispatch(:upsert, %{
               resource: "mixed_cols",
               attributes: %{"id" => "m1", "nome" => "Alice", "score" => 10}
             })

    assert row["score"] == 10
  end
end
