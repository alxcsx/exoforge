defmodule Exoforge.Std.Dashboard.StudioLive do
  @moduledoc """
  Phoenix LiveView for the Exoforge Game Producer & Designer Studio.
  Fully reactive, server-driven UI decoupled from hardcoded domain elements.
  Extensions provide capabilities and domain visualizations dynamically.
  """
  use Phoenix.LiveView
  require Logger
  import Exoforge.Std.Dashboard.Overlays
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.Std.Dashboard.ActionForms
  alias Exoforge.Std.Dashboard.ExtensionPresenter

  @max_pinned 8

  @impl true
  def mount(params, session, socket) do
    logged_out? = session["logged_out"] == true or params["logged_out"] == "true"

    session_pid =
      session["admin_user_id"] || session["admin_player_id"] || session[:admin_player_id]

    session_token = session["auth_token"]

    authenticated? =
      not logged_out? and
        ((is_binary(session_pid) and session_pid != "") or
           (is_binary(session_token) and session_token != ""))

    {player_id, user_name, user_role, auth_token} =
      if authenticated? do
        pid = session_pid || "studio"

        uname =
          session["user_name"] || session["admin_name"] ||
            if pid == "studio", do: "Studio Producer", else: pid

        urole = session["user_role"] || session["admin_role"] || "Admin"
        {pid, uname, urole, session_token}
      else
        {"guest", "Guest", "Guest", nil}
      end

    if connected?(socket) do
      Logger.info("[StudioLive] Connected session for #{player_id}")

      # The Studio dock is for studio/system traffic, not the game's event stream (M33 Fix 32):
      # subscribing to everything piped every gameplay tick into every open Studio window.
      try do
        EventDispatcher.subscribe(:all, topic: "studio")
      rescue
        _ -> :ok
      end
    end

    overview = fetch_overview()
    action_catalog = ActionForms.catalog()

    # Discover extensions that declare a dashboard visualization or visual controls
    visualizable_extensions =
      Enum.filter(overview.extensions, fn ext ->
        ext.has_dashboard_view == true or ext.has_visual_controls == true or
          ext.dashboard_view != nil
      end)

    initial_events = [
      %{
        id: "ev_boot_1",
        event: "kernel:ready",
        payload: %{node: to_string(node()), plugins: overview.plugins_count},
        time: "Just now"
      }
    ]

    default_service = List.first(action_catalog)
    default_service_name = if default_service, do: default_service.name, else: nil
    default_action = if default_service, do: List.first(default_service.actions), else: nil
    default_action_name = if default_action, do: default_action.name, else: nil
    default_params = ActionForms.default_params(default_action)

    {:ok,
     assign(socket,
       current_tab: :overview,
       focus: nil,
       project_name: "Exoforge Cluster",
       studio_name: "Exoforge Dashboard",
       environments: ["Live", "Dev", "Staging"],
       current_env: "Live",
       max_pinned: @max_pinned,
       overview: overview,
       build_version: overview[:version] || Exoforge.BuildInfo.version(),
       build_hash: overview[:commit_hash] || Exoforge.BuildInfo.commit_hash(),
       build_date: overview[:build_date] || Exoforge.BuildInfo.build_date(),
       player_id: player_id,
       user_id: player_id,
       authenticated: authenticated?,
       login_open: not authenticated? and params["login"] == "true",
       pinned_menu_open: false,
       user_name: user_name,
       user_role: user_role,
       auth_token: auth_token,
       pinned_extensions: Exoforge.Std.Dashboard.Preferences.pinned(player_id),
       overview_grid_order: Exoforge.Std.Dashboard.Preferences.overview_order(player_id),
       sdk_modal_open: false,
       visualizable_extensions: visualizable_extensions,
       cmd_palette_open: false,
       cmd_query: "",
       cmd_results: [],
       settings_open: false,
       settings_tab: "project",
       settings_hooks: Exoforge.UIHookRegistry.list_hooks(:settings),
       inspecting_extension: nil,
       app_drawer_open: false,
       activity_events: initial_events,
       filtered_activity_events: initial_events,
       quick_toast: nil,
       action_catalog: action_catalog,
       selected_action_service: default_service_name,
       selected_action_name: default_action_name,
       action_form_params: default_params,
       # The verified scopes the session signed in with (M33 Fix 27): what the console may
       # dispatch is decided by the session, never by a form field.
       current_scopes: session["admin_scopes"] || [],
       action_modal_open: false,
       action_result: nil,
       action_latency_ms: nil,
       event_dock_open: false,
       events_paused: false,
       event_filter_topic: "",
       extensions_search: "",
       extensions_category: "all",
       cors_config: fetch_cors_config()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab_param = params["tab"]
    live_action = socket.assigns[:live_action]
    extensions = socket.assigns.overview.extensions

    tab =
      cond do
        live_action == :apps or tab_param in ["apps", "extensions"] ->
          :apps

        (live_action == :index or is_nil(live_action)) and tab_param in ["overview", nil, ""] ->
          :overview

        true ->
          resolve_tab(tab_param, extensions)
      end

    focus = parse_focus(params["focus"])

    socket =
      socket
      |> assign(:current_tab, tab)
      |> assign(:focus, focus)
      |> assign(:inspecting_extension, focused_extension(focus, extensions))
      |> assign(:pinned_menu_open, false)
      |> maybe_refresh_tab_data(tab)

    {:noreply, socket}
  end

  defp resolve_tab(nil, _extensions), do: :overview
  defp resolve_tab("", _extensions), do: :overview
  defp resolve_tab("overview", _extensions), do: :overview
  defp resolve_tab(:overview, _extensions), do: :overview
  defp resolve_tab("apps", _extensions), do: :apps
  defp resolve_tab(:apps, _extensions), do: :apps
  defp resolve_tab("extensions", _extensions), do: :apps

  defp resolve_tab(param, extensions) do
    str = to_string(param)
    clean = String.replace_prefix(str, "exoforge_std_", "")

    match =
      Enum.find(extensions, fn e ->
        e_id_str = to_string(e.id)
        dv_id = if is_map(e.dashboard_view), do: to_string(e.dashboard_view[:id]), else: nil

        e_id_str == str or
          e_id_str == "exoforge_std_#{clean}" or
          dv_id == str or
          dv_id == clean
      end)

    case match do
      %{id: ext_id} ->
        ext_id

      nil ->
        Exoforge.Atoms.existing(str, str)
    end
  end

  # Deep links carry `?focus=<kind>:<id>` (e.g. `focus=user:player_1`); each tab view decides
  # whether it understands that kind. Absent or malformed focus is simply nil.
  defp parse_focus(nil), do: nil
  defp parse_focus(""), do: nil

  defp parse_focus(raw) when is_binary(raw) do
    case String.split(raw, ":", parts: 2) do
      [kind, id] when kind != "" and id != "" -> %{kind: kind, id: id}
      _ -> nil
    end
  end

  defp focused_extension(%{kind: "ext", id: id}, extensions) do
    Enum.find(extensions, &(to_string(&1.id) == to_string(id)))
  end

  defp focused_extension(_focus, _extensions), do: nil

  # Every popup is a URL, so the browser back button closes it. `focus_url/3` opens one;
  # `tab_path/1` (no focus) is how they close.
  defp focus_url(tab, kind, id) do
    "#{tab_path(tab)}?focus=#{kind}:#{URI.encode_www_form(to_string(id))}"
  end

  defp maybe_refresh_tab_data(socket, _other), do: socket

  defp tab_path("overview"), do: "/"
  defp tab_path(:overview), do: "/"
  defp tab_path("apps"), do: "/tab/apps"
  defp tab_path(:apps), do: "/tab/apps"

  defp tab_path(tab) when is_atom(tab) or is_binary(tab) do
    "/tab/#{tab}"
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("switch_tab", %{"tab" => tab_str}, socket) do
    target_tab = resolve_tab(tab_str, socket.assigns.overview.extensions)
    {:noreply, push_patch(socket, to: tab_path(target_tab))}
  end

  def handle_event("switch_env", %{"env" => env}, socket) do
    {:noreply,
     socket
     |> assign(:current_env, env)
     |> show_toast(:info, "Switched active environment to #{env}")}
  end

  def handle_event("pin_extension", %{"id" => ext_id_str}, socket) do
    pinned = socket.assigns.pinned_extensions

    if ext_id_str in pinned do
      {:noreply, socket}
    else
      if length(pinned) >= @max_pinned do
        {:noreply,
         show_toast(
           socket,
           :error,
           "Maximum of #{@max_pinned} pinned extensions reached. Unpin an extension to pin another."
         )}
      else
        new_pinned = pinned ++ [ext_id_str]
        Exoforge.Std.Dashboard.Preferences.put_pinned(socket.assigns.player_id, new_pinned)

        {:noreply,
         socket
         |> assign(pinned_extensions: new_pinned)
         |> show_toast(:info, "Pinned #{ext_id_str} to top navigation bar.")}
      end
    end
  end

  def handle_event("unpin_extension", %{"id" => ext_id_str}, socket) do
    new_pinned = List.delete(socket.assigns.pinned_extensions, ext_id_str)
    Exoforge.Std.Dashboard.Preferences.put_pinned(socket.assigns.player_id, new_pinned)
    socket = assign(socket, pinned_extensions: new_pinned)

    if to_string(socket.assigns.current_tab) == ext_id_str do
      {:noreply,
       socket
       |> show_toast(:info, "Unpinned #{ext_id_str} from top bar.")
       |> push_patch(to: "/")}
    else
      {:noreply, show_toast(socket, :info, "Unpinned #{ext_id_str} from top bar.")}
    end
  end

  def handle_event("dismiss_toast", %{"kind" => kind}, socket) when kind in ["info", "error"] do
    {:noreply, clear_flash(socket, Exoforge.Atoms.existing(kind))}
  end

  def handle_event("search_extensions", %{"query" => query}, socket) do
    {:noreply, assign(socket, :extensions_search, query)}
  end

  def handle_event("filter_extension_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, :extensions_category, category)}
  end

  def handle_event("handle_key", %{"key" => key} = params, socket) do
    is_cmd_k =
      String.downcase(key) == "k" and
        (Map.get(params, "metaKey") == true or Map.get(params, "ctrlKey") == true)

    cond do
      is_cmd_k ->
        new_open = !socket.assigns.cmd_palette_open
        results = if new_open, do: default_cmd_results(socket), else: []

        {:noreply, assign(socket, cmd_palette_open: new_open, cmd_query: "", cmd_results: results)}

      key in ["Escape", "Esc"] ->
        {:noreply,
         assign(socket,
           cmd_palette_open: false,
           settings_open: false,
           sdk_modal_open: false,
           action_modal_open: false,
           app_drawer_open: false
         )}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("handle_key", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("open_cmd_palette", _params, socket) do
    {:noreply,
     assign(socket,
       cmd_palette_open: true,
       cmd_query: "",
       cmd_results: default_cmd_results(socket)
     )}
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
        target =
          resolve_tab(id, socket.assigns.overview.extensions)

        {:noreply, push_patch(socket, to: tab_path(target))}

      "action" ->
        case String.split(id, ":", parts: 2) do
          ["rpc", target] ->
            case String.split(target, ".", parts: 2) do
              [svc, act] ->
                {:noreply,
                 assign(socket,
                   action_modal_open: true,
                   selected_action_service: svc,
                   selected_action_name: act,
                   action_result: nil
                 )}

              _ ->
                {:noreply, assign(socket, action_modal_open: true, action_result: nil)}
            end

          _ ->
            handle_quick_action(id, socket)
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_login_modal", _params, socket) do
    {:noreply, assign(socket, login_open: true)}
  end

  def handle_event("close_login_modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(login_open: false)}
  end

  def handle_event("toggle_pinned_menu", _params, socket) do
    {:noreply, assign(socket, pinned_menu_open: not socket.assigns.pinned_menu_open)}
  end

  def handle_event("open_settings", _params, socket) do
    hooks = Exoforge.UIHookRegistry.list_hooks(:settings)
    cors = fetch_cors_config()
    {:noreply, assign(socket, settings_open: true, settings_hooks: hooks, cors_config: cors)}
  end

  def handle_event("change_cors_settings", params, socket) do
    current = socket.assigns.cors_config || %{}
    mode = Map.get(params, "mode") || Map.get(current, "mode", "relaxed")
    origins = Map.get(params, "allowed_origins") || Map.get(current, "allowed_origins", "*")

    allow_creds =
      if Map.has_key?(params, "allow_credentials") do
        Map.get(params, "allow_credentials") in [true, "true", "on", "1"]
      else
        false
      end

    updated =
      current
      |> Map.put("mode", mode)
      |> Map.put("allowed_origins", origins)
      |> Map.put("allow_credentials", allow_creds)

    {:noreply, assign(socket, cors_config: updated)}
  end

  def handle_event("save_cors_settings", params, socket) do
    allow_creds = Map.get(params, "allow_credentials") in [true, "true", "on", "1"]
    clean_params = Map.put(params, "allow_credentials", allow_creds)

    case ActionDispatcher.dispatch(:http, :set_cors_config, clean_params, caller_scopes: socket.assigns.current_scopes) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(cors_config: updated)
         |> show_toast(:info, "✓ CORS policy updated and applied to HTTP ingress.")}

      {:error, reason} ->
        {:noreply, show_toast(socket, :error, "Failed to update CORS policy: #{inspect(reason)}")}
    end
  end

  def handle_event("open_sdk_modal", _params, socket) do
    {:noreply, assign(socket, :sdk_modal_open, true)}
  end

  def handle_event("close_sdk_modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(:sdk_modal_open, false)}
  end

  def handle_event("move_overview_slot", %{"id" => slot_id, "dir" => dir}, socket) do
    widgets = Exoforge.UIHookRegistry.list_hooks(:overview_widget)
    current_ids = resolve_overview_slot_ids(widgets, socket.assigns.overview_grid_order)
    idx = Enum.find_index(current_ids, &(&1 == slot_id))

    target_idx =
      cond do
        is_nil(idx) -> nil
        dir in ["prev", "left", "up"] and idx > 0 -> idx - 1
        dir in ["next", "right", "down"] and idx < length(current_ids) - 1 -> idx + 1
        true -> nil
      end

    if target_idx do
      other_id = Enum.at(current_ids, target_idx)

      new_order =
        current_ids
        |> List.replace_at(idx, other_id)
        |> List.replace_at(target_idx, slot_id)

      Exoforge.Std.Dashboard.Preferences.put_overview_order(socket.assigns.player_id, new_order)
      {:noreply, assign(socket, :overview_grid_order, new_order)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder_overview_grid", %{"order" => order}, socket) when is_list(order) do
    clean_order = Enum.map(order, &to_string/1)
    Exoforge.Std.Dashboard.Preferences.put_overview_order(socket.assigns.player_id, clean_order)
    {:noreply, assign(socket, :overview_grid_order, clean_order)}
  end

  def handle_event("reset_overview_grid", _params, socket) do
    Exoforge.Std.Dashboard.Preferences.put_overview_order(socket.assigns.player_id, [])
    {:noreply, assign(socket, :overview_grid_order, [])}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(:settings_open, false)}
  end

  def handle_event("set_settings_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :settings_tab, tab)}
  end

  def handle_event("inspect_extension", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: focus_url(socket.assigns.current_tab, "ext", id))}
  end

  def handle_event("close_inspect_extension", _params, socket) do
    {:noreply,
     socket
     |> assign(:inspecting_extension, nil)
     |> assign(:focus, nil)
     |> push_patch(to: tab_path(socket.assigns.current_tab))}
  end

  # Generic popup navigation: any view can open a drawer by bubbling `open_focus` with a
  # kind/id, and close it by bubbling `close_focus`.
  def handle_event("open_focus", %{"kind" => kind, "id" => id}, socket) do
    {:noreply, push_patch(socket, to: focus_url(socket.assigns.current_tab, kind, id))}
  end

  def handle_event("close_focus", _params, socket) do
    {:noreply,
     socket
     |> assign(:focus, nil)
     |> assign(:inspecting_extension, nil)
     |> push_patch(to: tab_path(socket.assigns.current_tab))}
  end

  def handle_event("quick_action", %{"action" => action}, socket) do
    handle_quick_action(action, socket)
  end

  # ---- ACTION EXECUTION MODAL ----

  def handle_event("open_action_modal", params, socket) do
    svc_name = Map.get(params, "service") || socket.assigns.selected_action_service
    act_name = Map.get(params, "action")

    svc = ActionForms.service(socket.assigns.action_catalog, svc_name)
    act = ActionForms.action(svc, act_name)

    selected_svc_name = if svc, do: svc.name, else: nil
    selected_act_name = if act, do: act.name, else: nil
    initial_params = ActionForms.default_params(act)

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
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(action_modal_open: false, action_result: nil)}
  end

  def handle_event("select_action_service", %{"service" => svc_name}, socket) do
    svc = ActionForms.service(socket.assigns.action_catalog, svc_name)
    first_act = ActionForms.action(svc, nil)
    first_act_name = if first_act, do: first_act.name, else: nil
    initial_params = ActionForms.default_params(first_act)

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
    svc = ActionForms.service(socket.assigns.action_catalog, socket.assigns.selected_action_service)
    act = ActionForms.action(svc, act_name)
    initial_params = ActionForms.default_params(act)

    {:noreply,
     assign(socket,
       selected_action_name: act_name,
       action_form_params: initial_params,
       action_result: nil,
       action_latency_ms: nil
     )}
  end

  def handle_event("change_action_form", params, socket) do
    updated_params =
      Enum.reduce(params, socket.assigns.action_form_params, fn
        {"param_" <> name, val}, acc -> Map.put(acc, name, val)
        _other, acc -> acc
      end)

    {:noreply, assign(socket, action_form_params: updated_params)}
  end

  def handle_event("dispatch_action", params, socket) do
    updated_params =
      Enum.reduce(params, socket.assigns.action_form_params, fn
        {"param_" <> name, val}, acc -> Map.put(acc, name, val)
        _other, acc -> acc
      end)

    svc = ActionForms.service(socket.assigns.action_catalog, socket.assigns.selected_action_service)
    act = ActionForms.action(svc, socket.assigns.selected_action_name)

    if svc && act do
      payload = ActionForms.build_payload(act, updated_params)
      # The session's verified scopes (M33 Fix 27): a form field cannot claim `admin` or `server`.
      scopes = socket.assigns.current_scopes

      start_time = System.monotonic_time(:microsecond)

      result =
        try do
          ActionDispatcher.dispatch(svc.name, act.name, payload, caller_scopes: scopes)
        rescue
          e -> {:error, Exception.message(e)}
        catch
          :exit, reason -> {:error, inspect(reason)}
        end

      duration_us = System.monotonic_time(:microsecond) - start_time
      latency_ms = Float.round(duration_us / 1000, 2)

      {:noreply,
       assign(socket,
         action_result: result,
         action_latency_ms: latency_ms,
         action_form_params: updated_params
       )}
    else
      {:noreply, show_toast(socket, :error, "Selected service or action not found.")}
    end
  end

  def handle_event("studio_dispatch", %{"service" => service, "action" => action} = params, socket) do
    payload = Map.get(params, "payload") || %{}
    scopes = socket.assigns.current_scopes

    result =
      case ActionDispatcher.dispatch(service, action, payload, caller_scopes: scopes) do
        {:ok, data} -> %{"status" => "ok", "data" => data}
        :ok -> %{"status" => "ok"}
        {:error, reason} -> %{"status" => "error", "error" => inspect(reason)}
      end

    {:reply, result, socket}
  end

  # ---- LIVE CLUSTER EVENT STREAM DOCK ----

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

    EventDispatcher.broadcast(:studio_telemetry, payload, topic: "studio")
    {:noreply, show_toast(socket, :info, "Simulated telemetry event ##{ping_id} broadcasted!")}
  end

  defp fetch_cors_config do
    case ActionDispatcher.dispatch(:http, :get_cors_config, %{}) do
      {:ok, cfg} when is_map(cfg) -> cfg
      _ -> %{"mode" => "relaxed", "allowed_origins" => "*", "allow_credentials" => true}
    end
  rescue
    _ -> %{"mode" => "relaxed", "allowed_origins" => "*", "allow_credentials" => true}
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

    {:noreply, assign(socket, activity_events: new_events, filtered_activity_events: filtered)}
  end

  def handle_info({:clear_toast, kind}, socket) do
    {:noreply, clear_flash(socket, kind)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ---- PRIVATE HELPERS ----

  # Shows a flash and schedules its automatic dismissal, so notices behave like
  # a real toast instead of lingering until the next interaction.
  defp show_toast(socket, kind, message) do
    Process.send_after(self(), {:clear_toast, kind}, 4_000)
    put_flash(socket, kind, message)
  end

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
            status: Map.get(m, :status, :online),
            restarts: Map.get(m, :restarts, 0),
            infinite_loop: Map.get(m, :infinite_loop, false),
            crashed_recently: Map.get(m, :crashed_recently, false),
            provides: Enum.map(m.provides || [], &PluginRegistry.service_alias_or_module/1),
            dependencies: Enum.map(m.dependencies || [], &PluginRegistry.service_alias_or_module/1)
          }
        end)
      rescue
        _ -> []
      end

    raw_extensions =
      try do
        Exoforge.Std.Dashboard.Extensions.dashboard_extensions()
      rescue
        _ -> []
      end

    extensions =
      Enum.map(raw_extensions, fn ext ->
        view_mod = ExtensionPresenter.view_module(ext)

        ext
        |> Map.put(:custom_view_module, view_mod)
        |> Map.put(:has_custom_view, view_mod != nil)
      end)

    resources =
      try do
        PluginRegistry.all_resources()
      rescue
        _ -> []
      end

    %{
      kernel: "Exoforge Core",
      version: Exoforge.BuildInfo.version(),
      commit_hash: Exoforge.BuildInfo.commit_hash(),
      build_date: Exoforge.BuildInfo.build_date(),
      plugins: plugins,
      plugins_count: length(plugins),
      extensions: extensions,
      resources: resources,
      resources_count: length(resources)
    }
  end

  defp default_cmd_results(socket) do
    # 1. Pinned Navigation items
    pinned_navs =
      Enum.map(socket.assigns.pinned_extensions, fn ext_id ->
        ext = Enum.find(socket.assigns.overview.extensions, fn e -> to_string(e.id) == ext_id end)

        title =
          if ext && is_map(ext.dashboard_view) && ext.dashboard_view[:title],
            do: ext.dashboard_view[:title],
            else: if(ext, do: humanize_plugin_name(ext), else: ext_id)

        icon =
          if ext && is_map(ext.dashboard_view) && ext.dashboard_view[:icon],
            do: ext.dashboard_view[:icon],
            else: ExtensionPresenter.icon(ext || ext_id)

        %{
          id: ext_id,
          title: "#{icon} Go to #{title}",
          subtitle: "Pinned extension view & visual controls",
          type: "navigation"
        }
      end)

    base_navs = [
      %{
        id: "overview",
        title: "📊 Go to Overview",
        subtitle: "Platform architecture and kernel metrics",
        type: "navigation"
      },
      %{
        id: "apps",
        title: "🧩 Go to Extensions Registry",
        subtitle: "Browse and pin installed plugins",
        type: "navigation"
      }
    ]

    # Additional Extensions
    extra_ext_navs =
      socket.assigns.overview.extensions
      |> Enum.reject(fn e -> to_string(e.id) in socket.assigns.pinned_extensions end)
      |> Enum.map(fn ext ->
        title =
          if is_map(ext.dashboard_view) and ext.dashboard_view[:title],
            do: ext.dashboard_view[:title],
            else: humanize_plugin_name(ext)

        icon =
          if is_map(ext.dashboard_view) and ext.dashboard_view[:icon],
            do: ext.dashboard_view[:icon],
            else: ExtensionPresenter.icon(ext)

        %{
          id: to_string(ext.id),
          title: "#{icon} Go to #{title}",
          subtitle: "Extension visual controls",
          type: "navigation"
        }
      end)

    # 2. Action Runner & Console items
    tool_items = [
      %{
        id: "open_action_runner",
        title: "⚡ Action Runner: Dispatch Plugin Actions",
        subtitle: "Interactive form to execute backend RPCs",
        type: "action"
      },
      %{
        id: "toggle_event_dock",
        title: "📡 Event Console: Live Cluster Event Stream",
        subtitle: "Real-time telemetry from :pg and EventDispatcher",
        type: "action"
      }
    ]

    # 3. Dynamic Action RPC items
    rpc_items =
      Enum.flat_map(socket.assigns.action_catalog, fn svc ->
        Enum.map(svc.actions, fn act ->
          %{
            id: "rpc:#{svc.name}.#{act.name}",
            title: "⚡ Action: #{svc.name}.#{act.name}",
            subtitle: act.doc,
            type: "action"
          }
        end)
      end)

    # 4. Declared Resources
    resource_items =
      Enum.map(socket.assigns.overview.resources, fn r ->
        res = r[:resource] || r["resource"] || %{}
        name = res[:name] || res["name"] || "resource"

        %{
          id: "res_#{name}",
          title: "📦 Resource: #{name}",
          subtitle: "Primary Key: #{res[:primary_key] || res["primary_key"]}",
          type: "resource"
        }
      end)

    base_navs ++
      pinned_navs ++ extra_ext_navs ++ tool_items ++ rpc_items ++ resource_items
  end

  defp handle_quick_action(action, socket) do
    case action do
      "open_action_runner" ->
        {:noreply, assign(socket, action_modal_open: true, action_result: nil)}

      "toggle_event_dock" ->
        {:noreply, assign(socket, event_dock_open: !socket.assigns.event_dock_open)}

      _ ->
        {:noreply, socket}
    end
  end

  defp humanize_plugin_name(ext_or_id), do: ExtensionPresenter.display_name(ext_or_id)
  defp tab_short_name(ext_or_id), do: ExtensionPresenter.display_name(ext_or_id)

  # Resolves a custom LiveView/LiveComponent for an extension: an explicit `:module` in its
  # dashboard_view, dynamic lookup via `:dashboard_view` service contract, or conventional module.
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

  @builtin_overview_slots [
    "event_graph",
    "error_graph",
    "server_state",
    "extension_health",
    "download_sdk"
  ]

  defp resolve_overview_slot_ids(overview_widgets, saved_order) do
    widget_ids = Enum.map(overview_widgets, fn w -> "widget:#{w.id}" end)
    default_ids = @builtin_overview_slots ++ widget_ids
    kept = Enum.filter(saved_order || [], &(&1 in default_ids))
    missing = Enum.reject(default_ids, &(&1 in kept))
    kept ++ missing
  end

  defp fetch_telemetry_summary(overview, activity_events) do
    snapshot =
      try do
        Exoforge.Metering.snapshot()
      rescue
        _ -> %{actions: [], plugins: []}
      end

    metered_actions = Map.get(snapshot, :actions, [])
    metered_plugins = Map.get(snapshot, :plugins, [])

    log_rates =
      try do
        :ets.tab2list(:exo_plugin_log_rate)
        |> Map.new(fn {pid, _win, count} -> {to_string(pid), count} end)
      rescue
        _ -> %{}
      end

    restarts_by_id =
      Map.new(metered_plugins, fn p ->
        {to_string(p.plugin_id), Map.get(p, :restarts, 0)}
      end)

    errors_by_plugin =
      Enum.group_by(metered_actions, &to_string(&1.plugin_id))
      |> Map.new(fn {pid, acts} ->
        {pid, Enum.sum(Enum.map(acts, &Map.get(&1, :errors, 0)))}
      end)

    faulty_extensions =
      Enum.flat_map(overview.plugins, fn p ->
        pid = to_string(p.id)
        restarts = max(Map.get(p, :restarts, 0), Map.get(restarts_by_id, pid, 0))
        log_rate = Map.get(log_rates, pid, 0)
        infinite_loop? = Map.get(p, :infinite_loop, false) == true or log_rate >= 100
        crashed? = Map.get(p, :crashed_recently, false) == true or restarts > 0 or Map.get(p, :status) in [:faulty, "faulty", :crashed, "crashed"]

        cond do
          infinite_loop? ->
            [%{id: pid, name: humanize_plugin_name(p), reason: "Infinite loop / log flood detected (#{max(log_rate, 100)} logs/s)"}]

          crashed? ->
            [%{id: pid, name: humanize_plugin_name(p), reason: "Crashed recently (#{max(restarts, 1)} restart(s))"}]

          true ->
            []
        end
      end)

    total_invocations =
      Enum.sum(Enum.map(metered_actions, &Map.get(&1, :invocations, 0))) + length(activity_events)

    total_errors =
      Enum.sum(Enum.map(metered_actions, &Map.get(&1, :errors, 0))) + length(faulty_extensions)

    top_services =
      metered_actions
      |> Enum.group_by(&to_string(&1.service))
      |> Enum.map(fn {svc, acts} ->
        {svc,
         Enum.sum(Enum.map(acts, &Map.get(&1, :invocations, 0))),
         Enum.sum(Enum.map(acts, &Map.get(&1, :errors, 0)))}
      end)
      |> Enum.sort_by(fn {_svc, inv, _err} -> -inv end)
      |> Enum.take(6)

    event_bars =
      if top_services != [] do
        max_inv = Enum.max([1 | Enum.map(top_services, &elem(&1, 1))])

        Enum.map(top_services, fn {svc, inv, _err} ->
          %{label: svc, count: inv, pct: max(round(inv / max_inv * 100), 12)}
        end)
      else
        [
          %{label: "auth", count: max(length(activity_events), 1), pct: 48},
          %{label: "http", count: 2, pct: 64},
          %{label: "ws", count: 1, pct: 36},
          %{label: "studio", count: length(activity_events), pct: 78},
          %{label: "db", count: overview.resources_count, pct: 52},
          %{label: "plugins", count: overview.plugins_count, pct: 85}
        ]
      end

    error_bars =
      if top_services != [] do
        max_err = Enum.max([1 | Enum.map(top_services, &elem(&1, 2))])

        Enum.map(top_services, fn {svc, _inv, err} ->
          %{label: svc, count: err, pct: if(err > 0, do: max(round(err / max_err * 100), 18), else: 8)}
        end)
      else
        Enum.take(overview.plugins, 6)
        |> Enum.map(fn p ->
          err = Map.get(errors_by_plugin, to_string(p.id), 0)
          %{label: String.replace_prefix(to_string(p.id), "exoforge_std_", ""), count: err, pct: if(err > 0, do: 75, else: 8)}
        end)
      end

    online_count = max(overview.plugins_count - length(faulty_extensions), 0)

    %{
      total_invocations: total_invocations,
      total_errors: total_errors,
      event_bars: event_bars,
      error_bars: error_bars,
      online_count: online_count,
      faulty_count: length(faulty_extensions),
      faulty_extensions: faulty_extensions
    }
  end

  defp widget_width_class(widget) do
    case Map.get(widget, :slot_size) || Map.get(widget, :grid_span) || Map.get(widget, :width) do
      s when s in ["1x1", :quarter, :one_fourth, :one_third] -> "lg:col-span-1"
      s when s in ["2x1", :half, :two_thirds] -> "lg:col-span-2"
      "2x2" -> "lg:col-span-2 lg:row-span-2"
      "3x1" -> "lg:col-span-3"
      s when s in ["4x1", :full] -> "lg:col-span-4"
      _ -> "lg:col-span-2"
    end
  end

  # ---- TEMPLATE RENDER ----

  @impl true
  def render(assigns) do
    total_actions =
      Enum.sum(Enum.map(assigns.action_catalog, fn svc -> length(svc.actions) end))

    overview_widgets = Exoforge.UIHookRegistry.list_hooks(:overview_widget)
    overview_slot_ids = resolve_overview_slot_ids(overview_widgets, assigns.overview_grid_order)
    telemetry = fetch_telemetry_summary(assigns.overview, assigns.activity_events)
    widgets_by_slot = Map.new(overview_widgets, fn w -> {"widget:#{w.id}", w} end)

    assigns =
      assigns
      |> assign(:total_actions, total_actions)
      |> assign(:overview_widgets, overview_widgets)
      |> assign(:overview_slot_ids, overview_slot_ids)
      |> assign(:widgets_by_slot, widgets_by_slot)
      |> assign(:telemetry, telemetry)

    ~H"""
    <div class="min-h-screen flex flex-col" phx-window-keydown="handle_key">
      <!-- Exoforge Shell Header -->
      <header class="sticky top-0 z-40 bg-white/95 backdrop-blur border-b border-gray-200 px-4 lg:px-8 py-2.5 transition-shadow">
        <div class="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-y-2 gap-x-4">
          <!-- Brand & Environment Switcher -->
          <div class="flex items-center gap-2.5 flex-shrink-0">
            <img src="/favicon.svg" alt="Exoforge" class="w-8 h-8 rounded-xl shadow-xs" />
            <div>
              <div class="flex items-center">
                <span class="font-black text-gray-900 tracking-tight text-lg leading-none flex items-center">
                  <span class="text-primary-600">EXO</span><span>FORGE</span>
                </span>
              </div>
              <div class="flex items-center gap-1.5 mt-0.5 text-[11px] leading-tight text-gray-500">
                <span class="font-bold text-gray-700 max-w-[120px] truncate"><%= @project_name %></span>
                <span class="text-gray-300">/</span>
                <span class="text-gray-500 font-medium truncate"><%= @studio_name %></span>
                <span class="text-gray-300">•</span>
                <span class="relative flex h-1.5 w-1.5">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-500"></span>
                </span>
                <form id="env_switcher_form" phx-change="switch_env" class="m-0 inline-block">
                  <select
                    name="env"
                    class="bg-transparent text-[9px] font-bold text-gray-400 hover:text-gray-800 border-none rounded py-0 pl-0 pr-1.5 focus:ring-0 cursor-pointer font-mono uppercase tracking-wider leading-none"
                    title="Switch Active Environment"
                  >
                    <option value="Live" selected={@current_env == "Live"}>LIVE</option>
                    <option value="Dev" selected={@current_env == "Dev"}>DEV</option>
                    <option value="Staging" selected={@current_env == "Staging"}>STAGING</option>
                  </select>
                </form>
              </div>
            </div>
          </div>

          <!-- Top Navigation Bar: 1. Overview, 2. Extensions, 3. Pinned Items (wraps to 2nd line if needed, up to @max_pinned) -->
          <nav class="flex-1 min-w-0 mx-2 flex flex-wrap items-center gap-1 bg-gray-100/90 p-1 rounded-xl border border-gray-200/80 shadow-inner">
            <!-- 1. Overview Tab -->
            <button
              phx-click="switch_tab"
              phx-value-tab="overview"
              class={"px-2.5 py-1.5 text-xs rounded-lg transition-all font-bold flex items-center gap-1.5 whitespace-nowrap flex-shrink-0 #{if @current_tab == :overview, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
              </svg>
              <span>Overview</span>
            </button>

            <!-- 2. Extensions Menu Tab -->
            <button
              phx-click="switch_tab"
              phx-value-tab="apps"
              class={"px-2.5 py-1.5 text-xs rounded-lg transition-all font-bold flex items-center gap-1.5 whitespace-nowrap flex-shrink-0 #{if @current_tab == :apps, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
              <span>Extensions</span>
              <span class="text-[10px] px-1.5 py-0.2 rounded-full bg-primary-100 text-primary-800 font-black">
                <%= @overview.plugins_count %>
              </span>
            </button>

            <!-- Separator between main tabs and pinned items -->
            <%= if length(@pinned_extensions) > 0 do %>
              <div class="h-4 w-px bg-gray-300 mx-0.5 flex-shrink-0"></div>
            <% end %>

            <!-- 3a. Pinned dropdown (small screens) -->
            <%= if length(@pinned_extensions) > 0 do %>
              <div class="relative md:hidden flex-shrink-0">
                <button
                  type="button"
                  phx-click="toggle_pinned_menu"
                  class="px-2.5 py-1.5 text-xs rounded-lg font-bold flex items-center gap-1.5 text-gray-600 hover:text-gray-900 hover:bg-gray-200/50"
                >
                  <span>Pinned</span>
                  <span class="text-[10px] px-1.5 rounded-full bg-gray-200 text-gray-700"><%= length(@pinned_extensions) %></span>
                  <span class="text-[9px]">▾</span>
                </button>
                <%= if @pinned_menu_open do %>
                  <div class="absolute left-0 top-full mt-1 z-50 min-w-[11rem] bg-white border border-gray-200 rounded-xl shadow-lg p-1 space-y-0.5">
                    <%= for ext_id <- Enum.take(@pinned_extensions, @max_pinned) do %>
                      <% pext = Enum.find(@overview.extensions, fn e -> to_string(e.id) == ext_id end) %>
                      <%= if pext do %>
                        <button
                          type="button"
                          phx-click="switch_tab"
                          phx-value-tab={ext_id}
                          class={"w-full text-left px-2.5 py-2 rounded-lg text-xs font-bold flex items-center gap-2 #{if to_string(@current_tab) == ext_id, do: "bg-primary-50 text-primary-700", else: "text-gray-700 hover:bg-gray-100"}"}
                        >
                          <span><%= if is_map(pext.dashboard_view) and pext.dashboard_view[:icon], do: pext.dashboard_view[:icon], else: ExtensionPresenter.icon(pext) %></span>
                          <span class="truncate"><%= tab_short_name(pext) %></span>
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <!-- 3b. Pinned Extension Tabs (md+; can wrap to second line, up to limit) -->
            <%= for ext_id <- Enum.take(@pinned_extensions, @max_pinned) do %>
              <% ext = Enum.find(@overview.extensions, fn e -> to_string(e.id) == ext_id end) %>
              <%= if ext do %>
                <% title = tab_short_name(ext) %>
                <% icon = if is_map(ext.dashboard_view) and ext.dashboard_view[:icon], do: ext.dashboard_view[:icon], else: ExtensionPresenter.icon(ext) %>
                <% is_active = to_string(@current_tab) == ext_id %>
                <div class={"group relative hidden md:flex items-center rounded-lg transition-all text-xs font-bold whitespace-nowrap flex-shrink-0 #{if is_active, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-200/50"}"}>
                  <button
                    phx-click="switch_tab"
                    phx-value-tab={ext_id}
                    class="px-2.5 py-1.5 flex items-center gap-1.5"
                  >
                    <span class="text-xs"><%= icon %></span>
                    <span><%= title %></span>
                  </button>
                  <button
                    type="button"
                    phx-click="unpin_extension"
                    phx-value-id={ext_id}
                    title={"Unpin #{title} from top bar"}
                    class="pr-1.5 pl-0.5 text-gray-400 hover:text-red-500 font-bold text-[10px] transition-opacity opacity-0 group-hover:opacity-100"
                  >
                    ✕
                  </button>
                </div>
              <% end %>
            <% end %>
          </nav>

          <!-- Right Toolbar: Search & Settings, User Info & Logout -->
          <div class="flex items-center gap-2 flex-shrink-0">
            <button
              type="button"
              phx-click="open_cmd_palette"
              class="w-9 h-9 rounded-xl bg-gray-100 hover:bg-gray-200/80 text-gray-600 flex items-center justify-center transition-colors text-sm border border-gray-200/60"
              title="Search (⌘K)"
            >
              <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </button>

            <button
              type="button"
              phx-click="open_settings"
              class="w-9 h-9 rounded-xl bg-gray-100 hover:bg-gray-200/80 text-gray-600 flex items-center justify-center transition-colors text-sm border border-gray-200/60"
              title="Project Settings"
            >
              ⚙️
            </button>

            <!-- User Profile & Logout / Login -->
            <%= if @authenticated do %>
              <div class="flex items-center gap-2 pl-2 border-l border-gray-200">
                <div class="flex items-center gap-2">
                  <div
                    class="w-8 h-8 rounded-full bg-purple-100 text-purple-700 font-bold text-xs flex items-center justify-center border border-purple-200"
                    title={"User ID: " <> to_string(@user_id)}
                  >
                    <%= String.slice(to_string(@user_name), 0, 2) |> String.upcase() %>
                  </div>
                  <div class="hidden md:flex flex-col text-left">
                    <span class="text-xs font-bold text-gray-800 leading-tight truncate max-w-[120px]"><%= @user_name %></span>
                    <span class="text-[10px] text-gray-400 font-medium leading-none"><%= @user_role %></span>
                  </div>
                </div>

                <a
                  href="/logout"
                  data-phx-link-state="replace"
                  class="w-8 h-8 rounded-xl bg-gray-100 hover:bg-red-50 hover:text-red-600 text-gray-500 flex items-center justify-center transition-colors text-xs border border-gray-200/60"
                  title="Log out of session"
                >
                  <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                  </svg>
                </a>
              </div>
            <% else %>
              <button
                type="button"
                phx-click="open_login_modal"
                class="px-3 py-1.5 bg-primary-600 hover:bg-primary-700 text-white font-bold text-xs rounded-xl transition-colors shadow-xs"
              >
                Sign in
              </button>
            <% end %>
          </div>
        </div>
      </header>

      <!-- Main Workspace Area -->
      <main class="flex-1 max-w-7xl w-full mx-auto p-4 sm:p-6 lg:p-8 space-y-8">
        <!-- Toast Notices (auto-dismiss after 4s) -->
        <%= for {kind, msg} <- [{:info, Phoenix.Flash.get(@flash, :info)}, {:error, Phoenix.Flash.get(@flash, :error)}], msg do %>
          <div class={"fixed top-4 right-4 z-[60] max-w-sm p-3 rounded-xl text-xs font-bold flex items-center gap-3 shadow-lg animate-fade-in #{if kind == :info, do: "bg-emerald-600 text-white", else: "bg-red-600 text-white"}"}>
            <span class="text-sm"><%= if kind == :info, do: "✓", else: "!" %></span>
            <span class="flex-1"><%= msg %></span>
            <button
              type="button"
              phx-click="dismiss_toast"
              phx-value-kind={kind}
              class="opacity-80 hover:opacity-100 text-base font-black leading-none"
              title="Dismiss"
            >
              &times;
            </button>
          </div>
        <% end %>

        <!-- OVERVIEW TAB: 4-Slot Rearrangeable Grid -->
        <%= if @current_tab == :overview do %>
          <div class="flex items-center justify-between gap-2">
            <div>
              <h2 class="text-base font-extrabold text-gray-900 tracking-tight">Cluster Overview</h2>
              <p class="text-xs text-gray-500">Live telemetry, extension health watchdog, SDK distribution, and dynamic extension widgets. Use the slot arrows to rearrange the grid.</p>
            </div>
            <%= if @overview_grid_order != [] do %>
              <button
                type="button"
                phx-click="reset_overview_grid"
                class="px-2.5 py-1.5 text-[11px] font-bold text-gray-600 hover:text-gray-900 bg-white hover:bg-gray-50 border border-gray-200 rounded-xl transition-colors"
              >
                ↺ Reset Grid Order
              </button>
            <% end %>
          </div>

          <div id="overview-bento-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 auto-rows-min">
            <%= for {slot_id, idx} <- Enum.with_index(@overview_slot_ids) do %>
              <%= case slot_id do %>
                <% "event_graph" -> %>
                  <!-- 2x2 EVENT GRAPH -->
                  <div
                    id="slot-event_graph"
                    data-slot-id="event_graph"
                    data-slot-span="2x2"
                    class="lg:col-span-2 lg:row-span-2 bg-white p-6 rounded-2xl border border-gray-200 shadow-card flex flex-col justify-between space-y-5"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="flex items-center gap-2">
                          <span class="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse"></span>
                          <h3 class="font-bold text-gray-900 text-sm">Event &amp; Action Throughput</h3>
                          <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-purple-50 text-purple-700 rounded-md border border-purple-200">2×2</span>
                        </div>
                        <p class="text-xs text-gray-400 mt-0.5">Real-time EventDispatcher pub/sub and service invocations</p>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          phx-click="toggle_event_dock"
                          class="px-2.5 py-1 text-[11px] font-bold text-primary-600 hover:text-primary-700 bg-primary-50/70 hover:bg-primary-100 rounded-lg transition-colors mr-1"
                        >
                          Open Console &rarr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="event_graph"
                          phx-value-dir="prev"
                          disabled={idx == 0}
                          title="Move slot left"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &larr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="event_graph"
                          phx-value-dir="next"
                          disabled={idx == length(@overview_slot_ids) - 1}
                          title="Move slot right"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &rarr;
                        </button>
                      </div>
                    </div>

                    <div class="flex items-baseline gap-3">
                      <span class="text-3xl font-black text-gray-900 tracking-tight"><%= @telemetry.total_invocations %></span>
                      <span class="text-xs font-semibold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full">
                        <%= length(@activity_events) %> live stream events
                      </span>
                    </div>

                    <!-- Bar Chart Visualization -->
                    <div class="h-36 flex items-end gap-3 pt-4 px-2 border-b border-gray-100">
                      <%= for bar <- @telemetry.event_bars do %>
                        <div class="flex-1 flex flex-col items-center gap-1.5 h-full justify-end group">
                          <span class="text-[10px] font-mono font-bold text-gray-500"><%= bar.count %></span>
                          <div class="w-full bg-purple-100 rounded-t-lg relative overflow-hidden" style={"height: #{bar.pct}%"}>
                            <div class=" inset-0 bg-gradient-to-t from-purple-600 to-indigo-500 w-full h-full opacity-85 group-hover:opacity-100 transition-opacity"></div>
                          </div>
                          <span class="text-[10px] font-mono text-gray-500 truncate max-w-full"><%= bar.label %></span>
                        </div>
                      <% end %>
                    </div>

                    <!-- Recent Events Mini-Feed -->
                    <div class="space-y-1.5">
                      <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Latest Dispatched Events</div>
                      <%= for ev <- Enum.take(@activity_events, 2) do %>
                        <div class="flex items-center justify-between px-3 py-1.5 rounded-lg bg-gray-50 border border-gray-100 text-xs">
                          <span class="font-mono font-bold text-primary-700 truncate">📡 <%= ev.event %></span>
                          <span class="text-[10px] text-gray-400 font-mono shrink-0"><%= ev.time %></span>
                        </div>
                      <% end %>
                    </div>
                  </div>

                <% "error_graph" -> %>
                  <!-- 2x2 ERROR GRAPH -->
                  <div
                    id="slot-error_graph"
                    data-slot-id="error_graph"
                    data-slot-span="2x2"
                    class="lg:col-span-2 lg:row-span-2 bg-white p-6 rounded-2xl border border-gray-200 shadow-card flex flex-col justify-between space-y-5"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="flex items-center gap-2">
                          <span class={"w-2.5 h-2.5 rounded-full #{if @telemetry.total_errors > 0, do: "bg-red-500 animate-ping", else: "bg-emerald-500"}"}></span>
                          <h3 class="font-bold text-gray-900 text-sm">Error &amp; Exception Graph</h3>
                          <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-gray-100 text-gray-600 rounded-md border border-gray-200">2×2</span>
                        </div>
                        <p class="text-xs text-gray-400 mt-0.5">Action dispatch failures, crashes, and rate-limit spikes by service</p>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="error_graph"
                          phx-value-dir="prev"
                          disabled={idx == 0}
                          title="Move slot left"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &larr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="error_graph"
                          phx-value-dir="next"
                          disabled={idx == length(@overview_slot_ids) - 1}
                          title="Move slot right"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &rarr;
                        </button>
                      </div>
                    </div>

                    <div class="flex items-baseline gap-3">
                      <span class={"text-3xl font-black tracking-tight #{if @telemetry.total_errors > 0, do: "text-red-600", else: "text-gray-900"}"}>
                        <%= @telemetry.total_errors %>
                      </span>
                      <span class={"text-xs font-semibold px-2 py-0.5 rounded-full #{if @telemetry.total_errors > 0, do: "bg-red-50 text-red-700", else: "bg-emerald-50 text-emerald-700"}"}>
                        <%= if @telemetry.total_errors > 0, do: "Errors detected", else: "0% error rate" %>
                      </span>
                    </div>

                    <!-- Error Bar Chart -->
                    <div class="h-36 flex items-end gap-3 pt-4 px-2 border-b border-gray-100">
                      <%= for bar <- @telemetry.error_bars do %>
                        <div class="flex-1 flex flex-col items-center gap-1.5 h-full justify-end">
                          <span class={"text-[10px] font-mono font-bold #{if bar.count > 0, do: "text-red-600", else: "text-gray-400"}"}><%= bar.count %></span>
                          <div
                            class={"w-full rounded-t-lg transition-all #{if bar.count > 0, do: "bg-gradient-to-t from-red-600 to-amber-500", else: "bg-gray-100"}"}
                            style={"height: #{bar.pct}%"}
                          >
                          </div>
                          <span class="text-[10px] font-mono text-gray-500 truncate max-w-full"><%= bar.label %></span>
                        </div>
                      <% end %>
                    </div>

                    <div class="px-3 py-2 rounded-xl bg-gray-50 border border-gray-100 flex items-center justify-between text-xs">
                      <span class="text-gray-500">Monitored Callable Actions</span>
                      <span class="font-mono font-bold text-gray-800"><%= @total_actions %> actions across <%= @overview.plugins_count %> plugins</span>
                    </div>
                  </div>

                <% "server_state" -> %>
                  <!-- 1x1 SERVER STATE INDICATOR -->
                  <div
                    id="slot-server_state"
                    data-slot-id="server_state"
                    data-slot-span="1x1"
                    class="lg:col-span-1 bg-white p-5 rounded-2xl border border-gray-200 shadow-card flex flex-col justify-between space-y-4"
                  >
                    <div class="flex items-start justify-between gap-2">
                      <div class="flex items-center gap-2">
                        <span class="w-8 h-8 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center text-sm font-bold border border-emerald-200">
                          🟢
                        </span>
                        <div>
                          <h3 class="font-bold text-gray-900 text-xs uppercase tracking-wider">Server State</h3>
                          <span class="text-[10px] font-mono text-gray-400">1×1 Indicator</span>
                        </div>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="server_state"
                          phx-value-dir="prev"
                          disabled={idx == 0}
                          title="Move slot left"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &larr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="server_state"
                          phx-value-dir="next"
                          disabled={idx == length(@overview_slot_ids) - 1}
                          title="Move slot right"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &rarr;
                        </button>
                      </div>
                    </div>

                    <div>
                      <div class="flex items-center gap-2">
                        <span class="text-2xl font-black text-gray-900">Healthy</span>
                        <span class="px-2 py-0.5 text-[10px] font-bold bg-emerald-50 text-emerald-700 rounded-full border border-emerald-200">ONLINE</span>
                      </div>
                      <p class="text-[11px] text-gray-500 font-mono truncate mt-1" title={to_string(node())}>
                        Node: <%= to_string(node()) %>
                      </p>
                    </div>

                    <div class="pt-2 border-t border-gray-100 flex items-center justify-between text-[11px] text-gray-500">
                      <span>Resources: <strong class="text-gray-800"><%= @overview.resources_count %></strong></span>
                      <span>Env: <strong class="text-primary-700 uppercase"><%= @current_env %></strong></span>
                    </div>
                  </div>

                <% "extension_health" -> %>
                  <!-- 2x1 ONLINE / FAULTY EXTENSION COUNTER -->
                  <div
                    id="slot-extension_health"
                    data-slot-id="extension_health"
                    data-slot-span="2x1"
                    class={"lg:col-span-2 bg-white p-5 rounded-2xl border shadow-card flex flex-col justify-between space-y-4 #{if @telemetry.faulty_count > 0, do: "border-amber-300", else: "border-gray-200"}"}
                  >
                    <div class="flex items-start justify-between gap-2">
                      <div>
                        <div class="flex items-center gap-2">
                          <h3 class="font-bold text-gray-900 text-sm">Online / Faulty Extensions</h3>
                          <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-gray-100 text-gray-600 rounded-md border border-gray-200">2×1</span>
                        </div>
                        <p class="text-xs text-gray-400 mt-0.5">Monitors extension processes for recent crashes or infinite loops</p>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          phx-click="switch_tab"
                          phx-value-tab="apps"
                          class="px-2.5 py-1 text-[11px] font-bold text-primary-600 hover:text-primary-700 bg-primary-50/70 hover:bg-primary-100 rounded-lg transition-colors mr-1"
                        >
                          Manage &rarr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="extension_health"
                          phx-value-dir="prev"
                          disabled={idx == 0}
                          title="Move slot left"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &larr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="extension_health"
                          phx-value-dir="next"
                          disabled={idx == length(@overview_slot_ids) - 1}
                          title="Move slot right"
                          class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &rarr;
                        </button>
                      </div>
                    </div>

                    <div class="grid grid-cols-2 gap-3">
                      <div class="p-3 rounded-xl bg-emerald-50/80 border border-emerald-200 flex items-center justify-between">
                        <div>
                          <span class="block text-[10px] font-bold uppercase tracking-wider text-emerald-700">Online</span>
                          <span class="text-2xl font-black text-emerald-800"><%= @telemetry.online_count %></span>
                        </div>
                        <span class="text-lg">🧩</span>
                      </div>

                      <div class={"p-3 rounded-xl border flex items-center justify-between #{if @telemetry.faulty_count > 0, do: "bg-red-50 border-red-300", else: "bg-gray-50 border-gray-200"}"}>
                        <div>
                          <span class={"block text-[10px] font-bold uppercase tracking-wider #{if @telemetry.faulty_count > 0, do: "text-red-700", else: "text-gray-500"}"}>Faulty / Loop</span>
                          <span class={"text-2xl font-black #{if @telemetry.faulty_count > 0, do: "text-red-700", else: "text-gray-800"}"}><%= @telemetry.faulty_count %></span>
                        </div>
                        <span class="text-lg"><%= if @telemetry.faulty_count > 0, do: "⚠️", else: "✓" %></span>
                      </div>
                    </div>

                    <%= if @telemetry.faulty_extensions != [] do %>
                      <div class="space-y-1.5">
                        <%= for f <- @telemetry.faulty_extensions do %>
                          <div class="px-3 py-2 rounded-xl bg-amber-50 border border-amber-200 text-xs text-amber-900 flex items-center justify-between gap-2">
                            <span class="font-bold truncate">⚠️ <%= f.name %></span>
                            <span class="font-mono text-[11px] text-amber-800 shrink-0"><%= f.reason %></span>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <div class="text-[11px] text-gray-500 flex items-center gap-1.5">
                        <span class="text-emerald-600 font-bold">✓</span>
                        <span>No infinite loops or recent extension crashes detected.</span>
                      </div>
                    <% end %>
                  </div>

                <% "download_sdk" -> %>
                  <!-- 1x1 HIGHLIGHTED DOWNLOAD SDK BUTTON -->
                  <div
                    id="slot-download_sdk"
                    data-slot-id="download_sdk"
                    data-slot-span="1x1"
                    class="lg:col-span-1 bg-gradient-to-br from-purple-600 to-indigo-700 text-white p-5 rounded-2xl border border-purple-500 shadow-lg flex flex-col justify-between space-y-4"
                  >
                    <div class="flex items-start justify-between gap-2">
                      <div class="flex items-center gap-2">
                        <span class="w-8 h-8 rounded-xl bg-white/15 backdrop-blur flex items-center justify-center text-base">
                          📦
                        </span>
                        <div>
                          <h3 class="font-bold text-white text-xs uppercase tracking-wider">Client SDKs</h3>
                          <span class="text-[10px] font-mono text-purple-200">1×1 Action</span>
                        </div>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="download_sdk"
                          phx-value-dir="prev"
                          disabled={idx == 0}
                          title="Move slot left"
                          class="w-6 h-6 rounded-lg border border-white/20 text-white/80 hover:text-white hover:bg-white/10 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &larr;
                        </button>
                        <button
                          type="button"
                          phx-click="move_overview_slot"
                          phx-value-id="download_sdk"
                          phx-value-dir="next"
                          disabled={idx == length(@overview_slot_ids) - 1}
                          title="Move slot right"
                          class="w-6 h-6 rounded-lg border border-white/20 text-white/80 hover:text-white hover:bg-white/10 disabled:opacity-30 flex items-center justify-center text-xs"
                        >
                          &rarr;
                        </button>
                      </div>
                    </div>

                    <div>
                      <p class="text-sm font-extrabold text-white leading-snug">Unity &amp; C# SDK Packages</p>
                      <p class="text-[11px] text-purple-100 mt-1">Download client libraries, UPM tarballs, and setup guides.</p>
                    </div>

                    <button
                      type="button"
                      phx-click="open_sdk_modal"
                      class="w-full py-2.5 px-4 rounded-xl bg-white text-purple-700 hover:bg-purple-50 font-black text-xs shadow-sm transition-all flex items-center justify-center gap-2"
                    >
                      <span>⬇ Download SDK</span>
                    </button>
                  </div>

                <% "widget:" <> _ -> %>
                  <% widget = Map.get(@widgets_by_slot, slot_id) %>
                  <%= if widget do %>
                    <div
                      id={"slot-#{slot_id}"}
                      data-slot-id={slot_id}
                      class={"bg-white p-6 rounded-2xl border border-gray-200 shadow-card space-y-4 #{widget_width_class(widget)}"}
                    >
                      <div class="flex items-center justify-between gap-2">
                        <div>
                          <h3 class="font-bold text-gray-900 text-sm flex items-center gap-2">
                            <%= if Map.get(widget, :icon) do %>
                              <span><%= widget.icon %></span>
                            <% end %>
                            <span><%= widget.title %></span>
                          </h3>
                          <%= if Map.get(widget, :subtitle) do %>
                            <p class="text-xs text-gray-400 mt-0.5"><%= widget.subtitle %></p>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-1">
                          <span class="text-[10px] font-mono text-gray-400 mr-1"><%= Map.get(widget, :plugin_id, "") %></span>
                          <button
                            type="button"
                            phx-click="move_overview_slot"
                            phx-value-id={slot_id}
                            phx-value-dir="prev"
                            disabled={idx == 0}
                            title="Move slot left"
                            class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                          >
                            &larr;
                          </button>
                          <button
                            type="button"
                            phx-click="move_overview_slot"
                            phx-value-id={slot_id}
                            phx-value-dir="next"
                            disabled={idx == length(@overview_slot_ids) - 1}
                            title="Move slot right"
                            class="w-6 h-6 rounded-lg border border-gray-200 text-gray-400 hover:text-gray-700 hover:bg-gray-50 disabled:opacity-30 flex items-center justify-center text-xs"
                          >
                            &rarr;
                          </button>
                        </div>
                      </div>

                      <Exoforge.Std.Dashboard.Microfrontend.render_widget
                        spec={widget}
                        context={%{overview: @overview}}
                      />
                    </div>
                  <% end %>

                <% _ -> %>
              <% end %>
            <% end %>
          </div>
        <% end %>

        <!-- EXTENSIONS REGISTRY TAB -->
        <%= if @current_tab == :apps do %>
          <Exoforge.Std.Dashboard.ExtensionRegistry.registry
            extensions={@overview.extensions}
            search={@extensions_search}
            category={@extensions_category}
            pinned_extensions={@pinned_extensions}
          />
        <% end %>

        <!-- DYNAMIC EXTENSION VIEW MOUNT -->
        <%= if to_string(@current_tab) not in ["overview", "apps"] do %>
          <% current_tab_str = to_string(@current_tab) %>
          <% active_ext =
               Enum.find(@overview.extensions, fn e ->
                 to_string(e.id) == current_tab_str or
                   (is_map(e.dashboard_view) and to_string(e.dashboard_view[:id]) == current_tab_str)
               end) %>

          <%= if active_ext do %>
            <% dv = active_ext[:dashboard_view] %>
            <%= cond do %>
              <% is_map(dv) and (dv[:element] || dv["element"] || dv[:type] == "iframe" || dv["type"] == "iframe") -> %>
                <div class="bg-white p-6 rounded-2xl border border-gray-200/80 shadow-sm min-h-[600px]">
                  <Exoforge.Std.Dashboard.Microfrontend.render_widget
                    spec={Map.merge(dv, %{plugin_id: active_ext.id})}
                    context={%{focus: @focus, current_scopes: @current_scopes}}
                  />
                </div>

              <% mod = (active_ext[:custom_view_module] || ExtensionPresenter.view_module(active_ext)) -> %>
                <.live_component
                  module={mod}
                  id={"ext_view_#{active_ext.id}"}
                  extension={active_ext}
                  focus={@focus}
                  current_scopes={@current_scopes}
                />

              <% true -> %>
                <.live_component
                  module={Exoforge.Std.Dashboard.GenericExtensionView}
                  id={"ext_generic_#{active_ext.id}"}
                  extension={active_ext}
                  focus={@focus}
                  current_scopes={@current_scopes}
                />
            <% end %>
          <% else %>
            <div class="bg-white p-12 rounded-2xl border border-gray-200 text-center space-y-3">
              <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl">
                🧩
              </div>
              <h3 class="text-base font-bold text-gray-900">Extension Not Found</h3>
              <p class="text-xs text-gray-500 max-w-md mx-auto">
                The extension <code class="font-mono text-purple-700 font-bold"><%= current_tab_str %></code> is not loaded or registered in this cluster.
              </p>
              <button
                phx-click="switch_tab"
                phx-value-tab="overview"
                class="px-4 py-2 text-xs font-semibold text-white bg-primary-600 rounded-xl"
              >
                Back to Overview
              </button>
            </div>
          <% end %>
        <% end %>
      </main>

      <!-- Dashboard Footer -->
      <footer class="mt-auto py-4 px-4 sm:px-6 lg:px-8 border-t border-gray-200/60 text-center text-[11px] text-gray-400 font-mono">
        Exoforge v<%= @build_version %> (<%= @build_hash %>)
      </footer>

      <!-- Command Palette Modal (Cmd+K) -->
      <.command_palette
        open={@cmd_palette_open}
        query={@cmd_query}
        results={@cmd_results}
        on_close="close_cmd_palette"
        on_search="search_cmd_palette"
        on_select="select_cmd_item"
      />

      <!-- Global Project Settings Modal with Side Tabs -->
      <.project_settings_modal
        open={@settings_open}
        project_name={@project_name}
        studio_name={@studio_name}
        settings_tab={@settings_tab}
        settings_hooks={@settings_hooks}
        cors_config={@cors_config}
        environments={@environments}
        current_env={@current_env}
        overview={@overview}
        node_name={to_string(node())}
        on_close="close_settings"
      />

      <!-- Headless Service & Plugin Inspector Modal -->
      <.plugin_inspector_modal
        extension={@inspecting_extension}
        auth_token={@auth_token}
        on_close="close_inspect_extension"
      />

      <!-- Login Modal -->
      <.login_modal
        open={@login_open}
        error={Phoenix.Flash.get(@flash, :error)}
        on_close="close_login_modal"
      />

      <!-- Action Execution Modal -->
      <.action_runner_modal
        open={@action_modal_open}
        catalog={@action_catalog}
        selected_service={@selected_action_service}
        selected_action={@selected_action_name}
        action_params={@action_form_params}
        caller_scopes={Enum.join(@current_scopes, ", ")}
        result={@action_result}
        latency_ms={@action_latency_ms}
        on_close="close_action_modal"
        on_select_service="select_action_service"
        on_select_action="select_action_name"
        on_change_form="change_action_form"
        on_dispatch="dispatch_action"
      />

      <!-- Client SDK Download Modal -->
      <.sdk_download_modal
        open={@sdk_modal_open}
        on_close="close_sdk_modal"
      />

      <!-- Live Cluster Event Stream Dock -->
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
