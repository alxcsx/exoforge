defmodule Exoforge.Std.Dashboard.GenericExtensionView do
  @moduledoc """
  Universal auto-generated Visual Control GUI component for Exoforge extensions.
  Transforms any extension's contract metadata (actions, parameters, resources, events)
  into rich, interactive visual controls without requiring custom UI code.
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.DrawerRegistry
  import Exoforge.Std.Dashboard.Components

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       subtab: "actions",
       action_forms: %{},
       action_results: %{},
       selected_resource_name: nil,
       resource_rows: [],
       filtered_resource_rows: [],
       resource_search: "",
       drawer_open: false,
       inspected_row: nil,
       inspected_drawer_tab: "overview",
       drawer_tabs: [],
       export_modal_open: false,
       export_format: "CSV",
       export_content: "",
       export_filename: "export.csv"
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    ext = socket.assigns.extension

    # Pick initial subtab based on what's available
    subtab =
      cond do
        socket.assigns.subtab in ["actions", "resources", "events", "contract", "schedule"] ->
          socket.assigns.subtab

        (ext[:actions] || []) != [] ->
          "actions"

        (ext[:resources] || []) != [] ->
          "resources"

        (ext[:events] || []) != [] ->
          "events"

        true ->
          "contract"
      end

    # Initialize resource if available
    resources = ext[:resources] || []
    first_res = List.first(resources)

    selected_res_name =
      socket.assigns.selected_resource_name ||
        if first_res, do: to_string(first_res[:name] || first_res["name"]), else: nil

    socket =
      socket
      |> assign(:subtab, subtab)
      |> assign(:selected_resource_name, selected_res_name)
      |> load_resource_data()

    {:ok, socket}
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("switch_subtab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :subtab, tab)}
  end

  @impl true
  def handle_event("select_resource", %{"name" => name}, socket) do
    socket =
      socket
      |> assign(:selected_resource_name, name)
      |> load_resource_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "change_param",
        %{"action" => act_name, "param" => param_name, "value" => val},
        socket
      ) do
    current_forms = socket.assigns.action_forms
    act_form = Map.get(current_forms, act_name, %{})
    updated_act_form = Map.put(act_form, param_name, val)
    updated_forms = Map.put(current_forms, act_name, updated_act_form)

    {:noreply, assign(socket, :action_forms, updated_forms)}
  end

  @impl true
  def handle_event("change_action_card_form", %{"action_name" => act_name} = params, socket) do
    current_forms = socket.assigns.action_forms
    act_form = Map.get(current_forms, act_name, %{})

    updated_act_form =
      Enum.reduce(params, act_form, fn
        {"param_" <> p_name, val}, acc -> Map.put(acc, p_name, val)
        {"caller_scopes", val}, acc -> Map.put(acc, "caller_scopes", val)
        _, acc -> acc
      end)

    updated_forms = Map.put(current_forms, act_name, updated_act_form)
    {:noreply, assign(socket, :action_forms, updated_forms)}
  end

  @impl true
  def handle_event("run_action", %{"action" => act_name, "service" => svc_name}, socket) do
    ext = socket.assigns.extension
    action_def = Enum.find(ext[:actions] || [], &(&1[:name] == act_name))

    act_form = Map.get(socket.assigns.action_forms, act_name, %{})
    scopes_str = Map.get(act_form, "caller_scopes", "admin, player")

    scopes =
      scopes_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    scopes = if scopes == [], do: [Exoforge.Auth.Roles.admin()], else: scopes

    # Cast parameters
    payload =
      if action_def do
        Enum.reduce(action_def[:params] || [], %{}, fn p, acc ->
          val_str =
            Map.get(act_form, p[:name] || p["name"], default_value_for(p[:type] || p["type"]))

          casted = cast_value(val_str, p[:type] || p["type"])
          Map.put(acc, existing_atom(p[:name] || p["name"]), casted)
        end)
      else
        %{}
      end

    start_time = System.monotonic_time(:microsecond)

    result =
      try do
        ActionDispatcher.dispatch(svc_name, act_name, payload, caller_scopes: scopes)
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, inspect(reason)}
      end

    duration_us = System.monotonic_time(:microsecond) - start_time
    latency_ms = Float.round(duration_us / 1000, 2)

    result_info = %{
      result: result,
      latency_ms: latency_ms,
      time: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    }

    updated_results = Map.put(socket.assigns.action_results, act_name, result_info)

    # Reload resource if action potentially changed resource data
    socket =
      socket
      |> assign(:action_results, updated_results)
      |> load_resource_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_resource", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:resource_search, query)
      |> apply_resource_search()

    {:noreply, socket}
  end

  @impl true
  def handle_event("inspect_row", %{"id" => id}, socket) do
    row =
      Enum.find(socket.assigns.resource_rows, fn r ->
        to_string(r[:id] || r["id"] || r[:player_id] || r["player_id"]) == to_string(id)
      end)

    res_name = socket.assigns.selected_resource_name
    tabs = if res_name, do: DrawerRegistry.list_tabs(res_name), else: []

    {:noreply,
     assign(socket,
       drawer_open: true,
       inspected_row: row,
       drawer_tabs: tabs,
       inspected_drawer_tab: "overview"
     )}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, drawer_open: false, inspected_row: nil)}
  end

  @impl true
  def handle_event("select_drawer_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, inspected_drawer_tab: tab)}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    res_name = socket.assigns.selected_resource_name || "data"
    rows = socket.assigns.resource_rows
    cols = current_resource_columns(socket)

    header = Enum.map_join(cols, ",", &"\"#{&1[:label] || &1[:key]}\"")

    body_lines =
      Enum.map(rows, fn row ->
        Enum.map_join(cols, ",", fn col ->
          key = col[:key] || col["key"]
          val = Map.get(row, key) || Map.get(row, to_string(key)) || ""
          escaped = String.replace(to_string(val), "\"", "\"\"")
          "\"#{escaped}\""
        end)
      end)

    csv_data = Enum.join([header | body_lines], "\n")

    {:noreply,
     assign(socket,
       export_modal_open: true,
       export_format: "CSV",
       export_content: csv_data,
       export_filename: "#{res_name}_export.csv"
     )}
  end

  @impl true
  def handle_event("export_json", _params, socket) do
    res_name = socket.assigns.selected_resource_name || "data"
    json_data = Jason.encode!(socket.assigns.resource_rows, pretty: true)

    {:noreply,
     assign(socket,
       export_modal_open: true,
       export_format: "JSON",
       export_content: json_data,
       export_filename: "#{res_name}_export.json"
     )}
  end

  @impl true
  def handle_event("close_export_modal", _params, socket) do
    {:noreply, assign(socket, export_modal_open: false)}
  end

  @impl true
  def handle_event("simulate_event", %{"event" => event_name}, socket) do
    ext_id = socket.assigns.extension.id
    topic = "ext:#{ext_id}"

    payload = %{
      simulated: true,
      event: event_name,
      extension: ext_id,
      timestamp: System.system_time(:millisecond)
    }

    EventDispatcher.broadcast(topic, payload)
    {:noreply, socket}
  end

  ## ---- PRIVATE HELPERS ----

  defp load_resource_data(socket) do
    case socket.assigns.selected_resource_name do
      nil ->
        assign(socket, resource_rows: [], filtered_resource_rows: [])

      name ->
        rows = PluginRegistry.fetch_resource_rows(name)

        socket
        |> assign(:resource_rows, rows)
        |> apply_resource_search()
    end
  end

  defp existing_atom(value) when is_atom(value), do: value

  defp existing_atom(value) do
    String.to_existing_atom(to_string(value))
  rescue
    ArgumentError -> value
  end

  defp apply_resource_search(socket) do
    q = String.downcase(String.trim(socket.assigns.resource_search))
    rows = socket.assigns.resource_rows

    filtered =
      if q == "" do
        rows
      else
        Enum.filter(rows, fn row ->
          Enum.any?(Map.values(row), fn val ->
            String.contains?(String.downcase(to_string(val)), q)
          end)
        end)
      end

    assign(socket, :filtered_resource_rows, filtered)
  end

  defp current_resource_columns(%Phoenix.LiveView.Socket{assigns: assigns}) do
    current_resource_columns(assigns)
  end

  defp current_resource_columns(assigns) when is_map(assigns) do
    res_name = assigns[:selected_resource_name]
    ext = assigns[:extension] || %{}
    resources = ext[:resources] || []

    res =
      Enum.find(resources, fn r -> to_string(r[:name] || r["name"]) == to_string(res_name) end)

    cols = if res, do: res[:columns] || res["columns"] || [], else: []

    if Enum.empty?(cols) do
      [%{key: :id, label: "ID"}, %{key: :data, label: "Data"}]
    else
      Enum.map(cols, fn c ->
        key = c[:name] || c["name"]
        label = c[:label] || c["label"] || Phoenix.Naming.humanize(to_string(key))
        %{key: key, label: label, badge: c[:badge] || c["badge"] || false}
      end)
    end
  end

  defp default_value_for(type) do
    case type do
      :integer -> "1"
      :float -> "1.0"
      :boolean -> "true"
      :map -> "{}"
      :list -> "[]"
      _ -> ""
    end
  end

  defp cast_value(val_str, type) when is_binary(val_str) do
    case type do
      :integer ->
        case Integer.parse(String.trim(val_str)) do
          {int, _} -> int
          _ -> 0
        end

      :float ->
        case Float.parse(String.trim(val_str)) do
          {flt, _} -> flt
          _ -> 0.0
        end

      :boolean ->
        String.trim(String.downcase(val_str)) in ["true", "1", "yes"]

      :map ->
        case Jason.decode(val_str) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      :list ->
        case Jason.decode(val_str) do
          {:ok, list} when is_list(list) ->
            list

          _ ->
            String.split(val_str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        end

      _ ->
        val_str
    end
  end

  defp cast_value(val, _), do: val

  ## ---- TEMPLATE RENDERING ----

  @impl true
  def render(assigns) do
    ext = assigns.extension
    icon = (is_map(ext[:dashboard_view]) && ext[:dashboard_view][:icon]) || "🧩"
    actions = ext[:actions] || []
    resources = ext[:resources] || []
    events = ext[:events] || []
    columns = current_resource_columns(assigns)

    has_schedule =
      Enum.any?(resources, fn r ->
        cols =
          (r[:columns] || [])
          |> Enum.map(fn
            %{name: n} -> to_string(n)
            %{"name" => n} -> to_string(n)
            other -> to_string(other)
          end)

        Enum.any?(cols, &String.contains?(&1, ["date", "time", "start", "end", "schedule", "window"])) or
          (r[:drawer] in [:schedule, :calendar, "schedule", "calendar"])
      end)

    schedule_events =
      if has_schedule do
        Enum.map(assigns[:resource_rows] || [], fn row ->
          start_val = Map.get(row, :start_at) || Map.get(row, "start_at") || Map.get(row, :created_at) || Map.get(row, "created_at")
          end_val = Map.get(row, :end_at) || Map.get(row, "end_at") || Map.get(row, :expires_at) || Map.get(row, "expires_at")
          id_val = Map.get(row, :id) || Map.get(row, "id") || "event"
          title_val = Map.get(row, :title) || Map.get(row, "title") || Map.get(row, :name) || Map.get(row, "name") || to_string(id_val)

          case Exoforge.TimeWindow.new(%{id: id_val, title: title_val, start_at: start_val, end_at: end_val, metadata: row}) do
            {:ok, tw} -> Exoforge.TimeWindow.to_map(tw)
            _ -> %{id: id_val, title: title_val, start_at: start_val, end_at: end_val, status: :active, countdown_text: "Active", progress: 0.5, metadata: row}
          end
        end)
      else
        []
      end

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:actions, actions)
      |> assign(:resources, resources)
      |> assign(:events, events)
      |> assign(:columns, columns)
      |> assign(:has_schedule, has_schedule)
      |> assign(:schedule_events, schedule_events)

    ~H"""
    <div class="space-y-6" id={@id}>
      <!-- Extension Visual Header -->
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200/80 shadow-sm">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-2xl bg-purple-100 text-purple-700 flex items-center justify-center text-2xl shadow-inner">
            <%= @icon %>
          </div>
          <div>
            <div class="flex items-center gap-2.5">
              <h2 class="text-xl font-bold text-gray-900"><%= Phoenix.Naming.humanize(to_string(@extension.name)) %></h2>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold bg-purple-100 text-purple-800">
                v<%= to_string(@extension.version) %>
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-800">
                <%= @extension.type %>
              </span>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              Provides: <code class="text-purple-700 font-bold"><%= Enum.join(@extension.provides, ", ") %></code>
              <%= if @extension.dependencies != [] do %>
                • Depends on: <code class="text-gray-600"><%= Enum.join(@extension.dependencies, ", ") %></code>
              <% end %>
            </p>
          </div>
        </div>

        <!-- Subtab Switcher -->
        <div class="flex items-center gap-1.5 bg-gray-100/80 p-1.5 rounded-xl border border-gray-200/60 overflow-x-auto">
          <%= if @actions != [] do %>
            <button
              phx-click="switch_subtab"
              phx-value-tab="actions"
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1.5 #{if @subtab == "actions", do: "bg-white text-purple-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>⚡ Actions</span>
              <span class="text-[10px] px-1.5 py-0.2 rounded-full bg-purple-100 text-purple-800"><%= length(@actions) %></span>
            </button>
          <% end %>

          <%= if @resources != [] do %>
            <button
              phx-click="switch_subtab"
              phx-value-tab="resources"
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1.5 #{if @subtab == "resources", do: "bg-white text-purple-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>📦 Data</span>
              <span class="text-[10px] px-1.5 py-0.2 rounded-full bg-blue-100 text-blue-800"><%= length(@resources) %></span>
            </button>
          <% end %>

          <%= if @events != [] do %>
            <button
              phx-click="switch_subtab"
              phx-value-tab="events"
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1.5 #{if @subtab == "events", do: "bg-white text-purple-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>📡 Telemetry</span>
              <span class="text-[10px] px-1.5 py-0.2 rounded-full bg-emerald-100 text-emerald-800"><%= length(@events) %></span>
            </button>
          <% end %>

          <%= if @has_schedule do %>
            <button
              phx-click="switch_subtab"
              phx-value-tab="schedule"
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1.5 #{if @subtab == "schedule", do: "bg-white text-purple-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>📅 Schedule & Calendar</span>
            </button>
          <% end %>

          <button
            phx-click="switch_subtab"
            phx-value-tab="contract"
            phx-target={@myself}
            class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1.5 #{if @subtab == "contract", do: "bg-white text-purple-700 shadow-sm", else: "text-gray-600 hover:text-gray-900"}"}
          >
            <span>🛡️ Contract</span>
          </button>
        </div>
      </div>

      <!-- SUBTAB: SCHEDULE & CALENDAR -->
      <%= if @subtab == "schedule" do %>
        <div class="space-y-6">
          <.schedule_timeline events={@schedule_events} title="LiveOps Schedule Timeline" />
          <.calendar_view events={@schedule_events} title="LiveOps Schedule Calendar" />
        </div>
      <% end %>

      <!-- SUBTAB 1: ACTIONS & VISUAL CONTROLS -->
      <%= if @subtab == "actions" do %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-bold text-gray-900">Interactive Action Control Panel</h3>
              <p class="text-xs text-gray-400 mt-0.5">Execute typed backend RPCs with parameter inputs and live latency profiling</p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
            <%= for act <- @actions do %>
              <% act_form = Map.get(@action_forms, act[:name], %{}) %>
              <% result_info = Map.get(@action_results, act[:name]) %>

              <div class="bg-white rounded-2xl border border-gray-200/80 shadow-sm p-5 space-y-4 hover:border-purple-200 transition-colors">
                <div class="flex items-start justify-between">
                  <div class="flex items-center gap-2.5">
                    <span class="w-8 h-8 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center font-bold text-sm">
                      ⚡
                    </span>
                    <div>
                      <h4 class="font-mono font-bold text-gray-900 text-sm"><%= act[:name] %></h4>
                      <span class="text-[11px] text-gray-400">Service: <code class="text-purple-700 font-semibold"><%= act[:service] %></code></span>
                    </div>
                  </div>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-md text-[10px] font-bold uppercase tracking-wider bg-gray-100 text-gray-700">
                    <%= act[:mode] %>
                  </span>
                </div>

                <p class="text-xs text-gray-600 bg-gray-50/60 p-2.5 rounded-xl border border-gray-100">
                  <%= act[:doc] %>
                </p>

                <form phx-change="change_action_card_form" phx-submit="run_action" phx-target={@myself} class="space-y-3">
                  <input type="hidden" name="action_name" value={act[:name]} />
                  <input type="hidden" name="service" value={act[:service]} />
                  <input type="hidden" name="action" value={act[:name]} />

                  <!-- Parameter Inputs -->
                  <%= if (act[:params] || []) != [] do %>
                    <div class="space-y-2 pt-1">
                      <%= for p <- act[:params] do %>
                        <% p_name = p[:name] || p["name"] %>
                        <% p_type = p[:type] || p["type"] %>
                        <% val = Map.get(act_form, p_name, default_value_for(p_type)) %>

                        <div>
                          <div class="flex items-center justify-between mb-1">
                            <label class="text-[11px] font-bold text-gray-700 font-mono"><%= p_name %></label>
                            <span class="text-[10px] text-purple-600 font-mono"><%= p_type %></span>
                          </div>

                          <%= case p_type do %>
                            <% :boolean -> %>
                              <select
                                name={"param_#{p_name}"}
                                class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-1.5 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 font-mono"
                              >
                                <option value="true" selected={val in ["true", true]}>true</option>
                                <option value="false" selected={val in ["false", false]}>false</option>
                              </select>

                            <% :map -> %>
                              <textarea
                                name={"param_#{p_name}"}
                                rows="2"
                                class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-1.5 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 font-mono"
                              ><%= val %></textarea>

                            <% _ -> %>
                              <input
                                type={if p_type in [:integer, :float], do: "number", else: "text"}
                                step={if p_type == :float, do: "0.1", else: "1"}
                                name={"param_#{p_name}"}
                                value={val}
                                class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-1.5 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 font-mono"
                              />
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- Scope Gating Input -->
                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <label class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">Caller Scopes</label>
                    </div>
                    <input
                      type="text"
                      name="caller_scopes"
                      value={Map.get(act_form, "caller_scopes", "admin, player")}
                      class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-1.5 focus:bg-white font-mono text-gray-600"
                    />
                  </div>

                  <!-- Run Button -->
                  <div class="pt-2 flex items-center justify-between">
                    <button
                      type="submit"
                      class="px-4 py-2 text-xs font-bold text-white bg-purple-600 rounded-xl hover:bg-purple-700 transition-colors shadow-sm flex items-center gap-1.5 active:scale-95"
                    >
                      <span>⚡ Run Action</span>
                    </button>

                    <%= if result_info do %>
                      <span class="inline-flex items-center gap-1 text-[11px] font-mono text-emerald-700 bg-emerald-50 px-2 py-1 rounded-lg border border-emerald-200 font-bold">
                        ⚡ <%= result_info.latency_ms %> ms
                      </span>
                    <% end %>
                  </div>
                </form>

                <!-- Action Result Box -->
                <%= if result_info do %>
                  <div class="mt-3 pt-3 border-t border-gray-100 space-y-1.5">
                    <div class="flex items-center justify-between text-[11px]">
                      <span class="font-bold text-gray-600">Response (<%= result_info.time %>):</span>
                      <span class={"font-bold px-1.5 py-0.5 rounded text-[10px] #{case result_info.result do
                        {:ok, _} -> "bg-emerald-100 text-emerald-800"
                        _ -> "bg-red-100 text-red-800"
                      end}"}>
                        <%= case result_info.result do
                          {:ok, _} -> "SUCCESS (200)"
                          _ -> "ERROR"
                        end %>
                      </span>
                    </div>
                    <pre class="text-[11px] font-mono bg-gray-900 text-emerald-400 p-3 rounded-xl overflow-x-auto max-h-40"><%= case result_info.result do
                      {:ok, payload} -> Jason.encode!(payload, pretty: true)
                      {:error, reason} -> inspect(reason)
                      other -> inspect(other)
                    end %></pre>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- SUBTAB 2: DATA & RESOURCES -->
      <%= if @subtab == "resources" do %>
        <div class="space-y-4">
          <!-- Resource Switcher & Toolbar -->
          <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold text-gray-500 uppercase tracking-wider mr-1">Resource:</span>
              <%= for res <- @resources do %>
                <% res_name = to_string(res[:name] || res["name"]) %>
                <button
                  type="button"
                  phx-click="select_resource"
                  phx-value-name={res_name}
                  phx-target={@myself}
                  class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-colors #{if to_string(@selected_resource_name) == res_name, do: "bg-purple-600 text-white shadow-sm", else: "bg-gray-100 text-gray-600 hover:bg-gray-200"}"}
                >
                  <%= Phoenix.Naming.humanize(res_name) %>
                </button>
              <% end %>
            </div>

            <div class="flex items-center gap-3">
              <input
                type="text"
                placeholder="Search rows..."
                value={@resource_search}
                phx-input="search_resource"
                phx-target={@myself}
                phx-debounce="200"
                name="query"
                class="px-3 py-1.5 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500"
              />

              <button
                type="button"
                phx-click="export_csv"
                phx-target={@myself}
                class="px-3 py-1.5 text-xs font-semibold text-gray-700 bg-white border border-gray-200 rounded-xl hover:bg-gray-50 shadow-xs flex items-center gap-1"
              >
                <span>⬇ CSV</span>
              </button>

              <button
                type="button"
                phx-click="export_json"
                phx-target={@myself}
                class="px-3 py-1.5 text-xs font-semibold text-gray-700 bg-white border border-gray-200 rounded-xl hover:bg-gray-50 shadow-xs flex items-center gap-1"
              >
                <span>⬇ JSON</span>
              </button>
            </div>
          </div>

          <!-- Declarative Resource Table -->
          <div class="bg-white rounded-2xl border border-gray-200/80 shadow-sm overflow-hidden">
            <%= if @filtered_resource_rows == [] do %>
              <div class="p-12 text-center space-y-2">
                <span class="text-3xl block">📦</span>
                <h3 class="text-sm font-bold text-gray-900">No records found</h3>
                <p class="text-xs text-gray-500 max-w-sm mx-auto">
                  No rows currently stored in resource <code class="font-mono text-purple-700 font-bold"><%= @selected_resource_name %></code>.
                </p>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr class="bg-gray-50/75 border-b border-gray-200 text-[10px] font-bold text-gray-500 uppercase tracking-wider">
                      <%= for col <- @columns do %>
                        <th class="py-3 px-4"><%= col[:label] %></th>
                      <% end %>
                      <th class="py-3 px-4 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-100">
                    <%= for row <- @filtered_resource_rows do %>
                      <% row_id = Map.get(row, :id) || Map.get(row, "id") || Map.get(row, :player_id) || Map.get(row, "player_id") || "item" %>
                      <tr class="hover:bg-purple-50/30 transition-colors group">
                        <%= for col <- @columns do %>
                          <% val = Map.get(row, col[:key]) || Map.get(row, to_string(col[:key])) || "" %>
                          <td class="py-3 px-4">
                            <%= if col[:badge] do %>
                              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                                <%= val %>
                              </span>
                            <% else %>
                              <span class="font-mono font-medium text-gray-800"><%= to_string(val) %></span>
                            <% end %>
                          </td>
                        <% end %>
                        <td class="py-3 px-4 text-right">
                          <button
                            type="button"
                            phx-click="inspect_row"
                            phx-value-id={to_string(row_id)}
                            phx-target={@myself}
                            class="px-2.5 py-1 text-xs font-semibold text-purple-700 bg-purple-50 hover:bg-purple-100 border border-purple-200 rounded-lg transition-colors"
                          >
                            Inspect
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- SUBTAB 3: LIVE TELEMETRY & EVENTS -->
      <%= if @subtab == "events" do %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-bold text-gray-900">Declared Event Contracts</h3>
              <p class="text-xs text-gray-400 mt-0.5">Cluster broadcasts emitted by this extension via EventDispatcher</p>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for ev <- @events do %>
              <% ev_name = to_string(ev[:name] || ev["name"]) %>
              <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm space-y-3">
                <div class="flex items-center justify-between">
                  <span class="font-mono font-bold text-purple-700 text-sm"><%= ev_name %></span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-md text-[10px] font-bold uppercase bg-gray-100 text-gray-700">
                    <%= ev[:scope] || "server" %>
                  </span>
                </div>
                <p class="text-xs text-gray-500"><%= ev[:doc] || "No description provided." %></p>

                <div class="pt-2 flex items-center justify-between border-t border-gray-100">
                  <span class="text-[11px] text-gray-400 font-mono">Topic: <%= ev[:topic] || ":global" %></span>
                  <button
                    type="button"
                    phx-click="simulate_event"
                    phx-value-event={ev_name}
                    phx-target={@myself}
                    class="px-3 py-1 text-xs font-bold text-purple-700 bg-purple-50 hover:bg-purple-100 border border-purple-200 rounded-lg transition-colors"
                  >
                    ⚡ Simulate Broadcast
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- SUBTAB 4: CONTRACT SPECIFICATION -->
      <%= if @subtab == "contract" do %>
        <div class="bg-white p-6 rounded-2xl border border-gray-200/80 shadow-sm space-y-4">
          <h3 class="text-sm font-bold text-gray-900">Contract & Architecture Specification</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
            <div class="p-4 bg-gray-50 rounded-xl border border-gray-100 space-y-2">
              <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Plugin Identity</span>
              <p><strong>ID:</strong> <code class="font-mono text-purple-700"><%= @extension.id %></code></p>
              <p><strong>Entry Point:</strong> <code class="font-mono text-gray-700"><%= inspect(@extension[:entry_point] || @extension.id) %></code></p>
              <p><strong>Runtime Engine:</strong> <%= @extension.type %></p>
            </div>
            <div class="p-4 bg-gray-50 rounded-xl border border-gray-100 space-y-2">
              <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Contract Topology</span>
              <p><strong>Provided Services:</strong> <%= Enum.join(@extension.provides, ", ") %></p>
              <p><strong>Dependencies:</strong> <%= if @extension.dependencies == [], do: "None (Kernel Root)", else: Enum.join(@extension.dependencies, ", ") %></p>
              <p><strong>Visual GUI Status:</strong> Synthesized by Exoforge Engine</p>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Slide-Over Entity/Row Inspector Drawer -->
      <%= if @drawer_open and @inspected_row do %>
        <div class="fixed inset-0 z-50 overflow-hidden bg-black/30 backdrop-blur-xs flex justify-end">
          <div class="bg-white w-full max-w-md h-full shadow-2xl border-l border-gray-200 p-6 flex flex-col justify-between overflow-y-auto animate-in slide-in-from-right duration-200">
            <div>
              <div class="flex items-center justify-between pb-4 border-b border-gray-100">
                <div class="flex items-center gap-3">
                  <span class="text-2xl">📦</span>
                  <div>
                    <h3 class="text-base font-bold text-gray-900 font-mono">
                      <%= Map.get(@inspected_row, :id) || Map.get(@inspected_row, "id") || "Record" %>
                    </h3>
                    <p class="text-xs text-gray-500">Resource: <%= @selected_resource_name %></p>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="close_drawer"
                  phx-target={@myself}
                  class="text-gray-400 hover:text-gray-600 text-lg font-bold p-1"
                >
                  ✕
                </button>
              </div>

              <!-- Drawer Tabs -->
              <%= if @drawer_tabs != [] do %>
                <div class="flex gap-2 pt-3 pb-2 border-b border-gray-100 overflow-x-auto">
                  <%= for tab <- @drawer_tabs do %>
                    <button
                      type="button"
                      phx-click="select_resource_drawer_tab"
                      phx-value-tab={tab.id}
                      phx-target={@myself}
                      class={"px-3 py-1 text-xs font-bold rounded-lg #{if @inspected_drawer_tab == tab.id, do: "bg-purple-100 text-purple-800", else: "text-gray-500 hover:text-gray-900"}"}
                    >
                      <%= tab.label %>
                    </button>
                  <% end %>
                </div>
              <% end %>

              <div class="mt-4 space-y-3">
                <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Record Fields</h4>
                <div class="space-y-2">
                  <%= for {k, v} <- @inspected_row do %>
                    <div class="p-2.5 bg-gray-50 rounded-xl border border-gray-100 flex flex-col text-xs font-mono">
                      <span class="text-gray-400 text-[10px] uppercase font-bold"><%= k %></span>
                      <span class="text-gray-900 break-all"><%= inspect(v) %></span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="pt-4 border-t border-gray-100">
              <button
                type="button"
                phx-click="close_drawer"
                phx-target={@myself}
                class="w-full py-2 text-xs font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
              >
                Close Inspector
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- CSV / JSON Export Modal -->
      <%= if @export_modal_open do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-xl w-full p-6 shadow-2xl border border-gray-200 space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="text-base font-bold text-gray-900">Export <%= @export_format %> Data (<%= @export_filename %>)</h3>
              <button
                type="button"
                phx-click="close_export_modal"
                phx-target={@myself}
                class="text-gray-400 hover:text-gray-600 font-bold"
              >
                ✕
              </button>
            </div>

            <textarea
              readonly
              rows="8"
              class="w-full text-xs font-mono bg-gray-50 border border-gray-200 rounded-xl p-3 focus:outline-none"
            ><%= @export_content %></textarea>

            <div class="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click="close_export_modal"
                phx-target={@myself}
                class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900"
              >
                Close
              </button>
              <button
                type="button"
                phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: @export_content})}
                class="px-4 py-2 text-xs font-bold text-white bg-purple-600 rounded-xl hover:bg-purple-700"
              >
                Copy to Clipboard
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
