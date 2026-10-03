defmodule Exoforge.Std.Dashboard.StudioLive do
  @moduledoc """
  Phoenix LiveView for the Exoforge Game Producer & Designer Studio.
  Fully reactive, server-driven UI decoupled from hardcoded domain elements.
  Extensions provide capabilities and domain visualizations dynamically.
  """
  use Phoenix.LiveView
  import Exoforge.Std.Dashboard.Components
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry

  @max_pinned 8

  @impl true
  def mount(_params, session, socket) do
    player_id = session["admin_player_id"] || session[:admin_player_id] || "studio"

    if connected?(socket) do
      try do
        EventDispatcher.subscribe(:all)
      rescue
        _ -> :ok
      end
    end

    overview = fetch_overview()
    action_catalog = fetch_action_catalog()

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
    default_params = default_params_for(default_action)

    {:ok,
     assign(socket,
       current_tab: :overview,
       project_name: "Exoforge Cluster",
       studio_name: "Producer Studio",
       environments: ["Live", "Dev", "Staging"],
       current_env: "Live",
       max_pinned: @max_pinned,
       overview: overview,
       player_id: player_id,
       pinned_extensions: Exoforge.Std.Dashboard.Preferences.pinned(player_id),
       visualizable_extensions: visualizable_extensions,
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
       event_filter_topic: "",
       extensions_search: "",
       extensions_category: "all",
       active_entities: fetch_active_entities()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab_param = params["tab"]
    pinned_ids = socket.assigns.pinned_extensions

    tab =
      cond do
        tab_param in ["overview", nil] ->
          :overview

        tab_param == "apps" ->
          :apps

        tab_param in pinned_ids ->
          existing_atom(tab_param)

        Enum.any?(socket.assigns.overview.extensions, fn e ->
          to_string(e.id) == tab_param or
              (is_map(e.dashboard_view) and to_string(e.dashboard_view[:id]) == tab_param)
        end) ->
          existing_atom(tab_param)

        true ->
          :overview
      end

    socket =
      if tab == :overview do
        assign(socket, active_entities: fetch_active_entities())
      else
        socket
      end

    {:noreply, assign(socket, :current_tab, tab)}
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("switch_tab", %{"tab" => tab_str}, socket) do
    {:noreply, assign(socket, :current_tab, existing_atom(tab_str))}
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

    socket =
      if to_string(socket.assigns.current_tab) == ext_id_str do
        assign(socket, current_tab: :overview)
      else
        socket
      end

    {:noreply, show_toast(socket, :info, "Unpinned #{ext_id_str} from top bar.")}
  end

  def handle_event("dismiss_toast", %{"kind" => kind}, socket) when kind in ["info", "error"] do
    {:noreply, clear_flash(socket, String.to_existing_atom(kind))}
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

        {:noreply,
         assign(socket, cmd_palette_open: new_open, cmd_query: "", cmd_results: results)}

      key in ["Escape", "Esc"] ->
        {:noreply,
         assign(socket,
           cmd_palette_open: false,
           settings_open: false,
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

  def handle_event("passivate_entity", %{"plugin" => plugin, "type" => type, "id" => id}, socket) do
    plugin_atom =
      Enum.find_value(socket.assigns.active_entities, fn entity ->
        if to_string(entity.plugin) == plugin, do: entity.plugin
      end)

    type_term =
      try do
        String.to_existing_atom(type)
      rescue
        _ -> type
      end

    if (plugin_atom && Code.ensure_loaded?(Exoforge.Entities)) and
         function_exported?(Exoforge.Entities, :stop, 3) do
      Exoforge.Entities.stop(plugin_atom, type_term, id)
    end

    {:noreply,
     socket
     |> assign(:active_entities, fetch_active_entities())
     |> show_toast(:info, "Passivated actor #{plugin}.#{id}")}
  end

  def handle_event("refresh_entities", _params, socket) do
    {:noreply, assign(socket, :active_entities, fetch_active_entities())}
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
        tab =
          cond do
            String.starts_with?(id, "entity:") ->
              :overview

            true ->
              existing_atom(id)
          end

        {:noreply, assign(socket, :current_tab, tab)}

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

  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :settings_open, true)}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, :settings_open, false)}
  end

  def handle_event("set_settings_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :settings_tab, tab)}
  end

  def handle_event("quick_action", %{"action" => action}, socket) do
    handle_quick_action(action, socket)
  end

  # ---- ACTION EXECUTION MODAL ----

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
    svc =
      Enum.find(
        socket.assigns.action_catalog,
        &(&1.name == socket.assigns.selected_action_service)
      )

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

    svc =
      Enum.find(
        socket.assigns.action_catalog,
        &(&1.name == socket.assigns.selected_action_service)
      )

    act = if svc, do: Enum.find(svc.actions, &(&1.name == socket.assigns.selected_action_name))

    if svc && act do
      payload =
        Enum.reduce(act.params, %{}, fn p, acc ->
          val_str = Map.get(updated_params, p.name, "")
          casted = cast_param_value(val_str, p.type)
          Map.put(acc, existing_atom(p.name), casted)
        end)

      scopes =
        caller_scopes_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      scopes = if scopes == [], do: [Exoforge.Auth.Roles.admin()], else: scopes

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
         action_form_params: updated_params,
         caller_scopes: caller_scopes_str
       )}
    else
      {:noreply, show_toast(socket, :error, "Selected service or action not found.")}
    end
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

    EventDispatcher.broadcast(:studio_telemetry, payload)
    {:noreply, show_toast(socket, :info, "Simulated telemetry event ##{ping_id} broadcasted!")}
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

  defp custom_ui?(ext), do: custom_view_module(ext) != nil

  # Category pills are derived from extension metadata; only the icon is presentation.
  defp extension_categories(extensions) do
    categories =
      extensions
      |> Enum.map(&(&1[:category] || "Extension"))
      |> Enum.uniq()
      |> Enum.sort()

    [{"all", "All Extensions", "🌐"}] ++
      Enum.map(categories, fn cat ->
        {String.downcase(to_string(cat)), to_string(cat), category_icon(cat)}
      end)
  end

  defp category_icon(category) do
    case String.downcase(to_string(category)) do
      "storage" -> "🗄️"
      "ingress" -> "🔌"
      "identity" -> "🔐"
      "liveops" -> "👤"
      "gameplay" -> "⚔️"
      "studio" -> "📊"
      _ -> "🧩"
    end
  end

  attr(:ext, :map, required: true)
  attr(:pinned, :boolean, default: false)

  defp extension_card(assigns) do
    ~H"""
    <div class="bg-white p-5 rounded-2xl border border-gray-200/90 hover:border-primary-300 shadow-sm hover:shadow-md transition-all flex flex-col justify-between space-y-4 group">
      <div class="space-y-3">
        <div class="flex items-start justify-between gap-2">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-xl bg-purple-50 text-purple-700 flex items-center justify-center text-xl shadow-xs">
              <%= (is_map(@ext.dashboard_view) && @ext.dashboard_view[:icon]) || default_extension_icon(@ext) %>
            </span>
            <div>
              <h4 class="font-bold text-gray-900 text-sm tracking-tight group-hover:text-primary-700 transition-colors">
                <%= humanize_plugin_name(@ext) %>
              </h4>
              <span class="text-[11px] font-mono text-gray-400"><%= @ext.id %></span>
            </div>
          </div>
          <div class="flex flex-col items-end gap-1">
            <.badge status={to_string(@ext.type)} />
            <%= if custom_ui?(@ext) do %>
              <span
                class="text-[10px] font-bold px-1.5 py-0.2 rounded bg-indigo-50 text-indigo-700 border border-indigo-200"
                title="This extension provides its own custom LiveView"
              >
                ✨ Custom UI
              </span>
            <% end %>
            <span class="text-[10px] font-mono font-semibold px-1.5 py-0.2 rounded bg-gray-100 text-gray-600">
              v<%= to_string(@ext.version) %>
            </span>
          </div>
        </div>

        <div class="flex items-center gap-2 text-[11px] text-gray-600 font-semibold pt-1">
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-md bg-purple-50 text-purple-700">
            <span>⚡</span> <%= @ext.actions_count %> actions
          </span>
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-md bg-blue-50 text-blue-700">
            <span>📦</span> <%= @ext.resources_count %> resources
          </span>
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-md bg-emerald-50 text-emerald-700">
            <span>📡</span> <%= @ext.events_count %> events
          </span>
        </div>

        <div class="space-y-1">
          <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Provides Services:</span>
          <div class="flex flex-wrap gap-1">
            <%= for s <- @ext.provides do %>
              <span class="px-2 py-0.5 rounded-md bg-gray-100 text-gray-800 text-[10px] font-mono font-semibold">
                <%= s %>
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <div class="pt-3 border-t border-gray-100 flex items-center justify-between text-xs">
        <div class="flex items-center gap-1.5">
          <%= if @pinned do %>
            <button
              type="button"
              phx-click="unpin_extension"
              phx-value-id={to_string(@ext.id)}
              class="px-2.5 py-1 text-[11px] font-semibold text-purple-700 bg-purple-50 hover:bg-purple-100 border border-purple-200 rounded-lg flex items-center gap-1 transition-colors"
              title="Unpin from top bar"
            >
              <span>📌</span> <span>Pinned</span>
            </button>
          <% else %>
            <button
              type="button"
              phx-click="pin_extension"
              phx-value-id={to_string(@ext.id)}
              class="px-2.5 py-1 text-[11px] font-semibold text-gray-600 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg flex items-center gap-1 transition-colors"
              title="Pin to top bar"
            >
              <span>📌</span> <span>Pin</span>
            </button>
          <% end %>

          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab={to_string(@ext.id)}
            class="px-3 py-1 text-[11px] font-bold text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors flex items-center gap-1 shadow-xs"
          >
            <span>Open Controls</span>
            <span>&rarr;</span>
          </button>
        </div>

        <%= if @ext.actions_count > 0 do %>
          <button
            type="button"
            phx-click="open_action_modal"
            phx-value-service={List.first(@ext.provides)}
            class="text-gray-500 hover:text-primary-700 font-bold flex items-center gap-1 transition-colors text-[11px]"
            title="Execute action in modal runner"
          >
            <span>⚡ Run</span>
          </button>
        <% end %>
      </div>
    </div>
    """
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
      kernel: "Exoforge Core",
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
            else: default_extension_icon(ext || ext_id)

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
            else: default_extension_icon(ext)

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

    # 5. Active Stateful Entity Actors
    active_ents = socket.assigns[:active_entities] || []

    entity_items =
      Enum.map(active_ents, fn ent ->
        %{
          id: "entity:#{ent.plugin}:#{ent.id}",
          title: "🤖 Actor: #{ent.plugin}.#{ent.id} (#{ent.memory_kb} KB)",
          subtitle: "Stateful Actor • PID #{ent.pid} • Queue: #{ent.queue_len}",
          type: "navigation"
        }
      end)

    base_navs ++
      pinned_navs ++ extra_ext_navs ++ entity_items ++ tool_items ++ rpc_items ++ resource_items
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

  defp default_extension_icon(ext_or_id) do
    case ext_or_id do
      %{dashboard_view: %{icon: icon}} when is_binary(icon) -> icon
      _ -> "🧩"
    end
  end

  defp humanize_plugin_name(ext_or_id) do
    case ext_or_id do
      %{dashboard_view: %{title: title}} when is_binary(title) -> title
      %{name: name} -> derive_display_name(name)
      other -> derive_display_name(other)
    end
  end

  defp tab_short_name(ext) do
    if is_map(ext.dashboard_view) and ext.dashboard_view[:title] do
      ext.dashboard_view[:title]
    else
      derive_display_name(ext.id)
    end
  end

  defp derive_display_name(id) do
    id
    |> to_string()
    |> String.replace_prefix("exoforge_std_", "")
    |> String.replace_prefix("Elixir.Exoforge.", "")
    |> String.replace_prefix("Std.Services.", "")
    |> String.replace("_", " ")
    |> Macro.camelize()
  end

  # Resolves a custom LiveView/LiveComponent for an extension: an explicit `:module` in its
  # dashboard_view, dynamic lookup via `:dashboard_view` service contract, or conventional module.
  defp custom_view_module(ext) do
    dv = ext.dashboard_view

    cond do
      is_map(dv) and is_atom(dv[:module]) and Code.ensure_loaded?(dv[:module]) ->
        dv[:module]

      is_map(dv) and not is_nil(dv[:id]) ->
        case Exoforge.ActionDispatcher.dispatch(:dashboard_view, :resolve_view, %{id: dv[:id]}) do
          {:ok, %{module: mod}} when is_atom(mod) and not is_nil(mod) ->
            if Code.ensure_loaded?(mod), do: mod, else: nil

          _ ->
            mod =
              Module.concat([
                Exoforge.Std.DashboardViews,
                Macro.camelize(to_string(dv[:id])) <> "View"
              ])

            if Code.ensure_loaded?(mod), do: mod, else: nil
        end

      true ->
        nil
    end
  end

  defp filter_extensions(extensions, query, category) do
    q = String.downcase(String.trim(query || ""))

    extensions
    |> Enum.filter(fn ext ->
      cat_match =
        case category do
          "all" -> true
          cat -> String.downcase(to_string(ext[:category] || "")) == String.downcase(cat)
        end

      query_match =
        if q == "" do
          true
        else
          String.contains?(String.downcase(to_string(ext.name)), q) or
            String.contains?(String.downcase(to_string(ext.id)), q) or
            Enum.any?(ext.provides || [], &String.contains?(String.downcase(to_string(&1)), q))
        end

      cat_match and query_match
    end)
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
      |> Enum.filter(
        &(Code.ensure_loaded?(&1) and function_exported?(&1, :__service_metadata__, 0))
      )
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
            params = PluginRegistry.normalize_action_params(raw_params)

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

  defp existing_atom(value) when is_atom(value), do: value

  defp existing_atom(value) do
    String.to_existing_atom(to_string(value))
  rescue
    ArgumentError -> value
  end

  defp fetch_active_entities do
    if Code.ensure_loaded?(Exoforge.Entities) and
         function_exported?(Exoforge.Entities, :list_active, 0) do
      try do
        Exoforge.Entities.list_active()
      rescue
        _ -> []
      end
    else
      []
    end
  end

  # ---- TEMPLATE RENDER ----

  @impl true
  def render(assigns) do
    total_actions =
      Enum.sum(Enum.map(assigns.action_catalog, fn svc -> length(svc.actions) end))

    assigns = assign(assigns, :total_actions, total_actions)

    ~H"""
    <div class="min-h-screen flex flex-col" phx-window-keydown="handle_key">
      <!-- Exoforge Shell Header -->
      <header class="sticky top-0 z-40 bg-white/95 backdrop-blur border-b border-gray-200 px-4 lg:px-8 py-2.5 transition-shadow">
        <div class="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-y-2 gap-x-4">
          <!-- Brand & Environment Switcher -->
          <div class="flex items-center gap-2.5 flex-shrink-0">
            <div class="w-8 h-8 rounded-xl bg-gradient-to-br from-primary-600 to-primary-700 text-white font-black text-xs flex items-center justify-center shadow-xs">
              EF
            </div>
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

            <!-- 3. Pinned Extension Tabs (can wrap to second line, up to limit) -->
            <%= for ext_id <- Enum.take(@pinned_extensions, @max_pinned) do %>
              <% ext = Enum.find(@overview.extensions, fn e -> to_string(e.id) == ext_id end) %>
              <%= if ext do %>
                <% title = tab_short_name(ext) %>
                <% icon = if is_map(ext.dashboard_view) and ext.dashboard_view[:icon], do: ext.dashboard_view[:icon], else: default_extension_icon(ext) %>
                <% is_active = to_string(@current_tab) == ext_id %>
                <div class={"group relative flex items-center rounded-lg transition-all text-xs font-bold whitespace-nowrap flex-shrink-0 #{if is_active, do: "bg-white text-primary-700 shadow-sm", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-200/50"}"}>
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

          <!-- Right Toolbar: Search & Settings -->
          <div class="flex items-center gap-1.5 flex-shrink-0">
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

        <!-- OVERVIEW TAB: Platform & Kernel Metrics -->
        <%= if @current_tab == :overview do %>
          <!-- METRIC CARDS ROW -->
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <.metric_card
              title="Active Extensions"
              value={"#{to_string(@overview.plugins_count)} Online"}
              delta="Active"
              delta_positive={true}
              subtitle="Game Services & Integrations"
            />
            <.metric_card
              title="Declared Resources"
              value={to_string(@overview.resources_count)}
              delta="Synced"
              delta_positive={true}
              subtitle="Schemas & Tables"
            />
            <.metric_card
              title="Callable Actions"
              value={to_string(@total_actions)}
              delta="Available"
              delta_positive={true}
              subtitle="Game Actions & Operations"
            />
            <.metric_card
              title="Cluster Status"
              value="Healthy"
              delta="Online"
              delta_positive={true}
              subtitle="Sub-ms Response Time"
            />
          </div>

          <!-- EXTENSIONS & RECENT TELEMETRY ROW -->
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Installed Extensions List -->
            <div class="lg:col-span-2 bg-white p-6 rounded-2xl border border-gray-200 shadow-card space-y-4">
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="font-bold text-gray-900 text-sm">Live Game Features &amp; Capability Modules</h3>
                  <p class="text-xs text-gray-400 mt-0.5">Active services powering gameplay, combat, auth, and backend logic</p>
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
                        <span class="text-xs font-bold text-gray-800"><%= humanize_plugin_name(ext) %></span>
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

          <!-- ACTIVE STATEFUL ENTITIES & ACTOR CLUSTER RUNTIME -->
          <div class="bg-white p-6 rounded-2xl border border-gray-200 shadow-card space-y-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class="w-10 h-10 rounded-xl bg-purple-50 text-purple-700 flex items-center justify-center text-xl shadow-xs">
                  🤖
                </span>
                <div>
                  <h3 class="font-bold text-gray-900 text-sm flex items-center gap-2">
                    <span>Stateful Entity Actors</span>
                    <span class="text-[10px] font-black px-2 py-0.5 rounded-full bg-purple-100 text-purple-800">
                      <%= length(@active_entities) %> active
                    </span>
                  </h3>
                  <p class="text-xs text-gray-400 mt-0.5">Live game entity actors with automated state hydration and passivation</p>
                </div>
              </div>
              <button
                type="button"
                phx-click="refresh_entities"
                class="px-3 py-1.5 text-xs font-bold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-xl transition-colors flex items-center gap-1.5"
                title="Refresh active entities"
              >
                <span>🔄</span>
                <span>Refresh</span>
              </button>
            </div>

            <%= if Enum.empty?(@active_entities) do %>
              <div class="p-8 text-center bg-gray-50/70 rounded-xl border border-gray-100 space-y-2">
                <span class="text-2xl block">💤</span>
                <h4 class="text-xs font-bold text-gray-700">All Entity Actors Passivated</h4>
                <p class="text-[11px] text-gray-400 max-w-md mx-auto">
                  Actors spawn and hydrate automatically on incoming game RPCs or client actions, and passivate to persistent storage on idle timeout.
                </p>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr class="bg-gray-50/75 border-b border-gray-200 text-[10px] font-bold text-gray-500 uppercase tracking-wider">
                      <th class="py-2.5 px-3">Plugin</th>
                      <th class="py-2.5 px-3">Entity Type</th>
                      <th class="py-2.5 px-3">Entity ID</th>
                      <th class="py-2.5 px-3">PID</th>
                      <th class="py-2.5 px-3">Memory</th>
                      <th class="py-2.5 px-3">Queue</th>
                      <th class="py-2.5 px-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-100">
                    <%= for ent <- @active_entities do %>
                      <tr class="hover:bg-purple-50/30 transition-colors">
                        <td class="py-2.5 px-3 font-semibold text-gray-800"><%= ent.plugin %></td>
                        <td class="py-2.5 px-3 font-mono text-purple-700 font-bold"><%= ent.type %></td>
                        <td class="py-2.5 px-3 font-mono font-medium text-gray-900"><%= ent.id %></td>
                        <td class="py-2.5 px-3 font-mono text-[11px] text-gray-400"><%= ent.pid %></td>
                        <td class="py-2.5 px-3 font-mono text-[11px] text-emerald-700 font-semibold"><%= ent.memory_kb %> KB</td>
                        <td class="py-2.5 px-3 font-mono text-[11px] text-gray-500"><%= ent.queue_len %></td>
                        <td class="py-2.5 px-3 text-right">
                          <button
                            type="button"
                            phx-click="passivate_entity"
                            phx-value-plugin={to_string(ent.plugin)}
                            phx-value-type={to_string(ent.type)}
                            phx-value-id={to_string(ent.id)}
                            class="px-2.5 py-1 text-[11px] font-bold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 rounded-lg transition-colors"
                            title="Force flush state and terminate actor"
                          >
                            Passivate
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- EXTENSIONS REGISTRY TAB -->
        <%= if @current_tab == :apps do %>
          <% filtered_exts = filter_extensions(@overview.extensions, @extensions_search, @extensions_category) %>
          <% regular_exts =
               filtered_exts
               |> Enum.reject(& &1.system)
               |> Enum.sort_by(&{not custom_ui?(&1), humanize_plugin_name(&1)}) %>
          <% system_exts = filtered_exts |> Enum.filter(& &1.system) |> Enum.sort_by(&humanize_plugin_name/1) %>
          <div class="space-y-6">
            <!-- Header with Title, Search & Category Filters -->
            <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm">
              <div>
                <h3 class="text-xl font-bold text-gray-900 flex items-center gap-2">
                  <span>🧩</span>
                  <span>Feature &amp; Capability Extensions Registry</span>
                </h3>
                <p class="text-xs text-gray-500 mt-1">
                  Installed extensions providing live gameplay actions, state schemas, and APIs.
                </p>
              </div>

              <!-- Live Search Bar -->
              <div class="w-full md:w-72">
                <form id="extensions_search_form" phx-change="search_extensions" class="m-0">
                  <div class="relative">
                    <span class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-gray-400">
                      🔍
                    </span>
                    <input
                      type="text"
                      name="query"
                      value={@extensions_search}
                      placeholder="Search extensions, services..."
                      class="w-full pl-9 pr-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:border-primary-500 font-medium"
                    />
                  </div>
                </form>
              </div>
            </div>

            <!-- Category Filter Pills -->
            <div class="flex items-center gap-2 overflow-x-auto pb-1 [scrollbar-width:none]">
              <%= for {cat_id, label, icon} <- extension_categories(@overview.extensions) do %>
                <button
                  type="button"
                  phx-click="filter_extension_category"
                  phx-value-category={cat_id}
                  class={"px-3 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 whitespace-nowrap #{if @extensions_category == cat_id, do: "bg-primary-600 text-white shadow-sm", else: "bg-white text-gray-600 hover:bg-gray-50 border border-gray-200/80"}"}
                >
                  <span><%= icon %></span>
                  <span><%= label %></span>
                  <%= if cat_id == "all" do %>
                    <span class={"text-[10px] px-1.5 py-0.2 rounded-full font-mono #{if @extensions_category == cat_id, do: "bg-white/20 text-white", else: "bg-gray-100 text-gray-600"}"}>
                      <%= length(@overview.extensions) %>
                    </span>
                  <% end %>
                </button>
              <% end %>
            </div>

            <!-- Extension Cards Grid -->
            <%= if Enum.empty?(filtered_exts) do %>
              <div class="bg-white p-12 rounded-2xl border border-gray-200 text-center space-y-3">
                <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl">
                  🔍
                </div>
                <h4 class="text-base font-bold text-gray-800">No extensions match your filter</h4>
                <p class="text-xs text-gray-400">Try changing the category or clearing the search query.</p>
                <button
                  type="button"
                  phx-click="filter_extension_category"
                  phx-value-category="all"
                  class="px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-bold rounded-xl transition-colors"
                >
                  Reset Filters
                </button>
              </div>
            <% else %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                <%= for ext <- regular_exts do %>
                  <.extension_card ext={ext} pinned={to_string(ext.id) in @pinned_extensions} />
                <% end %>
              </div>

              <%= if system_exts != [] do %>
                <details class="group bg-white rounded-2xl border border-gray-200/90 shadow-sm">
                  <summary class="cursor-pointer list-none px-5 py-4 flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class="text-base">⚙️</span>
                      <span class="text-sm font-bold text-gray-700">System Extensions</span>
                      <span class="text-[10px] font-mono px-1.5 py-0.2 rounded-full bg-gray-100 text-gray-600">
                        <%= length(system_exts) %>
                      </span>
                      <span class="hidden sm:inline text-xs text-gray-400">
                        — infrastructure you rarely configure
                      </span>
                    </div>
                    <span class="text-gray-400 transition-transform group-open:rotate-180">▾</span>
                  </summary>
                  <div class="px-5 pb-5 pt-1 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 opacity-80">
                    <%= for ext <- system_exts do %>
                      <.extension_card ext={ext} pinned={to_string(ext.id) in @pinned_extensions} />
                    <% end %>
                  </div>
                </details>
              <% end %>
            <% end %>
          </div>
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
            <%= if custom_view_module(active_ext) do %>
              <.live_component
                module={custom_view_module(active_ext)}
                id={"ext_view_#{active_ext.id}"}
                extension={active_ext}
              />
            <% else %>
              <.live_component
                module={Exoforge.Std.Dashboard.GenericExtensionView}
                id={"ext_generic_#{active_ext.id}"}
                extension={active_ext}
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
        subtitle={"#{@project_name} cluster configuration"}
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

      <!-- Action Execution Modal -->
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
