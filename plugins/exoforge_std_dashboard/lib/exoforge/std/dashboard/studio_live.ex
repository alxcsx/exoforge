defmodule Exoforge.Std.Dashboard.StudioLive do
  @moduledoc """
  Phoenix LiveView for the Exoforge Game Producer & Designer Studio.
  Fully reactive, server-driven UI aligned with game_producer_studio_fixed.html.
  """
  use Phoenix.LiveView
  import Exoforge.Std.Dashboard.Components
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.DrawerRegistry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      try do
        EventDispatcher.subscribe(:all)
      rescue
        _ -> :ok
      end
    end

    overview = fetch_overview()
    players = fetch_players()
    drawer_tabs = DrawerRegistry.list_tabs("players")

    initial_events = [
      %{
        id: "ev_boot_1",
        event: "kernel:ready",
        payload: %{node: "BEAM (Exoforge)", plugins: length(overview.plugins)},
        time: "Just now"
      }
    ]

    action_catalog = fetch_action_catalog()
    default_service = List.first(action_catalog)
    default_service_name = if default_service, do: default_service.name, else: nil
    default_action = if default_service, do: List.first(default_service.actions), else: nil
    default_action_name = if default_action, do: default_action.name, else: nil
    default_params = default_params_for(default_action)
    total_spent_display = compute_total_spent(players)

    {:ok,
     assign(socket,
       current_tab: :overview,
       project_name: "Sanctum Haven",
       studio_name: "Haven Studios",
       environments: ["Live", "Dev", "Staging"],
       current_env: "Live",
       overview: overview,
       players: players,
       filtered_players: players,
       total_spent_display: total_spent_display,
       player_search: "",
       player_filter: "all",
       drawer_open: false,
       inspected_player: nil,
       inspected_tab: "overview",
       drawer_tabs: drawer_tabs,
       cmd_palette_open: false,
       cmd_query: "",
       cmd_results: [],
       settings_open: false,
       settings_tab: "project",
       app_drawer_open: false,
       activity_events: initial_events,
       filtered_activity_events: initial_events,
       quick_toast: nil,
       action_catalog: action_catalog,
       selected_action_service: default_service_name,
       selected_action_name: default_action_name,
       action_form_params: default_params,
       caller_scopes: "admin, player",
       action_modal_open: false,
       action_result: nil,
       action_latency_ms: nil,
       event_dock_open: false,
       events_paused: false,
       event_filter_topic: ""
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "players" -> :players
        "economy" -> :economy
        "balancing" -> :balancing
        "guilds" -> :guilds
        "localization" -> :localization
        "analytics" -> :analytics
        "community" -> :community
        "apps" -> :apps
        _ -> :overview
      end

    {:noreply, assign(socket, :current_tab, tab)}
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :current_tab, String.to_existing_atom(tab))}
  end

  def handle_event("switch_env", %{"env" => env}, socket) do
    {:noreply, assign(socket, :current_env, env)}
  end

  def handle_event("open_cmd_palette", _params, socket) do
    {:noreply, assign(socket, cmd_palette_open: true, cmd_query: "", cmd_results: default_cmd_results(socket))}
  end

  def handle_event("close_cmd_palette", _params, socket) do
    {:noreply, assign(socket, cmd_palette_open: false, cmd_query: "", cmd_results: [])}
  end

  def handle_event("search_cmd_palette", %{"query" => query}, socket) do
    q = String.downcase(String.trim(query))

    results =
      if q == "" do
        default_cmd_results(socket)
      else
        all = default_cmd_results(socket)
        Enum.filter(all, fn item ->
          String.contains?(String.downcase(item.title), q) or
            String.contains?(String.downcase(item.subtitle), q)
        end)
      end

    {:noreply, assign(socket, cmd_query: query, cmd_results: results)}
  end

  def handle_event("select_cmd_item", %{"id" => id, "type" => type}, socket) do
    socket = assign(socket, cmd_palette_open: false)

    case type do
      "navigation" ->
        {:noreply, assign(socket, :current_tab, String.to_existing_atom(id))}

      "action" ->
        handle_quick_action(id, socket)

      "resource" ->
        {:noreply, assign(socket, :current_tab, :players)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :settings_open, true)}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, :settings_open, false)}
  end

  def handle_event("set_settings_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :settings_tab, tab)}
  end

  def handle_event("filter_players", %{"query" => query, "status" => status}, socket) do
    q = String.downcase(String.trim(query))

    filtered =
      Enum.filter(socket.assigns.players, fn p ->
        matches_q =
          q == "" or
            String.contains?(String.downcase(p.id), q) or
            String.contains?(String.downcase(p.name), q) or
            String.contains?(String.downcase(p.email), q)

        matches_s =
          case status do
            "all" -> true
            "Active" -> p.status == "Active"
            "Suspended" -> p.status == "Suspended"
            _ -> true
          end

        matches_q and matches_s
      end)

    {:noreply, assign(socket, filtered_players: filtered, player_search: query, player_filter: status)}
  end

  def handle_event("inspect_player", %{"id" => player_id}, socket) do
    player = Enum.find(socket.assigns.players, &(&1.id == player_id))
    tabs = DrawerRegistry.list_tabs("players")

    {:noreply,
     assign(socket,
       drawer_open: true,
       inspected_player: player,
       inspected_tab: "overview",
       drawer_tabs: tabs
     )}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, drawer_open: false, inspected_player: nil)}
  end

  def handle_event("select_drawer_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, inspected_tab: tab)}
  end

  def handle_event("add_attribute", _params, socket) do
    case socket.assigns.inspected_player do
      nil ->
        {:noreply, socket}

      player ->
        new_attrs = (player.attributes || []) ++ [%{key: "new_attribute", value: "value"}]
        updated_player = Map.put(player, :attributes, new_attrs)

        updated_players =
          Enum.map(socket.assigns.players, fn p ->
            if p.id == player.id, do: updated_player, else: p
          end)

        {:noreply, assign(socket, inspected_player: updated_player, players: updated_players)}
    end
  end

  def handle_event("delete_attribute", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case socket.assigns.inspected_player do
      nil ->
        {:noreply, socket}

      player ->
        new_attrs = List.delete_at(player.attributes || [], idx)
        updated_player = Map.put(player, :attributes, new_attrs)

        updated_players =
          Enum.map(socket.assigns.players, fn p ->
            if p.id == player.id, do: updated_player, else: p
          end)

        {:noreply, assign(socket, inspected_player: updated_player, players: updated_players)}
    end
  end

  def handle_event("quick_action", %{"action" => action}, socket) do
    handle_quick_action(action, socket)
  end

  # ---- ACTION EXECUTION MODAL (M13.3) ----

  def handle_event("open_action_modal", params, socket) do
    svc_name = Map.get(params, "service") || socket.assigns.selected_action_service
    act_name = Map.get(params, "action")

    svc =
      Enum.find(socket.assigns.action_catalog, &(&1.name == svc_name)) ||
        List.first(socket.assigns.action_catalog)

    selected_svc_name = if svc, do: svc.name, else: nil

    act =
      if svc do
        if act_name do
          Enum.find(svc.actions, &(&1.name == act_name)) || List.first(svc.actions)
        else
          List.first(svc.actions)
        end
      end

    selected_act_name = if act, do: act.name, else: nil
    initial_params = default_params_for(act)

    {:noreply,
     assign(socket,
       action_modal_open: true,
       selected_action_service: selected_svc_name,
       selected_action_name: selected_act_name,
       action_form_params: initial_params,
       action_result: nil,
       action_latency_ms: nil
     )}
  end

  def handle_event("close_action_modal", _params, socket) do
    {:noreply, assign(socket, action_modal_open: false, action_result: nil)}
  end

  def handle_event("select_action_service", %{"service" => svc_name}, socket) do
    svc = Enum.find(socket.assigns.action_catalog, &(&1.name == svc_name))
    first_act = if svc, do: List.first(svc.actions)
    first_act_name = if first_act, do: first_act.name, else: nil
    initial_params = default_params_for(first_act)

    {:noreply,
     assign(socket,
       selected_action_service: svc_name,
       selected_action_name: first_act_name,
       action_form_params: initial_params,
       action_result: nil,
       action_latency_ms: nil
     )}
  end

  def handle_event("select_action_name", %{"action" => act_name}, socket) do
    svc = Enum.find(socket.assigns.action_catalog, &(&1.name == socket.assigns.selected_action_service))
    act = if svc, do: Enum.find(svc.actions, &(&1.name == act_name))
    initial_params = default_params_for(act)

    {:noreply,
     assign(socket,
       selected_action_name: act_name,
       action_form_params: initial_params,
       action_result: nil,
       action_latency_ms: nil
     )}
  end

  def handle_event("change_action_form", params, socket) do
    caller_scopes = Map.get(params, "caller_scopes", socket.assigns.caller_scopes)

    updated_params =
      Enum.reduce(params, socket.assigns.action_form_params, fn
        {"param_" <> name, val}, acc -> Map.put(acc, name, val)
        _other, acc -> acc
      end)

    {:noreply, assign(socket, action_form_params: updated_params, caller_scopes: caller_scopes)}
  end

  def handle_event("dispatch_action", params, socket) do
    caller_scopes_str = Map.get(params, "caller_scopes") || socket.assigns.caller_scopes

    updated_params =
      Enum.reduce(params, socket.assigns.action_form_params, fn
        {"param_" <> name, val}, acc -> Map.put(acc, name, val)
        _other, acc -> acc
      end)

    svc = Enum.find(socket.assigns.action_catalog, &(&1.name == socket.assigns.selected_action_service))
    act = if svc, do: Enum.find(svc.actions, &(&1.name == socket.assigns.selected_action_name))

    if svc && act do
      payload =
        Enum.reduce(act.params, %{}, fn p, acc ->
          val_str = Map.get(updated_params, p.name, "")
          casted = cast_param_value(val_str, p.type)
          Map.put(acc, String.to_atom(p.name), casted)
        end)

      scopes =
        caller_scopes_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      scopes = if scopes == [], do: ["admin"], else: scopes

      start_time = System.monotonic_time(:microsecond)
      service_atom = String.to_atom(svc.name)
      action_atom = String.to_atom(act.name)

      result =
        try do
          ActionDispatcher.dispatch(service_atom, action_atom, payload, caller_scopes: scopes)
        rescue
          e -> {:error, Exception.message(e)}
        catch
          :exit, reason -> {:error, inspect(reason)}
        end

      duration_us = System.monotonic_time(:microsecond) - start_time
      latency_ms = Float.round(duration_us / 1000, 2)

      # If player was created or modified, refresh player table
      socket =
        if svc.name == "player_data" and act.name in ["create_player", "update_player"] do
          players = fetch_players()
          spent_display = compute_total_spent(players)
          assign(socket, players: players, filtered_players: players, total_spent_display: spent_display)
        else
          socket
        end

      {:noreply,
       assign(socket,
         action_result: result,
         action_latency_ms: latency_ms,
         action_form_params: updated_params,
         caller_scopes: caller_scopes_str
       )}
    else
      {:noreply, put_flash(socket, :error, "Selected service or action not found.")}
    end
  end

  # ---- LIVE CLUSTER EVENT STREAM DOCK (M13.4) ----

  def handle_event("toggle_event_dock", _params, socket) do
    {:noreply, assign(socket, :event_dock_open, !socket.assigns.event_dock_open)}
  end

  def handle_event("toggle_event_pause", _params, socket) do
    {:noreply, assign(socket, :events_paused, !socket.assigns.events_paused)}
  end

  def handle_event("filter_event_dock", %{"topic" => topic}, socket) do
    filtered = filter_activity_events(socket.assigns.activity_events, topic)
    {:noreply, assign(socket, event_filter_topic: topic, filtered_activity_events: filtered)}
  end

  def handle_event("clear_events", _params, socket) do
    {:noreply, assign(socket, activity_events: [], filtered_activity_events: [])}
  end

  def handle_event("simulate_test_event", _params, socket) do
    ping_id = System.unique_integer([:positive])

    payload = %{
      simulated: true,
      ping_id: ping_id,
      node: to_string(node()),
      timestamp: System.system_time(:millisecond)
    }

    EventDispatcher.broadcast(:studio_telemetry, payload)
    {:noreply, put_flash(socket, :info, "Simulated telemetry event ##{ping_id} broadcasted!")}
  end

  # ---- REAL-TIME EVENT STREAM FROM BEAM EventDispatcher ----

  @impl true
  def handle_info({:exo_event, event_key, payload, context}, socket) do
    ev_item = %{
      id: "ev_#{System.unique_integer([:positive])}",
      event: to_string(event_key),
      payload: payload,
      context: context,
      time: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    }

    new_events =
      if socket.assigns.events_paused do
        socket.assigns.activity_events
      else
        [ev_item | Enum.take(socket.assigns.activity_events, 99)]
      end

    filtered = filter_activity_events(new_events, socket.assigns.event_filter_topic)

    # If player lifecycle event, reload players
    ev_str = to_string(event_key)

    socket =
      if String.contains?(ev_str, "player_created") or String.contains?(ev_str, "player_deleted") do
        players = fetch_players()
        spent_display = compute_total_spent(players)
        assign(socket, players: players, filtered_players: players, total_spent_display: spent_display)
      else
        socket
      end

    {:noreply, assign(socket, activity_events: new_events, filtered_activity_events: filtered)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ---- PRIVATE HELPERS ----

  defp fetch_overview do
    plugins =
      try do
        :ets.tab2list(:exo_plugins_mem)
        |> Enum.map(fn {_id, m} ->
          %{
            id: to_string(m.id),
            name: to_string(m.name),
            version: to_string(m.version),
            type: to_string(m.type),
            provides: Enum.map(m.provides || [], &PluginRegistry.clean_service_name/1),
            dependencies: Enum.map(m.dependencies || [], &PluginRegistry.clean_service_name/1)
          }
        end)
      rescue
        _ -> []
      end

    extensions =
      try do
        PluginRegistry.dashboard_extensions()
      rescue
        _ -> []
      end

    resources =
      try do
        PluginRegistry.all_resources()
      rescue
        _ -> []
      end

    %{
      kernel: "BEAM (Exoforge)",
      plugins: plugins,
      plugins_count: length(plugins),
      extensions: extensions,
      resources: resources,
      resources_count: length(resources)
    }
  end

  defp fetch_players do
    case Exoforge.PluginRegistry.fetch_resource_rows(:players) do
      rows when is_list(rows) and rows != [] ->
        Enum.map(rows, fn r ->
          profile =
            case Map.get(r, "profile") || Map.get(r, :profile) do
              p when is_binary(p) -> (case Jason.decode(p) do {:ok, d} -> d; _ -> %{} end)
              p when is_map(p) -> p
              _ -> %{}
            end

          pid =
            Map.get(r, "player_id") ||
              Map.get(r, :player_id) ||
              Map.get(r, :id) ||
              Map.get(profile, "player_id") ||
              "p_1"

          %{
            id: to_string(pid),
            name: Map.get(profile, "name") || Map.get(r, "name") || Map.get(r, :name) || to_string(pid),
            email: Map.get(profile, "email") || Map.get(r, "email") || Map.get(r, :email) || "#{pid}@player.exoforge.io",
            status: Map.get(r, "state") || Map.get(r, :state) || Map.get(r, "status") || Map.get(r, :status) || "Active",
            total_spent: Map.get(profile, "total_spent") || "$0.00",
            time_in_game: Map.get(profile, "time_in_game") || "2h 45m",
            attributes: [
              %{key: "locale", value: "en_US"},
              %{key: "rank_tier", value: "Gold IV"}
            ]
          }
        end)

      _ ->
        default_sample_players()
    end
  end

  defp default_sample_players do
    [
      %{
        id: "p_1001",
        name: "ValkyrieOne",
        email: "valk@sanctumhaven.io",
        status: "Active",
        total_spent: "$149.50",
        time_in_game: "48h 12m",
        attributes: [
          %{key: "locale", value: "en_US"},
          %{key: "guild_id", value: "guild_alpha"},
          %{key: "vip_status", value: "true"}
        ]
      },
      %{
        id: "p_1002",
        name: "ShadowStrike",
        email: "shadow@sanctumhaven.io",
        status: "Active",
        total_spent: "$39.00",
        time_in_game: "14h 05m",
        attributes: [
          %{key: "locale", value: "en_GB"},
          %{key: "combat_rating", value: "1850"}
        ]
      },
      %{
        id: "p_1003",
        name: "ArchonPrime",
        email: "archon@sanctumhaven.io",
        status: "Suspended",
        total_spent: "$0.00",
        time_in_game: "1h 20m",
        attributes: [
          %{key: "sanction_reason", value: "speed_hack_detection"}
        ]
      }
    ]
  end

  defp default_cmd_results(socket) do
    nav_items = [
      %{id: "overview", title: "Go to Overview", subtitle: "System architecture and cluster health", type: "navigation"},
      %{id: "players", title: "Go to Players Directory", subtitle: "Profiles, inventories, and inspectors", type: "navigation"},
      %{id: "economy", title: "Go to Economy & Store", subtitle: "SKUs, currencies, and crates", type: "navigation"},
      %{id: "apps", title: "Go to Extension Drawer", subtitle: "Browse installed plugins", type: "navigation"}
    ]

    action_items = [
      %{id: "open_action_runner", title: "Action Runner: Dispatch Plugin Actions", subtitle: "Interactive form to execute backend RPCs", type: "action"},
      %{id: "toggle_event_dock", title: "Event Console: Live Cluster Event Stream", subtitle: "Real-time telemetry from :pg and EventDispatcher", type: "action"},
      %{id: "ping_auth", title: "Quick Action: Ping Auth Service", subtitle: "Verify session issuance", type: "action"},
      %{id: "simulate_combat", title: "Quick Action: Simulate Combat Attack", subtitle: "Invoke C# WASM sandbox", type: "action"},
      %{id: "create_sample_player", title: "Quick Action: Create Sample Player", subtitle: "Persist record to database", type: "action"}
    ]

    resource_items =
      Enum.map(socket.assigns.overview.resources, fn r ->
        res = r[:resource] || r["resource"] || %{}
        name = res[:name] || res["name"] || "resource"
        %{id: "res_#{name}", title: "Resource: #{name}", subtitle: "Primary Key: #{res[:primary_key] || res["primary_key"]}", type: "resource"}
      end)

    nav_items ++ action_items ++ resource_items
  end

  defp handle_quick_action(action, socket) do
    case action do
      "open_action_runner" ->
        {:noreply, assign(socket, action_modal_open: true, action_result: nil)}

      "toggle_event_dock" ->
        {:noreply, assign(socket, event_dock_open: !socket.assigns.event_dock_open)}

      "ping_auth" ->
        _ = ActionDispatcher.dispatch(:auth, :authenticate, %{token: "dev:admin"})
        {:noreply, put_flash(socket, :info, "Auth service responded successfully!")}

      "simulate_combat" ->
        _ = ActionDispatcher.dispatch(:combat, :attack, %{attacker_id: 1, target_id: 2, damage: 25})
        {:noreply, put_flash(socket, :info, "Simulated combat attack in C# WASM sandbox!")}

      "create_sample_player" ->
        pid = "p_#{System.unique_integer([:positive])}"
        _ = ActionDispatcher.dispatch(:player_data, :create_player, %{player_id: pid, profile: %{name: "Hero_#{pid}"}})
        players = fetch_players()
        spent_display = compute_total_spent(players)
        {:noreply, assign(socket, players: players, filtered_players: players, total_spent_display: spent_display) |> put_flash(:info, "Created player #{pid}!")}

      _ ->
        {:noreply, socket}
    end
  end

  defp compute_total_spent(players) do
    total =
      Enum.reduce(players, 0.0, fn p, acc ->
        spent_str = to_string(p[:total_spent] || p["total_spent"] || "0")
        cleaned = String.replace(spent_str, ~r/[^\d\.]/, "")

        case Float.parse(cleaned) do
          {val, _} -> acc + val
          :error -> acc
        end
      end)

    "$#{:erlang.float_to_binary(total, decimals: 2)}"
  end

  defp humanize_plugin_name(id) do
    case to_string(id) do
      "combat_wasm" -> "Combat Sandbox (C# WASM)"
      "exoforge_std_auth" -> "Authentication & Identity"
      "exoforge_std_player_data" -> "Player Profiles & State"
      "exoforge_std_database" -> "Multi-Tenant Storage Engine"
      "exoforge_std_ws" -> "Real-Time WebSocket Gateway"
      "exoforge_std_http" -> "REST Ingress Gateway"
      "exoforge_std_dashboard" -> "Game Producer Studio UI"
      "hello_world" -> "Hello World Plugin"
      other ->
        other
        |> String.replace_prefix("exoforge_std_", "")
        |> String.replace("_", " ")
        |> Macro.camelize()
    end
  end

  defp filter_activity_events(events, query) do
    q = String.downcase(String.trim(query || ""))

    if q == "" do
      events
    else
      Enum.filter(events, fn ev ->
        String.contains?(String.downcase(ev.event), q) or
          String.contains?(String.downcase(to_string(ev.id)), q) or
          (is_map(ev.payload) and String.contains?(String.downcase(Jason.encode!(ev.payload)), q))
      end)
    end
  end

  defp fetch_action_catalog do
    from_extensions =
      try do
        PluginRegistry.dashboard_extensions()
        |> Enum.flat_map(fn ext -> Map.get(ext, :services, []) end)
      rescue
        _ -> []
      end

    from_known =
      [
        Exoforge.Std.Services.Combat,
        Exoforge.Std.Services.Auth,
        Exoforge.Std.Services.PlayerData,
        Exoforge.Std.Services.Database,
        Exoforge.Std.Services.Lldb,
        Exoforge.Std.Services.Ws,
        Exoforge.Std.Services.Http
      ]
      |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__service_metadata__, 0)))
      |> Enum.map(& &1.__service_metadata__())

    (from_extensions ++ from_known)
    |> Enum.filter(fn svc ->
      actions = svc[:actions] || svc["actions"] || []
      is_list(actions) and actions != []
    end)
    |> Enum.map(fn svc ->
      name = PluginRegistry.clean_service_name(svc[:name] || svc["name"])
      actions = svc[:actions] || svc["actions"] || []

      %{
        name: name,
        actions:
          Enum.map(actions, fn act ->
            act_name = to_string(act[:name] || act["name"])
            doc = act[:doc] || act["doc"] || "No description provided."
            mode = to_string(act[:mode] || act["mode"] || "sync")
            raw_params = act[:params] || act["params"] || []
            params = normalize_action_params(raw_params)

            %{
              name: act_name,
              doc: doc,
              mode: mode,
              params: params
            }
          end)
      }
    end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_action_params(params) do
    cond do
      is_map(params) ->
        Enum.map(params, fn {k, v} ->
          type =
            case v do
              m when is_map(m) -> Map.get(m, :type) || Map.get(m, "type") || :string
              l when is_list(l) -> Keyword.get(l, :type, :string)
              atom when is_atom(atom) -> atom
              str when is_binary(str) -> String.to_atom(str)
              _ -> :string
            end

          %{name: to_string(k), type: type}
        end)

      is_list(params) and Keyword.keyword?(params) ->
        Enum.map(params, fn {k, v} ->
          type =
            case v do
              m when is_map(m) -> Map.get(m, :type) || Map.get(m, "type") || :string
              l when is_list(l) -> Keyword.get(l, :type, :string)
              atom when is_atom(atom) -> atom
              str when is_binary(str) -> String.to_atom(str)
              _ -> :string
            end

          %{name: to_string(k), type: type}
        end)

      is_list(params) ->
        Enum.map(params, fn
          {k, v} ->
            %{name: to_string(k), type: if(is_atom(v), do: v, else: :string)}

          item when is_map(item) ->
            name = Map.get(item, :name) || Map.get(item, "name") || "param"
            type = Map.get(item, :type) || Map.get(item, "type") || :string
            %{name: to_string(name), type: if(is_atom(type), do: type, else: String.to_atom(to_string(type)))}

          other ->
            %{name: to_string(other), type: :string}
        end)

      true ->
        []
    end
  end

  defp default_params_for(nil), do: %{}

  defp default_params_for(%{params: params}) do
    Enum.reduce(params, %{}, fn p, acc ->
      default_val =
        case p.type do
          :integer -> "1"
          :float -> "1.0"
          :boolean -> "true"
          :map -> "{}"
          _ -> ""
        end

      Map.put(acc, p.name, default_val)
    end)
  end

  defp cast_param_value(val_str, param_type) when is_binary(val_str) do
    case param_type do
      :integer ->
        case Integer.parse(String.trim(val_str)) do
          {int, _} -> int
          :error -> 0
        end

      :float ->
        case Float.parse(String.trim(val_str)) do
          {flt, _} -> flt
          :error -> 0.0
        end

      :boolean ->
        String.trim(String.downcase(val_str)) in ["true", "1", "yes"]

      :map ->
        case Jason.decode(val_str) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      _ ->
        val_str
    end
  end

  defp cast_param_value(val, _type), do: val

  # ---- TEMPLATE RENDER ----

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <!-- Exoforge Shell Header -->
      <header class="sticky top-0 z-40 bg-white/95 backdrop-blur border-b border-gray-200 px-4 lg:px-8 py-2.5 transition-shadow">
        <div class="max-w-7xl mx-auto flex items-center justify-between gap-4">
          <!-- Brand & Environment Switcher -->
          <div class="flex items-center gap-3 flex-shrink-0">
            <button
              phx-click="switch_tab"
              phx-value-tab="apps"
              class="w-10 h-10 rounded-xl bg-gradient-to-br from-primary-600 to-primary-700 hover:from-primary-500 hover:to-primary-600 text-white flex items-center justify-center transition-transform active:scale-95 shadow-md shadow-primary-300/50 p-1.5"
              title="Open Extension Drawer"
            >
              <svg viewBox="0 0 24 24" fill="none" class="w-6 h-6 text-white" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 2.5 L14.5 4.5 L9.5 4.5 Z" fill="currentColor" fill-opacity="0.9" stroke-width="0.8"/>
                <path d="M12 5.5 V18.5" stroke-width="2.2" stroke-linecap="square"/>
                <circle cx="12" cy="7.5" r="1.1" fill="currentColor"/>
                <circle cx="12" cy="11" r="1.1" fill="currentColor"/>
                <circle cx="12" cy="14.5" r="1.1" fill="currentColor"/>
                <path d="M7 6.5 L12 5.5 L17 6.5" stroke-width="1.8"/>
                <path d="M5.5 8.5 L7 6.5 L8.5 10" stroke-width="1.5"/>
                <path d="M18.5 8.5 L17 6.5 L15.5 10" stroke-width="1.5"/>
                <path d="M6 11.5 C7.8 9.8 10 10.5 12 11 C14 10.5 16.2 9.8 18 11.5" stroke-width="1.6"/>
                <path d="M6.8 15 C8.2 13.6 10.2 14.1 12 14.5 C13.8 14.1 15.8 13.6 17.2 15" stroke-width="1.5"/>
                <path d="M8.5 18.5 L12 17.5 L15.5 18.5" stroke-width="1.8"/>
                <path d="M7.5 21.5 L8.5 18.5 L10 21" stroke-width="1.6"/>
                <path d="M16.5 21.5 L15.5 18.5 L14 21" stroke-width="1.6"/>
              </svg>
            </button>
            <div>
              <div class="flex items-center gap-1.5 sm:gap-2">
                <span class="font-black text-gray-900 tracking-tight text-lg sm:text-xl flex items-center">
                  <span class="text-primary-600">EXO</span><span>FORGE</span>
                </span>
                <span class="hidden sm:inline-block text-[11px] font-semibold text-gray-400">/</span>
                <span class="text-xs font-bold text-gray-700 max-w-[140px] truncate"><%= @project_name %></span>
              </div>
              <div class="flex items-center gap-2">
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                </span>
                <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">
                  <%= @current_env %> • BEAM Live
                </span>
              </div>
            </div>
          </div>

          <!-- Top Navigation Bar -->
          <nav class="hidden md:flex items-center gap-1 bg-gray-100/80 p-1 rounded-xl border border-gray-200/60">
            <button
              phx-click="switch_tab"
              phx-value-tab="overview"
              class={"px-3 py-1.5 text-xs rounded-lg transition-all font-bold flex items-center gap-1.5 #{if @current_tab == :overview, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
              </svg>
              <span>Overview</span>
            </button>

            <button
              phx-click="switch_tab"
              phx-value-tab="players"
              class={"px-3 py-1.5 text-xs rounded-lg transition-all font-bold flex items-center gap-1.5 #{if @current_tab == :players, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              <span>Players</span>
            </button>

            <button
              phx-click="switch_tab"
              phx-value-tab="apps"
              class={"px-3 py-1.5 text-xs rounded-lg transition-all font-bold flex items-center gap-1.5 #{if @current_tab == :apps, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
              <span>Extensions</span>
              <span class="text-[10px] px-1.5 py-0.2 rounded-full bg-primary-100 text-primary-800 font-black">
                <%= @overview.plugins_count %>
              </span>
            </button>
          </nav>

          <!-- Right Toolbar: Action Runner, Event Stream, Cmd+K & Settings -->
          <div class="flex items-center gap-2">
            <!-- Event Stream Console Toggle -->
            <button
              phx-click="toggle_event_dock"
              class={"flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold transition-colors border #{if @event_dock_open, do: "bg-primary-50 text-primary-800 border-primary-200", else: "bg-gray-100 hover:bg-gray-200/80 text-gray-700 border-gray-200/60"}"}
              title="Toggle Live Cluster Event Stream Console"
            >
              <span class={"w-2 h-2 rounded-full #{if @events_paused, do: "bg-amber-400", else: "bg-emerald-500 animate-pulse"}"}></span>
              <span class="hidden sm:inline">Event Stream</span>
              <span class="px-1.5 py-0.2 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-black">
                <%= length(@activity_events) %>
              </span>
            </button>

            <!-- Action Runner Modal Trigger -->
            <button
              phx-click="open_action_modal"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition-all bg-primary-600 hover:bg-primary-700 text-white shadow-sm active:scale-95"
              title="Open Interactive Action Dispatcher Modal"
            >
              <span>⚡</span>
              <span class="hidden sm:inline">Action Runner</span>
            </button>

            <button
              phx-click="open_cmd_palette"
              class="hidden md:flex items-center gap-2 px-3 py-1.5 bg-gray-100 hover:bg-gray-200/80 text-gray-500 rounded-xl text-xs font-semibold transition-colors border border-gray-200/60"
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
              <span>Search...</span>
              <kbd class="px-1.5 py-0.5 bg-white rounded text-[10px] font-mono border text-gray-400">⌘K</kbd>
            </button>

            <button
              phx-click="open_settings"
              class="w-9 h-9 rounded-xl bg-gray-100 hover:bg-gray-200/80 text-gray-600 flex items-center justify-center transition-colors text-sm"
              title="Project Settings"
            >
              ⚙️
            </button>
          </div>
        </div>
      </header>

      <!-- Main Workspace Area -->
      <main class="flex-1 max-w-7xl w-full mx-auto p-4 sm:p-6 lg:p-8 space-y-8">
        <!-- Toast Notice -->
        <%= if Phoenix.Flash.get(@flash, :info) do %>
          <div class="p-3 bg-emerald-50 border border-emerald-200 text-emerald-800 rounded-xl text-xs font-bold flex items-center justify-between animate-fade-in">
            <span><%= Phoenix.Flash.get(@flash, :info) %></span>
          </div>
        <% end %>

        <%= if @current_tab == :overview do %>
          <!-- METRIC CARDS ROW -->
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <.metric_card
              title="Active Players (CCU)"
              value={to_string(length(@players))}
              delta="+8.4% today"
              delta_positive={true}
              subtitle="Peak CCU: 62.4k • 99.98% Live"
            />
            <.metric_card
              title="Economy & Gross LTV"
              value={@total_spent_display}
              delta="+14.2% vs yesterday"
              delta_positive={true}
              subtitle="Store purchases & currency velocity"
            />
            <.metric_card
              title="Active Game Services"
              value={"#{to_string(@overview.plugins_count)} Online"}
              delta="100% SLA"
              delta_positive={true}
              subtitle="Combat, Auth, Economy, PlayerData"
            />
            <.metric_card
              title="Gateway & Latency"
              value="0.8 ms"
              delta="Sub-millisecond"
              delta_positive={true}
              subtitle="Real-Time WebSocket & REST Ingress"
            />
          </div>

          <!-- EXTENSIONS & RECENT TELEMETRY ROW -->
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Installed Extensions List -->
            <div class="lg:col-span-2 bg-white p-6 rounded-2xl border border-gray-200 shadow-card space-y-4">
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="font-bold text-gray-900 text-sm">Live Game Features & Capability Modules</h3>
                  <p class="text-xs text-gray-400 mt-0.5">Active services powering gameplay, combat, economy, and liveops</p>
                </div>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="apps"
                  class="text-xs font-bold text-primary-600 hover:text-primary-700"
                >
                  View All &rarr;
                </button>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <%= for ext <- @overview.plugins do %>
                  <div class="p-3.5 rounded-xl border border-gray-100 hover:border-primary-200 bg-gray-50/50 hover:bg-white transition-all space-y-2">
                    <div class="flex items-center justify-between">
                      <div>
                        <span class="text-xs font-bold text-gray-800"><%= humanize_plugin_name(ext.id) %></span>
                        <span class="block text-[10px] text-gray-400 font-mono"><%= ext.id %></span>
                      </div>
                      <.badge status={ext.type} />
                    </div>
                    <p class="text-[11px] text-gray-500">
                      Provides: <code class="text-primary-700 font-semibold"><%= Enum.join(ext.provides, ", ") %></code>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Live Event Stream Feed -->
            <div class="bg-white p-6 rounded-2xl border border-gray-200 shadow-card space-y-4">
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="font-bold text-gray-900 text-sm">Real-Time Event Stream</h3>
                  <p class="text-xs text-gray-400 mt-0.5">Pushed directly via EventDispatcher</p>
                </div>
                <button
                  type="button"
                  phx-click="toggle_event_dock"
                  class="text-xs font-bold text-primary-600 hover:text-primary-700 flex items-center gap-1.5 transition-colors"
                >
                  <span class={"w-2 h-2 rounded-full #{if @events_paused, do: "bg-amber-400", else: "bg-emerald-500 animate-pulse"}"}></span>
                  <span>Open Console &rarr;</span>
                </button>
              </div>

              <div class="space-y-2 max-h-80 overflow-y-auto custom-scrollbar">
                <%= for ev <- @activity_events do %>
                  <div class="p-2.5 bg-gray-50/70 border border-gray-100 rounded-xl text-xs space-y-1">
                    <div class="flex items-center justify-between">
                      <span class="font-mono font-bold text-primary-700"><%= ev.event %></span>
                      <span class="text-[10px] text-gray-400"><%= ev.time %></span>
                    </div>
                    <pre class="text-[10px] text-gray-600 font-mono overflow-x-auto"><%= Jason.encode!(ev.payload) %></pre>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @current_tab == :players do %>
          <!-- PLAYERS DIRECTORY VIEW -->
          <div class="space-y-4">
            <div class="bg-white p-4 rounded-2xl border border-gray-200 shadow-card flex flex-col sm:flex-row items-center justify-between gap-3">
              <div>
                <h3 class="font-bold text-gray-900 text-sm">Player Directory & Profile Management</h3>
                <p class="text-xs text-gray-400 mt-0.5">Click any player to inspect attributes, inventory, and ledger history</p>
              </div>

              <form id="player_filter_form" phx-change="filter_players" class="flex items-center gap-2 w-full sm:w-auto">
                <input
                  type="text"
                  name="query"
                  value={@player_search}
                  placeholder="Search player ID, name, email..."
                  class="px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-xl text-xs text-gray-800 focus:outline-none focus:border-primary-500 w-full sm:w-64"
                />
                <select
                  name="status"
                  class="px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-xl text-xs text-gray-800 focus:outline-none"
                >
                  <option value="all">All Statuses</option>
                  <option value="Active">Active</option>
                  <option value="Suspended">Suspended</option>
                </select>
                <button
                  type="button"
                  phx-click="quick_action"
                  phx-value-action="create_sample_player"
                  class="px-3 py-1.5 bg-primary-600 hover:bg-primary-700 text-white rounded-xl text-xs font-bold shadow-sm whitespace-nowrap"
                >
                  + New Player
                </button>
              </form>
            </div>

            <!-- Players Data Table -->
            <.data_table
              id="players_table"
              rows={@filtered_players}
              columns={[
                %{key: :id, label: "Player ID", type: :code},
                %{key: :name, label: "Display Name"},
                %{key: :email, label: "Email Address"},
                %{key: :status, label: "Account Standing", type: :badge},
                %{key: :total_spent, label: "Lifetime LTV"},
                %{key: :time_in_game, label: "Time in Game"}
              ]}
              row_click_event="inspect_player"
              empty_text="No players match the current search filters."
            />
          </div>
        <% end %>

        <%= if @current_tab == :apps do %>
          <!-- EXTENSION APPS DRAWER VIEW -->
          <div class="space-y-6">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-lg font-bold text-gray-900">Game Feature &amp; Capability Registry</h3>
                <p class="text-xs text-gray-500">Modular capability plugins and live game services</p>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for plugin <- @overview.plugins do %>
                <div class="bg-white p-5 rounded-2xl border border-gray-200 hover:border-primary-300 shadow-card hover:shadow-md transition-all flex flex-col justify-between space-y-4">
                  <div class="space-y-2">
                    <div class="flex items-center justify-between">
                      <span class="font-bold text-gray-900 text-sm"><%= humanize_plugin_name(plugin.name) %></span>
                      <.badge status={plugin.type} />
                    </div>
                    <p class="text-xs text-gray-500">
                      Version: <span class="font-mono text-gray-700"><%= plugin.version %></span>
                    </p>
                    <div class="space-y-1">
                      <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Provides Services:</span>
                      <div class="flex flex-wrap gap-1">
                        <%= for s <- plugin.provides do %>
                          <span class="px-2 py-0.5 rounded-md bg-primary-50 text-primary-700 text-[10px] font-mono font-semibold">
                            <%= s %>
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <div class="pt-3 border-t border-gray-100 flex items-center justify-between text-xs">
                    <span class="text-gray-400">Dependency Order: OK</span>
                    <button
                      type="button"
                      phx-click="open_action_modal"
                      phx-value-service={List.first(plugin.provides)}
                      class="text-primary-600 hover:text-primary-700 font-bold flex items-center gap-1 transition-colors"
                    >
                      <span>⚡ Run Action &rarr;</span>
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </main>

      <!-- Side Inspector Slide-Over Drawer -->
      <.side_drawer
        open={@drawer_open}
        title={if @inspected_player, do: "Player Profile: #{@inspected_player.name}", else: "Entity Inspector"}
        subtitle={if @inspected_player, do: "ID: #{@inspected_player.id} • Status: #{@inspected_player.status}", else: ""}
        tabs={@drawer_tabs}
        active_tab={@inspected_tab}
        on_close="close_drawer"
        on_select_tab="select_drawer_tab"
      >
        <%= if @inspected_player do %>
          <%= if @inspected_tab == "overview" do %>
            <div class="space-y-4">
              <div class="grid grid-cols-2 gap-3">
                <div class="p-3 bg-gray-50 rounded-xl border border-gray-100">
                  <span class="text-[10px] font-bold text-gray-400 uppercase">Lifetime Spent</span>
                  <p class="text-lg font-black text-gray-900"><%= @inspected_player.total_spent %></p>
                </div>
                <div class="p-3 bg-gray-50 rounded-xl border border-gray-100">
                  <span class="text-[10px] font-bold text-gray-400 uppercase">Time In Game</span>
                  <p class="text-lg font-black text-gray-900"><%= @inspected_player.time_in_game %></p>
                </div>
              </div>
              <div class="p-4 border border-gray-100 rounded-xl space-y-2">
                <h4 class="text-xs font-bold text-gray-700 uppercase">Account Information</h4>
                <div class="text-xs space-y-1 text-gray-600">
                  <p><strong>Primary ID:</strong> <code class="font-mono text-primary-700"><%= @inspected_player.id %></code></p>
                  <p><strong>Email:</strong> <%= @inspected_player.email %></p>
                  <p><strong>Standing:</strong> <.badge status={@inspected_player.status} /></p>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @inspected_tab == "attributes" do %>
            <.attribute_editor
              attributes={@inspected_player.attributes || []}
              on_add="add_attribute"
              on_delete="delete_attribute"
            />
          <% end %>

          <%= if @inspected_tab not in ["overview", "attributes"] do %>
            <div class="p-8 text-center bg-gray-50 rounded-2xl border border-gray-200/60 text-xs text-gray-500 space-y-2">
              <p class="font-bold text-gray-800">Dynamic Sub-Panel: <%= String.capitalize(@inspected_tab) %></p>
              <p class="text-gray-400">Connected to multi-tenant schema partition via DrawerRegistry.</p>
            </div>
          <% end %>
        <% end %>
      </.side_drawer>

      <!-- Command Palette Modal (Cmd+K) -->
      <.command_palette
        open={@cmd_palette_open}
        query={@cmd_query}
        results={@cmd_results}
        on_close="close_cmd_palette"
        on_search="search_cmd_palette"
        on_select="select_cmd_item"
      />

      <!-- Global Project Settings Modal -->
      <.modal
        id="project_settings_modal"
        open={@settings_open}
        title="Project Settings & Topology"
        subtitle="Sanctum Haven cluster configuration"
        on_close="close_settings"
      >
        <div class="space-y-4 text-xs">
          <div class="flex gap-2 border-b pb-2">
            <button
              phx-click="set_settings_tab"
              phx-value-tab="project"
              class={"px-3 py-1 rounded-lg font-bold #{if @settings_tab == "project", do: "bg-primary-50 text-primary-700", else: "text-gray-500"}"}
            >
              Metadata
            </button>
            <button
              phx-click="set_settings_tab"
              phx-value-tab="environments"
              class={"px-3 py-1 rounded-lg font-bold #{if @settings_tab == "environments", do: "bg-primary-50 text-primary-700", else: "text-gray-500"}"}
            >
              Environments
            </button>
            <button
              phx-click="set_settings_tab"
              phx-value-tab="database"
              class={"px-3 py-1 rounded-lg font-bold #{if @settings_tab == "database", do: "bg-primary-50 text-primary-700", else: "text-gray-500"}"}
            >
              Database
            </button>
          </div>

          <%= if @settings_tab == "project" do %>
            <div class="space-y-2">
              <label class="block font-bold text-gray-700">Studio Name</label>
              <input type="text" value={@studio_name} readonly class="w-full px-3 py-1.5 bg-gray-50 border rounded-lg" />
              <label class="block font-bold text-gray-700">Project Title</label>
              <input type="text" value={@project_name} readonly class="w-full px-3 py-1.5 bg-gray-50 border rounded-lg" />
            </div>
          <% end %>

          <%= if @settings_tab == "environments" do %>
            <div class="space-y-2">
              <p class="text-gray-500">Active Node Environment:</p>
              <div class="flex gap-2">
                <%= for env <- @environments do %>
                  <button
                    phx-click="switch_env"
                    phx-value-env={env}
                    class={"px-3 py-1.5 rounded-xl font-bold border #{if @current_env == env, do: "bg-emerald-50 text-emerald-700 border-emerald-200", else: "bg-gray-50 text-gray-600"}"}
                  >
                    <%= env %>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @settings_tab == "database" do %>
            <div class="p-3 bg-gray-50 border rounded-xl space-y-1">
              <p><strong>Storage Engine:</strong> Sandbox & PostgreSQL Isolated Tenants</p>
              <p><strong>Multi-Tenancy Status:</strong> Operational</p>
            </div>
          <% end %>
        </div>
      </.modal>

      <!-- Action Execution Modal (M13.3) -->
      <.action_runner_modal
        open={@action_modal_open}
        catalog={@action_catalog}
        selected_service={@selected_action_service}
        selected_action={@selected_action_name}
        action_params={@action_form_params}
        caller_scopes={@caller_scopes}
        result={@action_result}
        latency_ms={@action_latency_ms}
        on_close="close_action_modal"
        on_select_service="select_action_service"
        on_select_action="select_action_name"
        on_change_form="change_action_form"
        on_dispatch="dispatch_action"
      />

      <!-- Live Cluster Event Stream Dock (M13.4) -->
      <.event_stream_dock
        open={@event_dock_open}
        events={@filtered_activity_events}
        paused={@events_paused}
        filter_topic={@event_filter_topic}
        on_toggle="toggle_event_dock"
        on_pause="toggle_event_pause"
        on_clear="clear_events"
        on_filter="filter_event_dock"
        on_simulate="simulate_test_event"
      />
    </div>
    """
  end
end
