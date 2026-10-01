defmodule Exoforge.ActionDispatcherTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry

  defmodule TestService do
    import Exoforge.Contracts.Service

    defservice math do
      action :add do
        params(a: :integer, b: :integer)
        returns(sum: :integer)
      end

      action :divide do
        params(a: :integer, b: :integer)
        returns(quotient: :float)
        errors([:division_by_zero])
      end

      action :admin_reset do
        scope :admin
        params(target: :string)
        returns(status: :string)
      end

      event :calculated do
        payload(result: :term)
      end
    end
  end

  defmodule TestPlugin do
    use Exoforge.Plugin, provides: [Exoforge.ActionDispatcherTest.TestService.Math]

    @impl true
    defaction add(payload) do
      %{a: a, b: b} = payload
      {:ok, %{sum: a + b}}
    end

    @impl true
    defaction divide(payload) do
      case payload do
        %{b: 0} -> {:error, :division_by_zero}
        %{a: a, b: b} -> {:ok, %{quotient: a / b}}
      end
    end

    @impl true
    defaction admin_reset(_payload), scope: :admin do
      {:ok, %{status: "reset_ok"}}
    end
  end

  setup do
    start_supervised!(PluginRegistry)
    :ok
  end

  test "metadata preserves source declaration order" do
    meta = TestService.Math.__service_metadata__()
    action_names = Enum.map(meta.actions, & &1.name)
    assert action_names == [:add, :divide, :admin_reset]
  end

  test "dispatches action directly to plugin module" do
    assert {:ok, %{sum: 7}} = ActionDispatcher.dispatch(TestPlugin, :add, %{a: 3, b: 4})
  end

  test "dispatches action by contract module via PluginRegistry" do
    manifest = %Manifest{
      id: :math_plugin,
      name: "math_plugin",
      version: "1.0.0",
      entry_point: TestPlugin,
      provides: [TestService.Math]
    }

    assert :ok = PluginRegistry.register(manifest)

    # Dispatching to the contract module TestService.Math
    assert {:ok, %{sum: 12}} = ActionDispatcher.dispatch(TestService.Math, :add, %{a: 5, b: 7})
    assert {:error, :division_by_zero} = ActionDispatcher.dispatch(TestService.Math, :divide, %{a: 10, b: 0})
  end

  test "returns error when service is not found" do
    assert {:error, :service_not_found} = ActionDispatcher.dispatch(NonExistentService, :foo, %{})
  end

  test "returns error when action is not found on plugin" do
    assert {:error, {:action_not_found, :unknown}} = ActionDispatcher.dispatch(TestPlugin, :unknown, %{})
  end

  describe "scope enforcement" do
    test "internal dispatch to scoped action succeeds" do
      assert {:ok, %{status: "reset_ok"}} = ActionDispatcher.dispatch(TestPlugin, :admin_reset, %{})
    end

    test "external unauthenticated caller is rejected with :unauthorized" do
      assert {:error, :unauthorized} =
               ActionDispatcher.dispatch(TestPlugin, :admin_reset, %{}, caller_scopes: [])
    end

    test "external caller with insufficient scope is rejected with :forbidden_scope" do
      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(TestPlugin, :admin_reset, %{}, caller_scopes: ["player"])
    end

    test "external caller with required scope succeeds" do
      assert {:ok, %{status: "reset_ok"}} =
               ActionDispatcher.dispatch(TestPlugin, :admin_reset, %{}, caller_scopes: ["admin"])
    end

    test "caller scope provided via payload _auth is honored" do
      payload_with_admin = %{"_auth" => %{"scopes" => ["admin"]}}

      assert {:ok, %{status: "reset_ok"}} =
               ActionDispatcher.dispatch(TestPlugin, :admin_reset, payload_with_admin)

      payload_with_player = %{"_auth" => %{"scopes" => ["player"]}}

      assert {:error, :forbidden_scope} =
               ActionDispatcher.dispatch(TestPlugin, :admin_reset, payload_with_player)
    end
  end
end
