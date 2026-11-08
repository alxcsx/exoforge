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
  alias Exoforge.ExtensionRegistry
  alias Exoforge.EventDispatcher
  alias Exoforge.Std.Database.Manager, as: DbManager

  @endpoint Endpoint

  defmodule UserRefsContract do
    import Exoforge.Contracts.Service

    defservice user_refs do
      resource :user_ref_rows do
        primary_key(:id)
        column(:id, :string)
        column(:player_id, :string, role: "user_id")
      end
    end
  end

  setup do
    ExtensionRegistry.initialize_ets()

    unless Process.whereis(DbManager) do
      start_supervised!({DbManager, [driver: :sqlite]})
    end

    unless Process.whereis(EventDispatcher.registry_name()) do
      start_supervised!(EventDispatcher)
    end

    unless Process.whereis(Exoforge.Std.Dashboard.PubSub) do
      start_supervised!({Phoenix.PubSub, name: Exoforge.Std.Dashboard.PubSub})
    end

    unless Process.whereis(Endpoint) do
      start_supervised!(Endpoint)
    end

    unless Process.whereis(Exoforge.Std.Dashboard.RecentEvents) do
      start_supervised!(Exoforge.Std.Dashboard.RecentEvents)
    end

    Exoforge.Std.Dashboard.RecentEvents.init_table()
    Exoforge.Std.Dashboard.RecentEvents.clear()

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb],
      category: "Storage",
      system: true,
      dashboard_view: %{id: :database, title: "Database Engine", icon: "🗄️"}
    })

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_resources,
      name: "exoforge_std_resources",
      version: "0.1.0",
      entry_point: Exoforge.Std.Resources,
      provides: [Exoforge.Std.Services.ResourceStore]
    })

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_dashboard,
      name: "exoforge_std_dashboard",
      version: "0.1.0",
      entry_point: Exoforge.Std.Dashboard,
      provides: [Exoforge.Std.Services.Dashboard],
      dependencies: [],
      category: "Studio",
      system: true,
      dashboard_view: %{id: :dashboard, title: "Exoforge Dashboard", icon: "📊"}
    })

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_dashboard_views,
      name: "exoforge_std_dashboard_views",
      version: "0.1.0",
      entry_point: Exoforge.Std.DashboardViews,
      provides: [Exoforge.Std.Services.DashboardView],
      dependencies: [Exoforge.Std.Services.Dashboard],
      category: "Studio"
    })

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
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
        module: Exoforge.Std.DashboardViews.AuthView
      },
      ui_hooks: %{
        resource_column: [
          %{id: :user_id, role: "user_id", target: "exoforge_std_auth", focus: "user", order: 10}
        ]
      }
    })

    Exoforge.Std.Auth.init_schema()

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_player_data,
      name: "exoforge_std_player_data",
      version: "0.1.0",
      entry_point: Exoforge.Std.PlayerData,
      provides: [Exoforge.Std.Services.PlayerData],
      dependencies: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Auth],
      category: "LiveOps",
      dashboard_view: %{id: :player_data, title: "Player Data", icon: "👤"},
      ui_hooks: %{
        user_inspect: [
          %{
            id: :players,
            title: "Players",
            icon: "🎮",
            order: 30,
            module: Exoforge.Std.DashboardViews.UserPlayersTab
          }
        ]
      }
    })

    Exoforge.Std.PlayerData.init_schema()

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
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

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :combat_plugin,
      name: "combat_plugin",
      version: Version.parse!("1.0.0"),
      entry_point: :combat_plugin,
      type: :native,
      provides: [Exoforge.Std.Services.Combat],
      dependencies: [],
      category: "Gameplay",
      dashboard_view: %{id: :combat, title: "Combat Sandbox", icon: "⚔️"}
    })

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_extension_manager,
      name: "exoforge_std_extension_manager",
      version: Version.parse!("0.1.0"),
      entry_point: Exoforge.Std.ExtensionManager,
      provides: [Exoforge.Std.Services.ExtensionManager],
      dependencies: [],
      category: "Management",
      system: true,
      dashboard_view: %{
        id: :extension_manager,
        title: "Extension Manager",
        icon: "📦",
        module: Exoforge.Std.DashboardViews.ExtensionManagerView
      }
    })

    ExtensionRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_docs,
      name: "exoforge_std_docs",
      version: Version.parse!("0.1.0"),
      entry_point: Exoforge.Std.Docs,
      provides: [Exoforge.Std.Services.Docs],
      dependencies: [Exoforge.Std.Services.ExtensionManager],
      category: "System",
      system: true,
      dashboard_view: %{
        id: :docs,
        title: "Developer Guide",
        icon: "📖",
        module: Exoforge.Std.Docs.DashboardView
      }
    })

    Exoforge.Std.Resources.run_migrations()

    # Clear pinned state only once :resource_store is registered — otherwise this no-ops and
    # pins leak between tests.
    Exoforge.Std.Dashboard.Preferences.put_pinned("admin", [])

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
      assert html =~ "Event &amp; Action Throughput"
      assert html =~ "Error &amp; Exception Graph"
      assert html =~ "Server State"
      assert html =~ "Online / Faulty Extensions"
      assert html =~ "Download SDK"

      # Start from a clean pinned list (other tests may have pinned up to @max_pinned).
      for id <- Exoforge.Std.Dashboard.Preferences.pinned("admin") do
        _ = render_click(view, "unpin_extension", %{"id" => id})
      end

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

      # Simulate kernel broadcasting an event on the studio topic the dock subscribes to
      # (M33 Fix 32: gameplay topics no longer reach the Studio).
      EventDispatcher.broadcast(:player_created, %{player_id: "p_live_999", name: "Nova"}, topic: "studio")

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

      # 3. Update form inputs. Caller scopes are not a form input anymore (M33 Fix 27): what the
      # console dispatches with is the session's verified scopes, shown read-only.
      html = render_change(view, "change_action_form", %{})

      assert html =~ "Caller Scopes (verified session scopes)"

      # 4. Dispatch the action — a form-supplied caller_scopes is discarded, not honored.
      html = render_submit(view, "dispatch_action", %{"caller_scopes" => "server, admin"})
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

      # Switch to combat_plugin extension tab (has no custom LiveView)
      html = render_click(view, "switch_tab", %{"tab" => "combat_plugin"})
      # This test manifest declares no actions/resources/events, so the generic view opens on
      # its contract.
      assert html =~ "Architecture Specification"
    end

    test "the registry marks custom UIs subtly and lists system plugins first" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "switch_tab", %{"tab" => "apps"})

      # Every view opens as a Control Panel; no custom-vs-generated badge remains.
      assert html =~ "Control Panel"
      assert html =~ "Inspect"
      refute html =~ "Dedicated UI"
      refute html =~ "Auto-Generated"

      # Plugins shipping their own UI carry a subtle marker.
      assert html =~ "✦"

      # System plugins with a UI sort ahead of headless ones.
      assert :binary.match(html, "exoforge_std_extension_manager") <
               :binary.match(html, "exoforge_std_resources")
    end

    # The Data tab used to be read-only: a developer could look at their plugin's rows and delete
    # them, but not make one. The form is built from the schema the plugin declares, so a record that
    # gains a column gains an input without anything here knowing what the column means.
    test "a resource row is created and edited from its declared schema" do
      ExtensionRegistry.register(%Exoforge.Domain.Manifest{
        id: :row_form_ext,
        name: "row_form_ext",
        version: "0.1.0",
        entry_point: nil,
        provides: [UserRefsContract.UserRefs],
        category: "Gameplay",
        dashboard_view: %{id: :row_form_ext, title: "Rows", icon: "📝"}
      })

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")
      _html = render_click(view, "switch_tab", %{"tab" => "row_form_ext"})

      # The form is the schema: both declared columns, and the key marked as one.
      html = view |> element("button[phx-click=new_resource]") |> render_click()
      assert html =~ "Fields come from the schema this plugin declares"
      assert html =~ "Id · key"
      assert html =~ "Player id"

      # A resource with no key cannot be identified, so the form refuses it.
      html =
        view
        |> element("form[phx-submit=submit_resource_form]")
        |> render_submit(%{"values" => %{"id" => "", "player_id" => "p1"}})

      assert html =~ "is required"

      html =
        view
        |> element("form[phx-submit=submit_resource_form]")
        |> render_submit(%{"values" => %{"id" => "g1", "player_id" => "p1"}})

      assert html =~ "g1"
      assert Enum.any?(ExtensionRegistry.fetch_resource_rows("user_ref_rows"), &(&1["id"] == "g1"))

      # And it can be edited, which is the other half of what the tab was missing.
      html = view |> element("button[phx-click=open_focus]") |> render_click()

      # The drawer opens on the schema's view: the columns as declared, labelled, with their types.
      assert html =~ "Id · key"
      assert html =~ "Player id"
      refute html =~ "As stored."

      # And the other declared tab is the raw row, which is a different question - keys as stored,
      # values as stored, including anything the schema does not describe.
      html =
        view
        |> element(~s{button[phx-click=select_drawer_tab][phx-value-tab="attributes"]})
        |> render_click()

      assert html =~ "As stored."

      html = view |> element("button[phx-click=edit_resource]") |> render_click()
      assert html =~ "Edit"

      _html =
        view
        |> element("form[phx-submit=submit_resource_form]")
        |> render_submit(%{"values" => %{"id" => "g1", "player_id" => "p2"}})

      assert Enum.any?(
               ExtensionRegistry.fetch_resource_rows("user_ref_rows"),
               &(&1["player_id"] == "p2")
             )
    end

    test "a resource column tagged with a role renders as a deep link" do
      ExtensionRegistry.register(%Exoforge.Domain.Manifest{
        id: :user_ref_ext,
        name: "user_ref_ext",
        version: "0.1.0",
        entry_point: nil,
        provides: [UserRefsContract.UserRefs],
        category: "Gameplay",
        dashboard_view: %{id: :user_ref_ext, title: "Refs", icon: "🔗"}
      })

      Exoforge.Std.Database.put(:user_ref_ext, "user_ref_rows", "row1", %{
        "id" => "row1",
        "player_id" => "player_7"
      })

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "switch_tab", %{"tab" => "user_ref_ext"})

      assert html =~ "/tab/exoforge_std_auth?focus=user:player_7"
    end

    test "the user inspector renders plugin-contributed tabs" do
      {:ok, _} =
        Exoforge.ActionDispatcher.dispatch(:auth, :register, %{
          user_id: "u_test",
          player_id: "u_test",
          name: "Test User",
          email: "test@example.com",
          password: "secret123",
          scopes: ["player"]
        })

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")
      render_click(view, "switch_tab", %{"tab" => "exoforge_std_auth"})

      # One "Inspect" button per user row, and the table is shared with every other test in the
      # suite, so select this user's rather than the only one there is.
      html =
        view
        |> element(~s{button[phx-click=open_focus][phx-value-id="u_test"]})
        |> render_click()

      # Opening the drawer is a URL change, so it is linkable and back-navigable.
      assert_patch(view, "/tab/exoforge_std_auth?focus=user:u_test")

      # The tab comes from the player data plugin's `:user_inspect` hook.
      assert html =~ "Players"

      html =
        view
        |> element(~s{button[phx-click=switch_user_inspect_tab][phx-value-tab="players"]})
        |> render_click()

      assert html =~ "Linked Players"

      # Closing is a URL change too.
      view |> element("button[phx-click=close_focus]", "Close") |> render_click()
      assert_patch(view, "/tab/exoforge_std_auth")
      refute render(view) =~ "Linked Players"
    end

    test "mounts PlayerDataView from dashboard_views for exoforge_std_player_data" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "switch_tab", %{"tab" => "exoforge_std_player_data"})
      assert html =~ "Registered Players"
      assert html =~ "New Player Profile"
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
      assert html =~ "Extension Registry"
      assert html =~ "combat_plugin"
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
      Exoforge.Std.Dashboard.Preferences.put_pinned("toast_user", [])
      conn = build_conn() |> Plug.Test.init_test_session(session)
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "pin_extension", %{"id" => "exoforge_std_ws"})
      assert html =~ "Pinned exoforge_std_ws to top navigation bar."

      send(view.pid, {:clear_toast, :info})
      refute render(view) =~ "Pinned exoforge_std_ws to top navigation bar."
    end

    test "pinned extensions persist across remounts" do
      session = %{"admin_player_id" => "pin_persist_user", "admin_scopes" => ["admin"]}

      Exoforge.Std.Dashboard.Preferences.put_pinned("pin_persist_user", [])

      conn = build_conn() |> Plug.Test.init_test_session(session)
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "pin_extension", %{"id" => "exoforge_std_ws"})

      assert Exoforge.Std.Dashboard.Preferences.pinned("pin_persist_user") == ["exoforge_std_ws"]

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

      # Start from a clean pinned list (other tests may have pinned up to @max_pinned).
      for id <- Exoforge.Std.Dashboard.Preferences.pinned("admin") do
        _ = render_click(view, "unpin_extension", %{"id" => id})
      end

      # Pin exoforge_std_ws and exoforge_std_auth
      html = render_click(view, "pin_extension", %{"id" => "exoforge_std_ws"})
      assert html =~ "WebSocket"

      html = render_click(view, "pin_extension", %{"id" => "exoforge_std_auth"})
      assert html =~ "Users &amp; Auth" or html =~ "Users & Auth"

      # Unpin both so the pinned list does not leak into other tests
      html = render_click(view, "unpin_extension", %{"id" => "exoforge_std_auth"})
      assert html =~ "Unpinned exoforge_std_auth from top bar"

      _ = render_click(view, "unpin_extension", %{"id" => "exoforge_std_ws"})
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

      # Pin beyond the limit with circular queue (FIFO)
      # Default max pinned is 8
      for i <- 1..10 do
        render_click(view, "pin_extension", %{"id" => "ext_#{i}"})
      end

      # Circular pinning: removes the oldest pin in a circle
      html = render_click(view, "pin_extension", %{"id" => "ext_overflow"})
      assert html =~ "ext_overflow"
      refute html =~ ~s(phx-value-tab="ext_1")

      # Screen size adjustment via set_nav_capacity hook
      render_click(view, "set_nav_capacity", %{"max_pinned" => 4, "screen_width" => 800})
      html_resized = render(view)
      assert html_resized =~ "ext_overflow"
    end

    test "plugin manager extension view displays cluster runtime telemetry, inspector drawer, and modals" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Pin and switch to Extension Manager tab
      render_click(view, "pin_extension", %{"id" => "exoforge_std_extension_manager"})
      html = render_click(view, "switch_tab", %{"tab" => "exoforge_std_extension_manager"})

      assert html =~ "Extension Manager &amp; Cluster Runtime" or
               html =~ "Extension Manager & Cluster Runtime"

      assert html =~ "Installed Extensions" or html =~ "Installed Plugins"
      assert html =~ "BEAM Memory &amp; Load" or html =~ "BEAM Memory & Load"
      assert html =~ "Cluster Node"
      assert html =~ "Upload Extension" or html =~ "Upload Plugin"
      assert html =~ "Restart Cluster"

      # Open upload modal via ExtensionManagerView component
      html = view |> element("button", "Upload Extension") |> render_click()
      assert html =~ "Upload C# Extension"
      assert html =~ "Extension Binary"

      # Close upload modal
      html = view |> element("button", "Cancel") |> render_click()
      refute html =~ "Upload C# Extension"

      # Open restart cluster modal
      html = view |> element("button", "Restart Cluster") |> render_click()
      assert html =~ "Restart Cluster Supervision?"

      # Close restart modal
      html = view |> element("button", "Cancel") |> render_click()
      refute html =~ "Restart Cluster Supervision?"

      # Open dependency graph modal
      html = view |> element("button", "Show Dependency Graph") |> render_click()
      assert html =~ "Extension Dependency Architecture"
    end

    test "direct URL navigation and deep-linking routes correctly" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      # Direct load of /extensions
      {:ok, _view, html} = live(conn, "/extensions")
      assert html =~ "Extension Registry"

      # Direct deep-link to /tab/player_data
      {:ok, view, html} = live(conn, "/tab/player_data")
      assert html =~ "Registered Players"
      assert html =~ "New Player Profile"

      # Switching tab patches URL
      render_click(view, "switch_tab", %{"tab" => "exoforge_std_auth"})
      assert_patched(view, "/tab/exoforge_std_auth")

      # Switching to overview patches URL to /
      render_click(view, "switch_tab", %{"tab" => "overview"})
      assert_patched(view, "/")
    end

    test "renders dark-by-default theme engine, favicon, visual settings theme toggle, and unfolded system plugins" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      conn = get(conn, "/")
      page_html = html_response(conn, 200)

      # Default dark mode class on <html> and synchronous theme boot script
      assert page_html =~ ~s(<html lang="en" class="dark">)
      assert page_html =~ "window.ExoforgeTheme"
      assert page_html =~ ~s(href="/favicon.svg")
      assert page_html =~ ~s(href="/favicon.ico")

      # Header no longer has the theme toggle button; it lives in Settings -> Visual Settings
      {:ok, view, html} = live(conn)
      refute html =~ "Toggle Dark / Light Theme"

      settings_html = render_click(view, "open_settings", %{})
      assert settings_html =~ "Visual Settings"
      refute settings_html =~ ~s(phx-value-tab="sdks")
      assert settings_html =~ "Commit Hash"
      assert settings_html =~ Exoforge.BuildInfo.version()

      visual_html = render_click(view, "set_settings_tab", %{"tab" => "visual"})
      assert visual_html =~ "Studio Color Theme"
      assert visual_html =~ "Toggle Theme"
      _ = render_click(view, "close_settings", %{})

      # Extensions Registry renders technical badges, table for system extensions, and clickable cards
      ext_html = render_click(view, "switch_tab", %{"tab" => "apps"})
      refute ext_html =~ "Technical Specs"
      assert ext_html =~ "System Extensions &amp; Headless Services"
      assert ext_html =~ "<table"
      assert ext_html =~ ~s(phx-click="switch_tab")

      # Test pinning an extension from the registry
      pin_html = render_click(view, "pin_extension", %{"id" => "exoforge_std_auth"})
      assert pin_html =~ "Pinned"

      # Test inspecting an extension
      inspect_html = render_click(view, "inspect_extension", %{"id" => "exoforge_std_auth"})
      assert inspect_html =~ "exoforge_std_auth"

      # Test unpinning
      unpin_html = render_click(view, "unpin_extension", %{"id" => "exoforge_std_auth"})
      assert unpin_html =~ "Pin"
    end

    test "overview 4-slot grid supports slot rearrangement, SDK modal popup, and faulty extension warnings" do
      # Register a faulty extension with infinite_loop flag and a dynamic overview widget
      :ets.insert(:exo_extensions_mem, {
        :looping_economy_ext,
        %{
          id: :looping_economy_ext,
          name: "Looping Economy Extension",
          version: "1.0.0",
          type: :native,
          infinite_loop: true,
          provides: [:economy],
          dependencies: [],
          resources: [],
          events: [],
          ui_hooks: %{
            overview_widget: [
              %{
                id: "economy_money_graph",
                title: "Economy Money Graph",
                subtitle: "Live gold sink/faucet balance",
                icon: "💰",
                slot_size: "2x1",
                type: :stat_list,
                items: [%{label: "Gold Minted", value: "12,400"}]
              }
            ]
          }
        }
      })

      on_exit(fn ->
        try do
          :ets.delete(:exo_extensions_mem, :looping_economy_ext)
        rescue
          _ -> :ok
        end
      end)

      admin_id = "grid_test_admin_#{System.unique_integer([:positive])}"

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => admin_id,
          "admin_scopes" => ["admin"]
        })

      {:ok, view, html} = live(conn, "/")

      # Verify Project Overview title and no subtitle
      assert html =~ "Project Overview"
      refute html =~ "Cluster Overview"

      # Verify 4-slot grid elements and dynamic widget
      assert html =~ ~s(id="slot-quickstart")
      assert html =~ ~s(id="slot-event_graph")
      assert html =~ ~s(id="slot-error_graph")
      assert html =~ ~s(id="slot-server_state")
      assert html =~ ~s(id="slot-download_sdk")
      assert html =~ ~s(id="slot-extension_health")
      assert html =~ "Economy Money Graph"
      assert html =~ "Infinite loop / log flood detected"

      # Verify download sdk and health items switched places (download_sdk before extension_health)
      {sdk_pos, _} = :binary.match(html, ~s(id="slot-download_sdk"))
      {health_pos, _} = :binary.match(html, ~s(id="slot-extension_health"))
      assert sdk_pos < health_pos

      # When not in edit mode, size badges (2×2, 1×1) and movement arrows are hidden
      assert html =~ "Edit Grid Order"
      refute html =~ "Reset Grid"
      refute html =~ "2×2"

      # Multi-line time series SVG graphs (X axis time, Y axis count)
      assert html =~ "polyline"
      assert html =~ "-25m"
      assert html =~ "Now"
      refute html =~ "Open Console"

      # Console is available in Settings modal only
      render_click(view, "open_settings", %{})
      console_html = render_click(view, "set_settings_tab", %{"tab" => "console"})
      assert console_html =~ "Cluster Event Stream &amp; Console"
      render_click(view, "close_settings", %{})

      # Enable edit mode: size badges, movement arrows, and done editing appear
      edit_html = render_click(view, "toggle_grid_edit_mode", %{})
      assert edit_html =~ "Done Editing"
      assert edit_html =~ "2×2"
      assert edit_html =~ "move_overview_slot"

      # Rearrange slot: move event_graph right (after error_graph)
      reordered_html =
        render_click(view, "move_overview_slot", %{"id" => "event_graph", "dir" => "next"})

      {err_pos, _} = :binary.match(reordered_html, ~s(id="slot-error_graph"))
      {ev_pos, _} = :binary.match(reordered_html, ~s(id="slot-event_graph"))
      assert err_pos < ev_pos

      saved_order = Exoforge.Std.Dashboard.Preferences.overview_order(admin_id)
      assert Enum.at(saved_order, 0) == "quickstart"
      assert Enum.at(saved_order, 1) == "error_graph"
      assert Enum.at(saved_order, 2) == "event_graph"

      # Test removing a slot and re-adding it
      removed_html =
        render_click(view, "remove_overview_slot", %{"id" => "quickstart"})
      refute removed_html =~ ~s(id="slot-quickstart")

      order_after_remove = Exoforge.Std.Dashboard.Preferences.overview_order(admin_id)
      refute "quickstart" in order_after_remove

      added_html =
        render_click(view, "add_overview_slot", %{"id" => "quickstart"})
      assert added_html =~ ~s(id="slot-quickstart")
      order_after_add = Exoforge.Std.Dashboard.Preferences.overview_order(admin_id)
      assert "quickstart" in order_after_add

      # Reset button is now visible in edit mode because order is modified
      assert reordered_html =~ "Reset Grid"

      # Open SDK Download Modal from Overview tab
      sdk_html = render_click(view, "open_sdk_modal", %{})
      assert sdk_html =~ "Download Engine &amp; Client SDKs"
      assert sdk_html =~ "Installation Instructions"
      assert sdk_html =~ "Unity Package Manager (UPM)"

      # Verify 0 error labels are hidden from Error Graph
      assert html =~ "Zero errors detected across all monitored actions"
      refute html =~ "(0 errors)"

      # Broadcast a cluster event to verify live event feed update
      refute html =~ "Emit Test Event"
      ev_item = Exoforge.Std.Dashboard.RecentEvents.record("auth.login", %{player_id: "user_42"})
      send(view.pid, {:studio_event, ev_item})
      feed_html = render(view)
      assert feed_html =~ "auth.login"
      assert feed_html =~ "Live Stream Events"
      assert feed_html =~ "More"

      # Open Events History Modal via "More" button
      events_modal_html = render_click(view, "open_events_modal", %{})
      assert events_modal_html =~ "Cluster Event Stream &amp; History"
      assert events_modal_html =~ "auth.login"
      render_click(view, "close_events_modal", %{})

      # Open Actions Detail Modal via graph Expand button (includes expanded graph + table)
      detail_html = render_click(view, "open_actions_detail_modal", %{"mode" => "actions"})
      assert detail_html =~ "Action Invocations &amp; Telemetry Details"
      assert detail_html =~ "Expanded Action Throughput"
      assert detail_html =~ "Filter actions by name or service..."
      assert detail_html =~ "Active Traffic"

      # Open Error Breakdown mode
      err_detail_html = render_click(view, "open_actions_detail_modal", %{"mode" => "errors"})
      assert err_detail_html =~ "Action Exceptions &amp; Error Breakdown"
      assert err_detail_html =~ "Expanded Error Spikes"

      # Close detail modal
      closed_html = render_click(view, "close_actions_detail_modal", %{})
      refute closed_html =~ "Action Exceptions &amp; Error Breakdown"
    end

    test "CORS access policy controller updates highlight and disables allowed_origins when relaxed or strict" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")
      _ = render_click(view, "open_settings", %{})
      cors_html = render_click(view, "set_settings_tab", %{"tab" => "cors"})

      # Default mode is relaxed: allowed_origins input should be disabled
      assert cors_html =~ ~s(id="cors-policy-relaxed")
      assert cors_html =~ ~s(disabled)

      # Switch to whitelist: allowed_origins input is enabled (not disabled)
      whitelist_html =
        render_change(view, "change_cors_settings", %{
          "mode" => "whitelist",
          "allowed_origins" => "https://game.example.com"
        })

      assert whitelist_html =~ "https://game.example.com"
      refute whitelist_html =~ ~r/<input[^>]*name="allowed_origins"[^>]*disabled/

      # Switch to strict: allowed_origins input is disabled again
      strict_html =
        render_change(view, "change_cors_settings", %{
          "mode" => "strict",
          "allowed_origins" => "https://game.example.com"
        })

      assert strict_html =~ ~r/<input[^>]*name="allowed_origins"[^>]*disabled/
    end

    test "project metadata persists via ProjectMetadata and updates live through settings modal" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, _html} = live(conn, "/")

      # Check initial get
      initial_meta = Exoforge.Std.Dashboard.ProjectMetadata.get()
      assert is_binary(initial_meta["project_name"])
      assert is_binary(initial_meta["studio_name"])

      # Open settings modal
      _ = render_click(view, "open_settings", %{})

      # Submit project metadata form
      save_html =
        render_submit(view, "save_project_metadata", %{
          "project_name" => "Cyber Arena 2099",
          "studio_name" => "RetroForge Labs",
          "description" => "Next-gen competitive arena",
          "website_url" => "https://retroforge.dev",
          "custom_json" => Jason.encode!(%{"genre" => "cyberpunk", "region" => "eu-central"})
        })

      assert save_html =~ "Cyber Arena 2099"
      assert save_html =~ "RetroForge Labs"
      assert save_html =~ "Project metadata saved successfully."

      # Verify persistence in ProjectMetadata module
      persisted = Exoforge.Std.Dashboard.ProjectMetadata.get()
      assert persisted["project_name"] == "Cyber Arena 2099"
      assert persisted["studio_name"] == "RetroForge Labs"
      assert persisted["description"] == "Next-gen competitive arena"
      assert persisted["website_url"] == "https://retroforge.dev"
      assert persisted["custom"]["genre"] == "cyberpunk"
      assert persisted["custom"]["region"] == "eu-central"

      # Verify Application env sync
      assert Exoforge.Metering.project_name() == "Cyber Arena 2099"
      assert Exoforge.Metering.studio_name() == "RetroForge Labs"
    end

    test "developer guide button in settings modal navigates to guide tab and supports attribute subpages" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "admin_player_id" => "admin",
          "admin_scopes" => ["admin"]
        })

      {:ok, view, html} = live(conn, "/")

      # Verify fixed top nav bar does NOT have guide button
      [_, header_html, _] = String.split(html, ~r{</?header[^>]*>}, parts: 3)
      refute header_html =~ ~s(phx-value-tab="guide")

      # Open settings modal
      settings_html = render_click(view, "open_settings", %{})
      assert settings_html =~ "Developer Guide"
      assert settings_html =~ ~s(phx-value-tab="guide")

      # Switch to guide tab in settings modal
      guide_tab_html = render_click(view, "set_settings_tab", %{"tab" => "guide"})
      assert guide_tab_html =~ "Exoforge Developer Guide"
      assert guide_tab_html =~ "open_guide_from_settings"

      # Click Developer Guide button in settings to open full extension tab
      _ = render_click(view, "open_guide_from_settings", %{})

      # Now on Guide screen: verify default Quickstart Flow
      guide_html = render(view)
      assert guide_html =~ "From Zero to Live Online Multiplayer Features"
      assert guide_html =~ "Connect &amp; Authenticate"

      # Switch to Architecture subpage
      arch_html = render_click(view, "set_guide_subpage", %{"subpage" => "architecture"})
      assert arch_html =~ "Exoforge UML Architecture Diagram"
      assert arch_html =~ "ActionDispatcher"

      # Switch to aggregated C# Attributes subpage
      attr_html = render_click(view, "set_guide_subpage", %{"subpage" => "attributes"})
      assert attr_html =~ "[ExoExtension]"
      assert attr_html =~ "[ExoAction]"
      assert attr_html =~ "[ExoEvent]"
      assert attr_html =~ "[ExoResource]"
      assert attr_html =~ "Exoforge.Plugin.SDK"
      assert attr_html =~ "exoforge_std_extension_manager"
      assert attr_html =~ "exoforge_std_resources"
      assert attr_html =~ "[ExoResource] Parameters"
      assert attr_html =~ "[ExoColumn] Parameters"

      # Switch to What You Can Build subpage
      use_cases_html = render_click(view, "set_guide_subpage", %{"subpage" => "use_cases"})
      assert use_cases_html =~ "What You Can Build with Exoforge"
      assert use_cases_html =~ "The Paradigm Shift: Exoforge vs. Legacy BaaS"
      assert use_cases_html =~ "Auction House &amp; P2P"
      assert use_cases_html =~ "In-Memory Matchmaker"
      assert use_cases_html =~ "Hot State in RAM, Durable in DB"
    end
  end
end
