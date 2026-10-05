defmodule Exoforge.Std.DashboardViews.PluginManagerView do
  @moduledoc """
  Phoenix LiveComponent providing the dynamic Producer & Designer Studio visualization
  for the Plugin Manager & Cluster Runtime service (:plugin_manager).

  Enables game producers and backend engineers to:
  - Inspect installed standard and WASM plugins, entity schemas, and manifests
    (capability inspection lives in the Extensions Registry; this view owns lifecycle)
  - Monitor live BEAM node metrics, memory, process counts, and active stateful entities
  - Drag-and-drop or upload new sandboxed C# WASM plugins directly into the running cluster
  - Hot-reload and restart the cluster runtime supervision tree
  - Remove dynamically installed plugins safely
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       plugins: [],
       filtered_plugins: [],
       system_info: %{},
       search_query: "",
       type_filter: "all",
       selected_plugin: nil,
       active_drawer_tab: "overview",
       show_upload_modal: false,
       show_restart_modal: false,
       show_dependency_graph: false,
       graph_selected_plugin_id: nil,
       upload_form: %{
         "name" => "",
         "binary" => "",
         "manifest_json" => ""
       },
       upload_file_info: nil,
       upload_error: nil,
       upload_success: nil,
       restart_status: nil,
       action_notification: nil,
       loaded: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.loaded do
        socket
      else
        socket
        |> assign(:loaded, true)
        |> load_data()
      end

    {:ok, socket}
  end

  ## ---- EVENT HANDLERS ----

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(search_query: query)
      |> apply_filters()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(type_filter: type)
      |> apply_filters()

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_dependency_graph", _params, socket) do
    {:noreply, assign(socket, show_dependency_graph: true, graph_selected_plugin_id: nil)}
  end

  @impl true
  def handle_event("close_dependency_graph", _params, socket) do
    {:noreply, assign(socket, show_dependency_graph: false, graph_selected_plugin_id: nil)}
  end

  @impl true
  def handle_event("select_graph_plugin", %{"id" => id}, socket) do
    current = socket.assigns.graph_selected_plugin_id
    new_id = if current == id, do: nil, else: id
    {:noreply, assign(socket, graph_selected_plugin_id: new_id)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("inspect_plugin", %{"id" => id}, socket) do
    plugin =
      case ActionDispatcher.dispatch(:plugin_manager, :get_plugin, %{id: id}) do
        {:ok, %{plugin: p}} ->
          p

        _ ->
          Enum.find(socket.assigns.plugins, fn p ->
            to_string(p["id"]) == to_string(id)
          end)
      end

    {:noreply, assign(socket, selected_plugin: plugin, active_drawer_tab: "overview")}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, selected_plugin: nil)}
  end

  @impl true
  def handle_event("set_drawer_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_drawer_tab: tab)}
  end

  @impl true
  def handle_event("open_upload_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_upload_modal: true,
       upload_error: nil,
       upload_file_info: nil,
       upload_form: %{
         "name" => "",
         "type" => "wasm",
         "binary" => "",
         "elixir_code" => "",
         "manifest_json" => ""
       }
     )}
  end

  @impl true
  def handle_event("close_upload_modal", _params, socket) do
    {:noreply, assign(socket, show_upload_modal: false, upload_error: nil)}
  end

  @impl true
  def handle_event("change_upload_form", %{"upload" => params}, socket) do
    merged = Map.merge(socket.assigns.upload_form, params)
    {:noreply, assign(socket, upload_form: merged)}
  end

  @impl true
  def handle_event(
        "file_selected",
        %{"filename" => filename, "content_base64" => base64, "size" => size},
        socket
      ) do
    ext = Path.extname(filename)
    is_ex = ext in [".ex", ".exs"]

    clean_name =
      filename
      |> Path.rootname(ext)
      |> Macro.underscore()
      |> String.replace(~r/[^a-z0-9_]/, "")

    current_form = socket.assigns.upload_form

    updated_form =
      if is_ex do
        decoded =
          case Base.decode64(base64) do
            {:ok, txt} -> txt
            _ -> ""
          end

        current_form
        |> Map.put("type", "elixir")
        |> Map.put("elixir_code", decoded)
        |> Map.put(
          "name",
          if(current_form["name"] == "", do: clean_name, else: current_form["name"])
        )
      else
        current_form
        |> Map.put("type", "wasm")
        |> Map.put("binary", base64)
        |> Map.put(
          "name",
          if(current_form["name"] == "", do: clean_name, else: current_form["name"])
        )
      end

    {:noreply,
     assign(socket,
       upload_form: updated_form,
       upload_file_info: %{filename: filename, size_bytes: size},
       upload_error: nil
     )}
  end

  @impl true
  def handle_event("submit_upload", %{"upload" => params}, socket) do
    name = String.trim(Map.get(params, "name", ""))
    type = Map.get(params, "type", socket.assigns.upload_form["type"] || "wasm")

    raw_binary =
      String.trim(Map.get(params, "binary", socket.assigns.upload_form["binary"] || ""))

    elixir_code =
      String.trim(Map.get(params, "elixir_code", socket.assigns.upload_form["elixir_code"] || ""))

    manifest_raw = String.trim(Map.get(params, "manifest_json", ""))

    manifest =
      if manifest_raw != "" do
        case Jason.decode(manifest_raw) do
          {:ok, parsed} -> parsed
          _ -> nil
        end
      else
        nil
      end

    cond do
      name == "" ->
        {:noreply, assign(socket, upload_error: "Plugin name is required.")}

      type == "elixir" and elixir_code == "" ->
        {:noreply, assign(socket, upload_error: "Elixir module code is required.")}

      type == "wasm" and raw_binary == "" ->
        {:noreply, assign(socket, upload_error: "WASM binary content or file is required.")}

      true ->
        payload =
          if type == "elixir" do
            %{
              name: name,
              type: "elixir",
              elixir_code: elixir_code,
              manifest: manifest
            }
          else
            %{
              name: name,
              type: "wasm",
              binary: raw_binary,
              manifest: manifest
            }
          end

        case ActionDispatcher.dispatch(:plugin_manager, :upload_plugin, payload) do
          {:ok, result} ->
            socket =
              socket
              |> assign(
                show_upload_modal: false,
                upload_error: nil,
                upload_file_info: nil,
                upload_success:
                  "Plugin '#{result.plugin_id}' (#{result[:type] || type}) successfully uploaded and initialized!"
              )
              |> load_data()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, upload_error: "Upload failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("remove_plugin", %{"id" => id}, socket) do
    case ActionDispatcher.dispatch(:plugin_manager, :remove_plugin, %{id: id}) do
      {:ok, _result} ->
        socket =
          socket
          |> assign(
            selected_plugin: nil,
            action_notification: "Plugin '#{id}' successfully removed from runtime."
          )
          |> load_data()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         assign(socket, action_notification: "Failed to remove plugin: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("open_restart_modal", _params, socket) do
    {:noreply, assign(socket, show_restart_modal: true)}
  end

  @impl true
  def handle_event("close_restart_modal", _params, socket) do
    {:noreply, assign(socket, show_restart_modal: false)}
  end

  @impl true
  def handle_event("confirm_restart", _params, socket) do
    case ActionDispatcher.dispatch(:plugin_manager, :restart_system, %{}) do
      {:ok, result} ->
        socket =
          socket
          |> assign(
            show_restart_modal: false,
            restart_status:
              "Runtime cluster restarted. #{result.plugins_count} plugins reloaded successfully."
          )
          |> load_data()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           show_restart_modal: false,
           action_notification: "System restart failed: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def handle_event("dismiss_notification", _params, socket) do
    {:noreply,
     assign(socket,
       upload_success: nil,
       restart_status: nil,
       action_notification: nil
     )}
  end

  ## ---- PRIVATE HELPERS ----

  defp load_data(socket) do
    plugins =
      case ActionDispatcher.dispatch(:plugin_manager, :list_plugins, %{}) do
        {:ok, %{plugins: list}} -> list
        _ -> []
      end

    sys_info =
      case ActionDispatcher.dispatch(:plugin_manager, :get_system_info, %{}) do
        {:ok, %{system: info}} -> info
        _ -> %{}
      end

    socket
    |> assign(plugins: plugins, system_info: sys_info)
    |> apply_filters()
  end

  defp apply_filters(socket) do
    query = String.downcase(String.trim(socket.assigns.search_query))

    filtered =
      Enum.filter(socket.assigns.plugins, fn p ->
        id = String.downcase(to_string(p["id"] || ""))
        name = String.downcase(to_string(p["name"] || ""))
        provides = Enum.map(p["provides"] || [], &String.downcase(to_string(&1)))

        query == "" or
          String.contains?(id, query) or
          String.contains?(name, query) or
          Enum.any?(provides, &String.contains?(&1, query))
      end)

    assign(socket, filtered_plugins: filtered)
  end

  defp format_uptime(nil), do: "—"

  defp format_uptime(secs) when is_integer(secs) do
    cond do
      secs < 60 -> "#{secs}s"
      secs < 3600 -> "#{div(secs, 60)}m #{rem(secs, 60)}s"
      true -> "#{div(secs, 3600)}h #{div(rem(secs, 3600), 60)}m"
    end
  end

  defp format_uptime(_), do: "—"

  defp wasm_plugin?(plugin) do
    type = String.downcase(to_string(plugin["type"] || ""))
    type in ["wasm", "c# wasm", "wasi"]
  end

  defp csharp_snippet(plugin) do
    provides = plugin["provides"] || ["service"]

    services_code =
      Enum.map_join(provides, "\n\n", fn svc ->
        "// Call action on '" <>
          svc <>
          "' service\n" <>
          "var response = await client.InvokeAsync<dynamic>(\n" <>
          "    service: \"" <>
          svc <>
          "\",\n" <>
          "    action: \"execute\",\n" <>
          "    parameters: new {\n" <>
          "        // arguments here\n" <>
          "    }\n" <>
          ");"
      end)

    "// C# Unity / Client SDK snippet\n" <>
      "using Exoforge.Client;\n\n" <>
      services_code
  end

  ## ---- TEMPLATE RENDERING ----

  @impl true
  def render(assigns) do
    total_plugins = length(assigns.plugins)
    wasm_count = Enum.count(assigns.plugins, &wasm_plugin?/1)
    native_count = total_plugins - wasm_count
    active_entities = Map.get(assigns.system_info, "active_entities_count", 0)
    memory_mb = Map.get(assigns.system_info, "memory_mb", 0.0)
    node_name = Map.get(assigns.system_info, "node", "nonode@nohost")
    uptime = format_uptime(Map.get(assigns.system_info, "uptime_seconds"))
    otp_release = Map.get(assigns.system_info, "otp_release", System.otp_release())
    elixir_ver = Map.get(assigns.system_info, "elixir_version", System.version())

    assigns =
      assigns
      |> assign(:total_plugins, total_plugins)
      |> assign(:wasm_count, wasm_count)
      |> assign(:native_count, native_count)
      |> assign(:active_entities, active_entities)
      |> assign(:memory_mb, memory_mb)
      |> assign(:node_name, node_name)
      |> assign(:uptime, uptime)
      |> assign(:otp_release, otp_release)
      |> assign(:elixir_ver, elixir_ver)

    ~H"""
    <div class="space-y-6" id={@id}>
      <!-- Top Header & Actions -->
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200/80 shadow-sm">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-2xl bg-violet-100 text-violet-700 flex items-center justify-center text-2xl shadow-inner">
            📦
          </div>
          <div>
            <div class="flex items-center gap-3">
              <h2 class="text-xl font-bold text-gray-900">Plugin Manager &amp; Cluster Runtime</h2>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-800">
                Extension Live
              </span>
            </div>
            <p class="text-sm text-gray-500 mt-0.5">
              Manage runtime lifecycle, inspect contracts &amp; actor schemas, and hot-load sandboxed C# WebAssembly modules.
            </p>
          </div>
        </div>

        <div class="flex items-center gap-3">
          <button
            phx-click="refresh"
            phx-target={@myself}
            class="px-3.5 py-2 text-sm font-semibold text-gray-700 bg-white border border-gray-300 rounded-xl hover:bg-gray-50 transition-colors shadow-sm flex items-center gap-2"
          >
            <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>

          <button
            phx-click="open_dependency_graph"
            phx-target={@myself}
            class="px-3.5 py-2 text-sm font-semibold text-violet-700 bg-violet-50 border border-violet-200 rounded-xl hover:bg-violet-100 transition-colors shadow-sm flex items-center gap-2"
            title="View visual dependency graph"
          >
            <svg class="w-4 h-4 text-violet-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z" />
            </svg>
            Dependency Graph
          </button>

          <button
            phx-click="open_restart_modal"
            phx-target={@myself}
            class="px-3.5 py-2 text-sm font-semibold text-red-700 bg-red-50 border border-red-200 rounded-xl hover:bg-red-100 transition-colors shadow-sm flex items-center gap-2"
            title="Hot-reload plugin supervision trees and clear cache"
          >
            <svg class="w-4 h-4 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            Restart Cluster
          </button>

          <button
            phx-click="open_upload_modal"
            phx-target={@myself}
            class="px-4 py-2 text-sm font-semibold text-white bg-violet-600 rounded-xl hover:bg-violet-700 transition-colors shadow-sm flex items-center gap-2"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
            </svg>
            Upload WASM Plugin
          </button>
        </div>
      </div>

      <!-- Action Success / Notification Banner -->
      <%= if @upload_success || @restart_status || @action_notification do %>
        <div class="bg-gradient-to-r from-emerald-50 to-teal-50 border border-emerald-200 rounded-2xl p-4 shadow-sm flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-lg bg-emerald-600 text-white flex items-center justify-center font-bold text-sm shrink-0">
              ✓
            </div>
            <p class="text-xs font-bold text-emerald-900">
              <%= @upload_success || @restart_status || @action_notification %>
            </p>
          </div>
          <button
            phx-click="dismiss_notification"
            phx-target={@myself}
            class="text-emerald-500 hover:text-emerald-800 text-sm font-bold p-1"
          >
            ✕
          </button>
        </div>
      <% end %>

      <!-- Metric Cards Grid -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-5">
        <!-- 1. Installed Plugins -->
        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Installed Plugins</span>
            <span class="text-lg">📦</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @total_plugins %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-violet-50 text-violet-700">
              Active Extensions
            </span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Modular service extensions</p>
        </div>

        <!-- 2. BEAM Memory & Processes -->
        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">BEAM Memory &amp; Load</span>
            <span class="text-lg">⚡</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @memory_mb %> MB</span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-emerald-50 text-emerald-700">
              <%= Map.get(@system_info, "process_count", "—") %> procs
            </span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Erlang memory allocated</p>
        </div>

        <!-- 3. Cluster Node & Uptime -->
        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Cluster Node</span>
            <span class="text-lg">🌐</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-sm font-black font-mono text-gray-900 truncate max-w-[140px]" title={@node_name}><%= @node_name %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-blue-50 text-blue-700"><%= @uptime %></span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Distributed node uptime</p>
        </div>

        <!-- 4. Stateful Actors & Engine -->
        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Active Entities</span>
            <span class="text-lg">👾</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @active_entities %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-purple-50 text-purple-700">
              OTP <%= @otp_release %>
            </span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Distributed virtual actors</p>
        </div>
      </div>

      <!-- Filters & Search Toolbar -->
      <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div class="flex items-center gap-3 flex-1 max-w-lg">
          <div class="relative w-full">
            <input
              type="text"
              placeholder="Search plugin by name, ID, or provided service..."
              value={@search_query}
              phx-input="search"
              phx-target={@myself}
              phx-debounce="150"
              name="query"
              class="w-full pl-9 pr-4 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white transition-all"
            />
            <svg class="w-4 h-4 text-gray-400 absolute left-3 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <button
            phx-click="open_dependency_graph"
            phx-target={@myself}
            class="px-3 py-1.5 text-xs font-semibold text-violet-700 bg-violet-50 hover:bg-violet-100 border border-violet-200 rounded-lg transition-colors flex items-center gap-1.5"
          >
            <svg class="w-3.5 h-3.5 text-violet-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z" />
            </svg>
            Show Dependency Graph
          </button>
        </div>
      </div>

      <!-- Plugins Directory Table -->
      <div class="bg-white rounded-2xl border border-gray-200/80 shadow-sm overflow-hidden">
        <%= if @filtered_plugins == [] do %>
          <div class="p-12 text-center">
            <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl mb-3">
              📦
            </div>
            <h3 class="text-sm font-bold text-gray-900">No plugins match your query</h3>
            <p class="text-xs text-gray-500 mt-1 max-w-sm mx-auto">
              Try adjusting your search terms to locate installed plugins.
            </p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="bg-gray-50/75 border-b border-gray-200 text-[11px] font-bold text-gray-500 uppercase tracking-wider">
                  <th class="py-3 px-4">Plugin</th>
                  <th class="py-3 px-4">Version</th>
                  <th class="py-3 px-4">Provided Services</th>
                  <th class="py-3 px-4">Dependencies</th>
                  <th class="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 text-sm">
                <%= for plugin <- @filtered_plugins do %>
                  <% is_wasm = wasm_plugin?(plugin) %>
                  <tr class="hover:bg-violet-50/20 transition-colors group">
                    <td class="py-3 px-4">
                      <div class="flex items-center gap-3">
                        <div class="w-8 h-8 rounded-lg bg-violet-100 text-violet-800 flex items-center justify-center font-bold text-sm shrink-0">
                          📦
                        </div>
                        <div>
                          <div class="font-bold text-gray-900 flex items-center gap-1.5">
                            <span><%= plugin["name"] %></span>
                          </div>
                          <span class="font-mono text-[11px] text-gray-400"><%= plugin["id"] %></span>
                        </div>
                      </div>
                    </td>

                    <td class="py-3 px-4 font-mono text-xs text-gray-600">
                      v<%= plugin["version"] || "0.1.0" %>
                    </td>

                    <td class="py-3 px-4">
                      <div class="flex flex-wrap gap-1">
                        <%= for s <- plugin["provides"] || [] do %>
                          <span class="inline-flex items-center px-2 py-0.5 rounded-md text-[10px] font-bold font-mono bg-violet-50 text-violet-700 border border-violet-200">
                            :<%= s %>
                          </span>
                        <% end %>
                        <%= if (plugin["provides"] || []) == [] do %>
                          <span class="text-xs text-gray-400 italic">—</span>
                        <% end %>
                      </div>
                    </td>

                    <td class="py-3 px-4">
                      <div class="flex flex-wrap gap-1">
                        <%= for d <- plugin["dependencies"] || [] do %>
                          <span class="inline-flex items-center px-2 py-0.5 rounded-md text-[10px] font-semibold font-mono bg-gray-100 text-gray-600">
                            :<%= d %>
                          </span>
                        <% end %>
                        <%= if (plugin["dependencies"] || []) == [] do %>
                          <span class="text-xs text-gray-400 italic">None</span>
                        <% end %>
                      </div>
                    </td>

                    <td class="py-3 px-4 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <button
                          phx-click="inspect_plugin"
                          phx-value-id={plugin["id"]}
                          phx-target={@myself}
                          title="Inspect manifest, actions, and schemas"
                          class="px-2.5 py-1 text-xs font-semibold text-gray-700 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg transition-colors"
                        >
                          Inspect
                        </button>

                        <%= if is_wasm do %>
                          <button
                            phx-click="remove_plugin"
                            phx-value-id={plugin["id"]}
                            phx-target={@myself}
                            data-confirm={"Are you sure you want to unload plugin #{plugin["id"]}?"}
                            title="Unload and remove plugin from cluster"
                            class="px-2.5 py-1 text-xs font-semibold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 rounded-lg transition-colors"
                          >
                            Remove
                          </button>
                        <% else %>
                          <span class="text-[11px] text-gray-400 px-1 font-medium" title="Core system plugin cannot be removed">
                            System
                          </span>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <!-- Slide-over Plugin Inspector Drawer -->
      <%= if @selected_plugin do %>
        <div class="fixed inset-0 z-50 overflow-hidden bg-black/40 backdrop-blur-xs flex justify-end">
          <div class="bg-white w-full max-w-2xl h-full shadow-2xl border-l border-gray-200 flex flex-col justify-between overflow-y-auto animate-in slide-in-from-right duration-200">
            <div>
              <!-- Drawer Header -->
              <div class="p-6 border-b border-gray-100 flex items-center justify-between bg-gray-50/70">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-800 flex items-center justify-center font-bold text-lg">
                    📦
                  </div>
                  <div>
                    <h3 class="text-base font-bold text-gray-900"><%= @selected_plugin["name"] %></h3>
                    <p class="text-xs font-mono text-gray-500"><%= @selected_plugin["id"] %> (v<%= @selected_plugin["version"] %>)</p>
                  </div>
                </div>
                <button
                  phx-click="close_drawer"
                  phx-target={@myself}
                  class="text-gray-400 hover:text-gray-600 text-lg font-bold p-1"
                >
                  ✕
                </button>
              </div>

              <!-- Drawer Tabs -->
              <div class="flex items-center gap-1 px-6 py-2 border-b border-gray-100 bg-white">
                <%= for {tab_id, tab_label} <- [{"overview", "Overview"}, {"entities", "Entities"}, {"csharp", "C# / Unity SDK"}, {"manifest", "Raw Manifest"}] do %>
                  <button
                    phx-click="set_drawer_tab"
                    phx-value-tab={tab_id}
                    phx-target={@myself}
                    class={"px-3 py-1.5 rounded-lg text-xs font-bold transition-all #{if @active_drawer_tab == tab_id, do: "bg-violet-50 text-violet-800 border border-violet-200", else: "text-gray-500 hover:text-gray-900 hover:bg-gray-50"}"}
                  >
                    <%= tab_label %>
                  </button>
                <% end %>
              </div>

              <!-- Drawer Tab Content -->
              <div class="p-6 space-y-6">
                <%= if @active_drawer_tab == "overview" do %>
                  <div class="space-y-4">
                    <div class="grid grid-cols-2 gap-3">
                      <div class="bg-gray-50 p-3.5 rounded-xl border border-gray-200">
                        <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">Plugin Version</span>
                        <span class="text-sm font-bold text-gray-900 mt-1 block">
                          v<%= @selected_plugin["version"] || "0.1.0" %>
                        </span>
                      </div>
                      <div class="bg-gray-50 p-3.5 rounded-xl border border-gray-200">
                        <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">Supervision Status</span>
                        <span class="text-sm font-bold text-emerald-600 mt-1 block flex items-center gap-1.5">
                          <span class="w-2 h-2 rounded-full bg-emerald-500"></span> Active &amp; Supervised
                        </span>
                      </div>
                    </div>

                    <div>
                      <span class="text-xs font-bold text-gray-700 uppercase tracking-wider block mb-1">Entry Point</span>
                      <p class="font-mono text-xs bg-gray-50 p-2.5 rounded-xl border border-gray-200 text-gray-800 break-all select-all">
                        <%= @selected_plugin["entry_point"] || "Elixir Module" %>
                      </p>
                    </div>

                    <%= if @selected_plugin["physical_path"] do %>
                      <div>
                        <span class="text-xs font-bold text-gray-700 uppercase tracking-wider block mb-1">Physical Path</span>
                        <p class="font-mono text-xs bg-gray-50 p-2.5 rounded-xl border border-gray-200 text-gray-800 break-all select-all">
                          <%= @selected_plugin["physical_path"] %>
                        </p>
                      </div>
                    <% end %>

                    <div>
                      <span class="text-xs font-bold text-gray-700 uppercase tracking-wider block mb-2">Provided Service Contracts</span>
                      <div class="flex flex-wrap gap-1.5">
                        <%= for svc <- @selected_plugin["provides"] || [] do %>
                          <span class="px-2.5 py-1 bg-violet-50 text-violet-800 border border-violet-200 rounded-lg text-xs font-mono font-bold">
                            :<%= svc %>
                          </span>
                        <% end %>
                      </div>
                    </div>

                    <div>
                      <span class="text-xs font-bold text-gray-700 uppercase tracking-wider block mb-2">Service Dependencies</span>
                      <div class="flex flex-wrap gap-1.5">
                        <%= for dep <- @selected_plugin["dependencies"] || [] do %>
                          <span class="px-2.5 py-1 bg-gray-100 text-gray-700 border border-gray-200 rounded-lg text-xs font-mono font-semibold">
                            :<%= dep %>
                          </span>
                        <% end %>
                        <%= if (@selected_plugin["dependencies"] || []) == [] do %>
                          <span class="text-xs text-gray-400 italic">No dependencies required</span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>

                <%= if @active_drawer_tab == "entities" do %>
                  <div class="space-y-4">
                    <% entities = @selected_plugin["entities"] || [] %>
                    <%= if entities == [] do %>
                      <p class="text-xs text-gray-400 italic bg-gray-50 p-4 rounded-xl border border-gray-200">
                        No stateful virtual entities registered for this plugin.
                      </p>
                    <% else %>
                      <%= for ent <- entities do %>
                        <div class="bg-gray-50 p-4 rounded-xl border border-gray-200 space-y-2">
                          <div class="flex items-center justify-between">
                            <span class="text-sm font-bold font-mono text-purple-700">:<%= ent["name"] || ent[:name] %></span>
                            <span class="text-[10px] font-bold text-gray-500">Stateful Entity</span>
                          </div>
                          <p class="text-xs text-gray-500">
                            Clustered actor supervised via Horde / :pg distributed runtime.
                          </p>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>

                <%= if @active_drawer_tab == "csharp" do %>
                  <div class="space-y-3">
                    <p class="text-xs text-gray-500">
                      Invoke this plugin directly from Unity or C# clients using <code class="font-mono text-violet-700 font-bold">Exoforge.Client</code>:
                    </p>
                    <pre class="bg-gray-900 text-gray-100 p-4 rounded-xl font-mono text-xs overflow-x-auto select-all leading-relaxed"><%= csharp_snippet(@selected_plugin) %></pre>
                  </div>
                <% end %>

                <%= if @active_drawer_tab == "manifest" do %>
                  <div class="space-y-2">
                    <pre class="bg-gray-900 text-gray-100 p-4 rounded-xl font-mono text-xs overflow-x-auto select-all leading-relaxed max-h-96"><%= Jason.encode!(@selected_plugin, pretty: true) %></pre>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Drawer Footer -->
            <div class="p-6 border-t border-gray-100 bg-gray-50 flex items-center justify-between">
              <%= if wasm_plugin?(@selected_plugin) do %>
                <button
                  phx-click="remove_plugin"
                  phx-value-id={@selected_plugin["id"]}
                  phx-target={@myself}
                  data-confirm={"Are you sure you want to unload plugin #{@selected_plugin["id"]}?"}
                  class="px-4 py-2 text-xs font-bold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 rounded-xl transition-colors"
                >
                  Unload &amp; Remove Plugin
                </button>
              <% else %>
                <span class="text-xs text-gray-400 italic">Built-in standard plugin</span>
              <% end %>

              <button
                phx-click="close_drawer"
                phx-target={@myself}
                class="px-4 py-2 text-xs font-bold text-gray-700 bg-white hover:bg-gray-100 border border-gray-300 rounded-xl transition-colors shadow-sm ml-auto"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Upload WASM Plugin Modal -->
      <%= if @show_upload_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_upload_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-5">
              <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-700 flex items-center justify-center text-xl">
                ⚡
              </div>
              <div>
                <h3 class="text-lg font-bold text-gray-900"><%= if @upload_form["type"] == "elixir", do: "Upload Elixir Plugin", else: "Upload C# WASM Plugin" %></h3>
                <p class="text-xs text-gray-500">Deploy a compiled WebAssembly binary or live Elixir plugin into the runtime.</p>
              </div>
            </div>

            <%= if @upload_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @upload_error %>
              </div>
            <% end %>

            <form id="upload_plugin_form" phx-submit="submit_upload" phx-change="change_upload_form" phx-target={@myself} class="space-y-4">
              <!-- Plugin Type Selector -->
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-2">Plugin Type</label>
                <div class="grid grid-cols-2 gap-3">
                  <label class={"flex items-center gap-2 p-3 rounded-xl border cursor-pointer transition-colors #{if @upload_form["type"] != "elixir", do: "border-violet-500 bg-violet-50/50 text-violet-900", else: "border-gray-200 bg-gray-50 text-gray-700"}"}>
                    <input
                      type="radio"
                      name="upload[type]"
                      value="wasm"
                      checked={@upload_form["type"] != "elixir"}
                      class="text-violet-600 focus:ring-violet-500"
                    />
                    <div>
                      <span class="text-xs font-bold block">C# WASM</span>
                      <span class="text-[10px] text-gray-500">Compiled .wasm binary</span>
                    </div>
                  </label>
                  <label class={"flex items-center gap-2 p-3 rounded-xl border cursor-pointer transition-colors #{if @upload_form["type"] == "elixir", do: "border-violet-500 bg-violet-50/50 text-violet-900", else: "border-gray-200 bg-gray-50 text-gray-700"}"}>
                    <input
                      type="radio"
                      name="upload[type]"
                      value="elixir"
                      checked={@upload_form["type"] == "elixir"}
                      class="text-violet-600 focus:ring-violet-500"
                    />
                    <div>
                      <span class="text-xs font-bold block">Elixir Plugin</span>
                      <span class="text-[10px] text-gray-500">Live source module (.ex)</span>
                    </div>
                  </label>
                </div>
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Plugin Name / Identifier</label>
                <input
                  type="text"
                  name="upload[name]"
                  value={@upload_form["name"]}
                  placeholder={if @upload_form["type"] == "elixir", do: "e.g. custom_quest", else: "e.g. my_wasm_plugin"}
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                />
              </div>

              <%= if @upload_form["type"] == "elixir" do %>
                <!-- Elixir Module Code Input -->
                <div>
                  <div class="flex items-center justify-between mb-1">
                    <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider">Elixir Source Code (.ex)</label>
                    <span class="text-[11px] text-gray-400 font-mono">use Exoforge.Plugin</span>
                  </div>
                  <textarea
                    name="upload[elixir_code]"
                    rows="6"
                    placeholder={"defmodule MyPlugin do\n  use Exoforge.Plugin, provides: [:my_service]\n\n  defaction ping(payload) do\n    {:ok, %{pong: payload}}\n  end\nend"}
                    class="w-full px-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                  ><%= @upload_form["elixir_code"] %></textarea>
                </div>
              <% else %>
                <!-- WASM File Dropzone / Selector -->
                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">WASM Binary (.wasm)</label>
                  <div class="border-2 border-dashed border-gray-300 rounded-xl p-4 text-center hover:border-violet-400 transition-colors bg-gray-50/50">
                    <input
                      type="file"
                      id="wasm_file_picker"
                      accept=".wasm"
                      onchange="
                        const file = this.files[0];
                        if (file) {
                          const reader = new FileReader();
                          reader.onload = (e) => {
                            const base64 = e.target.result.split(',')[1];
                            const input = document.getElementById('wasm_base64_input');
                            if (input) {
                              input.value = base64;
                              input.dispatchEvent(new Event('input', {bubbles: true}));
                            }
                          };
                          reader.readAsDataURL(file);
                        }
                      "
                      class="block w-full text-xs text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-xs file:font-semibold file:bg-violet-50 file:text-violet-700 hover:file:bg-violet-100 cursor-pointer"
                    />
                    <%= if @upload_file_info do %>
                      <p class="text-xs text-emerald-600 font-bold mt-2">
                        Selected: <%= @upload_file_info.filename %> (<%= Float.round(@upload_file_info.size_bytes / 1024, 1) %> KB)
                      </p>
                    <% end %>
                  </div>
                </div>

                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Or Paste Base64 WASM Data</label>
                  <textarea
                    id="wasm_base64_input"
                    name="upload[binary]"
                    rows="3"
                    placeholder="AGFzbQEAAAA... (Base64 encoded binary)"
                    class="w-full px-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                  ><%= @upload_form["binary"] %></textarea>
                  <p class="text-[11px] text-gray-400 mt-0.5">Must start with WASM magic bytes (\0asm).</p>
                </div>
              <% end %>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Optional Manifest Metadata (JSON)</label>
                <textarea
                  name="upload[manifest_json]"
                  rows="2"
                  placeholder='{"version": "1.0.0", "category": "Gameplay"}'
                  class="w-full px-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                ><%= @upload_form["manifest_json"] %></textarea>
              </div>

              <div class="pt-4 flex items-center justify-end gap-3 border-t border-gray-100">
                <button
                  type="button"
                  phx-click="close_upload_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-5 py-2 text-xs font-bold text-white bg-violet-600 rounded-xl hover:bg-violet-700 transition-colors shadow-sm"
                >
                  Upload &amp; Hot-Load Plugin
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Restart Confirmation Modal -->
      <%= if @show_restart_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-red-100 text-red-700 flex items-center justify-center text-xl shrink-0">
                ⚠️
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900">Restart Cluster Supervision?</h3>
                <p class="text-xs text-gray-500">Hot-reloads all plugin supervision trees and manifests.</p>
              </div>
            </div>

            <p class="text-xs text-gray-600 mb-5 leading-relaxed bg-amber-50 p-3 rounded-xl border border-amber-200">
              This action re-executes topological sorting, re-initializes plugin worker registries, and hot-swaps updated WASM binaries into memory.
            </p>

            <div class="flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_restart_modal"
                phx-target={@myself}
                class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900 transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                phx-click="confirm_restart"
                phx-target={@myself}
                class="px-5 py-2 text-xs font-bold text-white bg-red-600 rounded-xl hover:bg-red-700 transition-colors shadow-sm"
              >
                Yes, Restart Runtime
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Plugin Dependency Graph Modal -->
      <%= if @show_dependency_graph do %>
        <Exoforge.Std.DashboardViews.DependencyGraph.graph
          plugins={@plugins}
          selected_plugin_id={@graph_selected_plugin_id}
          target={@myself}
        />
      <% end %>
    </div>
    """
  end
end
