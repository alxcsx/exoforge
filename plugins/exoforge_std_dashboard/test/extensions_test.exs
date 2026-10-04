defmodule Exoforge.Std.Dashboard.ExtensionsTest do
  use ExUnit.Case, async: false

  alias Exoforge.Domain.Manifest
  alias Exoforge.PluginRegistry
  alias Exoforge.Std.Dashboard.Extensions

  setup do
    unless Process.whereis(PluginRegistry), do: start_supervised!(PluginRegistry)
    PluginRegistry.initialize_ets()
    :ok
  end

  test "resolves dashboard_view and the has_dashboard_view flag" do
    manifest = %Manifest{
      id: :auth_plugin,
      name: "Auth Plugin",
      version: "0.1.0",
      entry_point: nil,
      provides: [:auth],
      dashboard_view: %{id: :auth, title: "Users & Auth", icon: "🛡️"}
    }

    assert :ok = PluginRegistry.register(manifest)

    summary = Extensions.dashboard_extensions() |> Enum.find(&(&1.id == :auth_plugin))

    assert summary != nil
    assert summary.has_dashboard_view == true
    assert summary.dashboard_view.title == "Users & Auth"
    assert summary.provides == ["auth"]
  end

  test "plugins have no UI by default" do
    manifest = %Manifest{
      id: :headless_service,
      name: "Headless Service",
      version: "1.0.0",
      entry_point: nil,
      provides: [:headless],
      services: [
        %{name: :headless, actions: [%{name: :ping, mode: :sync}], resources: [], events: []}
      ],
      dashboard_view: nil
    }

    assert :ok = PluginRegistry.register(manifest)

    summary = Extensions.dashboard_extensions() |> Enum.find(&(&1.id == :headless_service))

    assert summary != nil
    assert summary.has_dashboard_view == false
    assert summary.has_visual_controls == false
    assert summary.has_custom_view == false
    assert summary.actions_count == 1
  end

  test "normalize_action_params keeps unknown types as strings without creating atoms" do
    unknown = "custom_type_#{System.unique_integer([:positive])}"

    [param] = Extensions.normalize_action_params(%{"thing" => unknown})
    assert param.type == unknown
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end
end
