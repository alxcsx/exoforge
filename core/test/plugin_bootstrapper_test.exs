defmodule Exoforge.PluginBootstrapperTest do
  use ExUnit.Case, async: true

  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginBootstrapper

  defp manifest(id, provides \\ [], dependencies \\ []) do
    %Manifest{
      id: id,
      name: "#{id}",
      version: "0.1.0",
      entry_point: Module.concat(Exoforge.Fixture, Macro.camelize(to_string(id))),
      provides: provides,
      dependencies: dependencies
    }
  end

  test "sorts providers before dependents" do
    provider = manifest(:provider, [:svc])
    dependent = manifest(:dependent, [], [:svc])

    assert PluginBootstrapper.sort!([dependent, provider]) == [provider, dependent]
  end

  test "raises on missing dependency" do
    assert_raise RuntimeError, ~r/Missing Dependency/, fn ->
      PluginBootstrapper.sort!([manifest(:lonely, [], [:svc_nobody_provides])])
    end
  end

  test "raises on circular dependency" do
    a = manifest(:a, [:svc_b], [:svc_a])
    b = manifest(:b, [:svc_a], [:svc_b])

    assert_raise RuntimeError, ~r/Circular dependency/, fn ->
      PluginBootstrapper.sort!([a, b])
    end
  end
end
