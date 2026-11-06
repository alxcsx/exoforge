defmodule Exoforge.DatabaseTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Database
  alias Exoforge.Std.Database.Manager

  setup do
    start_supervised!({Manager, [driver: :sqlite]})
    Database.reset!(:auth)
    Database.reset!(:player_data)
    Database.reset!(:combat)
    :ok
  end

  describe "Multi-tenant Isolation" do
    test "each plugin operates in its own isolated database" do
      # 1. Plugin :auth creates a users table and inserts a user
      assert {:ok, _} =
               Database.execute(:auth, "CREATE TABLE users (id text, username text, email text)")

      assert {:ok, _} =
               Database.execute(
                 :auth,
                 "INSERT INTO users (id, username, email) VALUES ($1, $2, $3)",
                 ["u1", "alice", "alice@example.com"]
               )

      # Verify :auth can see its own user
      {:ok, %{rows: auth_users}} = Database.execute(:auth, "SELECT * FROM users")
      assert length(auth_users) == 1
      assert hd(auth_users)["username"] == "alice"

      # 2. Plugin :player_data tries to select from users
      # In player_data's isolated database, the table is empty or has no rows
      {:ok, %{rows: player_data_users}} = Database.execute(:player_data, "SELECT * FROM users")
      assert player_data_users == []

      # 3. Plugin :player_data creates its own users table with different data
      assert {:ok, _} =
               Database.execute(
                 :player_data,
                 "CREATE TABLE users (id text, username text, email text)"
               )

      assert {:ok, _} =
               Database.execute(
                 :player_data,
                 "INSERT INTO users (id, username, email) VALUES ($1, $2, $3)",
                 ["u2", "bob_player", "bob@exoforge.dev"]
               )

      # :player_data sees ONLY Bob
      {:ok, %{rows: player_data_users_after}} =
        Database.execute(:player_data, "SELECT * FROM users")

      assert length(player_data_users_after) == 1
      assert hd(player_data_users_after)["username"] == "bob_player"

      # :auth STILL sees ONLY Alice
      {:ok, %{rows: auth_users_after}} = Database.execute(:auth, "SELECT * FROM users")
      assert length(auth_users_after) == 1
      assert hd(auth_users_after)["username"] == "alice"

      # 4. Deleting in :player_data does NOT delete in :auth
      Database.execute(:player_data, "DELETE FROM users WHERE id = $1", ["u2"])

      {:ok, %{rows: player_data_empty}} = Database.execute(:player_data, "SELECT * FROM users")
      assert player_data_empty == []

      {:ok, %{rows: auth_still_has_alice}} = Database.execute(:auth, "SELECT * FROM users")
      assert length(auth_still_has_alice) == 1
      assert hd(auth_still_has_alice)["username"] == "alice"
    end
  end

  describe "SQL Query Operations" do
    test "handles parameterized INSERT, SELECT, UPDATE, and DELETE" do
      assert {:ok, _} =
               Database.execute(:combat, "CREATE TABLE weapons (id text, name text, damage text)")

      assert {:ok, _} =
               Database.execute(
                 :combat,
                 "INSERT INTO weapons (id, name, damage) VALUES ($1, $2, $3)",
                 ["w1", "Iron Sword", "15"]
               )

      assert {:ok, _} =
               Database.execute(
                 :combat,
                 "INSERT INTO weapons (id, name, damage) VALUES ($1, $2, $3)",
                 ["w2", "Fire Staff", "30"]
               )

      # SELECT with WHERE
      {:ok, %{rows: selected}} =
        Database.execute(:combat, "SELECT * FROM weapons WHERE name = $1", ["Fire Staff"])

      assert length(selected) == 1
      assert hd(selected)["damage"] == "30"

      # UPDATE with WHERE (real SQL: UPDATE returns affected count, not rows)
      assert {:ok, %{num_rows: 1}} =
               Database.execute(:combat, "UPDATE weapons SET damage = $1 WHERE id = $2", [
                 "20",
                 "w1"
               ])

      {:ok, %{rows: [updated]}} =
        Database.execute(:combat, "SELECT * FROM weapons WHERE id = $1", ["w1"])

      assert updated["damage"] == "20"

      # DELETE with WHERE
      {:ok, _} = Database.execute(:combat, "DELETE FROM weapons WHERE id = $1", ["w1"])

      {:ok, %{rows: remaining}} = Database.execute(:combat, "SELECT * FROM weapons")
      assert length(remaining) == 1
      assert hd(remaining)["id"] == "w2"
    end
  end

  describe "Document / Key-Value operations" do
    test "put, get, delete, all operate per-plugin" do
      assert {:ok, _} =
               Database.put(:auth, "sessions", "sess_123", %{"token" => "abc", "scope" => "admin"})

      assert {:ok, %{"token" => "abc"}} = Database.get(:auth, "sessions", "sess_123")

      # Other plugin cannot see the session
      assert {:error, :not_found} = Database.get(:player_data, "sessions", "sess_123")

      # All sessions in auth
      assert {:ok, sessions} = Database.all(:auth, "sessions")
      assert length(sessions) == 1

      # Delete session
      assert {:ok, _} = Database.delete(:auth, "sessions", "sess_123")
      assert {:error, :not_found} = Database.get(:auth, "sessions", "sess_123")
    end
  end

  describe "Service Contracts & Connection Config" do
    test "lldb connection_config returns unique isolated details" do
      {:ok, auth_config} = Database.get_connection_config(:auth)
      assert auth_config.database == "exoforge_auth"
      assert auth_config.schema == "plugin_auth"
      assert String.contains?(auth_config.url, "exoforge_auth")

      {:ok, player_config} = Database.get_connection_config(:player_data)
      assert player_config.database == "exoforge_player_data"
      assert player_config.schema == "plugin_player_data"
      assert auth_config.url != player_config.url
    end

    test "health_check returns ok status" do
      assert {:ok, %{status: "ok"}} = Database.health_check()
    end
  end


  describe "M33 hardening" do
    test "a plugin's database is provisioned once, not per query (M33 Fix 7)" do
      table = :adapter_calls

      if :ets.info(table) == :undefined do
        :ets.new(table, [:set, :public, :named_table])
      end

      :ets.insert(table, {:ensures, 0})

      defmodule CountingSqlite do
        @behaviour Exoforge.Std.Database.Adapter
        alias Exoforge.Std.Database.Adapters.Sqlite

        @table :adapter_calls

        def ensures, do: :ets.lookup_element(@table, :ensures, 2)

        @impl true
        def ensure_database(id, config) do
          :ets.update_counter(@table, :ensures, {2, 1}, {:ensures, 0})
          Sqlite.ensure_database(id, config)
        end

        @impl true
        defdelegate execute(id, q, a, c), to: Sqlite
        @impl true
        defdelegate table_columns(id, t, c), to: Sqlite
        @impl true
        defdelegate connection_config(id, c), to: Sqlite
        @impl true
        defdelegate health_check(c), to: Sqlite
        @impl true
        defdelegate reset(id, c), to: Sqlite
      end

      # Parallel ExUnit modules share one Manager process; whatever happens in this test, they and
      # later runs must never meet the counting spy. The pid is captured once: a Manager from a
      # parallel module may stop between a name lookup and the call.
      on_exit(fn ->
        case Process.whereis(Manager) do
          pid when is_pid(pid) ->
            try do
              GenServer.call(pid, {:set_adapter, Exoforge.Std.Database.Adapters.Sqlite})
            rescue
              _ -> :ok
            end

          _ ->
            :ok
        end
      end)

      Manager.set_adapter(CountingSqlite)

      # A unique plugin id: other tests (and other runs) must not share its database file.
      plugin = :"counted_#{System.unique_integer([:positive])}"

      assert {:ok, _} = Database.execute(plugin, "CREATE TABLE t (id text)")
      assert {:ok, _} = Database.execute(plugin, "INSERT INTO t VALUES ($1)", ["x"])
      assert {:ok, %{rows: rows}} = Database.execute(plugin, "SELECT * FROM t")
      assert length(rows) == 1

      # Three queries, one provision.
      assert CountingSqlite.ensures() == 1

      Manager.set_adapter(Exoforge.Std.Database.Adapters.Sqlite)
    end

    test "table_columns answers through the adapter's dialect (M33 Fix 9)" do
      plugin = :"cols_#{System.unique_integer([:positive])}"

      assert {:ok, _} = Database.execute(plugin, "CREATE TABLE things (id text, size integer)")

      assert {:ok, columns} = Manager.table_columns(plugin, "things")

      assert "id" in columns
      assert "size" in columns
    end

    test "positional SQL rejects map arguments (M33 Fix 10)" do
      plugin = :"map_args_#{System.unique_integer([:positive])}"

      assert {:error, :positional_args_must_be_list} =
               Database.execute(plugin, "SELECT * FROM t WHERE id = $1", %{"id" => "x"})
    end
  end
end
