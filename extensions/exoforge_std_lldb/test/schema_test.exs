defmodule Exoforge.Std.Lldb.SchemaTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Adapters.Postgres
  alias Exoforge.Std.Lldb.Manager
  alias Exoforge.Std.Lldb.Schema
  alias Exoforge.Std.Lldb.TestDB

  defp pg_config, do: TestDB.config()

  setup do
    unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
      start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
    end

    unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
      start_supervised!(
        {DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one}
      )
    end

    unless Process.whereis(Exoforge.ExtensionRegistry) do
      start_supervised!(Exoforge.ExtensionRegistry)
    end

    Exoforge.ExtensionRegistry.initialize_ets()

    cfg = pg_config()

    unless Process.whereis(Manager) do
      start_supervised!({Manager, [driver: :postgres] ++ Map.to_list(cfg)})
    end

    plugin = :"t2_schema_#{System.unique_integer([:positive])}"
    assert {:ok, _} = Postgres.ensure_database(plugin, cfg)

    schema = "plugin_#{Lldb.clean_id(plugin)}"

    conn =
      start_supervised!(
        {Postgrex,
         hostname: cfg.host,
         port: cfg.port,
         username: cfg.username,
         password: cfg.password,
         database: cfg.database,
         parameters: [search_path: ~s("#{schema}", public)]},
        id: :test_conn
      )

    on_exit(fn ->
      _ = Postgres.reset(plugin, cfg)
    end)

    {:ok, plugin: plugin, schema: schema, conn: conn, cfg: cfg}
  end

  defp base_resource(overrides \\ %{}) do
    Map.merge(
      %{
        source: %{table: "items"},
        schema_hash: "hash_v1",
        columns: [
          %{
            name: "id",
            storage: "text",
            nullable: false,
            primary_key: true,
            unique: false,
            indexed: false,
            default: nil,
            choices: nil
          },
          %{
            name: "price",
            storage: "integer",
            nullable: false,
            primary_key: false,
            unique: false,
            indexed: true,
            default: 10,
            choices: nil
          },
          %{
            name: "tier",
            storage: "text",
            nullable: false,
            primary_key: false,
            unique: false,
            indexed: false,
            default: "common",
            choices: ["common", "rare"]
          }
        ]
      },
      overrides
    )
  end

  test "fresh create, ledgers written, and idempotent re-run via fast path", %{
    conn: conn,
    schema: schema
  } do
    res = base_resource()
    assert {:ok, live0} = Schema.read_live_state(conn, schema, [res])
    assert {:ok, plan1} = Schema.plan([res], live0)

    assert Enum.any?(plan1.ops, &(&1.op == :create_table and &1.table == "items" and &1.safety == :safe))
    assert Enum.any?(plan1.ops, &(&1.op == :create_index and &1.column == "price" and &1.safety == :safe))
    assert Enum.all?(plan1.ops, &(&1.safety == :safe))

    assert {:ok, %{applied: applied_count}} = Schema.apply(conn, plan1)
    assert applied_count > 0

    # Verify table, column defaults, check constraint, and index exist
    Postgrex.query!(conn, ~s[INSERT INTO "#{schema}"."items" ("id") VALUES ('sword')], [])

    assert {:ok, %Postgrex.Result{rows: [["sword", 10, "common"]]}} =
             Postgrex.query(conn, ~s[SELECT "id", "price", "tier" FROM "#{schema}"."items"], [])

    # Check constraint rejects invalid enum value
    assert {:error, _} =
             Postgrex.query(
               conn,
               ~s[INSERT INTO "#{schema}"."items" ("id", "tier") VALUES ('bad', 'mythic')],
               []
             )

    # Verify ledgers exist and _exo_schema row was written
    assert {:ok, %Postgrex.Result{rows: [["items", "hash_v1"]]}} =
             Postgrex.query(
               conn,
               ~s[SELECT table_name, schema_hash FROM "#{schema}"."_exo_schema"],
               []
             )

    assert {:ok, %Postgrex.Result{rows: []}} =
             Postgrex.query(conn, ~s[SELECT id FROM "#{schema}"."_exo_migrations"], [])

    assert {:ok, %Postgrex.Result{rows: []}} =
             Postgrex.query(conn, ~s[SELECT id FROM "#{schema}"."_exo_rejects"], [])

    # Idempotent re-run: fast path skips diffing when schema_hash matches and table exists
    assert {:ok, live1} = Schema.read_live_state(conn, schema, [res])
    assert {:ok, plan2} = Schema.plan([res], live1)
    assert plan2.ops == []
    assert "items" in plan2.skipped_tables

    assert {:ok, %{applied: 0}} = Schema.apply(conn, plan2)

    # Still only 1 row in _exo_schema because nothing was applied on fast-path no-op
    assert {:ok, %Postgrex.Result{rows: [["items"]]}} =
             Postgrex.query(conn, ~s[SELECT table_name FROM "#{schema}"."_exo_schema"], [])

    # Even if schema_hash changes without actual column diff, diff produces 0 DDL ops
    res_rehashed = Map.put(res, :schema_hash, "hash_v1_rehashed")
    assert {:ok, live2} = Schema.read_live_state(conn, schema, [res_rehashed])
    assert {:ok, plan3} = Schema.plan([res_rehashed], live2)
    assert plan3.ops == []
  end

  test "add nullable column and add NOT NULL column with default to non-empty table", %{
    conn: conn,
    schema: schema
  } do
    res1 = base_resource()
    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])

    Postgrex.query!(conn, ~s[INSERT INTO "#{schema}"."items" ("id") VALUES ('i1')], [])

    res2 =
      base_resource(%{
        schema_hash: "hash_v2",
        columns:
          res1.columns ++
            [
              %{name: "note", storage: "text", nullable: true},
              %{name: "qty", storage: "integer", nullable: false, default: 5}
            ]
      })

    assert {:ok, live} = Schema.read_live_state(conn, schema, [res2])
    assert {:ok, plan} = Schema.plan([res2], live)
    assert length(plan.ops) == 2
    assert Enum.all?(plan.ops, &(&1.op == :add_column and &1.safety == :safe))

    assert {:ok, _} = Schema.apply(conn, plan)

    assert {:ok, %Postgrex.Result{rows: [["i1", nil, 5]]}} =
             Postgrex.query(
               conn,
               ~s[SELECT "id", "note", "qty" FROM "#{schema}"."items" WHERE "id" = 'i1'],
               []
             )
  end

  test "a text default that contains SQL-looking text is stored as data, never split into statements", %{
    conn: conn,
    schema: schema
  } do
    res1 = base_resource()
    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])
    Postgrex.query!(conn, ~s[INSERT INTO "#{schema}"."items" ("id") VALUES ('i1')], [])

    hostile = "x'; ALTER TABLE victim DROP COLUMN y; -- ; ALTER TABLE z"

    res2 =
      base_resource(%{
        schema_hash: "hash_hostile_default",
        columns: res1.columns ++ [%{name: "note", storage: "text", nullable: false, default: hostile}]
      })

    assert {:ok, live} = Schema.read_live_state(conn, schema, [res2])
    assert {:ok, plan} = Schema.plan([res2], live)
    assert {:ok, _} = Schema.apply(conn, plan)

    assert {:ok, %Postgrex.Result{rows: [[^hostile]]}} =
             Postgrex.query(conn, ~s[SELECT "note" FROM "#{schema}"."items" WHERE "id" = 'i1'], [])
  end

  test "add NOT NULL column without default: safe on empty table, unsafe on non-empty table", %{
    conn: conn,
    schema: schema
  } do
    res1 = base_resource()
    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])

    # 1. Empty table -> safe
    res_empty_add =
      base_resource(%{
        schema_hash: "hash_empty_add",
        columns:
          res1.columns ++
            [%{name: "sku", storage: "text", nullable: false, default: nil}]
      })

    assert {:ok, live_empty} = Schema.read_live_state(conn, schema, [res_empty_add])
    assert {:ok, plan_empty} = Schema.plan([res_empty_add], live_empty)
    assert [%{op: :add_column, column: "sku", safety: :safe}] = plan_empty.ops
    assert {:ok, _} = Schema.apply(conn, plan_empty)

    # 2. Insert a row -> non-empty table -> unsafe
    Postgrex.query!(
      conn,
      ~s[INSERT INTO "#{schema}"."items" ("id", "sku") VALUES ('i1', 'SKU-1')],
      []
    )

    res_nonempty_add =
      base_resource(%{
        schema_hash: "hash_nonempty_add",
        columns:
          res_empty_add.columns ++
            [%{name: "owner_id", storage: "text", nullable: false, default: nil}]
      })

    assert {:ok, live_nonempty} = Schema.read_live_state(conn, schema, [res_nonempty_add])
    assert {:ok, plan_nonempty} = Schema.plan([res_nonempty_add], live_nonempty)
    assert [%{op: :add_column, table: "items", column: "owner_id", safety: :unsafe, reason: reason}] =
             plan_nonempty.ops

    assert reason =~ "items"
    assert reason =~ "owner_id"

    assert {:error, {:unsafe_schema_change, [unsafe_op]}} = Schema.apply(conn, plan_nonempty)
    assert unsafe_op.table == "items"
    assert unsafe_op.column == "owner_id"
  end

  test "index and unique index creation, and unique index over duplicates refused", %{
    conn: conn,
    schema: schema
  } do
    res1 =
      base_resource(%{
        schema_hash: "hash_idx_1",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "code", storage: "text", nullable: false, default: "A"},
          %{name: "tag", storage: "text", nullable: true}
        ]
      })

    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])

    Postgrex.query!(
      conn,
      ~s[INSERT INTO "#{schema}"."items" ("id", "code", "tag") VALUES ('1', 'DUP', 't1'), ('2', 'DUP', 't2')],
      []
    )

    # Unique index on 'code' (has duplicates) -> unsafe
    res_dup =
      base_resource(%{
        schema_hash: "hash_idx_2",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "code", storage: "text", nullable: false, default: "A", unique: true},
          %{name: "tag", storage: "text", nullable: true, indexed: true}
        ]
      })

    assert {:ok, live_dup} = Schema.read_live_state(conn, schema, [res_dup])
    assert {:ok, plan_dup} = Schema.plan([res_dup], live_dup)

    unique_op = Enum.find(plan_dup.ops, &(&1.column == "code"))
    assert unique_op.op == :create_unique_index
    assert unique_op.safety == :unsafe
    assert unique_op.reason =~ "duplicate"

    assert {:error, {:unsafe_schema_change, _}} = Schema.apply(conn, plan_dup)

    # Fix duplicates -> unique index + normal index both safe
    Postgrex.query!(
      conn,
      ~s[UPDATE "#{schema}"."items" SET "code" = 'UNIQ2' WHERE "id" = '2'],
      []
    )

    assert {:ok, live_ok} = Schema.read_live_state(conn, schema, [res_dup])
    assert {:ok, plan_ok} = Schema.plan([res_dup], live_ok)
    assert Enum.all?(plan_ok.ops, &(&1.safety == :safe))
    assert {:ok, _} = Schema.apply(conn, plan_ok)
  end

  test "safe type widening and unsafe narrowing/incompatible type changes (including ->jsonb)", %{
    conn: conn,
    schema: schema
  } do
    res1 =
      base_resource(%{
        schema_hash: "widen_1",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "count", storage: "smallint", nullable: false, default: 1},
          %{name: "ratio", storage: "real", nullable: false, default: 1.5}
        ]
      })

    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])

    # Safe widening: smallint -> integer, real -> double precision
    res2 =
      base_resource(%{
        schema_hash: "widen_2",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "count", storage: "integer", nullable: false, default: 1},
          %{name: "ratio", storage: "double precision", nullable: false, default: 1.5}
        ]
      })

    assert {:ok, live2} = Schema.read_live_state(conn, schema, [res2])
    assert {:ok, plan2} = Schema.plan([res2], live2)
    assert length(plan2.ops) == 2
    assert Enum.all?(plan2.ops, &(&1.op == :widen_type and &1.safety == :safe))
    assert {:ok, _} = Schema.apply(conn, plan2)

    # Safe widening: integer -> bigint -> numeric
    res3 =
      base_resource(%{
        schema_hash: "widen_3",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "count", storage: "numeric", nullable: false, default: 1},
          %{name: "ratio", storage: "double precision", nullable: false, default: 1.5}
        ]
      })

    assert {:ok, _} = Schema.reconcile(conn, schema, [res3])

    # Unsafe narrowing: numeric -> integer
    res_narrow =
      base_resource(%{
        schema_hash: "narrow_1",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "count", storage: "integer", nullable: false, default: 1},
          %{name: "ratio", storage: "double precision", nullable: false, default: 1.5}
        ]
      })

    assert {:ok, live_narrow} = Schema.read_live_state(conn, schema, [res_narrow])
    assert {:ok, plan_narrow} = Schema.plan([res_narrow], live_narrow)
    assert [%{op: :alter_type, column: "count", safety: :unsafe}] = plan_narrow.ops
    assert {:error, {:unsafe_schema_change, _}} = Schema.apply(conn, plan_narrow)

    # Unsafe: text/numeric -> jsonb is NOT safe
    res_jsonb =
      base_resource(%{
        schema_hash: "to_jsonb",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "count", storage: "jsonb", nullable: true},
          %{name: "ratio", storage: "double precision", nullable: false, default: 1.5}
        ]
      })

    assert {:ok, live_jb} = Schema.read_live_state(conn, schema, [res_jsonb])
    assert {:ok, plan_jb} = Schema.plan([res_jsonb], live_jb)
    assert Enum.any?(plan_jb.ops, &(&1.column == "count" and &1.safety == :unsafe))
    assert {:error, {:unsafe_schema_change, _}} = Schema.apply(conn, plan_jb)
  end

  test "enum CHECK widening is safe and narrowing is unsafe", %{conn: conn, schema: schema} do
    res1 = base_resource()
    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])

    # Widen choices: ["common", "rare"] -> ["common", "rare", "epic"]
    res_wide =
      base_resource(%{
        schema_hash: "enum_wide",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "price", storage: "integer", nullable: false, indexed: true, default: 10},
          %{
            name: "tier",
            storage: "text",
            nullable: false,
            default: "common",
            choices: ["common", "rare", "epic"]
          }
        ]
      })

    assert {:ok, live_wide} = Schema.read_live_state(conn, schema, [res_wide])
    assert {:ok, plan_wide} = Schema.plan([res_wide], live_wide)
    assert [%{op: :alter_enum_check, column: "tier", safety: :safe}] = plan_wide.ops
    assert {:ok, _} = Schema.apply(conn, plan_wide)

    # Insert 'epic' row now works
    Postgrex.query!(
      conn,
      ~s[INSERT INTO "#{schema}"."items" ("id", "tier") VALUES ('e1', 'epic')],
      []
    )

    # Narrow choices: ["common", "rare", "epic"] -> ["common", "rare"] -> unsafe
    res_narrow = base_resource(%{schema_hash: "enum_narrow"})
    assert {:ok, live_narrow} = Schema.read_live_state(conn, schema, [res_narrow])
    assert {:ok, plan_narrow} = Schema.plan([res_narrow], live_narrow)
    assert [%{op: :alter_enum_check, column: "tier", safety: :unsafe, reason: reason}] =
             plan_narrow.ops

    assert reason =~ "tier"
    assert {:error, {:unsafe_schema_change, _}} = Schema.apply(conn, plan_narrow)
  end

  test "drop_column and primary key change are refused with messages naming them", %{
    conn: conn,
    schema: schema
  } do
    res1 = base_resource()
    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])

    # Drop 'tier' column
    res_drop =
      base_resource(%{
        schema_hash: "drop_col",
        columns: Enum.reject(res1.columns, &(&1.name == "tier"))
      })

    assert {:ok, live_drop} = Schema.read_live_state(conn, schema, [res_drop])
    assert {:ok, plan_drop} = Schema.plan([res_drop], live_drop)
    assert [%{op: :drop_column, table: "items", column: "tier", safety: :unsafe, reason: drop_msg}] =
             plan_drop.ops

    assert drop_msg =~ "items"
    assert drop_msg =~ "tier"
    assert {:error, {:unsafe_schema_change, _}} = Schema.apply(conn, plan_drop)

    # Change PK from 'id' to 'price'
    res_pk =
      base_resource(%{
        schema_hash: "pk_change",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: false},
          %{name: "price", storage: "integer", nullable: false, primary_key: true, default: 10},
          %{
            name: "tier",
            storage: "text",
            nullable: false,
            default: "common",
            choices: ["common", "rare"]
          }
        ]
      })

    assert {:ok, live_pk} = Schema.read_live_state(conn, schema, [res_pk])
    assert {:ok, plan_pk} = Schema.plan([res_pk], live_pk)
    pk_op = Enum.find(plan_pk.ops, &(&1.op == :change_primary_key))
    assert pk_op.safety == :unsafe
    assert pk_op.reason =~ "items"
    assert {:error, {:unsafe_schema_change, _}} = Schema.apply(conn, plan_pk)
  end

  test "set NOT NULL on nullable live column is unsafe without default or with NULLs, safe when default exists and no NULLs",
       %{conn: conn, schema: schema} do
    res1 =
      base_resource(%{
        schema_hash: "nn_1",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "tag", storage: "text", nullable: true}
        ]
      })

    assert {:ok, _} = Schema.reconcile(conn, schema, [res1])
    Postgrex.query!(conn, ~s[INSERT INTO "#{schema}"."items" ("id", "tag") VALUES ('1', NULL)], [])

    # Has NULLs -> unsafe even with default
    res_with_default =
      base_resource(%{
        schema_hash: "nn_2",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "tag", storage: "text", nullable: false, default: "none"}
        ]
      })

    assert {:ok, live_nulls} = Schema.read_live_state(conn, schema, [res_with_default])
    assert {:ok, plan_nulls} = Schema.plan([res_with_default], live_nulls)
    assert Enum.any?(plan_nulls.ops, &(&1.op == :set_not_null and &1.safety == :unsafe))

    # Update NULLs to non-null, but no default -> unsafe
    Postgrex.query!(conn, ~s[UPDATE "#{schema}"."items" SET "tag" = 'ok' WHERE "id" = '1'], [])

    res_no_default =
      base_resource(%{
        schema_hash: "nn_3",
        columns: [
          %{name: "id", storage: "text", nullable: false, primary_key: true},
          %{name: "tag", storage: "text", nullable: false, default: nil}
        ]
      })

    assert {:ok, live_nodef} = Schema.read_live_state(conn, schema, [res_no_default])
    assert {:ok, plan_nodef} = Schema.plan([res_no_default], live_nodef)
    assert Enum.any?(plan_nodef.ops, &(&1.op == :set_not_null and &1.safety == :unsafe))

    # No NULLs and default exists -> safe
    assert {:ok, live_safe} = Schema.read_live_state(conn, schema, [res_with_default])
    assert {:ok, plan_safe} = Schema.plan([res_with_default], live_safe)
    assert Enum.all?(plan_safe.ops, &(&1.safety == :safe))
    assert {:ok, _} = Schema.apply(conn, plan_safe)
  end

  test "envelope table (id text PK, data jsonb, updated_at) is reported as :convert_envelope (:unsafe) and left untouched",
       %{conn: conn, schema: schema} do
    Postgrex.query!(
      conn,
      """
      CREATE TABLE "#{schema}"."items" (
        id text PRIMARY KEY,
        data jsonb NOT NULL,
        updated_at timestamp DEFAULT CURRENT_TIMESTAMP
      )
      """,
      []
    )

    Postgrex.query!(
      conn,
      ~s[INSERT INTO "#{schema}"."items" (id, data) VALUES ('old_1', '{"price": 99}'::jsonb)],
      []
    )

    res = base_resource()
    assert {:ok, live} = Schema.read_live_state(conn, schema, [res])
    assert {:ok, plan} = Schema.plan([res], live)

    assert [%{op: :convert_envelope, table: "items", safety: :unsafe, reason: reason}] = plan.ops
    assert reason =~ "items"

    assert {:error, {:unsafe_schema_change, [op]}} = Schema.apply(conn, plan)
    assert op.op == :convert_envelope

    # Verify table is completely untouched
    assert {:ok, %Postgrex.Result{rows: [["old_1", %{"price" => 99}]]}} =
             Postgrex.query(conn, ~s[SELECT id, data FROM "#{schema}"."items"], [])
  end

  test "lldb.plan_schema action returns ops, classification and reasons and changes nothing", %{
    plugin: plugin,
    conn: conn,
    schema: schema
  } do
    Exoforge.ExtensionCase.start_kernel()
    Exoforge.ExtensionCase.register_extension(Exoforge.Std.Lldb,
      id: :exoforge_std_lldb,
      provides: [Exoforge.Std.Services.Lldb]
    )

    res = base_resource()

    Exoforge.ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: plugin,
      name: to_string(plugin),
      version: "1.0.0",
      entry_point: nil,
      provides: [plugin],
      services: [
        %{
          name: plugin,
          resources: [res]
        }
      ]
    })

    assert {:ok, result} =
             Exoforge.ActionDispatcher.dispatch(
               :lldb,
               :plan_schema,
               %{extension: plugin},
               caller_scopes: ["studio"]
             )

    assert result.safe == true
    assert Enum.any?(result.ops, &(&1.op == :create_table and &1.table == "items"))

    # Verify nothing was applied in the database
    assert {:ok, %Postgrex.Result{rows: []}} =
             Postgrex.query(
               conn,
               "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'items'",
               [schema]
             )

    # Player scope is forbidden
    assert {:error, {:forbidden_scope, _}} =
             Exoforge.ActionDispatcher.dispatch(
               :lldb,
               :plan_schema,
               %{extension: plugin},
               caller_scopes: ["player"]
             )
  end

  test "hostile identifiers, storage types, and defaults are rejected without SQL injection", %{
    conn: conn,
    schema: schema
  } do
    hostile_table =
      base_resource(%{
        source: %{table: "items\"; DROP TABLE users; --"}
      })

    assert {:error, {:invalid_identifier, _}} =
             Schema.reconcile(conn, schema, [hostile_table])

    hostile_col =
      base_resource(%{
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "BadUpper", storage: "text"}
        ]
      })

    assert {:error, {:invalid_identifier, "BadUpper"}} =
             Schema.reconcile(conn, schema, [hostile_col])

    hostile_type =
      base_resource(%{
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "x", storage: "text; DROP SCHEMA public CASCADE"}
        ]
      })

    assert {:error, {:invalid_storage_type, _}} =
             Schema.reconcile(conn, schema, [hostile_type])

    hostile_int_default =
      base_resource(%{
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "price", storage: "integer", default: "0; DROP TABLE items; --"}
        ]
      })

    assert {:error, {:invalid_default, "price", "integer", _}} =
             Schema.reconcile(conn, schema, [hostile_int_default])

    hostile_uuid_default =
      base_resource(%{
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "uid", storage: "uuid", default: "not-a-uuid' OR 1=1"}
        ]
      })

    assert {:error, {:invalid_default, "uid", "uuid", _}} =
             Schema.reconcile(conn, schema, [hostile_uuid_default])

    hostile_ts_default =
      base_resource(%{
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "created_at", storage: "timestamptz", default: "2026-99-99'; DROP TABLE items;--"}
        ]
      })

    assert {:error, {:invalid_default, "created_at", "timestamptz", _}} =
             Schema.reconcile(conn, schema, [hostile_ts_default])

    hostile_json_default =
      base_resource(%{
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "meta", storage: "jsonb", default: "{bad json"}
        ]
      })

    assert {:error, {:invalid_default, "meta", "jsonb", _}} =
             Schema.reconcile(conn, schema, [hostile_json_default])

    # Text default with single quotes is safely escaped, not injected
    quoted_text_res =
      base_resource(%{
        schema_hash: "quoted_text",
        columns: [
          %{name: "id", storage: "text", primary_key: true},
          %{name: "title", storage: "text", nullable: false, default: "O'Reilly'; DROP TABLE items;--"}
        ]
      })

    assert {:ok, _} = Schema.reconcile(conn, schema, [quoted_text_res])
    Postgrex.query!(conn, ~s[INSERT INTO "#{schema}"."items" ("id") VALUES ('b1')], [])

    assert {:ok, %Postgrex.Result{rows: [["O'Reilly'; DROP TABLE items;--"]]}} =
             Postgrex.query(conn, ~s[SELECT "title" FROM "#{schema}"."items" WHERE "id" = 'b1'], [])
  end

  test "two concurrent applies serialize via pg_advisory_xact_lock without error", %{
    schema: schema,
    cfg: cfg
  } do
    res = base_resource()

    conn1 =
      start_supervised!(
        {Postgrex,
         hostname: cfg.host,
         port: cfg.port,
         username: cfg.username,
         password: cfg.password,
         database: cfg.database},
        id: :concurrent_conn1
      )

    conn2 =
      start_supervised!(
        {Postgrex,
         hostname: cfg.host,
         port: cfg.port,
         username: cfg.username,
         password: cfg.password,
         database: cfg.database},
        id: :concurrent_conn2
      )

    assert {:ok, live1} = Schema.read_live_state(conn1, schema, [res])
    assert {:ok, live2} = Schema.read_live_state(conn2, schema, [res])
    assert {:ok, plan1} = Schema.plan([res], live1)
    assert {:ok, plan2} = Schema.plan([res], live2)

    t1 = Task.async(fn -> Schema.apply(conn1, plan1) end)
    t2 = Task.async(fn -> Schema.apply(conn2, plan2) end)

    assert {:ok, _} = Task.await(t1, 10_000)
    assert {:ok, _} = Task.await(t2, 10_000)
  end
end
