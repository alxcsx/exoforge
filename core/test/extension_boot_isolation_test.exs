defmodule Exoforge.ExtensionBootIsolationTest do
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Domain.Manifest
  alias Exoforge.Drivers.Runtime.ElixirExtensionRunner
  alias Exoforge.ExtensionBootstrapper
  alias Exoforge.ExtensionRegistry

  # Runners are modules with `load/1`; the bootstrapper accepts one as a manifest `type`.
  defmodule OkRunner do
    def load(_manifest), do: {:ok, self()}
  end

  defmodule ErrorRunner do
    def load(_manifest), do: {:error, {:handshake_refused, :protocol_mismatch}}
  end

  defmodule RaisingRunner do
    def load(_manifest), do: raise("kaboom")
  end

  defmodule ExitingRunner do
    def load(_manifest), do: exit(:gone)
  end

  # An Elixir extension module that cannot start.
  defmodule BrokenElixirExtension do
    def handled_events, do: []
    def init(_manifest), do: {:error, :boom}
  end

  defmodule Driver do
    def load_extensions(manifests), do: manifests
  end

  # A resource store whose provisioning answer the test chooses.
  defmodule StubResourceStore do
    use Exoforge.Extension, provides: [:resource_store]

    @manifest %{category: "Storage", system: true, title: "Stub resource store", icon: "🧪", dashboard_view: nil}

    def start, do: Agent.start_link(fn -> %{answer: {:ok, %{provisioned: 1}}, asked: []} end, name: __MODULE__)
    def answer(value), do: Agent.update(__MODULE__, &%{&1 | answer: value})
    def asked, do: Agent.get(__MODULE__, &Enum.reverse(&1.asked))

    @impl true
    defaction provision(payload) do
      Agent.get_and_update(__MODULE__, fn state ->
        {state.answer, %{state | asked: [payload[:extension] | state.asked]}}
      end)
    end
  end

  setup do
    start_supervised!(ExtensionRegistry)
    start_supervised!(Exoforge.EventDispatcher)
    start_supervised!(Exoforge.ExtensionSupervisor)
    :ok
  end

  defp manifest(id, runner, provides, dependencies \\ []) do
    %Manifest{
      id: id,
      name: "#{id}",
      version: "0.1.0",
      type: runner,
      entry_point: Module.concat(Exoforge.Fixture, Macro.camelize(to_string(id))),
      provides: provides,
      dependencies: dependencies
    }
  end

  test "an extension that fails to start does not stop the ones around it" do
    first = manifest(:first, OkRunner, [:svc_first])
    broken = manifest(:broken, ErrorRunner, [:svc_broken])
    last = manifest(:last, OkRunner, [:svc_last])

    loaded = ExtensionBootstrapper.run(Driver, [first, broken, last])

    assert Enum.map(loaded, & &1.id) |> Enum.sort() == [:first, :last]
    assert ExtensionRegistry.fetch_manifest(:first)
    assert ExtensionRegistry.fetch_manifest(:last)
    # the failed one is not registered, so it provides nothing
    assert ExtensionRegistry.fetch_manifest(:broken) == nil
    assert ExtensionRegistry.fetch_service(:svc_broken) == nil
  end

  test "the failure is recorded with its stage and reason, and the extension can still be listed" do
    broken = manifest(:broken, ErrorRunner, [:svc_broken])

    ExtensionBootstrapper.run(Driver, [broken])

    assert %{kind: :boot_failed, stage: :start, message: message, at: at} = ExtensionRegistry.get_failure(:broken)
    assert message =~ "handshake_refused"
    assert is_integer(at)
    assert {:crashed, %{kind: :boot_failed}} = ExtensionRegistry.get_crash_info(:broken)
    assert [{%Manifest{id: :broken}, %{kind: :boot_failed}}] = ExtensionRegistry.failed_extensions()
  end

  test "a runner that raises or exits is a failure of that extension only" do
    raising = manifest(:raising, RaisingRunner, [:svc_raising])
    exiting = manifest(:exiting, ExitingRunner, [:svc_exiting])
    fine = manifest(:fine, OkRunner, [:svc_fine])

    loaded = ExtensionBootstrapper.run(Driver, [raising, exiting, fine])

    assert Enum.map(loaded, & &1.id) == [:fine]
    assert %{stage: :load, message: "kaboom"} = ExtensionRegistry.get_failure(:raising)
    assert %{stage: :load, message: exit_message} = ExtensionRegistry.get_failure(:exiting)
    assert exit_message =~ "gone"
  end

  test "a dependent of a failed extension is blocked, not started" do
    broken = manifest(:broken, ErrorRunner, [:svc_broken])
    dependent = manifest(:dependent, RaisingRunner, [:svc_dependent], [:svc_broken])
    independent = manifest(:independent, OkRunner, [:svc_independent])

    loaded = ExtensionBootstrapper.run(Driver, [dependent, broken, independent])

    # the dependent's runner would raise if it were started: it was not
    assert Enum.map(loaded, & &1.id) == [:independent]

    assert %{kind: :blocked, stage: :dependencies, message: "dependency broken failed", detail: %{dependencies: ["broken"]}} =
             ExtensionRegistry.get_failure(:dependent)

    # blocking is transitive
    third = manifest(:third, OkRunner, [:svc_third], [:svc_dependent])
    ExtensionBootstrapper.run(Driver, [broken, dependent, third])
    assert %{kind: :blocked, message: "dependency dependent failed"} = ExtensionRegistry.get_failure(:third)
  end

  test "a dependency with a healthy provider does not block" do
    broken = manifest(:broken_provider, ErrorRunner, [:svc_shared])
    healthy = manifest(:healthy_provider, OkRunner, [:svc_shared])
    dependent = manifest(:dependent, OkRunner, [:svc_dependent], [:svc_shared])

    loaded = ExtensionBootstrapper.run(Driver, [broken, healthy, dependent])

    assert Enum.map(loaded, & &1.id) |> Enum.sort() == [:dependent, :healthy_provider]
  end

  test "a missing dependency or a cycle fails only the extensions involved" do
    lonely = manifest(:lonely, OkRunner, [:svc_lonely], [:svc_nobody_provides])
    a = manifest(:cycle_a, OkRunner, [:svc_a], [:svc_b])
    b = manifest(:cycle_b, OkRunner, [:svc_b], [:svc_a])
    fine = manifest(:fine, OkRunner, [:svc_fine])

    loaded = ExtensionBootstrapper.run(Driver, [lonely, a, b, fine])

    assert Enum.map(loaded, & &1.id) == [:fine]
    assert %{kind: :boot_failed, stage: :dependencies, message: m1} = ExtensionRegistry.get_failure(:lonely)
    assert m1 =~ "Missing Dependency"
    assert %{message: m2} = ExtensionRegistry.get_failure(:cycle_a)
    assert m2 =~ "Circular dependency"
    assert ExtensionRegistry.get_failure(:cycle_b)
  end

  test "calls to a failed extension say it is unavailable, not that the service does not exist" do
    ExtensionBootstrapper.run(Driver, [manifest(:broken, ErrorRunner, [:svc_broken])])

    assert {:error, {:extension_unavailable, :broken}} = ActionDispatcher.dispatch_internal(:svc_broken, :ping, %{})
    assert {:error, :service_not_found} = ActionDispatcher.dispatch_internal(:svc_nobody, :ping, %{})
  end

  test "boot announces each failure on the event bus and in the extension's log" do
    Exoforge.EventDispatcher.subscribe("extension.boot_failed")

    ExtensionBootstrapper.run(Driver, [manifest(:broken, ErrorRunner, [:svc_broken])])

    assert_receive {:exo_event, "extension.boot_failed", %{id: "broken", kind: :boot_failed, stage: :start}, _}, 500
    assert Enum.any?(Exoforge.ExtensionLogs.list("broken"), fn line -> inspect(line) =~ "boot_failed" end)
  end

  test "a failed extension can boot on a later attempt, which clears the failure" do
    ExtensionBootstrapper.run(Driver, [manifest(:flaky, ErrorRunner, [:svc_flaky])])
    assert ExtensionRegistry.get_failure(:flaky)

    ExtensionBootstrapper.run(Driver, [manifest(:flaky, OkRunner, [:svc_flaky])])

    assert ExtensionRegistry.get_failure(:flaky) == nil
    assert ExtensionRegistry.get_crash_info(:flaky) == nil
    assert ExtensionRegistry.fetch_manifest(:flaky)
  end

  describe "storage provisioning" do
    setup do
      {:ok, _} = StubResourceStore.start()

      ExtensionRegistry.register(%Manifest{
        id: :stub_resource_store,
        name: "stub_resource_store",
        version: "0.1.0",
        type: OkRunner,
        entry_point: StubResourceStore,
        provides: [Exoforge.Std.Services.ResourceStore],
        dependencies: []
      })

      on_exit(fn -> if Process.whereis(StubResourceStore), do: Agent.stop(StubResourceStore) end)
      :ok
    end

    defp with_resources(manifest), do: %{manifest | services: [%{name: manifest.id, resources: [%{name: "inventory"}]}]}

    test "an extension that declares resources is provisioned before it starts" do
      stores = with_resources(manifest(:stores, OkRunner, [:svc_stores]))

      assert [%Manifest{id: :stores}] = ExtensionBootstrapper.run(Driver, [stores])
      assert StubResourceStore.asked() == ["stores"]
      assert ExtensionRegistry.get_failure(:stores) == nil
    end

    test "an extension without resources is not asked about storage" do
      ExtensionBootstrapper.run(Driver, [manifest(:plain, OkRunner, [:svc_plain])])
      assert StubResourceStore.asked() == []
    end

    test "a storage failure fails that extension alone, with the stage, where and what to do" do
      StubResourceStore.answer(
        {:error,
         {:unsafe_schema_change,
          %{
            extension: "stores",
            table: "inventory",
            changes: [%{table: "inventory", column: "qty", change: :alter_type, reason: "text is not a widening of int32", decl: "Inventory.cs:14"}],
            hint: "Add a migration, or set EXOFORGE_SCHEMA_CHANGE_MODE=reset."
          }}}
      )

      stores = with_resources(manifest(:stores, RaisingRunner, [:svc_stores]))
      healthy = manifest(:healthy, OkRunner, [:svc_healthy])

      # the failing extension's own runner would raise if it were started: it never is
      assert [%Manifest{id: :healthy}] = ExtensionBootstrapper.run(Driver, [stores, healthy])

      assert %{kind: :boot_failed, stage: :storage, message: message} = ExtensionRegistry.get_failure(:stores)
      assert message =~ "cannot bring inventory to its declared shape"
      assert message =~ "inventory.qty [Inventory.cs:14] (alter_type): text is not a widening of int32"
      assert message =~ "EXOFORGE_SCHEMA_CHANGE_MODE=reset"
      assert ExtensionRegistry.get_failure(:healthy) == nil
    end

    test "a dependent of an extension whose storage failed is blocked" do
      StubResourceStore.answer({:error, {:migration_failed, %{table: "inventory"}}})

      stores = with_resources(manifest(:stores, OkRunner, [:svc_stores]))
      dependent = manifest(:dependent, RaisingRunner, [:svc_dependent], [:svc_stores])

      assert [] = ExtensionBootstrapper.run(Driver, [stores, dependent])
      assert %{stage: :storage} = ExtensionRegistry.get_failure(:stores)
      assert %{kind: :blocked, message: "dependency stores failed"} = ExtensionRegistry.get_failure(:dependent)
    end
  end

  test "the Elixir runner reports a start failure instead of raising" do
    manifest = %Manifest{
      id: :broken_elixir,
      name: "broken_elixir",
      version: "0.1.0",
      type: :elixir,
      entry_point: BrokenElixirExtension,
      provides: [:svc_broken_elixir],
      dependencies: []
    }

    assert {:error, {:extension_start_failed, BrokenElixirExtension, _reason}} = ElixirExtensionRunner.load(manifest)
  end
end
