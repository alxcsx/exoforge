defmodule Exoforge.ActionDispatcherTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Domain.Manifest
  alias Exoforge.ExtensionRegistry

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
        scope(:admin)
        params(target: :string)
        returns(status: :string)
      end

      action :flag do
        params(enabled: :boolean)
      end

      event :calculated do
        payload(result: :term)
      end
    end
  end

  defmodule TestPlugin do
    use Exoforge.Extension, provides: [Exoforge.ActionDispatcherTest.TestService.Math]

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

    @impl true
    defaction(flag(%{enabled: enabled}), do: {:ok, %{enabled: enabled}})
  end

  setup do
    unless Process.whereis(ExtensionRegistry) do
      start_supervised!(ExtensionRegistry)
    end

    :ok
  end

  test "metadata preserves source declaration order" do
    meta = TestService.Math.__service_metadata__()
    action_names = Enum.map(meta.actions, & &1.name)
    assert action_names == [:add, :divide, :admin_reset, :flag]
  end

  test "dispatches action directly to plugin module" do
    assert {:ok, %{sum: 7}} = ActionDispatcher.dispatch_internal(TestPlugin, :add, %{a: 3, b: 4})
  end

  test "dispatches action by contract module via ExtensionRegistry" do
    manifest = %Manifest{
      id: :math_plugin,
      name: "math_plugin",
      version: "1.0.0",
      entry_point: TestPlugin,
      provides: [TestService.Math]
    }

    assert :ok = ExtensionRegistry.register(manifest)

    # Dispatching to the contract module TestService.Math
    assert {:ok, %{sum: 12}} = ActionDispatcher.dispatch_internal(TestService.Math, :add, %{a: 5, b: 7})
    assert {:error, :division_by_zero} = ActionDispatcher.dispatch_internal(TestService.Math, :divide, %{a: 10, b: 0})
  end

  test "a dispatch stamps its request id on the event, the log, the trace and the error group" do
    Exoforge.ExtensionCase.start_kernel()
    Exoforge.ExtensionCase.register_extension(TestPlugin, id: "math_plugin", provides: [TestService.Math])
    Exoforge.ErrorGroups.clear()
    Exoforge.ActionTrace.enable()
    _ = Exoforge.EventDispatcher.subscribe(:all, topic: :global)

    on_exit(fn ->
      Exoforge.ExtensionCase.reset_action_trace()
      Exoforge.ErrorGroups.clear()
    end)

    assert {:error, :division_by_zero} =
             ActionDispatcher.dispatch(TestService.Math, :divide, %{a: 1, b: 0},
               caller: "alice",
               rid: "r_test_1",
               caller_scopes: [:player]
             )

    assert_receive {:exo_event, _key, payload, context}, 1_000
    assert payload.rid == "r_test_1"
    assert context.rid == "r_test_1"
    assert context.origin == "alice"

    # The extension's log line belongs to the request, not to a time window.
    assert Enum.any?(Exoforge.ExtensionLogs.list("math_plugin", 50), &(&1.rid == "r_test_1"))

    assert %{samples: [sample]} = Exoforge.ActionTrace.samples("#{TestService.Math}.divide")
    assert sample.rid == "r_test_1"
    assert sample.depth == 0

    assert [group] = Exoforge.ErrorGroups.list(%{service: to_string(TestService.Math)})
    assert group.rid == "r_test_1"
    assert group.caller == "alice"
    assert group.action == "divide"
    assert group.count == 1
    assert group.request == %{a: 1, b: 0}
  end

  test "returns error when service is not found" do
    assert {:error, :service_not_found} = ActionDispatcher.dispatch(NonExistentService, :foo, %{})
  end

  test "returns error when action is not found on plugin" do
    assert {:error, {:action_not_found, :unknown}} = ActionDispatcher.dispatch(TestPlugin, :unknown, %{})
  end

  describe "scope enforcement" do
    test "internal dispatch to scoped action succeeds" do
      assert {:ok, %{status: "reset_ok"}} = ActionDispatcher.dispatch_internal(TestPlugin, :admin_reset, %{})
      assert {:ok, %{status: "reset_ok"}} = ActionDispatcher.dispatch(TestPlugin, :admin_reset, %{}, internal: true)
    end

    test "external unauthenticated caller without scopes is denied by default with :unauthorized" do
      assert {:error, :unauthorized} = ActionDispatcher.dispatch(TestPlugin, :admin_reset, %{})

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

  describe "parameter validation" do
    test "rejects invalid parameter types with descriptive error" do
      assert {:error, {:invalid_param_type, field: :b, expected: :integer, received: "invalid"}} =
               ActionDispatcher.dispatch_internal(TestPlugin, :add, %{a: 5, b: "invalid"})
    end

    test "rejects missing required parameters when require_params is enabled" do
      assert {:error, {:missing_param, :target}} =
               ActionDispatcher.dispatch_internal(TestPlugin, :admin_reset, %{}, require_params: true)
    end

    test "accepts false boolean parameters" do
      assert {:ok, %{enabled: false}} =
               ActionDispatcher.dispatch_internal(TestPlugin, :flag, %{enabled: false}, require_params: true)
    end
  end
end
