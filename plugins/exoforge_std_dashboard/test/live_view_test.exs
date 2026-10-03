defmodule Exoforge.DashboardLiveViewTest do
  @moduledoc """
  Tests for Phoenix LiveView components and StudioLive state interactions.
  """
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias Exoforge.Std.Dashboard.Components
  alias Exoforge.Std.Dashboard.Endpoint
  alias Exoforge.PluginRegistry
  alias Exoforge.EventDispatcher
  alias Exoforge.Std.Database.Manager, as: DbManager

  @endpoint Endpoint

  setup do
    PluginRegistry.initialize_ets()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sandbox]})
    end

    unless Process.whereis(EventDispatcher.registry_name()) do
      start_supervised!(EventDispatcher)
    end

    unless Process.whereis(Exoforge.DrawerRegistry) do
      start_supervised!(Exoforge.DrawerRegistry)
    end

    unless Process.whereis(Exoforge.Std.Dashboard.PubSub) do
      start_supervised!({Phoenix.PubSub, name: Exoforge.Std.Dashboard.PubSub})
    end

    unless Process.whereis(Endpoint) do
      start_supervised!(Endpoint)
    end

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb],
      category: "Storage",
      system: true,
      dashboard_view: %{id: :database, title: "Database Engine", icon: "🗄️"}
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_dashboard,
      name: "exoforge_std_dashboard",
      version: "0.1.0",
      entry_point: Exoforge.Std.Dashboard,
      provides: [Exoforge.Std.Services.DashboardView],
      dependencies: [Exoforge.Std.Services.Database],
      category: "Studio",
      dashboard_view: %{id: :dashboard, title: "Producer Studio", icon: "📊"}
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_auth,
      name: "exoforge_std_auth",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [Exoforge.Std.Services.Auth],
      dependencies: [Exoforge.Std.Services.Database],
      category: "Identity",
      dashboard_view: %{
        id: :auth,
        title: "Users & Auth",
        icon: "🛡️",
        module: Exoforge.Std.Dashboard.Views.AuthView
      }
    })

    Exoforge.Std.Auth.init_schema()

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_player_data,
      name: "exoforge_std_player_data",
      version: "0.1.0",
      entry_point: Exoforge.Std.PlayerData,
      provides: [Exoforge.Std.Services.PlayerData],
      dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth],
      category: "LiveOps",
      dashboard_view: %{id: :player_data, title: "Player Data", icon: "👤"}
    })

    Exoforge.Std.PlayerData.init_schema()

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_ws,
      name: "exoforge_std_ws",
      version: Version.parse!("0.1.0"),
      entry_point: Exoforge.Std.Ws,
      provides: [Exoforge.Std.Services.Ws],
      dependencies: [Exoforge.Std.Services.Auth],
      category: "Ingress",
      system: true,
      dashboard_view: %{id: :ws, title: "WebSocket Gateway", icon: "🔌"}
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :combat_wasm,
      name: "combat_wasm",
      version: Version.parse!("1.0.0"),
      entry_point: :combat_wasm,
      type: :wasm,
      provides: [Exoforge.Std.Services.Combat],
      dependencies: [],
      category: "Gameplay",
      dashboard_view: %{id: :combat, title: "Combat Sandbox", icon: "⚔️"}
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_plugin_manager,
      name: "exoforge_std_plugin_manager",
      version: Version.parse!("0.1.0"),
      entry_point: Exoforge.Std.PluginManager,
      provides: [Exoforge.Std.Services.PluginManager],
      dependencies: [],
      category: "Management",
      dashboard_view: %{
        id: :plugin_manager,
        title: "Plugin Manager",
        icon: "📦",
        module: Exoforge.Std.Dashboard.Views.PluginManagerView
      }
    })

    Exoforge.Std.Dashboard.Preferences.ensure_schema()

    :ok
  end

  describe "Shared Exoforge Functional Components" do
    test "metric_card renders title, value, and delta" do
      assigns = %{title: "Active CCU", value: "1,450", delta: "+18%", delta_positive: true}

      html =
        rendered_to_string(~H"""
        <Components.metric_card title={@title} value={@value} delta={@delta} delta_positive={@delta_positive} />
        """)

      assert html =~ "Active CCU"
      assert html =~ "1,450"
      assert html =~ "+18%"
    end

    test "badge renders correct color class by status" do
      assigns = %{status: "active"}

      html =
        rendered_to_string(~H"""
        <Components.badge status={@status} />
        """)

      assert html =~ "bg-emerald-50 text-emerald-700"
      assert html =~ "active"
    end

    test "data_table renders column headers and rows" do
      assigns = %{
        rows: [%{id: "p_1", name: "Alpha"}, %{id: "p_2", name: "Beta"}],
        columns: [%{key: :id, label: "Player ID"}, %{key: :name, label: "Display Name"}]
      }

      html =
        rendered_to_string(~H"""
        <Components.data_table id="test_tbl" rows={@rows} columns={@columns} />
        """)

      assert html =~ "Player ID"
      assert html =~ "Display Name"
      assert html =~ "Alpha"
      assert html =~ "Beta"
    end

    test "side_drawer renders 7 inspector tabs when open" do
      tabs = Exoforge.DrawerRegistry.list_tabs("players")
      assigns = %{open: true, title: "Player Details", tabs: tabs, active_tab: "overview"}

      html =
        rendered_to_string(~H"""
        <Components.side_drawer open={@open} title={@title} tabs={@tabs} active_tab={@active_tab}>
          <p>Inner overview content</p>
        </Components.side_drawer>
        """)

      assert html =~ "Player Details"
      assert html =~ "Overview"
      assert html =~ "Attributes"
      assert html =~ "Inner overview content"
    end

    test "attribute_editor renders dynamic key-value entries" do
      assigns = %{attributes: [%{key: "guild_rank", value: "Officer"}]}

      html =
        rendered_to_string(~H"""
        <Components.attribute_editor attributes={@attributes} />
        """)

      assert html =~ "Dynamic Attributes"
      assert html =~ "guild_rank"
      assert html =~ "Officer"
    end
  end

  describe "StudioLive Interactive LiveView" do
    test "mounts and displays Exoforge Shell header and platform metric cards" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, html} = live(conn, "/")

      assert html =~ "EXOFORGE"
      assert html =~ "Overview"
      assert html =~ "Active Extensions"
      assert html =~ "Declared Resources"
      assert html =~ "Callable Actions"
      assert html =~ "Cluster Status"
      assert html =~ "Live Game Features"

      # Pin extension (Users & Auth) to top bar
      html = render_click(view, "pin_extension", %{"id" => "exoforge_std_auth"})
      assert html =~ "Pinned exoforge_std_auth to top navigation bar"
      assert html =~ "Users &amp; Auth" or html =~ "Users & Auth"

      # Switch to pinned Users & Auth tab
      html = render_click(view, "switch_tab", %{"tab" => "exoforge_std_auth"})
      assert html =~ "Users &amp; Authentication" or html =~ "Users & Authentication"
      assert html =~ "Registered Accounts"
      assert html =~ "Active Tokens"

      # Open Command Palette (Cmd+K)
      html = render_click(view, "open_cmd_palette", %{})
      assert html =~ "Search plugins, resources, players, actions... (Cmd+K)"

      # Search in Command Palette for dynamic action
      html = render_change(view, "search_cmd_palette", %{"query" => "register"})
      assert html =~ "Action: auth.register"

      # Test unpinning logic
      html = render_click(view, "unpin_extension", %{"id" => "exoforge_std_auth"})
      assert html =~ "Unpinned exoforge_std_auth from top bar"
    end

    test "receives real-time events pushed by EventDispatcher and updates feed" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Simulate kernel broadcasting an event
      EventDispatcher.broadcast(:player_created, %{player_id: "p_live_999", name: "Nova"})

      # Allow message to be processed by LiveView
      :timer.sleep(50)

      html = render(view)
      assert html =~ "player_created"
    end

    test "action runner modal opens, generates form inputs, and dispatches actions" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # 1. Open action runner modal
      html = render_click(view, "open_action_modal", %{})
      assert html =~ "Action Dispatcher &amp; Form Generator"
      assert html =~ "Target Service"
      assert html =~ "Target Action"

      # 2. Select service and action
      html = render_change(view, "select_action_service", %{"service" => "lldb"})
      assert html =~ "lldb"

      html = render_change(view, "select_action_name", %{"action" => "health_check"})
      assert html =~ "health_check"

      # 3. Update form inputs and scopes
      html =
        render_change(view, "change_action_form", %{
          "caller_scopes" => "admin"
        })

      assert html =~ "caller_scopes"

      # 4. Dispatch the action
      html = render_submit(view, "dispatch_action", %{"caller_scopes" => "admin"})
      assert html =~ "Execution Output"
      assert html =~ "SUCCESS (200)"
      assert html =~ "healthy" or html =~ "ok" or html =~ "status"

      # 5. Verify dynamic form input generation with required and optional badges
      _html = render_change(view, "select_action_service", %{"service" => "auth"})
      html = render_change(view, "select_action_name", %{"action" => "issue_token"})
      assert html =~ "player_id"
      assert html =~ "required"
      assert html =~ "param_player_id"
      assert html =~ "optional"
    end

    test "cluster event stream dock toggles, pauses, clears, and streams events" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # 1. Open event dock
      html = render_click(view, "toggle_event_dock", %{})
      assert html =~ "Cluster Event Stream (:pg / EventDispatcher)"
      assert html =~ "Clear"
      assert html =~ "Simulate Event"

      # 2. Simulate broadcasting a cluster telemetry event
      html = render_click(view, "simulate_test_event", %{})
      assert html =~ "Simulated telemetry event"

      :timer.sleep(50)
      html = render(view)
      assert html =~ "studio_telemetry"

      # 3. Filter event dock
      html = render_change(view, "filter_event_dock", %{"topic" => "studio_telemetry"})
      assert html =~ "studio_telemetry"

      # 4. Toggle pause
      html = render_click(view, "toggle_event_pause", %{})
      assert html =~ "STREAM PAUSED" or html =~ "Resume"

      # 5. Clear events
      html = render_click(view, "clear_events", %{})
      assert html =~ "Waiting for live cluster events"
    end

    test "mounts GenericExtensionView for extensions without custom LiveComponent" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Switch to player_data extension tab
      html = render_click(view, "switch_tab", %{"tab" => "exoforge_std_player_data"})
      assert html =~ "Interactive Action Control Panel"
      assert html =~ "create_player" or html =~ "Run Action"
      assert html =~ "Execute typed backend RPCs"
    end

    test "switching tab to exoforge_std_ws renders GenericExtensionView without Version struct error" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Switch to exoforge_std_ws tab (which has a %Version{} struct in manifest)
      html = render_click(view, "switch_tab", %{"tab" => "exoforge_std_ws"})
      assert html =~ "v0.1.0"
      assert html =~ "Provides:"
      assert html =~ "WebSocket" or html =~ "ws" or html =~ "Ws"
      refute html =~ "Protocol.UndefinedError"
    end

    test "extensions registry tab renders with search and category filtering" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Switch to extensions tab
      html = render_click(view, "switch_tab", %{"tab" => "apps"})
      assert html =~ "Extensions Registry"
      assert html =~ "combat_wasm"
      assert html =~ "exoforge_std_ws"

      # 1. Search extensions
      html = render_change(view, "search_extensions", %{"query" => "combat"})
      assert html =~ "Combat Sandbox"
      refute html =~ "WebSocket Gateway"

      # 2. Clear search and filter by category
      html = render_change(view, "search_extensions", %{"query" => ""})
      assert html =~ "WebSocket Gateway"

      html = render_click(view, "filter_extension_category", %{"category" => "ingress"})
      assert html =~ "WebSocket Gateway"
      refute html =~ "Combat Sandbox"

      # 3. Search yielding no results shows empty state with Reset Filters button
      html = render_change(view, "search_extensions", %{"query" => "nonexistent_extension_xyz"})
      assert html =~ "No extensions match your filter"
      assert html =~ "Reset Filters"

      # 4. Reset filters
      _html = render_click(view, "filter_extension_category", %{"category" => "all"})
      # Search input still holds query until cleared
      html = render_change(view, "search_extensions", %{"query" => ""})
      assert html =~ "Combat Sandbox"
      assert html =~ "WebSocket Gateway"
    end

    test "toast notices auto-dismiss" do
      session = %{"admin_player_id" => "toast_user", "admin_scopes" => ["admin"]}
      conn = build_conn() |> Plug.Test.init_test_session(session)
      {:ok, view, _html} = live(conn, "/")

      html = render_change(view, "switch_env", %{"env" => "Dev"})
      assert html =~ "Switched active environment to Dev"

      send(view.pid, {:clear_toast, :info})
      refute render(view) =~ "Switched active environment to Dev"
    end

    test "pinned extensions persist across remounts" do
      session = %{"admin_player_id" => "pin_persist_user", "admin_scopes" => ["admin"]}

      conn = build_conn() |> Plug.Test.init_test_session(session)
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "pin_extension", %{"id" => "exoforge_std_ws"})

      conn2 = build_conn() |> Plug.Test.init_test_session(session)
      {:ok, _view2, html} = live(conn2, "/")
      assert html =~ "WebSocket Gateway"
    end

    test "supports pinning extensions to the top navigation bar" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Pin exoforge_std_ws and combat_wasm
      html = render_click(view, "pin_extension", %{"id" => "exoforge_std_ws"})
      assert html =~ "WebSocket"

      html = render_click(view, "pin_extension", %{"id" => "combat_wasm"})
      assert html =~ "Combat"

      # Unpin combat_wasm
      html = render_click(view, "unpin_extension", %{"id" => "combat_wasm"})
      assert html =~ "Unpinned combat_wasm from top bar"
    end

    test "keyboard shortcuts: Cmd+K toggles Command Palette and Escape closes it" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # 1. Trigger Cmd+K keydown event
      html = render_hook(view, "handle_key", %{"key" => "k", "metaKey" => true})
      assert html =~ "Search plugins, resources, players, actions... (Cmd+K)"

      # 2. Trigger Escape keydown event to close modal
      html = render_hook(view, "handle_key", %{"key" => "Escape"})
      refute html =~ "Search plugins, resources, players, actions... (Cmd+K)"
    end

    test "quick environment switcher updates environment badge and state" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Switch environment to Dev
      html = render_change(view, "switch_env", %{"env" => "Dev"})
      assert html =~ "Switched active environment to Dev"
      assert html =~ "DEV"

      # Switch environment to Staging
      html = render_change(view, "switch_env", %{"env" => "Staging"})
      assert html =~ "Switched active environment to Staging"
      assert html =~ "STAGING"
    end

    test "topbar navigation orders overview first, extensions second, and enforces pin limit" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, html} = live(conn, "/")

      # Verify Overview and Extensions order in navigation
      assert html =~ "Overview"
      assert html =~ "Extensions"

      # Overview appears before Extensions in the rendered HTML
      {overview_pos, _} = :binary.match(html, "Overview")
      {extensions_pos, _} = :binary.match(html, "Extensions")
      assert overview_pos < extensions_pos

      # Attempt to pin beyond the limit
      # Max pinned is 8
      for i <- 1..10 do
        render_click(view, "pin_extension", %{"id" => "ext_#{i}"})
      end

      # Should hit the maximum limit
      html = render_click(view, "pin_extension", %{"id" => "ext_overflow"})
      assert html =~ "Maximum of 8 pinned extensions reached"
    end

    test "stateful entity runtime panel displays cluster actors and supports refresh" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, html} = live(conn, "/")

      # Overview includes the new Actor panel
      assert html =~ "Stateful Entity Actors"

      # Refresh entities event
      html = render_click(view, "refresh_entities", %{})
      assert html =~ "Stateful Entity Actors"
      assert html =~ "Refresh"
    end

    test "plugin manager extension view displays cluster runtime telemetry, inspector drawer, and modals" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Pin and switch to Plugin Manager tab
      render_click(view, "pin_extension", %{"id" => "exoforge_std_plugin_manager"})
      html = render_click(view, "switch_tab", %{"tab" => "exoforge_std_plugin_manager"})

      assert html =~ "Plugin Manager &amp; Cluster Runtime" or html =~ "Plugin Manager & Cluster Runtime"
      assert html =~ "Installed Plugins"
      assert html =~ "BEAM Memory &amp; Load" or html =~ "BEAM Memory & Load"
      assert html =~ "Cluster Node"
      assert html =~ "Active Entities"
      assert html =~ "Upload WASM Plugin"
      assert html =~ "Restart Cluster"

      # Open upload modal via PluginManagerView component
      html = view |> element("button", "Upload WASM Plugin") |> render_click()
      assert html =~ "Upload C# WASM Plugin"
      assert html =~ "WASM Binary (.wasm)"

      # Close upload modal
      html = view |> element("button", "Cancel") |> render_click()
      refute html =~ "Upload C# WASM Plugin"

      # Open restart cluster modal
      html = view |> element("button", "Restart Cluster") |> render_click()
      assert html =~ "Restart Cluster Supervision?"

      # Close restart modal
      html = view |> element("button", "Cancel") |> render_click()
      refute html =~ "Restart Cluster Supervision?"
    end
  end
end
