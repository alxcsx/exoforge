defmodule Exoforge.Std.Lldb.Adapters.PostgresTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Adapters.Postgres
  alias Exoforge.Std.Lldb.Manager
  alias Exoforge.Std.Lldb.TestDB

  defp pg_config, do: TestDB.config()

  describe "pool size" do
    test "defaults to 4 connections, overridable for everyone and for one extension" do
      {:ok, default_cfg} = Postgres.connection_config(:wallet, %{})
      assert default_cfg.pool_size == 4

      {:ok, custom_cfg} = Postgres.connection_config(:wallet, %{pool_size: 6})
      assert custom_cfg.pool_size == 6

      # an extension's own setting beats the shared one; the others keep the shared one
      config = %{pool_size: 6, pool_sizes: %{"auth" => 12}}
      assert {:ok, %{pool_size: 12}} = Postgres.connection_config(:auth, config)
      assert {:ok, %{pool_size: 6}} = Postgres.connection_config(:wallet, config)

      # nonsense falls back instead of starting a pool of nothing
      assert {:ok, %{pool_size: 4}} = Postgres.connection_config(:wallet, %{pool_size: 0, pool_sizes: %{"wallet" => -1}})
    end

    test "the environment sets the shared size and per-extension sizes" do
      System.put_env("EXOFORGE_DB_POOL_SIZE", "5")
      System.put_env("EXOFORGE_DB_POOL_SIZES", "auth=9, player_data=7 ,bogus,x=0")

      try do
        {:ok, pid} = Manager.start_link([])
        {_adapter, config} = :persistent_term.get({Manager, :runtime})
        assert config.pool_size == 5
        assert config.pool_sizes == %{"auth" => 9, "player_data" => 7}
        GenServer.stop(pid)
      after
        System.delete_env("EXOFORGE_DB_POOL_SIZE")
        System.delete_env("EXOFORGE_DB_POOL_SIZES")
      end
    end
  end

  describe "cross-extension tables" do
    @tag :postgres
    test "a missing relation explains that tables are private to each extension" do
      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      plugin = :"pg_missing_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Postgres.ensure_database(plugin, pg_config())
      on_exit(fn -> _ = Postgres.reset(plugin, pg_config()) end)

      assert {:error, {:postgres_error, message}} =
               Postgres.execute(plugin, "SELECT * FROM other_extension_table", [], pg_config())

      assert message =~ "does not exist"
      assert message =~ "get_many"
      assert message =~ "typed stub"
    end
  end

  describe "throwaway test database & Manager isolation" do
    @tag :postgres
    test "uses a throwaway exoforge_test_* database and isolates plugin schemas via Manager" do
      cfg = pg_config()
      assert cfg.database != "exoforge_prod"
      assert String.starts_with?(cfg.database, "exoforge_test_")

      unless Process.whereis(Exoforge.Std.Lldb.PoolRegistry) do
        start_supervised!({Registry, keys: :unique, name: Exoforge.Std.Lldb.PoolRegistry})
      end

      unless Process.whereis(Exoforge.Std.Lldb.PoolSupervisor) do
        start_supervised!({DynamicSupervisor, name: Exoforge.Std.Lldb.PoolSupervisor, strategy: :one_for_one})
      end

      unless Process.whereis(Manager) do
        start_supervised!({Manager, [driver: :postgres] ++ Map.to_list(cfg)})
      end

      plugin_a = :"pg_mgr_a_#{System.unique_integer([:positive])}"
      plugin_b = :"pg_mgr_b_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        _ = Postgres.reset(plugin_a, cfg)
        _ = Postgres.reset(plugin_b, cfg)
      end)

      assert {:ok, conn_cfg} = Manager.connection_config(plugin_a)
      assert conn_cfg.driver == :postgres
      assert conn_cfg.schema == "plugin_#{Lldb.clean_id(plugin_a)}"

      assert {:ok, %{rows: [%{"db" => current_db, "schema" => current_schema}]}} =
               Manager.execute(plugin_a, "SELECT current_database() AS db, current_schema() AS schema")

      assert current_db == cfg.database
      assert current_schema == "plugin_#{Lldb.clean_id(plugin_a)}"

      assert {:ok, _} = Manager.execute(plugin_a, "CREATE TABLE items (id text PRIMARY KEY, owner text NOT NULL)")
      assert {:ok, _} = Manager.execute(plugin_a, "INSERT INTO items (id, owner) VALUES ($1, $2)", ["i1", "alpha"])

      assert {:error, {:postgres_error, msg}} = Manager.execute(plugin_b, "SELECT * FROM items")
      assert msg =~ "does not exist"

      assert {:ok, _} = Manager.execute(plugin_b, "CREATE TABLE items (id text PRIMARY KEY, owner text NOT NULL)")
      assert {:ok, _} = Manager.execute(plugin_b, "INSERT INTO items (id, owner) VALUES ($1, $2)", ["i1", "beta"])

      assert {:ok, %{rows: [%{"id" => "i1", "owner" => "alpha"}]}} =
               Manager.execute(plugin_a, "SELECT id, owner FROM items")

      assert {:ok, %{rows: [%{"id" => "i1", "owner" => "beta"}]}} =
               Manager.execute(plugin_b, "SELECT id, owner FROM items")
    end
  end

  describe "D5: per-extension login roles and db_read grants" do
    test "ManifestLoader preserves declared db_read list from manifest.json" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "d5_manifest_loader_#{System.unique_integer([:positive])}")

      ext_dir = Path.join(tmp_dir, "store_ext")
      File.mkdir_p!(ext_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      File.write!(
        Path.join(ext_dir, "manifest.json"),
        Jason.encode!(%{
          "id" => "store_ext",
          "version" => "1.0.0",
          "type" => "native",
          "entry_point" => "StoreExt",
          "dependencies" => ["items_ext", "catalog_ext"],
          "provides" => ["store_ext"],
          "db_read" => ["items_ext", "catalog_ext"]
        })
      )

      [manifest] = Exoforge.Drivers.Loaders.ManifestLoader.load_extensions(tmp_dir)
      assert manifest.id == :store_ext
      assert Map.get(manifest, :db_read) == [:items_ext, :catalog_ext]
    end

    test "role_name is deterministic, <= 63 bytes, includes db hash, and rejects invalid identifiers" do
      cfg_a = %{database: "exoforge_test_aaa"}
      cfg_b = %{database: "exoforge_test_bbb"}

      role_a = Postgres.role_name(:store, cfg_a)
      assert role_a == Postgres.role_name("store", cfg_a)
      assert byte_size(role_a) <= 63
      assert role_a =~ ~r/^ext_[a-f0-9]{8}_store$/

      role_b = Postgres.role_name(:store, cfg_b)
      assert role_a != role_b

      long_id = String.duplicate("very_long_extension_name_", 4)
      long_role = Postgres.role_name(long_id, cfg_a)
      assert byte_size(long_role) == 63
      assert long_role =~ ~r/^[a-z0-9_]+$/
      assert long_role == Postgres.role_name(long_id, cfg_a)

      assert_raise ArgumentError, fn ->
        Postgres.role_name("bad; DROP ROLE postgres--", cfg_a)
      end

      assert_raise ArgumentError, fn ->
        Postgres.role_name(:store, %{database: "bad\"db"})
      end
    end

    @tag :postgres
    test "enforces per-extension login roles, db_read grants, revocations, migration, uninstall, and CREATEROLE check" do
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

      super_cfg = pg_config()
      suffix = System.unique_integer([:positive])
      admin_user = "exo_cr_admin_#{suffix}"
      nocr_user = "exo_nocr_admin_#{suffix}"

      {:ok, root_conn} =
        Postgrex.start_link(
          hostname: super_cfg.host,
          port: super_cfg.port,
          username: super_cfg.username,
          password: super_cfg.password,
          database: super_cfg.database
        )

      Postgrex.query!(
        root_conn,
        ~s[CREATE ROLE "#{admin_user}" WITH LOGIN CREATEROLE NOCREATEDB NOSUPERUSER PASSWORD 'cr_secret'],
        []
      )

      Postgrex.query!(
        root_conn,
        ~s[CREATE ROLE "#{nocr_user}" WITH LOGIN NOCREATEROLE NOCREATEDB NOSUPERUSER PASSWORD 'nocr_secret'],
        []
      )

      Postgrex.query!(
        root_conn,
        ~s[ALTER DATABASE "#{super_cfg.database}" OWNER TO "#{admin_user}"],
        []
      )

      Postgrex.query!(
        root_conn,
        ~s[GRANT CONNECT, CREATE ON DATABASE "#{super_cfg.database}" TO "#{nocr_user}"],
        []
      )

      GenServer.stop(root_conn)

      cfg =
        Map.merge(super_cfg, %{
          username: admin_user,
          password: "cr_secret",
          role_secret: "d5_test_hmac_secret"
        })

      nocr_cfg =
        Map.merge(super_cfg, %{
          username: nocr_user,
          password: "nocr_secret",
          role_secret: "d5_test_hmac_secret"
        })

      items_id = :"d5_items_#{suffix}"
      store_id = :"d5_store_#{suffix}"
      secret_id = :"d5_secret_#{suffix}"
      legacy_id = :"d5_legacy_#{suffix}"
      plain_nocr_id = :"d5_plain_nocr_#{suffix}"
      reader_nocr_id = :"d5_reader_nocr_#{suffix}"

      on_exit(fn ->
        _ = Postgres.reset(store_id, cfg)
        _ = Postgres.reset(items_id, cfg)
        _ = Postgres.reset(secret_id, cfg)
        _ = Postgres.reset(legacy_id, cfg)
        _ = Postgres.reset(plain_nocr_id, nocr_cfg)
      end)

      register_manifest = fn id, db_read ->
        Exoforge.ExtensionRegistry.register(%Exoforge.Domain.Manifest{
          id: id,
          name: to_string(id),
          version: "1.0.0",
          entry_point: nil,
          provides: [id],
          dependencies: db_read,
          db_read: db_read
        })
      end

      register_manifest.(items_id, [])
      register_manifest.(secret_id, [])
      register_manifest.(store_id, [items_id, :"d5_unprovisioned_#{suffix}"])

      # 1. Provision items, secret, and store (idempotent on repeated ensure_database calls;
      #    unprovisioned db_read target logs a warning instead of crashing)
      assert {:ok, _} = Postgres.ensure_database(items_id, cfg)
      assert {:ok, _} = Postgres.ensure_database(items_id, cfg)
      assert {:ok, _} = Postgres.ensure_database(secret_id, cfg)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, _} = Postgres.ensure_database(store_id, cfg)
        end)

      assert log =~ "d5_unprovisioned_#{suffix}"

      store_role = Postgres.role_name(store_id, cfg)
      items_role = Postgres.role_name(items_id, cfg)
      secret_role = Postgres.role_name(secret_id, cfg)
      items_schema = "plugin_#{items_id}"
      secret_schema = "plugin_#{secret_id}"

      # 2. Pool connects as the extension's LOGIN role with timeouts and connection limit
      assert {:ok, %{rows: [%{"u" => ^store_role, "st" => "30s", "it" => "1min"}]}} =
               Postgres.execute(
                 store_id,
                 "SELECT current_user AS u, current_setting('statement_timeout') AS st, current_setting('idle_in_transaction_session_timeout') AS it",
                 [],
                 cfg
               )

      assert {:ok, %{rows: [%{"rolconnlimit" => 6}]}} =
               Postgres.execute(
                 store_id,
                 "SELECT rolconnlimit FROM pg_roles WHERE rolname = $1",
                 [store_role],
                 cfg
               )

      # 3. Own schema read/write works for each extension
      assert {:ok, _} =
               Postgres.execute(
                 items_id,
                 "CREATE TABLE catalog (id text PRIMARY KEY, price integer NOT NULL)",
                 [],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 items_id,
                 "INSERT INTO catalog (id, price) VALUES ($1, $2)",
                 ["sword", 100],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 secret_id,
                 "CREATE TABLE vault (id text PRIMARY KEY, code text NOT NULL)",
                 [],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 secret_id,
                 "INSERT INTO vault (id, code) VALUES ($1, $2)",
                 ["v1", "top_secret"],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 store_id,
                 "CREATE TABLE orders (id text PRIMARY KEY, item_id text NOT NULL, qty integer NOT NULL)",
                 [],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 store_id,
                 "INSERT INTO orders (id, item_id, qty) VALUES ($1, $2, $3)",
                 ["o1", "sword", 2],
                 cfg
               )

      # Re-run ensure_database on store so existing + future tables in items are granted
      register_manifest.(store_id, [items_id])
      assert {:ok, _} = Postgres.ensure_database(store_id, cfg)

      # 4. Declared JOIN across schemas returns rows (including tables created after the grant via default privileges)
      assert {:ok, %{rows: [%{"id" => "o1", "total" => 200}]}} =
               Postgres.execute(
                 store_id,
                 ~s[SELECT o.id, o.qty * c.price AS total FROM orders o JOIN "#{items_schema}".catalog c ON c.id = o.item_id],
                 [],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 items_id,
                 "CREATE TABLE seasonal_items (id text PRIMARY KEY, discount integer NOT NULL)",
                 [],
                 cfg
               )

      assert {:ok, _} =
               Postgres.execute(
                 items_id,
                 "INSERT INTO seasonal_items (id, discount) VALUES ($1, $2)",
                 ["sword", 15],
                 cfg
               )

      assert {:ok, %{rows: [%{"id" => "sword", "discount" => 15}]}} =
               Postgres.execute(
                 store_id,
                 ~s[SELECT id, discount FROM "#{items_schema}".seasonal_items],
                 [],
                 cfg
               )

      # 5. Write and DROP on declared foreign schema are denied
      assert {:error, {:postgres_error, ins_err}} =
               Postgres.execute(
                 store_id,
                 ~s[INSERT INTO "#{items_schema}".catalog (id, price) VALUES ('hack', 1)],
                 [],
                 cfg
               )

      assert ins_err =~ "permission denied"

      assert {:error, {:postgres_error, upd_err}} =
               Postgres.execute(
                 store_id,
                 ~s[UPDATE "#{items_schema}".catalog SET price = 0],
                 [],
                 cfg
               )

      assert upd_err =~ "permission denied"

      assert {:error, {:postgres_error, del_err}} =
               Postgres.execute(
                 store_id,
                 ~s[DELETE FROM "#{items_schema}".catalog],
                 [],
                 cfg
               )

      assert del_err =~ "permission denied"

      assert {:error, {:postgres_error, drop_err}} =
               Postgres.execute(
                 store_id,
                 ~s[DROP TABLE "#{items_schema}".catalog],
                 [],
                 cfg
               )

      assert drop_err =~ "must be owner" or drop_err =~ "permission denied"

      # 6. Undeclared schema is denied
      assert {:error, {:postgres_error, secret_err}} =
               Postgres.execute(
                 store_id,
                 ~s[SELECT * FROM "#{secret_schema}".vault],
                 [],
                 cfg
               )

      assert secret_err =~ "permission denied"

      # 7. SET ROLE other / admin and RESET ROLE escape attempts are denied / no-op
      assert {:error, {:postgres_error, set_other_err}} =
               Postgres.execute(store_id, ~s[SET ROLE "#{secret_role}"], [], cfg)

      assert set_other_err =~ "permission denied"

      assert {:error, {:postgres_error, set_items_err}} =
               Postgres.execute(store_id, ~s[SET ROLE "#{items_role}"], [], cfg)

      assert set_items_err =~ "permission denied"

      assert {:error, {:postgres_error, set_admin_err}} =
               Postgres.execute(store_id, ~s[SET ROLE "#{admin_user}"], [], cfg)

      assert set_admin_err =~ "permission denied"

      assert {:ok, _} = Postgres.execute(store_id, "RESET ROLE", [], cfg)

      assert {:ok, %{rows: [%{"u" => ^store_role}]}} =
               Postgres.execute(store_id, "SELECT current_user AS u", [], cfg)

      assert {:error, {:postgres_error, _}} =
               Postgres.execute(store_id, ~s[SELECT * FROM "#{secret_schema}".vault], [], cfg)

      # 8. Revoke when reader drops the db_read declaration
      register_manifest.(store_id, [])
      assert {:ok, _} = Postgres.ensure_database(store_id, cfg)

      assert {:error, {:postgres_error, revoked_err}} =
               Postgres.execute(
                 store_id,
                 ~s[SELECT * FROM "#{items_schema}".catalog],
                 [],
                 cfg
               )

      assert revoked_err =~ "permission denied"

      # 9. Uninstall (reset) revokes reads as each grantor, drops owned objects and role, leaving no residue
      register_manifest.(store_id, [items_id])
      assert {:ok, _} = Postgres.ensure_database(store_id, cfg)

      assert {:ok, %{rows: [%{"id" => "sword"}]}} =
               Postgres.execute(store_id, ~s[SELECT id FROM "#{items_schema}".catalog], [], cfg)

      assert :ok = Postgres.reset(store_id, cfg)

      assert {:ok, %{rows: []}} =
               Postgres.execute(
                 items_id,
                 "SELECT rolname FROM pg_roles WHERE rolname = $1",
                 [store_role],
                 cfg
               )

      assert {:ok, %{rows: []}} =
               Postgres.execute(
                 items_id,
                 "SELECT nspname FROM pg_namespace WHERE nspname = $1",
                 ["plugin_#{store_id}"],
                 cfg
               )

      # 10. Existing schema owned by admin is migrated (tables first, then schema)
      {:ok, admin_conn} =
        Postgrex.start_link(
          hostname: cfg.host,
          port: cfg.port,
          username: cfg.username,
          password: cfg.password,
          database: cfg.database
        )

      legacy_schema = "plugin_#{legacy_id}"
      Postgrex.query!(admin_conn, ~s[CREATE SCHEMA "#{legacy_schema}"], [])

      Postgrex.query!(
        admin_conn,
        ~s[CREATE TABLE "#{legacy_schema}".legacy_data (id text PRIMARY KEY, v integer NOT NULL)],
        []
      )

      Postgrex.query!(
        admin_conn,
        ~s[INSERT INTO "#{legacy_schema}".legacy_data (id, v) VALUES ('k1', 77)],
        []
      )

      GenServer.stop(admin_conn)

      register_manifest.(legacy_id, [])
      assert {:ok, _} = Postgres.ensure_database(legacy_id, cfg)
      legacy_role = Postgres.role_name(legacy_id, cfg)

      assert {:ok, %{rows: [%{"tableowner" => ^legacy_role}]}} =
               Postgres.execute(
                 legacy_id,
                 "SELECT tableowner FROM pg_tables WHERE schemaname = $1 AND tablename = 'legacy_data'",
                 [legacy_schema],
                 cfg
               )

      assert {:ok, %{rows: [%{"rolname" => ^legacy_role}]}} =
               Postgres.execute(
                 legacy_id,
                 "SELECT r.rolname FROM pg_namespace n JOIN pg_roles r ON r.oid = n.nspowner WHERE n.nspname = $1",
                 [legacy_schema],
                 cfg
               )

      assert {:ok, %{rows: [%{"id" => "k1", "v" => 77, "u" => ^legacy_role}]}} =
               Postgres.execute(
                 legacy_id,
                 "SELECT id, v, current_user AS u FROM legacy_data",
                 [],
                 cfg
               )

      # 11. Missing CREATEROLE keeps single-user fallback without db_read and refuses db_read
      register_manifest.(plain_nocr_id, [])
      assert {:ok, _} = Postgres.ensure_database(plain_nocr_id, nocr_cfg)

      assert {:ok, %{rows: [%{"u" => ^nocr_user}]}} =
               Postgres.execute(plain_nocr_id, "SELECT current_user AS u", [], nocr_cfg)

      register_manifest.(reader_nocr_id, [items_id])
      assert {:error, {:createrole_required, err_msg}} =
               Postgres.ensure_database(reader_nocr_id, nocr_cfg)

      assert err_msg =~ "CREATEROLE"
      assert err_msg =~ "db_read"
    end
  end
end
