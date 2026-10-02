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
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    PluginRegistry.register(%Exoforge.Domain.Manifest{
      id: :exoforge_std_dashboard,
      name: "exoforge_std_dashboard",
      version: "0.1.0",
      entry_point: Exoforge.Std.Dashboard,
      provides: [Exoforge.Std.Services.DashboardView],
      dependencies: [Exoforge.Std.Services.Database]
    })

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
      assert html =~ "Overview &amp; Stats"
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
    test "mounts and displays Exoforge Shell header and metric cards" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})
      {:ok, view, html} = live(conn, "/")

      assert html =~ "EXOFORGE"
      assert html =~ "Overview"
      assert html =~ "Active Players"
      assert html =~ "Economy &amp; Gross LTV"
      assert html =~ "Active Game Services"
      assert html =~ "Gateway &amp; Latency"
      assert html =~ "Live Game Features"

      # Switch to Players tab
      html = render_click(view, "switch_tab", %{"tab" => "players"})
      assert html =~ "Player Directory &amp; Profile Management"

      # Search filter players
      html = render_change(view, "filter_players", %{"query" => "Valkyrie", "status" => "all"})
      assert html =~ "ValkyrieOne"

      # Open Command Palette (Cmd+K)
      html = render_click(view, "open_cmd_palette", %{})
      assert html =~ "Search plugins, resources, players, actions... (Cmd+K)"

      # Search in Command Palette
      html = render_change(view, "search_cmd_palette", %{"query" => "combat"})
      assert html =~ "Quick Action: Simulate Combat Attack"

      # Open entity side-drawer for player
      html = render_click(view, "inspect_player", %{"id" => "p_1001"})
      assert html =~ "Player Profile: ValkyrieOne"
      assert html =~ "Overview &amp; Stats"

      # Switch drawer tab to attributes
      html = render_click(view, "select_drawer_tab", %{"tab" => "attributes"})
      assert html =~ "Dynamic Attributes"
    end

    test "receives real-time events pushed by EventDispatcher and updates feed" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})
      {:ok, view, _html} = live(conn, "/")

      # Simulate kernel broadcasting an event
      EventDispatcher.broadcast(:player_created, %{player_id: "p_live_999", name: "Nova"})

      # Allow message to be processed by LiveView
      :timer.sleep(50)

      html = render(view)
      assert html =~ "player_created"
    end

    test "action runner modal opens, generates form inputs, and dispatches actions" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})
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
    end

    test "cluster event stream dock toggles, pauses, clears, and streams events" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})
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
  end
end
