defmodule Exoforge.Std.Dashboard.GenericExtensionView do
  @moduledoc """
  Universal auto-generated Visual Control GUI component for Exoforge extensions.
  Transforms any extension's contract metadata (actions, parameters, resources, events)
  into rich, interactive visual controls without requiring custom UI code.
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Dashboard.ResourceForms
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.DrawerRegistry
  import Exoforge.Std.Dashboard.Components
  import Exoforge.Std.Dashboard.InputTypes, only: [widget: 1]

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       subtab: nil,
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
       resource_form: nil,
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
        socket.assigns.subtab in ["actions", "resources", "events", "contract"] ->
          socket.assigns.subtab

        (ext[:resources] || []) != [] ->
          "resources"

        (ext[:actions] || []) != [] ->
          "actions"

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
      |> sync_focus()

    {:ok, socket}
  end

  # The row drawer is a URL (`?focus=row:<id>`), not component state, so the browser back button
  # closes it and a deep link opens it.
  defp sync_focus(socket) do
    case socket.assigns[:focus] do
      %{kind: "row", id: id} -> open_row(socket, id)
      _ -> assign(socket, drawer_open: false, inspected_row: nil)
    end
  end

  defp open_row(socket, id) do
    current = socket.assigns[:inspected_row]
    current_id = current && (current[:id] || current["id"] || current[:player_id] || current["player_id"])

    if current && to_string(current_id) == to_string(id) do
      socket
    else
      row =
        Enum.find(socket.assigns.resource_rows, fn r ->
          to_string(r[:id] || r["id"] || r[:player_id] || r["player_id"]) == to_string(id)
        end)

      res_name = socket.assigns.selected_resource_name
      tabs = if res_name, do: DrawerRegistry.list_tabs(res_name), else: []

      assign(socket,
        drawer_open: true,
        inspected_row: row,
        drawer_tabs: tabs,
        inspected_drawer_tab: "overview"
      )
    end
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

    # The session's verified scopes (M33 Fix 27): the caller's RBAC comes from the login, not
    # from a form field that could claim `admin` or `server`.
    scopes = socket.assigns[:current_scopes] || []

    # Cast parameters
    payload =
      if action_def do
        Enum.reduce(action_def[:params] || [], %{}, fn p, acc ->
          val_str =
            Map.get(act_form, p[:name] || p["name"], default_value_for(p[:type] || p["type"]))

          casted = cast_value(val_str, p[:type] || p["type"])
          Map.put(acc, Exoforge.Atoms.existing(p[:name] || p["name"]), casted)
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
  def handle_event("select_drawer_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, inspected_drawer_tab: tab)}
  end

  # A new row and an edited one are the same form: the schema decides the fields, and the primary key
  # is the only thing that differs — it is what identifies the row, so it is fixed once it exists.
  @impl true
  def handle_event("new_resource", _params, socket) do
    columns = current_resource_columns(socket)

    {:noreply, assign(socket, resource_form: %{mode: :new, values: ResourceForms.defaults(columns), errors: %{}})}
  end

  @impl true
  def handle_event("edit_resource", _params, socket) do
    columns = current_resource_columns(socket)
    values = ResourceForms.values_for(socket.assigns.inspected_row, columns)

    {:noreply, assign(socket, resource_form: %{mode: :edit, values: values, errors: %{}})}
  end

  @impl true
  def handle_event("resource_form_change", %{"values" => values}, socket) do
    {:noreply, assign(socket, resource_form: %{socket.assigns.resource_form | values: values})}
  end

  @impl true
  def handle_event("close_resource_form", _params, socket) do
    {:noreply, assign(socket, resource_form: nil)}
  end

  @impl true
  def handle_event("submit_resource_form", %{"values" => values}, socket) do
    columns = current_resource_columns(socket)
    form = socket.assigns.resource_form
    name = socket.assigns.selected_resource_name

    case ResourceForms.errors(values, columns) do
      errors when errors != %{} ->
        {:noreply, assign(socket, resource_form: %{form | values: values, errors: errors})}

      _ ->
        attributes = ResourceForms.attributes(values, columns)
        key = Enum.find(columns, & &1.primary_key)

        result =
          case form.mode do
            :new ->
              ActionDispatcher.dispatch(:resource_store, :create, %{
                resource: name,
                attributes: attributes
              })

            :edit ->
              ActionDispatcher.dispatch(:resource_store, :update, %{
                resource: name,
                id: Map.get(values, to_string(key.key)),
                attributes: attributes
              })
          end

        case result do
          {:ok, _} ->
            {:noreply, socket |> assign(resource_form: nil) |> load_resource_data()}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               resource_form: %{form | values: values, errors: %{"_form" => inspect(reason)}}
             )}
        end
    end
  end

  @impl true
  def handle_event("delete_resource", _params, socket) do
    _ =
      ActionDispatcher.dispatch(:resource_store, :clear, %{
        resource: socket.assigns.selected_resource_name
      })

    {:noreply, load_resource_data(socket)}
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
    case ResourceForms.columns(current_resource(assigns)) do
      [] -> [%{key: :id, label: "ID"}, %{key: :data, label: "Data"}]
      columns -> columns
    end
  end

  # The resource the Data tab is showing, as the manifest declares it.
  defp current_resource(assigns) when is_map(assigns) do
    res_name = assigns[:selected_resource_name]
    ext = assigns[:extension] || %{}

    (ext[:resources] || [])
    |> Enum.find(fn r -> to_string(r[:name] || r["name"]) == to_string(res_name) end)
  end

  # A column role (e.g. "user_id") turns a plain string into a deep link. The target is
  # contributed by whichever plugin owns the role, through a `:resource_column` UI hook, so the
  # dashboard never hardcodes a plugin's tab.
  defp column_link(nil), do: nil

  defp column_link(role) do
    role = to_string(role)

    Exoforge.UIHookRegistry.list_hooks(:resource_column)
    |> Enum.find(fn hook ->
      to_string(hook[:role] || hook[:id]) == role and is_binary(hook[:target]) and
        is_binary(hook[:focus])
    end)
  end

  defp focus_path(link, value) do
    "/tab/#{link[:target]}?focus=#{link[:focus]}:#{URI.encode_www_form(to_string(value))}"
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

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:actions, actions)
      |> assign(:resources, resources)
      |> assign(:events, events)
      |> assign(:columns, columns)

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

                          <% custom_spec = Exoforge.Std.Dashboard.InputTypes.resolve(p) %>

                          <%= if is_map(custom_spec) do %>
                            <.widget spec={custom_spec} name={"param_#{p_name}"} value={val} />
                          <% else %>
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
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- Scope Gating (display only, M33 Fix 27) -->
                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <label class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">Caller Scopes</label>
                    </div>
                    <div class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-1.5 font-mono text-gray-500">
                      <%= Enum.join(@current_scopes || [], ", ") %>
                    </div>
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

              <button
                type="button"
                phx-click="new_resource"
                phx-target={@myself}
                class="px-3 py-1.5 text-xs font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-xl hover:bg-emerald-100 shadow-xs flex items-center gap-1"
              >
                <span>＋ New</span>
              </button>

              <button
                type="button"
                phx-click="delete_resource"
                phx-target={@myself}
                data-confirm={"Delete all data for resource '#{@selected_resource_name}'? This cannot be undone."}
                class="px-3 py-1.5 text-xs font-semibold text-red-600 bg-red-50 border border-red-200 rounded-xl hover:bg-red-100 shadow-xs flex items-center gap-1"
              >
                <span>🗑 Delete</span>
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
                            <%= if link = column_link(col[:role]) do %>
                              <.link
                                patch={focus_path(link, val)}
                                class="inline-flex items-center gap-1 font-mono font-semibold text-primary-700 hover:text-primary-900 hover:underline"
                                title={"Open " <> to_string(col[:label])}
                              >
                                <span><%= to_string(val) %></span>
                                <span class="text-[10px]"><%= link[:icon] || "↗" %></span>
                              </.link>
                            <% else %>
                              <%= if col[:badge] do %>
                                <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                                  <%= val %>
                                </span>
                              <% else %>
                                <span class="font-mono font-medium text-gray-800"><%= to_string(val) %></span>
                              <% end %>
                            <% end %>
                          </td>
                        <% end %>
                        <td class="py-3 px-4 text-right">
                          <button
                            type="button"
                            phx-click="open_focus"
                            phx-value-kind="row"
                            phx-value-id={to_string(row_id)}
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

      <!-- Entity/Row Inspector Popup -->
      <%= if @drawer_open and @inspected_row do %>
        <.inspect_popup
          open={true}
          icon="📦"
          title={to_string(Map.get(@inspected_row, :id) || Map.get(@inspected_row, "id") || "Record")}
          subtitle={"Resource: #{@selected_resource_name}"}
          tabs={@drawer_tabs}
          active_tab={@inspected_drawer_tab}
          on_close="close_focus"
          on_select_tab="select_drawer_tab"
          target={@myself}
          width="max-w-2xl"
        >
          <%= if @inspected_drawer_tab == "attributes" do %>
            <!--
              The row exactly as the store returned it. Keys as stored, values as stored, and
              including anything the schema does not describe - which is what you want when a column
              is not what the schema says it should be.
            -->
            <div class="space-y-3">
              <p class="text-xs text-gray-500">
                As stored. Unlabelled, and including anything the schema does not describe.
              </p>

              <div class="space-y-2">
                <%= for {k, v} <- @inspected_row do %>
                  <div class="p-2.5 bg-gray-50 rounded-xl border border-gray-100 flex flex-col text-xs font-mono">
                    <span class="text-gray-400 text-[10px] uppercase font-bold"><%= k %></span>
                    <span class="text-gray-900 break-all"><%= inspect(v) %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <!--
              The schema's view: the columns the plugin declared, in the order it declared them, with
              their labels and types. A column the row has no value for says so rather than being
              omitted - an absent field and an empty one are different questions.
            -->
            <div class="space-y-3">
              <%= for column <- current_resource_columns(assigns) do %>
                <% key = to_string(column.key) %>
                <% value = Map.get(@inspected_row, key) || Map.get(@inspected_row, column.key) %>

                <div class="p-2.5 bg-gray-50 rounded-xl border border-gray-100 flex items-start justify-between gap-3">
                  <div class="flex flex-col min-w-0">
                    <span class="text-[10px] text-gray-400 uppercase font-bold">
                      <%= column.label %><%= if column.primary_key, do: " · key" %>
                    </span>
                    <span class="text-xs text-gray-900 break-all font-mono">
                      <%= if is_nil(value) or value == "" do %>
                        <span class="text-gray-300 italic">no value</span>
                      <% else %>
                        <%= value %>
                      <% end %>
                    </span>
                  </div>

                  <%= if column.badge and value not in [nil, ""] do %>
                    <span class="px-2 py-0.5 text-[10px] font-bold rounded-full bg-violet-100 text-violet-800 shrink-0">
                      <%= value %>
                    </span>
                  <% else %>
                    <span class="text-[10px] font-mono text-gray-400 shrink-0"><%= column.type %></span>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <div class="pt-4 border-t border-gray-100 flex items-center gap-2">
            <button
              type="button"
              phx-click="edit_resource"
              phx-target={@myself}
              class="px-4 py-2 text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 border border-violet-200 rounded-xl transition-colors"
            >
              Edit
            </button>

            <button
              type="button"
              phx-click="close_focus"
              class="flex-1 py-2 text-xs font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
            >
              Close Inspector
            </button>
          </div>
        </.inspect_popup>
      <% end %>

      <!-- CSV / JSON Export Modal -->
      <!--
        The row form. Every field comes from the plugin's declared schema, so a record that gains a
        column gains an input and nothing here has to know what the column means.
      -->
      <%= if @resource_form do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 space-y-4">
            <div class="flex items-start justify-between">
              <div>
                <h3 class="text-base font-bold text-gray-900">
                  <%= if @resource_form.mode == :new, do: "New", else: "Edit" %>
                  <%= Phoenix.Naming.humanize(to_string(@selected_resource_name)) %>
                </h3>
                <p class="text-xs text-gray-500 mt-0.5">
                  Fields come from the schema this plugin declares.
                </p>
              </div>

              <button
                type="button"
                phx-click="close_resource_form"
                phx-target={@myself}
                class="text-gray-400 hover:text-gray-600 font-bold"
              >
                ✕
              </button>
            </div>

            <form
              phx-submit="submit_resource_form"
              phx-change="resource_form_change"
              phx-target={@myself}
              class="space-y-3"
            >
              <%= for column <- current_resource_columns(assigns) do %>
                <% key = to_string(column.key) %>
                <% value = Map.get(@resource_form.values, key, "") %>
                <% locked = column.primary_key and @resource_form.mode == :edit %>

                <div>
                  <label class="block text-[11px] font-bold text-gray-500 uppercase tracking-wider mb-1">
                    <%= column.label %><%= if column.primary_key, do: " · key" %>
                  </label>

                  <% custom_spec = Exoforge.Std.Dashboard.InputTypes.resolve(column) %>

                  <%= if is_map(custom_spec) do %>
                    <.widget spec={custom_spec} name={"values[#{key}]"} value={value} readonly={locked} />
                  <% else %>
                    <%= case column.type do %>
                      <% _ when column.choices != [] -> %>
                        <select
                          name={"values[#{key}]"}
                          class="w-full px-3 py-2 text-sm border border-gray-200 rounded-xl focus:ring-2 focus:ring-violet-500 focus:border-transparent font-mono bg-white"
                        >
                          <%= for choice <- column.choices do %>
                            <option value={choice} selected={to_string(value) == to_string(choice)}>
                              <%= choice %>
                            </option>
                          <% end %>
                        </select>
                      <% :boolean -> %>
                        <input type="hidden" name={"values[#{key}]"} value="false" />
                        <input
                          type="checkbox"
                          name={"values[#{key}]"}
                          value="true"
                          checked={value == "true"}
                          class="w-4 h-4 text-violet-600 rounded border-gray-300 focus:ring-violet-500"
                        />
                      <% :integer -> %>
                        <input
                          type="number"
                          step="1"
                          name={"values[#{key}]"}
                          value={value}
                          readonly={locked}
                          class="w-full px-3 py-2 text-sm border border-gray-200 rounded-xl focus:ring-2 focus:ring-violet-500 focus:border-transparent font-mono"
                        />
                      <% :float -> %>
                        <input
                          type="number"
                          step="any"
                          name={"values[#{key}]"}
                          value={value}
                          readonly={locked}
                          class="w-full px-3 py-2 text-sm border border-gray-200 rounded-xl focus:ring-2 focus:ring-violet-500 focus:border-transparent font-mono"
                        />
                      <% _ -> %>
                        <input
                          type="text"
                          name={"values[#{key}]"}
                          value={value}
                          readonly={locked}
                          class={"w-full px-3 py-2 text-sm border border-gray-200 rounded-xl focus:ring-2 focus:ring-violet-500 focus:border-transparent font-mono #{if locked, do: "bg-gray-50 text-gray-500"}"}
                        />
                    <% end %>
                  <% end %>

                  <%= if error = @resource_form.errors[key] do %>
                    <p class="text-[11px] text-red-600 mt-1 font-semibold"><%= error %></p>
                  <% end %>
                </div>
              <% end %>

              <%= if error = @resource_form.errors["_form"] do %>
                <p class="text-xs text-red-600 bg-red-50 border border-red-200 rounded-xl p-3 font-mono">
                  <%= error %>
                </p>
              <% end %>

              <div class="pt-2 flex items-center gap-2">
                <button
                  type="submit"
                  class="px-4 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl transition-colors shadow-sm"
                >
                  Save
                </button>

                <button
                  type="button"
                  phx-click="close_resource_form"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

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
