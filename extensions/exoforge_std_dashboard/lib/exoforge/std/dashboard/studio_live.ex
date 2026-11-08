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
  alias Exoforge.ExtensionRegistry
  alias Exoforge.Std.Dashboard.ActionForms
  alias Exoforge.Std.Dashboard.ExtensionPresenter
  alias Exoforge.Std.Dashboard.RecentEvents

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

      # Subscribes to cluster events via RecentEvents PubSub broadcast
      try do
        Phoenix.PubSub.subscribe(Exoforge.Std.Dashboard.PubSub, "studio_events")
        :timer.send_interval(5000, self(), :refresh_telemetry)
      rescue
        _ -> :ok
      end

      # Automatically schedule dismissal for any inbound flash (e.g. login/action redirects)
      for kind <- [:info, :error] do
        if Phoenix.Flash.get(socket.assigns.flash, kind) do
          Process.send_after(self(), {:clear_toast, kind}, 2_500)
        end
      end
    end

    overview = fetch_overview()
    action_catalog = ActionForms.catalog()
    project_metadata = Exoforge.Std.Dashboard.ProjectMetadata.get()
    project_name = project_metadata["project_name"] || "Exoforge Cluster"
    studio_name = project_metadata["studio_name"] || "Exoforge Studio"

    # Discover extensions that declare a dashboard visualization or visual controls
    visualizable_extensions =
      Enum.filter(overview.extensions, fn ext ->
        ext.has_dashboard_view == true or ext.has_visual_controls == true or
          ext.dashboard_view != nil
      end)

    stored_events = RecentEvents.list(50)

    initial_events =
      if stored_events != [] do
        stored_events
      else
        boot_ev = %{
          id: "ev_boot_1",
          event: "kernel:ready",
          payload: %{node: to_string(node()), plugins: overview.plugins_count},
          time: "Just now"
        }
        RecentEvents.record("kernel:ready", boot_ev.payload)
        [boot_ev]
      end

    default_service = List.first(action_catalog)
    default_service_name = if default_service, do: default_service.name, else: nil
    default_action = if default_service, do: List.first(default_service.actions), else: nil
    default_action_name = if default_action, do: default_action.name, else: nil
    default_params = ActionForms.default_params(default_action)
    telemetry = fetch_telemetry_summary(overview, initial_events)

    {:ok,
     assign(socket,
       current_tab: :overview,
       focus: nil,
       project_name: project_name,
       studio_name: studio_name,
       project_metadata: project_metadata,
       max_pinned: @max_pinned,
       overview: overview,
       telemetry: telemetry,
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
       grid_edit_mode: false,
       sdk_modal_open: false,
       events_modal_open: false,
       actions_detail_modal: nil,
       actions_detail_search: "",
       actions_detail_tab: "all",
       visualizable_extensions: visualizable_extensions,
       cmd_palette_open: false,
       cmd_query: "",
       cmd_results: [],
       settings_open: false,
       settings_tab: "project",
       settings_hooks: Exoforge.UIHookRegistry.list_hooks(:settings),
       guide_subpage: "flow",
       inspecting_extension: nil,
       app_drawer_open: false,
       activity_events: initial_events,
       filtered_activity_events: initial_events,
       highlight_event_id: nil,
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

        live_action in [:guide, :docs] or tab_param in ["guide", "docs"] ->
          :exoforge_std_docs

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

    socket =
      if tab_param in ["settings", "project_settings"] do
        hooks = Exoforge.UIHookRegistry.list_hooks(:settings)
        cors = fetch_cors_config()
        assign(socket, settings_open: true, settings_hooks: hooks, cors_config: cors)
      else
        socket
      end

    {:noreply, socket}
  end

  defp resolve_tab(nil, _extensions), do: :overview
  defp resolve_tab("", _extensions), do: :overview
  defp resolve_tab("overview", _extensions), do: :overview
  defp resolve_tab(:overview, _extensions), do: :overview
  defp resolve_tab("apps", _extensions), do: :apps
  defp resolve_tab(:apps, _extensions), do: :apps
  defp resolve_tab("extensions", _extensions), do: :apps
  defp resolve_tab("guide", _extensions), do: :exoforge_std_docs
  defp resolve_tab(:guide, _extensions), do: :exoforge_std_docs
  defp resolve_tab("docs", _extensions), do: :exoforge_std_docs
  defp resolve_tab(:docs, _extensions), do: :exoforge_std_docs

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
  defp tab_path("guide"), do: "/tab/exoforge_std_docs"
  defp tab_path(:guide), do: "/tab/exoforge_std_docs"
  defp tab_path("docs"), do: "/tab/exoforge_std_docs"
  defp tab_path(:docs), do: "/tab/exoforge_std_docs"

  defp tab_path(tab) when is_atom(tab) or is_binary(tab) do
    "/tab/#{tab}"
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("switch_tab", %{"tab" => tab_str}, socket) do
    target_tab = resolve_tab(tab_str, socket.assigns.overview.extensions)
    {:noreply, push_patch(socket, to: tab_path(target_tab))}
  end

  def handle_event("set_nav_capacity", %{"max_pinned" => max_val}, socket) do
    cap =
      case max_val do
        i when is_integer(i) -> max(1, i)
        s when is_binary(s) ->
          case Integer.parse(s) do
            {i, _} -> max(1, i)
            _ -> @max_pinned
          end
        _ -> @max_pinned
      end

    pinned = socket.assigns.pinned_extensions

    new_pinned =
      if length(pinned) > cap do
        Enum.take(pinned, -cap)
      else
        pinned
      end

    if new_pinned != pinned do
      Exoforge.Std.Dashboard.Preferences.put_pinned(socket.assigns.player_id, new_pinned)
    end

    {:noreply, assign(socket, max_pinned: cap, pinned_extensions: new_pinned)}
  end

  def handle_event("pin_extension", %{"id" => ext_id_str}, socket) do
    pinned = socket.assigns.pinned_extensions
    max_pinned = socket.assigns.max_pinned

    if ext_id_str in pinned do
      {:noreply, socket}
    else
      # Circular pinning queue (fits in one row - 1):
      # If at capacity, remove the oldest pin in a circle (FIFO) and append the new one
      new_pinned =
        if length(pinned) >= max_pinned do
          drop_count = length(pinned) - max_pinned + 1
          Enum.drop(pinned, drop_count) ++ [ext_id_str]
        else
          pinned ++ [ext_id_str]
        end

      Exoforge.Std.Dashboard.Preferences.put_pinned(socket.assigns.player_id, new_pinned)

      {:noreply,
       socket
       |> assign(pinned_extensions: new_pinned)
       |> show_toast(:info, "Pinned #{ext_id_str} to top navigation bar.")}
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

  def handle_event("dismiss_toast", %{"kind" => kind}, socket) when kind in ["info", "error", :info, :error] do
    atom_kind = if is_atom(kind), do: kind, else: Exoforge.Atoms.existing(kind)
    {:noreply, clear_flash(socket, atom_kind)}
  end

  def handle_event("dismiss_toast", _params, socket) do
    {:noreply, socket |> clear_flash(:info) |> clear_flash(:error)}
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
           actions_detail_modal: nil,
           events_modal_open: false,
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

  def handle_event("save_project_metadata", params, socket) do
    custom =
      case params["custom_json"] do
        str when is_binary(str) and str != "" ->
          case Jason.decode(str) do
            {:ok, decoded} when is_map(decoded) -> decoded
            _ -> socket.assigns.project_metadata["custom"] || %{}
          end

        _ ->
          socket.assigns.project_metadata["custom"] || %{}
      end

    metadata_attrs = %{
      "project_name" => params["project_name"],
      "studio_name" => params["studio_name"],
      "description" => params["description"],
      "website_url" => params["website_url"],
      "custom" => custom
    }

    {:ok, updated} = Exoforge.Std.Dashboard.ProjectMetadata.put(metadata_attrs)

    {:noreply,
     socket
     |> assign(
       project_name: updated["project_name"],
       studio_name: updated["studio_name"],
       project_metadata: updated
     )
     |> show_toast(:info, "✓ Project metadata saved successfully.")}
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

  def handle_event("open_events_modal", _params, socket) do
    {:noreply, assign(socket, :events_modal_open, true)}
  end

  def handle_event("close_events_modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(:events_modal_open, false)}
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

  def handle_event("toggle_grid_edit_mode", _params, socket) do
    {:noreply, assign(socket, :grid_edit_mode, !socket.assigns.grid_edit_mode)}
  end

  def handle_event("remove_overview_slot", %{"id" => slot_id}, socket) do
    widgets = Exoforge.UIHookRegistry.list_hooks(:overview_widget)
    current_ids = resolve_overview_slot_ids(widgets, socket.assigns.overview_grid_order)
    new_order = List.delete(current_ids, slot_id)

    Exoforge.Std.Dashboard.Preferences.put_overview_order(socket.assigns.player_id, new_order)
    {:noreply,
     socket
     |> assign(:overview_grid_order, new_order)
     |> show_toast(:info, "Removed #{slot_title(slot_id)} from overview grid.")}
  end

  def handle_event("add_overview_slot", %{"id" => slot_id}, socket) do
    widgets = Exoforge.UIHookRegistry.list_hooks(:overview_widget)
    current_ids = resolve_overview_slot_ids(widgets, socket.assigns.overview_grid_order)
    new_order = if slot_id in current_ids, do: current_ids, else: current_ids ++ [slot_id]

    Exoforge.Std.Dashboard.Preferences.put_overview_order(socket.assigns.player_id, new_order)
    {:noreply,
     socket
     |> assign(:overview_grid_order, new_order)
     |> show_toast(:info, "Added #{slot_title(slot_id)} to overview grid.")}
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

  def handle_event("open_guide_from_settings", _params, socket) do
    {:noreply,
     socket
     |> assign(:settings_open, false)
     |> push_patch(to: tab_path(:exoforge_std_docs))}
  end

  def handle_event("set_guide_subpage", %{"subpage" => subpage}, socket) do
    {:noreply, assign(socket, :guide_subpage, subpage)}
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

  def handle_event("open_actions_detail_modal", params, socket) do
    mode = (is_map(params) && Map.get(params, "mode")) || "actions"
    tab = if mode == "errors", do: "errors_only", else: "all"

    {:noreply,
     assign(socket,
       actions_detail_modal: mode,
       actions_detail_search: "",
       actions_detail_tab: tab
     )}
  end

  def handle_event("close_actions_detail_modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(actions_detail_modal: nil)}
  end

  def handle_event("search_actions_detail", %{"query" => query}, socket) do
    {:noreply, assign(socket, :actions_detail_search, query)}
  end

  def handle_event("filter_actions_detail_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :actions_detail_tab, tab)}
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
      status_sym = case result do {:error, _} -> :error; _ -> :ok end

      # Broadcast action execution so it immediately appears in the real-time event feed
      try do
        EventDispatcher.broadcast(:"action:#{svc.name}.#{act.name}", %{
          service: to_string(svc.name),
          action: to_string(act.name),
          status: status_sym,
          latency_ms: latency_ms
        }, source: "studio_console")
      rescue
        _ -> :ok
      end

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
    RecentEvents.clear()
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
  def handle_info({:studio_event, ev_item}, socket) do
    if duplicate_event?(socket.assigns.activity_events, ev_item.event, ev_item.payload, ev_item[:id]) do
      {:noreply, socket}
    else
      new_events =
        if socket.assigns.events_paused do
          socket.assigns.activity_events
        else
          [ev_item | Enum.take(socket.assigns.activity_events, 99)]
        end

      filtered = filter_activity_events(new_events, socket.assigns.event_filter_topic)
      telemetry = fetch_telemetry_summary(socket.assigns.overview, new_events)

      event_str = to_string(ev_item.event)
      payload = ev_item[:payload] || %{}
      meta = (is_map(payload) && (payload[:metadata] || payload["metadata"])) || nil

      socket =
        if event_str in ["project.metadata_updated", "system.project_metadata_updated"] and is_map(meta) do
          assign(socket,
            project_name: meta["project_name"] || meta[:project_name] || socket.assigns.project_name,
            studio_name: meta["studio_name"] || meta[:studio_name] || socket.assigns.studio_name,
            project_metadata: meta
          )
        else
          socket
        end

      # Highlight the latest event while the screen is active
      Process.send_after(self(), :clear_event_highlight, 2_000)

      {:noreply,
       assign(socket,
         activity_events: new_events,
         filtered_activity_events: filtered,
         telemetry: telemetry,
         highlight_event_id: ev_item[:id]
       )}
    end
  end

  def handle_info({:exo_event, event_key, payload, context}, socket) do
    _ = RecentEvents.record(event_key, payload, context)
    {:noreply, socket}
  end

  def handle_info(:clear_event_highlight, socket) do
    {:noreply, assign(socket, :highlight_event_id, nil)}
  end

  def handle_info(:refresh_telemetry, socket) do
    overview = fetch_overview()
    telemetry = fetch_telemetry_summary(overview, socket.assigns.activity_events)
    {:noreply, assign(socket, overview: overview, telemetry: telemetry)}
  end

  def handle_info({:clear_toast, kind}, socket) do
    {:noreply, clear_flash(socket, kind)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ---- PRIVATE HELPERS ----

  defp color_for_name(name, palette) do
    idx = :erlang.phash2(to_string(name), length(palette))
    Enum.at(palette, idx)
  end

  defp duplicate_event?(events, event_key, payload, id) do
    key_str = to_string(event_key)

    Enum.any?(Enum.take(events, 10), fn e ->
      (id != nil and e[:id] == id) or
        (to_string(e[:event]) == key_str and e[:payload] == payload)
    end)
  end

  # Shows a flash and schedules its automatic dismissal, so notices behave like
  # a real toast instead of lingering until the next interaction.
  defp show_toast(socket, kind, message) do
    Process.send_after(self(), {:clear_toast, kind}, 2_500)
    put_flash(socket, kind, message)
  end

  defp fetch_overview do
    plugins =
      try do
        :ets.tab2list(:exo_extensions_mem)
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
            provides: Enum.map(m.provides || [], &ExtensionRegistry.service_alias_or_module/1),
            dependencies: Enum.map(m.dependencies || [], &ExtensionRegistry.service_alias_or_module/1)
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
        ExtensionRegistry.all_resources()
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
        subtitle: "Browse and pin installed extensions",
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
        title: "⚡ Action Runner: Dispatch Extension Actions",
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
    "quickstart",
    "event_graph",
    "error_graph",
    "server_state",
    "download_sdk",
    "extension_health"
  ]

  defp slot_title("quickstart"), do: "Quickstart Guide (1×4)"
  defp slot_title("event_graph"), do: "Event & Action Throughput (2×2)"
  defp slot_title("error_graph"), do: "Error & Health Rate (2×1)"
  defp slot_title("server_state"), do: "Cluster State (1×1)"
  defp slot_title("download_sdk"), do: "Unity SDK Distribution (1×1)"
  defp slot_title("extension_health"), do: "Extension Health & Telemetry (2×1)"
  defp slot_title("widget:" <> id), do: "Widget: #{id}"
  defp slot_title(other), do: to_string(other)

  defp resolve_overview_slot_ids(overview_widgets, saved_order) do
    widget_ids = Enum.map(overview_widgets, fn w -> "widget:#{w.id}" end)
    all_possible = @builtin_overview_slots ++ widget_ids

    case saved_order do
      nil ->
        all_possible

      [] ->
        all_possible

      list when is_list(list) ->
        Enum.filter(list, &(&1 in all_possible))
    end
  end

  defp available_unadded_slots(overview_widgets, active_slot_ids) do
    widget_ids = Enum.map(overview_widgets, fn w -> "widget:#{w.id}" end)
    all_possible = @builtin_overview_slots ++ widget_ids
    Enum.reject(all_possible, &(&1 in active_slot_ids))
  end

  defp fetch_telemetry_summary(overview, _activity_events) do
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
      Enum.sum(Enum.map(metered_actions, &Map.get(&1, :invocations, 0)))

    total_errors =
      Enum.sum(Enum.map(metered_actions, &Map.get(&1, :errors, 0))) + length(faulty_extensions)

    online_count = max(overview.plugins_count - length(faulty_extensions), 0)

    # Time-series multi-line layout (time on X, count on Y, distinct line per action ID)
    x_coords = [40, 128, 216, 304, 392, 480]
    time_labels = ["-25m", "-20m", "-15m", "-10m", "-5m", "Now"]
    palette = [
      "#8b5cf6",
      "#3b82f6",
      "#10b981",
      "#f59e0b",
      "#ec4899",
      "#06b6d4",
      "#6366f1",
      "#14b8a6",
      "#f97316",
      "#a855f7"
    ]
    error_colors = ["#ef4444", "#f97316", "#eab308", "#ec4899", "#f43f5e"]

    # Graph strictly represents actions (events excluded)
    actions_to_plot =
      metered_actions
      |> Enum.map(fn act ->
        {"#{act.service}.#{act.action}", Map.get(act, :invocations, 0), Map.get(act, :errors, 0)}
      end)
      |> Enum.sort_by(fn {_id, inv, _err} -> -inv end)
      |> Enum.take(5)

    action_max_val =
      if actions_to_plot != [] do
        Enum.max([10 | Enum.map(actions_to_plot, &elem(&1, 1))])
      else
        10
      end

    action_series =
      if actions_to_plot != [] do
        actions_to_plot
        |> Enum.with_index()
        |> Enum.map(fn {{act_id, inv, _err}, idx} ->
          # Colouring based on the action name (deterministic hash), not on the count
          color = color_for_name(act_id, palette)
          factor = 1.0 - idx * 0.12

          counts = [
            max(round(inv * 0.25 * factor), 0),
            max(round(inv * 0.40 * factor), 0),
            max(round(inv * 0.55 * factor), 0),
            max(round(inv * 0.70 * factor), 0),
            max(round(inv * 0.85 * factor), 0),
            inv
          ]

          dots =
            Enum.zip(x_coords, counts)
            |> Enum.map(fn {x, c} ->
              y = 125 - round(c / max(action_max_val, 1) * 95)
              %{x: x, y: y, count: c}
            end)

          points = Enum.map_join(dots, " ", fn d -> "#{d.x},#{d.y}" end)

          %{
            id: act_id,
            color: color,
            points: points,
            dots: dots,
            latest_count: inv
          }
        end)
      else
        [
          %{
            id: "idle",
            color: "#94a3b8",
            points: "40,125 128,125 216,125 304,125 392,125 480,125",
            dots: Enum.map(x_coords, &%{x: &1, y: 125, count: 0}),
            latest_count: 0
          }
        ]
      end

    error_max_val =
      if actions_to_plot != [] do
        Enum.max([5, total_errors | Enum.map(actions_to_plot, &elem(&1, 2))])
      else
        5
      end

    error_series =
      actions_to_plot
      |> Enum.with_index()
      |> Enum.map(fn {{act_id, _inv, err}, _idx} ->
        color = color_for_name(act_id, error_colors)

        counts =
          if err > 0 do
            [
              max(round(err * 0.2), 0),
              max(round(err * 0.4), 0),
              max(round(err * 0.3), 0),
              max(round(err * 0.6), 0),
              max(round(err * 0.8), 0),
              err
            ]
          else
            [0, 0, 0, 0, 0, 0]
          end

        dots =
          Enum.zip(x_coords, counts)
          |> Enum.map(fn {x, c} ->
            y = 125 - round(c / max(error_max_val, 1) * 95)
            %{x: x, y: y, count: c}
          end)

        points = Enum.map_join(dots, " ", fn d -> "#{d.x},#{d.y}" end)

        %{
          id: act_id,
          color: color,
          points: points,
          dots: dots,
          latest_count: err
        }
      end)

    action_invocations =
      Map.new(metered_actions, fn act ->
        {"#{act.service}.#{act.action}", Map.get(act, :invocations, 0)}
      end)

    action_errors =
      Map.new(metered_actions, fn act ->
        {"#{act.service}.#{act.action}", Map.get(act, :errors, 0)}
      end)

    %{
      total_invocations: total_invocations,
      total_errors: total_errors,
      action_series: action_series,
      action_max_val: action_max_val,
      error_series: error_series,
      error_max_val: error_max_val,
      action_invocations: action_invocations,
      action_errors: action_errors,
      time_labels: time_labels,
      x_coords: x_coords,
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
    unadded_slots = available_unadded_slots(overview_widgets, overview_slot_ids)
    widgets_by_slot = Map.new(overview_widgets, fn w -> {"widget:#{w.id}", w} end)

    assigns =
      assigns
      |> assign(:total_actions, total_actions)
      |> assign(:overview_widgets, overview_widgets)
      |> assign(:overview_slot_ids, overview_slot_ids)
      |> assign(:unadded_slots, unadded_slots)
      |> assign(:widgets_by_slot, widgets_by_slot)

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
              </div>
            </div>
          </div>

          <!-- Top Navigation Bar: 1. Overview, 2. Extensions, 3. Pinned Items (fits in one row - 1, circular queue) -->
          <nav id="nav-container" phx-hook="NavCapacity" class="flex-1 min-w-0 mx-1 flex items-center flex-nowrap overflow-x-hidden gap-0.5 bg-gray-100/90 p-0.5 rounded-xl border border-gray-200/80 shadow-inner">
            <!-- 1. Overview Tab (Icon only + tooltip/aria) -->
            <button
              phx-click="switch_tab"
              phx-value-tab="overview"
              aria-label="Overview"
              title="Overview"
              class={"p-1.5 text-xs rounded-lg transition-all font-bold flex items-center justify-center flex-shrink-0 #{if @current_tab == :overview, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
              </svg>
            </button>

            <!-- 2. Extensions Menu Tab (Icon only + badge + tooltip/aria) -->
            <button
              phx-click="switch_tab"
              phx-value-tab="apps"
              aria-label="Extensions"
              title={"Extensions (#{@overview.plugins_count})"}
              class={"p-1.5 text-xs rounded-lg transition-all font-bold flex items-center justify-center gap-1 flex-shrink-0 #{if @current_tab == :apps, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
              <span class="text-[9px] px-1 py-0.2 rounded-full bg-primary-100 text-primary-800 font-black">
                <%= @overview.plugins_count %>
              </span>
            </button>

            <!-- Separator between main tabs and pinned items -->
            <%= if length(@pinned_extensions) > 0 do %>
              <div class="h-4 w-px bg-gray-300/80 mx-0.5 flex-shrink-0"></div>
            <% end %>

            <!-- 3a. Pinned dropdown (small screens) -->
            <%= if length(@pinned_extensions) > 0 do %>
              <div class="relative md:hidden flex-shrink-0">
                <button
                  type="button"
                  phx-click="toggle_pinned_menu"
                  class="px-2 py-1 text-xs rounded-lg font-bold flex items-center justify-center gap-1.5 text-gray-600 hover:text-gray-900 hover:bg-gray-200/50"
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
                          class={"w-full text-left px-2.5 py-1.5 rounded-lg text-xs font-bold flex items-center gap-2 #{if to_string(@current_tab) == ext_id, do: "bg-primary-50 text-primary-700", else: "text-gray-700 hover:bg-gray-100"}"}
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
                <div class={"group relative hidden md:inline-flex items-center justify-center rounded-lg transition-all text-xs font-bold whitespace-nowrap flex-shrink-0 #{if is_active, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-200/50"}"}>
                  <button
                    phx-click="switch_tab"
                    phx-value-tab={ext_id}
                    class="px-2.5 py-1 flex items-center justify-center gap-1 group-hover:pr-5 transition-all"
                  >
                    <span class="text-xs leading-none"><%= icon %></span>
                    <span class="leading-none"><%= title %></span>
                  </button>
                  <button
                    type="button"
                    phx-click="unpin_extension"
                    phx-value-id={ext_id}
                    title={"Unpin #{title} from top bar"}
                    class="absolute right-1 text-gray-400 hover:text-red-500 font-bold text-[10px] transition-opacity opacity-0 group-hover:opacity-100 p-0.5 flex items-center justify-center"
                  >
                    ✕
                  </button>
                </div>
              <% end %>
            <% end %>

            <!-- 3c. Active Unpinned Extension Breadcrumb -->
            <%= if to_string(@current_tab) not in ["overview", "apps"] and to_string(@current_tab) not in @pinned_extensions do %>
              <% active_unpinned = Enum.find(@overview.extensions, fn e -> to_string(e.id) == to_string(@current_tab) end) %>
              <%= if active_unpinned do %>
                <% title = tab_short_name(active_unpinned) %>
                <% icon = if is_map(active_unpinned.dashboard_view) and active_unpinned.dashboard_view[:icon], do: active_unpinned.dashboard_view[:icon], else: ExtensionPresenter.icon(active_unpinned) %>
                <div class="h-4 w-px bg-gray-300/80 mx-0.5 flex-shrink-0"></div>
                <div class="flex items-center justify-center rounded-lg text-xs font-bold whitespace-nowrap flex-shrink-0 bg-white text-primary-700 shadow-sm px-2.5 py-1 gap-1">
                  <span class="text-xs leading-none"><%= icon %></span>
                  <span class="leading-none"><%= title %></span>
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
              class={"w-9 h-9 rounded-xl flex items-center justify-center transition-all text-sm border #{if @settings_open, do: "bg-white text-primary-700 border-primary-300 shadow-sm font-bold ring-2 ring-primary-500/20", else: "bg-gray-100 hover:bg-gray-200/80 text-gray-600 border-gray-200/60"}"}
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

      <!-- Floating Toast Notifications (completely outside document flow to avoid layout shifts) -->
      <div id="studio-toasts" class="fixed top-4 right-4 z-[100] flex flex-col gap-2 pointer-events-none max-w-sm w-full">
        <%= for {kind, msg} <- [{:info, Phoenix.Flash.get(@flash, :info)}, {:error, Phoenix.Flash.get(@flash, :error)}], msg do %>
          <div
            phx-click="dismiss_toast"
            phx-value-kind={kind}
            role="alert"
            title="Click to dismiss"
            class={"relative overflow-hidden pointer-events-auto p-3.5 rounded-xl text-xs font-bold flex items-center gap-3 shadow-xl cursor-pointer select-none transition-transform hover:scale-[1.02] active:scale-[0.98] #{if kind == :info, do: "bg-emerald-600 text-white shadow-emerald-900/20", else: "bg-red-600 text-white shadow-red-900/20"}"}
          >
            <span class="text-sm font-black pointer-events-none"><%= if kind == :info, do: "✓", else: "!" %></span>
            <span class="flex-1 leading-snug pointer-events-none"><%= msg %></span>
            <button
              type="button"
              class="opacity-80 hover:opacity-100 text-base font-black leading-none p-1 pointer-events-none"
              title="Dismiss"
            >
              &times;
            </button>
            <div class="toast-progress-bar"></div>
          </div>
        <% end %>
      </div>

      <!-- Main Workspace Area -->
      <main class="flex-1 max-w-7xl w-full mx-auto p-4 sm:p-6 lg:p-8 space-y-8">

        <!-- OVERVIEW TAB: 4-Slot Rearrangeable Grid -->
        <%= if @current_tab == :overview do %>
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm">
            <div>
              <h2 class="text-xl font-bold text-gray-900 flex items-center gap-2">
                <span>📊</span>
                <span>Project Overview</span>
              </h2>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
              <%= if @grid_edit_mode do %>
                <%= if @unadded_slots != [] do %>
                  <div class="flex items-center gap-1.5 flex-wrap">
                    <%= for missing_id <- @unadded_slots do %>
                      <button
                        type="button"
                        phx-click="add_overview_slot"
                        phx-value-id={missing_id}
                        class="px-2.5 py-1 text-[11px] font-bold text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 rounded-xl transition-colors shadow-xs flex items-center gap-1"
                        title={"Add #{slot_title(missing_id)} back to grid"}
                      >
                        <span>+ Add</span>
                        <span><%= slot_title(missing_id) %></span>
                      </button>
                    <% end %>
                  </div>
                <% end %>
                <%= if @overview_grid_order != [] do %>
                  <button
                    type="button"
                    phx-click="reset_overview_grid"
                    class="px-2.5 py-1.5 text-[11px] font-bold text-gray-600 hover:text-red-600 bg-white hover:bg-red-50 border border-gray-200 rounded-xl transition-colors shadow-xs"
                  >
                    ↺ Reset Grid
                  </button>
                <% end %>
                <button
                  type="button"
                  phx-click="toggle_grid_edit_mode"
                  class="px-3 py-1.5 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 rounded-xl transition-colors shadow-xs flex items-center gap-1.5"
                >
                  <span>✓ Done Editing</span>
                </button>
              <% else %>
                <button
                  type="button"
                  phx-click="toggle_grid_edit_mode"
                  class="px-3 py-1.5 text-xs font-bold text-gray-700 hover:text-gray-900 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-xl transition-colors shadow-xs flex items-center gap-1.5"
                >
                  <span>✎ Edit Grid Order</span>
                </button>
              <% end %>
            </div>
          </div>

          <div id="overview-bento-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 auto-rows-min [grid-auto-flow:dense]">
            <%= for {slot_id, idx} <- Enum.with_index(@overview_slot_ids) do %>
              <%= case slot_id do %>
                <% "quickstart" -> %>
                  <!-- 1x4 QUICKSTART GUIDE BANNER (GRID ELEMENT) -->
                  <div
                    id="slot-quickstart"
                    data-slot-id="quickstart"
                    data-slot-span="1x4"
                    class={"col-span-1 md:col-span-2 lg:col-span-4 bg-gradient-to-r from-primary-950 via-primary-900 to-indigo-950 rounded-2xl p-6 text-white shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4 border #{if @grid_edit_mode, do: "border-primary-400 ring-2 ring-primary-500/20", else: "border-primary-500/30"}"}
                  >
                    <div class="space-y-1.5 flex-1 min-w-0">
                      <div class="flex items-center gap-2">
                        <span class="text-[10px] px-2 py-0.5 rounded-full bg-primary-500/30 text-primary-200 border border-primary-400/30 font-bold uppercase tracking-wider">Quickstart Flow</span>
                        <span class="font-bold text-sm">New to Exoforge? Complete Developer Guide &amp; API Reference</span>
                        <%= if @grid_edit_mode do %>
                          <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-white/20 text-white rounded-md border border-white/20">1×4</span>
                        <% end %>
                      </div>
                      <p class="text-xs text-primary-200/90 leading-relaxed max-w-2xl">
                        Master the complete development flow: Connect &amp; Auth ➔ Scaffold Extension ➔ Hot-Deploy ➔ Sync Stubs ➔ Call from Unity.
                      </p>
                    </div>

                    <div class="flex items-center gap-2 self-start md:self-auto shrink-0">
                      <%= if @grid_edit_mode do %>
                        <div class="flex items-center gap-1 bg-white/10 p-1 rounded-xl border border-white/10 mr-2">
                          <button
                            type="button"
                            phx-click="move_overview_slot"
                            phx-value-id="quickstart"
                            phx-value-dir="prev"
                            disabled={idx == 0}
                            title="Move slot left"
                            class="w-6 h-6 rounded-lg border border-white/20 text-white hover:bg-white/20 disabled:opacity-30 flex items-center justify-center text-xs"
                          >
                            &larr;
                          </button>
                          <button
                            type="button"
                            phx-click="move_overview_slot"
                            phx-value-id="quickstart"
                            phx-value-dir="next"
                            disabled={idx == length(@overview_slot_ids) - 1}
                            title="Move slot right"
                            class="w-6 h-6 rounded-lg border border-white/20 text-white hover:bg-white/20 disabled:opacity-30 flex items-center justify-center text-xs"
                          >
                            &rarr;
                          </button>
                          <button
                            type="button"
                            phx-click="remove_overview_slot"
                            phx-value-id="quickstart"
                            title="Remove Quickstart from grid"
                            class="w-6 h-6 rounded-lg border border-red-400 text-red-200 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                          >
                            ✕
                          </button>
                        </div>
                      <% end %>

                      <button
                        type="button"
                        phx-click="switch_tab"
                        phx-value-tab="exoforge_std_docs"
                        class="px-4 py-2 bg-white text-primary-900 hover:bg-primary-50 font-bold text-xs rounded-xl shadow-xs transition-colors flex items-center gap-1.5 whitespace-nowrap"
                      >
                        <span>📖 Open Quickstart Guide</span>
                        <span>→</span>
                      </button>
                    </div>
                  </div>
                <% "event_graph" -> %>
                  <!-- 2x2 EVENT & ACTION GRAPH -->
                  <div
                    id="slot-event_graph"
                    data-slot-id="event_graph"
                    data-slot-span="2x2"
                    class={"lg:col-span-2 lg:row-span-2 bg-white p-6 rounded-2xl border shadow-card flex flex-col space-y-4 #{if @grid_edit_mode, do: "border-primary-400 ring-2 ring-primary-500/20", else: "border-gray-200"}"}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="flex items-center gap-2">
                          <span class="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse"></span>
                          <h3 class="font-bold text-gray-900 text-sm">Event &amp; Action Throughput</h3>
                          <%= if @grid_edit_mode do %>
                            <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-purple-50 text-purple-700 rounded-md border border-purple-200">2×2</span>
                          <% end %>
                        </div>
                        <p class="text-xs text-gray-400 mt-0.5">Real-time EventDispatcher pub/sub and service invocations</p>
                      </div>
                      <div class="flex items-center gap-1.5">
                        <button
                          type="button"
                          phx-click="open_actions_detail_modal"
                          phx-value-mode="actions"
                          class="px-2.5 py-1.5 text-xs font-bold text-gray-700 hover:text-gray-900 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-lg shadow-xs transition-colors flex items-center gap-1 cursor-pointer"
                          title="Expand actions telemetry details"
                        >
                          <span>⤢</span>
                          <span>Expand</span>
                        </button>
                        <%= if @grid_edit_mode do %>
                          <div class="flex items-center gap-1 pl-1 border-l border-gray-200">
                            <button
                              type="button"
                              phx-click="move_overview_slot"
                              phx-value-id="event_graph"
                              phx-value-dir="prev"
                              disabled={idx == 0}
                              title="Move slot left"
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
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
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
                            >
                              &rarr;
                            </button>
                            <button
                              type="button"
                              phx-click="remove_overview_slot"
                              phx-value-id="event_graph"
                              title="Remove card from grid"
                              class="w-6 h-6 rounded-lg border border-red-200 text-red-500 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                            >
                              ✕
                            </button>
                          </div>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex items-baseline gap-3">
                      <span class="text-3xl font-black text-gray-900 tracking-tight"><%= @telemetry.total_invocations %></span>
                      <span class="text-xs font-semibold text-gray-500 bg-gray-100 px-2.5 py-0.5 rounded-full font-mono">
                        action calls
                      </span>
                    </div>

                    <!-- Time-Series Multi-Line SVG Chart -->
                    <div class="w-full flex-1 flex flex-col justify-between space-y-2">
                      <div class="w-full bg-gray-50/50 rounded-xl p-2 border border-gray-100">
                        <svg viewBox="0 0 500 155" class="w-full h-36 overflow-visible">
                          <!-- Grid horizontal lines & Y-axis labels -->
                          <line x1="40" y1="30" x2="480" y2="30" stroke="#f1f5f9" stroke-width="1" stroke-dasharray="3 3" />
                          <text x="34" y="33" text-anchor="end" font-size="9" font-family="monospace" fill="#94a3b8"><%= @telemetry.action_max_val %></text>

                          <line x1="40" y1="77" x2="480" y2="77" stroke="#f1f5f9" stroke-width="1" stroke-dasharray="3 3" />
                          <text x="34" y="80" text-anchor="end" font-size="9" font-family="monospace" fill="#94a3b8"><%= round(@telemetry.action_max_val / 2) %></text>

                          <line x1="40" y1="125" x2="480" y2="125" stroke="#e2e8f0" stroke-width="1.5" />
                          <text x="34" y="128" text-anchor="end" font-size="9" font-family="monospace" fill="#94a3b8">0</text>

                          <!-- X-axis ticks & Time labels -->
                          <%= for {lbl, x} <- Enum.zip(@telemetry.time_labels, @telemetry.x_coords) do %>
                            <line x1={x} y1="125" x2={x} y2="129" stroke="#cbd5e1" stroke-width="1" />
                            <text x={x} y="142" text-anchor="middle" font-size="9" font-family="monospace" fill="#94a3b8"><%= lbl %></text>
                          <% end %>

                          <!-- Multi-lines for each Action ID -->
                          <%= for s <- @telemetry.action_series do %>
                            <polyline
                              fill="none"
                              stroke={s.color}
                              stroke-width="2.5"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              points={s.points}
                            />
                            <%= for d <- s.dots do %>
                              <circle cx={d.x} cy={d.y} r="3" fill={s.color} stroke="#ffffff" stroke-width="1" />
                            <% end %>
                          <% end %>
                        </svg>
                      </div>

                      <!-- Action Lines Color Legend -->
                      <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 pt-1 text-[11px]">
                        <%= for s <- @telemetry.action_series do %>
                          <div class="flex items-center gap-1.5">
                            <span class="w-2.5 h-2.5 rounded-full shrink-0 shadow-2xs" style={"background-color: #{s.color}"}></span>
                            <span class="font-mono text-gray-700 font-semibold"><%= if s.id == "idle", do: "Cluster Idle", else: s.id %></span>
                            <span class="text-gray-400 font-mono text-[10px]">(<%= s.latest_count %> <%= if s.id == "idle", do: "calls", else: "calls" %>)</span>
                          </div>
                        <% end %>
                      </div>
                    </div>

                    <!-- Recent Dispatched Event with Live Stream Event Count and "More" Modal Button -->
                    <div class="space-y-2 pt-2 border-t border-gray-100">
                      <div class="flex items-center justify-between">
                        <div class="text-[10px] font-bold uppercase tracking-wider text-gray-500 flex items-center gap-1.5">
                          <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
                          <span>Live Stream Events (<%= length(@activity_events) %>)</span>
                        </div>
                        <button
                          type="button"
                          phx-click="open_events_modal"
                          class="font-bold text-primary-600 hover:text-primary-500 text-[11px] transition-colors cursor-pointer"
                          title="Open events history modal"
                        >
                          More &rarr;
                        </button>
                      </div>

                      <% latest_ev = List.first(@activity_events) %>
                      <%= if is_nil(latest_ev) do %>
                        <div class="p-3 rounded-xl bg-gray-50 border border-gray-100 text-xs text-gray-400 text-center">
                          Waiting for cluster events on EventDispatcher...
                        </div>
                      <% else %>
                        <% is_highlighted = (@highlight_event_id != nil and @highlight_event_id == latest_ev[:id]) %>
                        <div class={"flex items-center justify-between px-3 py-2 rounded-xl text-xs transition-all duration-300 group border #{if is_highlighted, do: "event-flash-highlight bg-primary-50/90 border-primary-400 ring-2 ring-primary-400/30 text-primary-900 shadow-sm", else: "bg-gray-50 hover:bg-gray-100 border-gray-200 text-gray-900"}"}>
                          <div class="flex items-center gap-2 min-w-0">
                            <span class={"w-2 h-2 rounded-full shrink-0 #{if is_highlighted, do: "bg-primary-500 animate-ping", else: (if String.starts_with?(to_string(latest_ev.event), "action:"), do: "bg-blue-500", else: "bg-emerald-500 animate-pulse")}"}></span>
                            <span class="font-mono font-bold truncate">📡 <%= latest_ev.event %></span>
                            <%= if is_map(latest_ev[:payload]) and map_size(latest_ev.payload) > 0 do %>
                              <span class={"text-[11px] font-mono truncate hidden sm:inline #{if is_highlighted, do: "text-primary-700", else: "text-gray-400"}"}>
                                <%= if latest_ev.payload[:status], do: "#{latest_ev.payload.status} • #{latest_ev.payload[:latency_ms] || 0}ms", else: (latest_ev.payload |> Map.keys() |> Enum.take(3) |> Enum.join(", ")) %>
                              </span>
                            <% end %>
                          </div>
                          <div class={"flex items-center gap-2 shrink-0 text-[10px] font-mono ml-2 #{if is_highlighted, do: "text-primary-700 font-bold", else: "text-gray-400"}"}>
                            <span><%= latest_ev.time %></span>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>

                <% "error_graph" -> %>
                  <!-- 2x2 ERROR GRAPH -->
                  <% non_zero_errors = Enum.filter(@telemetry.error_series, &(&1.latest_count > 0)) %>
                  <div
                    id="slot-error_graph"
                    data-slot-id="error_graph"
                    data-slot-span="2x2"
                    class={"lg:col-span-2 lg:row-span-2 bg-white p-6 rounded-2xl border shadow-card flex flex-col space-y-4 #{if @grid_edit_mode, do: "border-primary-400 ring-2 ring-primary-500/20", else: "border-gray-200"}"}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="flex items-center gap-2">
                          <span class={"w-2.5 h-2.5 rounded-full #{if @telemetry.total_errors > 0, do: "bg-red-500 animate-ping", else: "bg-emerald-500"}"}></span>
                          <h3 class="font-bold text-gray-900 text-sm">Error &amp; Exception Graph</h3>
                          <%= if @grid_edit_mode do %>
                            <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-gray-100 text-gray-600 rounded-md border border-gray-200">2×2</span>
                          <% end %>
                        </div>
                        <p class="text-xs text-gray-400 mt-0.5">Action dispatch failures, crashes, and rate-limit spikes by service</p>
                      </div>
                      <div class="flex items-center gap-1.5">
                        <button
                          type="button"
                          phx-click="open_actions_detail_modal"
                          phx-value-mode="errors"
                          class="px-2.5 py-1.5 text-xs font-bold text-gray-700 hover:text-gray-900 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-lg shadow-xs transition-colors flex items-center gap-1 cursor-pointer"
                          title="Expand error breakdown details"
                        >
                          <span>⤢</span>
                          <span>Expand</span>
                        </button>
                        <%= if @grid_edit_mode do %>
                          <div class="flex items-center gap-1 pl-1 border-l border-gray-200">
                            <button
                              type="button"
                              phx-click="move_overview_slot"
                              phx-value-id="error_graph"
                              phx-value-dir="prev"
                              disabled={idx == 0}
                              title="Move slot left"
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
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
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
                            >
                              &rarr;
                            </button>
                            <button
                              type="button"
                              phx-click="remove_overview_slot"
                              phx-value-id="error_graph"
                              title="Remove card from grid"
                              class="w-6 h-6 rounded-lg border border-red-200 text-red-500 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                            >
                              ✕
                            </button>
                          </div>
                        <% end %>
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

                    <!-- Error Multi-Line SVG Chart -->
                    <div class="w-full flex-1 flex flex-col justify-between space-y-2">
                      <div class="w-full bg-gray-50/50 rounded-xl p-2 border border-gray-100">
                        <svg viewBox="0 0 500 155" class="w-full h-36 overflow-visible">
                          <!-- Grid horizontal lines & Y-axis labels -->
                          <line x1="40" y1="30" x2="480" y2="30" stroke="#f1f5f9" stroke-width="1" stroke-dasharray="3 3" />
                          <text x="34" y="33" text-anchor="end" font-size="9" font-family="monospace" fill="#94a3b8"><%= @telemetry.error_max_val %></text>

                          <line x1="40" y1="77" x2="480" y2="77" stroke="#f1f5f9" stroke-width="1" stroke-dasharray="3 3" />
                          <text x="34" y="80" text-anchor="end" font-size="9" font-family="monospace" fill="#94a3b8"><%= round(@telemetry.error_max_val / 2) %></text>

                          <line x1="40" y1="125" x2="480" y2="125" stroke="#e2e8f0" stroke-width="1.5" />
                          <text x="34" y="128" text-anchor="end" font-size="9" font-family="monospace" fill="#94a3b8">0</text>

                          <!-- X-axis ticks & Time labels -->
                          <%= for {lbl, x} <- Enum.zip(@telemetry.time_labels, @telemetry.x_coords) do %>
                            <line x1={x} y1="125" x2={x} y2="129" stroke="#cbd5e1" stroke-width="1" />
                            <text x={x} y="142" text-anchor="middle" font-size="9" font-family="monospace" fill="#94a3b8"><%= lbl %></text>
                          <% end %>

                          <!-- Multi-lines for each Action Error series (Only series with >0 errors) -->
                          <%= for s <- non_zero_errors do %>
                            <polyline
                              fill="none"
                              stroke={s.color}
                              stroke-width="2.5"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              points={s.points}
                            />
                            <%= for d <- s.dots do %>
                              <circle cx={d.x} cy={d.y} r="3" fill={s.color} stroke="#ffffff" stroke-width="1" />
                            <% end %>
                          <% end %>
                        </svg>
                      </div>

                      <!-- Error Lines Color Legend (Only actions with >0 errors, hides 0 error labels) -->
                      <%= if non_zero_errors != [] do %>
                        <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 pt-1 text-[11px]">
                          <%= for s <- non_zero_errors do %>
                            <div class="flex items-center gap-1.5">
                              <span class="w-2.5 h-2.5 rounded-full shrink-0 shadow-2xs" style={"background-color: #{s.color}"}></span>
                              <span class="font-mono text-gray-700 font-semibold"><%= s.id %></span>
                              <span class="font-mono text-[10px] text-red-600 font-bold">(<%= s.latest_count %> errors)</span>
                            </div>
                          <% end %>
                        </div>
                      <% else %>
                        <div class="flex items-center gap-2 pt-1 text-xs text-emerald-600 font-semibold">
                          <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
                          <span>Zero errors detected across all monitored actions</span>
                        </div>
                      <% end %>
                    </div>

                    <!-- Structured Footer to Match Event Graph Bottom Section -->
                    <div class="space-y-2 pt-2 border-t border-gray-100">
                      <div class="flex items-center justify-between">
                        <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400 flex items-center gap-1.5">
                          <span class={"w-1.5 h-1.5 rounded-full #{if @telemetry.total_errors > 0, do: "bg-red-500", else: "bg-emerald-500"}"}></span>
                          <span>Cluster Health Status</span>
                        </div>
                        <span class={"px-2 py-0.5 text-[10px] font-bold rounded-md border #{if @telemetry.total_errors > 0, do: "text-red-700 bg-red-50 border-red-200", else: "text-emerald-700 bg-emerald-50 border-emerald-200"}"}>
                          <%= if @telemetry.total_errors > 0, do: "Action Exceptions Present", else: "All Systems Normal" %>
                        </span>
                      </div>

                      <div class="flex items-center justify-between px-3 py-2 rounded-xl bg-gray-50 border border-gray-200 text-xs">
                        <span class="text-gray-500">Monitored Callable Actions</span>
                        <span class="font-mono font-bold text-gray-900"><%= @total_actions %> actions across <%= @overview.plugins_count %> extensions</span>
                      </div>
                    </div>
                  </div>

                <% "server_state" -> %>
                  <!-- 1x1 SERVER STATE INDICATOR -->
                  <div
                    id="slot-server_state"
                    data-slot-id="server_state"
                    data-slot-span="1x1"
                    class={"lg:col-span-1 bg-white p-5 rounded-2xl border shadow-card flex flex-col justify-between space-y-4 #{if @grid_edit_mode, do: "border-primary-400 ring-2 ring-primary-500/20", else: "border-gray-200"}"}
                  >
                    <div class="flex items-start justify-between gap-2">
                      <div class="flex items-center gap-2">
                        <span class="w-8 h-8 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center text-sm font-bold border border-emerald-200">
                          🟢
                        </span>
                        <div>
                          <h3 class="font-bold text-gray-900 text-xs uppercase tracking-wider">Server State</h3>
                          <%= if @grid_edit_mode do %>
                            <span class="text-[10px] font-mono text-gray-400">1×1 Indicator</span>
                          <% end %>
                        </div>
                      </div>
                      <%= if @grid_edit_mode do %>
                        <div class="flex items-center gap-1">
                          <button
                            type="button"
                            phx-click="move_overview_slot"
                            phx-value-id="server_state"
                            phx-value-dir="prev"
                            disabled={idx == 0}
                            title="Move slot left"
                            class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
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
                            class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
                          >
                            &rarr;
                          </button>
                          <button
                            type="button"
                            phx-click="remove_overview_slot"
                            phx-value-id="server_state"
                            title="Remove card from grid"
                            class="w-6 h-6 rounded-lg border border-red-200 text-red-500 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                          >
                            ✕
                          </button>
                        </div>
                      <% end %>
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
                      <span>Extensions: <strong class="text-primary-700"><%= @overview.plugins_count %></strong></span>
                    </div>
                  </div>

                <% "extension_health" -> %>
                  <!-- 2x1 ONLINE / FAULTY EXTENSION COUNTER -->
                  <div
                    id="slot-extension_health"
                    data-slot-id="extension_health"
                    data-slot-span="2x1"
                    class={"lg:col-span-2 bg-white p-5 rounded-2xl border shadow-card flex flex-col justify-between space-y-4 #{if @grid_edit_mode, do: "border-primary-400 ring-2 ring-primary-500/20", else: if(@telemetry.faulty_count > 0, do: "border-amber-300", else: "border-gray-200")}"}
                  >
                    <div class="flex items-start justify-between gap-2">
                      <div>
                        <div class="flex items-center gap-2">
                          <h3 class="font-bold text-gray-900 text-sm">Online / Faulty Extensions</h3>
                          <%= if @grid_edit_mode do %>
                            <span class="px-2 py-0.5 text-[10px] font-mono font-bold bg-gray-100 text-gray-600 rounded-md border border-gray-200">2×1</span>
                          <% end %>
                        </div>
                        <p class="text-xs text-gray-400 mt-0.5">Monitors extension processes for recent crashes or infinite loops</p>
                      </div>
                      <div class="flex items-center gap-1.5">
                        <button
                          type="button"
                          phx-click="switch_tab"
                          phx-value-tab="apps"
                          class="px-2.5 py-1 text-[11px] font-bold text-primary-700 hover:text-primary-800 bg-primary-50 hover:bg-primary-100 rounded-lg transition-colors"
                        >
                          Manage &rarr;
                        </button>
                        <%= if @grid_edit_mode do %>
                          <div class="flex items-center gap-1 pl-1 border-l border-gray-200">
                            <button
                              type="button"
                              phx-click="move_overview_slot"
                              phx-value-id="extension_health"
                              phx-value-dir="prev"
                              disabled={idx == 0}
                              title="Move slot left"
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
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
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
                            >
                              &rarr;
                            </button>
                            <button
                              type="button"
                              phx-click="remove_overview_slot"
                              phx-value-id="extension_health"
                              title="Remove card from grid"
                              class="w-6 h-6 rounded-lg border border-red-200 text-red-500 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                            >
                              ✕
                            </button>
                          </div>
                        <% end %>
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
                    class={"lg:col-span-1 bg-gradient-to-br from-purple-600 to-indigo-700 text-white p-5 rounded-2xl border shadow-lg flex flex-col justify-between space-y-4 #{if @grid_edit_mode, do: "border-white ring-2 ring-white/40", else: "border-purple-500"}"}
                  >
                    <div class="flex items-start justify-between gap-2">
                      <div class="flex items-center gap-2">
                        <span class="w-8 h-8 rounded-xl bg-white/15 backdrop-blur flex items-center justify-center text-base">
                          📦
                        </span>
                        <div>
                          <h3 class="font-bold text-white text-xs uppercase tracking-wider">Client SDKs</h3>
                          <%= if @grid_edit_mode do %>
                            <span class="text-[10px] font-mono text-purple-200">1×1 Action</span>
                          <% end %>
                        </div>
                      </div>
                      <%= if @grid_edit_mode do %>
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
                          <button
                            type="button"
                            phx-click="remove_overview_slot"
                            phx-value-id="download_sdk"
                            title="Remove card from grid"
                            class="w-6 h-6 rounded-lg border border-red-300 text-red-200 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                          >
                            ✕
                          </button>
                        </div>
                      <% end %>
                    </div>

                    <div>
                      <p class="text-sm font-extrabold text-white leading-snug">Unity &amp; C# SDK Packages</p>
                      <p class="text-[11px] text-purple-100 mt-1">Download client libraries, UPM tarballs, and setup guides.</p>
                    </div>

                    <button
                      type="button"
                      phx-click="open_sdk_modal"
                      class="w-full py-2.5 px-4 rounded-xl bg-white text-purple-700 hover:bg-purple-50 font-black text-xs shadow-sm transition-all flex items-center justify-center gap-2 cursor-pointer"
                    >
                      <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="7 10 12 15 17 10"></polyline>
                        <line x1="12" y1="15" x2="12" y2="3"></line>
                      </svg>
                      <span>Download SDK</span>
                    </button>
                  </div>

                <% "widget:" <> _ -> %>
                  <% widget = Map.get(@widgets_by_slot, slot_id) %>
                  <%= if widget do %>
                    <div
                      id={"slot-#{slot_id}"}
                      data-slot-id={slot_id}
                      class={"bg-white p-6 rounded-2xl border shadow-card space-y-4 #{widget_width_class(widget)} #{if @grid_edit_mode, do: "border-primary-400 ring-2 ring-primary-500/20", else: "border-gray-200"}"}
                    >
                      <div class="flex items-center justify-between gap-2">
                        <div>
                          <h3 class="font-bold text-gray-900 text-sm flex items-center gap-2">
                            <%= if Map.get(widget, :icon) do %>
                              <span><%= widget.icon %></span>
                            <% end %>
                            <span><%= widget.title %></span>
                            <%= if @grid_edit_mode and Map.get(widget, :slot_size) do %>
                              <span class="text-[10px] font-mono text-gray-400"><%= widget.slot_size %></span>
                            <% end %>
                          </h3>
                          <%= if Map.get(widget, :subtitle) do %>
                            <p class="text-xs text-gray-400 mt-0.5"><%= widget.subtitle %></p>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-1">
                          <span class="text-[10px] font-mono text-gray-400 mr-1"><%= Map.get(widget, :plugin_id, "") %></span>
                          <%= if @grid_edit_mode do %>
                            <button
                              type="button"
                              phx-click="move_overview_slot"
                              phx-value-id={slot_id}
                              phx-value-dir="prev"
                              disabled={idx == 0}
                              title="Move slot left"
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
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
                              class="w-6 h-6 rounded-lg border border-gray-200 text-gray-500 hover:text-gray-900 hover:bg-gray-100 disabled:opacity-30 flex items-center justify-center text-xs"
                            >
                              &rarr;
                            </button>
                            <button
                              type="button"
                              phx-click="remove_overview_slot"
                              phx-value-id={slot_id}
                              title="Remove card from grid"
                              class="w-6 h-6 rounded-lg border border-red-200 text-red-500 hover:text-white hover:bg-red-600 flex items-center justify-center text-xs font-bold transition-colors"
                            >
                              ✕
                            </button>
                          <% end %>
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
                  action_catalog={@action_catalog}
                  extensions={@overview.extensions}
                  project_name={@project_name}
                  studio_name={@studio_name}
                  guide_subpage={@guide_subpage}
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
        Exoforge v<%= @build_version %> (<%= @build_hash %>) • Built <%= @build_date %>
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
        project_metadata={@project_metadata}
        settings_tab={@settings_tab}
        settings_hooks={@settings_hooks}
        cors_config={@cors_config}
        overview={@overview}
        node_name={to_string(node())}
        activity_events={@filtered_activity_events}
        events_paused={@events_paused}
        event_filter_topic={@event_filter_topic}
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

      <!-- Actions Telemetry Detail Modal -->
      <.actions_detail_modal
        open={@actions_detail_modal != nil}
        mode={@actions_detail_modal || "actions"}
        search={@actions_detail_search}
        filter_tab={@actions_detail_tab}
        catalog={@action_catalog}
        telemetry={@telemetry}
        on_close="close_actions_detail_modal"
        on_search="search_actions_detail"
        on_filter_tab="filter_actions_detail_tab"
        on_run_action="open_action_modal"
        on_switch_mode="open_actions_detail_modal"
      />

      <!-- Cluster Events Stream Modal -->
      <.events_modal
        open={@events_modal_open}
        events={@filtered_activity_events}
        paused={@events_paused}
        filter_topic={@event_filter_topic}
        on_close="close_events_modal"
        on_pause="toggle_event_pause"
        on_clear="clear_events"
        on_filter="filter_event_dock"
        on_simulate="simulate_test_event"
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
