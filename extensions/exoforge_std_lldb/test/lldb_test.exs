defmodule Exoforge.Std.LldbTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Lldb
  alias Exoforge.Std.Lldb.Manager

  setup do
    Exoforge.ExtensionCase.start_kernel()

    unless Process.whereis(Manager) do
      start_supervised!(Manager)
    end

    Exoforge.ExtensionCase.register_extension(Lldb, id: :exoforge_std_lldb, provides: [Exoforge.Std.Services.Lldb])

    # Cleaned up front: by the time on_exit callbacks run the Manager is already stopped.
    Manager.reset(:lldb_contract)
    :ok
  end

  describe "connection config and health" do
    test "connection_config returns unique isolated details per namespace" do
      {:ok, auth_config} = Manager.connection_config(:auth)
      assert auth_config.database == "exoforge_auth"
      assert auth_config.schema == "plugin_auth"
      assert String.contains?(auth_config.url, "exoforge_auth")

      {:ok, player_config} = Manager.connection_config(:player_data)
      assert player_config.database == "exoforge_player_data"
      assert player_config.schema == "plugin_player_data"
      assert auth_config.url != player_config.url
    end

    test "health_check returns ok status" do
      assert {:ok, %{status: "ok"}} = Manager.health_check()
    end
  end

  describe "the lldb service contract" do
    test "provision_namespace, exec, table_columns and drop_namespace work through the service" do
      ns = :lldb_contract

      assert {:ok, _} = ActionDispatcher.dispatch_internal(:lldb, :provision_namespace, %{namespace: ns})

      assert {:ok, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation: "CREATE TABLE widgets (id text, name text)"
               })

      assert {:ok, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation: "INSERT INTO widgets (id, name) VALUES ($1, $2)",
                 arguments: ["w1", "gear"]
               })

      assert {:ok, %{rows: [%{"name" => "gear"}]}} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{
                 namespace: ns,
                 operation: "SELECT name FROM widgets WHERE id = $1",
                 arguments: ["w1"]
               })

      assert {:ok, %{columns: columns}} =
               ActionDispatcher.dispatch_internal(:lldb, :table_columns, %{namespace: ns, table: "widgets"})

      assert Enum.sort(columns) == ["id", "name"]

      assert :ok = ActionDispatcher.dispatch_internal(:lldb, :drop_namespace, %{namespace: ns}) |> normalize()

      assert {:error, _} =
               ActionDispatcher.dispatch_internal(:lldb, :exec, %{namespace: ns, operation: "SELECT * FROM widgets"})
    end

    test "the contract names no engine: namespace, not schema or role" do
      contract = Exoforge.Std.Services.Lldb.__service_metadata__()
      text = inspect(contract) |> String.downcase()

      for word <- ["postgres", "schema", "role", "search_path", "jsonb"] do
        refute text =~ word, "the lldb contract must not mention #{word}"
      end
    end
  end

  defp normalize({:ok, _}), do: :ok
  defp normalize(other), do: other
end
