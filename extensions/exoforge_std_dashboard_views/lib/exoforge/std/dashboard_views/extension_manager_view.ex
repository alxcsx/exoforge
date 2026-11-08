defmodule Exoforge.Std.DashboardViews.ExtensionManagerView do
  @moduledoc """
  Phoenix LiveComponent providing the dynamic Producer & Designer Studio visualization
  for the Extension Manager & Cluster Runtime service (:extension_manager).

  Enables game producers and backend engineers to:
  - Inspect installed standard and native extensions, entity schemas, and manifests
    (capability inspection lives in the Extensions Registry; this view owns lifecycle)
  - Monitor live BEAM node metrics, memory, process counts, and active stateful entities
  - Drag-and-drop or upload new native C# extensions directly into the running cluster
  - Hot-reload and restart the cluster runtime supervision tree
  - Remove dynamically installed extensions safely
  """
  use Phoenix.LiveComponent

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.DashboardViews.ExtensionUpload

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

    {:ok, sync_focus(socket)}
  end

  ## ---- EVENT HANDLERS ----

  @impl true
  def handle_event("search", params, socket) do
    query = Map.get(params, "query") || Map.get(params, "value") || ""

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
  def handle_event("close_focus", _params, socket) do
    tab = (socket.assigns[:extension] && socket.assigns.extension.id) || "exoforge_std_extension_manager"
    {:noreply,
     socket
     |> assign(selected_plugin: nil)
     |> push_patch(to: "/tab/#{tab}")}
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
         "type" => "native",
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
    {:noreply,
     assign(socket,
       upload_form: ExtensionUpload.form_with_file(socket.assigns.upload_form, filename, base64),
       upload_file_info: %{filename: filename, size_bytes: size},
       upload_error: nil
     )}
  end

  @impl true
  def handle_event("submit_upload", %{"upload" => params}, socket) do
    case ExtensionUpload.payload(params, socket.assigns.upload_form) do
      {:error, message} ->
        {:noreply, assign(socket, upload_error: message)}

      {:ok, payload} ->
        case ActionDispatcher.dispatch(:extension_manager, :upload_extension, payload, caller_scopes: caller_scopes(socket)) do
          {:ok, result} ->
            ext_id = result[:extension_id] || result[:plugin_id]
            socket =
              socket
              |> assign(
                show_upload_modal: false,
                upload_error: nil,
                upload_file_info: nil,
                upload_success: "Extension '#{ext_id}' (#{result[:type] || payload.type}) successfully uploaded and initialized!"
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
    case ActionDispatcher.dispatch(:extension_manager, :remove_extension, %{id: id}, caller_scopes: caller_scopes(socket)) do
      {:ok, _result} ->
        socket =
          socket
          |> assign(
            selected_plugin: nil,
            action_notification: "Extension '#{id}' successfully removed from runtime."
          )
          |> load_data()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, action_notification: "Failed to remove extension: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("open_restart_modal", _params, socket) do
    {:noreply, assign(socket, show_restart_modal: true)}
  end

  @impl true
  def handle_event("close_restart_modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-popup", %{})
     |> assign(show_restart_modal: false)}
  end

  @impl true
  def handle_event("confirm_restart", _params, socket) do
    case ActionDispatcher.dispatch(:extension_manager, :restart_system, %{}, caller_scopes: caller_scopes(socket)) do
      {:ok, result} ->
        count = result[:extensions_count] || result[:plugins_count] || 0
        socket =
          socket
          |> assign(
            show_restart_modal: false,
            restart_status: "Runtime cluster restarted. #{count} extensions reloaded successfully."
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

  # The plugin drawer is a URL (`?focus=plugin:<id>`), not component state, so back/forward works.
  defp sync_focus(socket) do
    case socket.assigns[:focus] do
      %{kind: "plugin", id: id} -> select_plugin(socket, id)
      _ -> assign(socket, selected_plugin: nil)
    end
  end

  defp select_plugin(socket, id) do
    current = socket.assigns[:selected_plugin] && socket.assigns.selected_plugin["id"]

    if to_string(current) == to_string(id) do
      socket
    else
      plugin =
        case ActionDispatcher.dispatch(:extension_manager, :get_extension, %{id: id}) do
          {:ok, %{extension: p}} ->
            p

          {:ok, %{plugin: p}} ->
            p

          _ ->
            Enum.find(socket.assigns.plugins, fn p -> to_string(p["id"]) == to_string(id) end)
        end

      assign(socket, selected_plugin: plugin, active_drawer_tab: "overview")
    end
  end

  # The plugin inspector's tabs. Same ids the `set_drawer_tab` handler switches on.
  defp pm_inspect_tabs do
    [
      %{id: "overview", title: "Overview"},
      %{id: "csharp", title: "C# / Unity SDK"},
      %{id: "manifest", title: "Raw Manifest"}
    ]
  end

  defp load_data(socket) do
    plugins =
      case ActionDispatcher.dispatch(:extension_manager, :list_extensions, %{}) do
        {:ok, %{extensions: list}} -> list
        {:ok, %{plugins: list}} -> list
        _ -> []
      end

    sys_info =
      case ActionDispatcher.dispatch(:extension_manager, :get_system_info, %{}) do
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

  defp csharp_snippet(plugin) do
    provides = plugin["provides"] || ["service"]

    services_code =
      Enum.map_join(provides, "\n\n", fn svc ->
        pascal_svc = Macro.camelize(to_string(svc))

        "// Call generated typed service client\n" <>
          "var result = await client." <>
          pascal_svc <>
          "().ExecuteAsync();"
      end)

    "// C# Unity / Client SDK snippet (typed contract stubs)\n" <>
      "using Exoforge.Client;\n\n" <>
      services_code
  end

  ## ---- TEMPLATE RENDERING ----

  @impl true
  def render(assigns) do
    total_plugins = length(assigns.plugins)
    memory_mb = Map.get(assigns.system_info, "memory_mb", 0.0)
    node_name = Map.get(assigns.system_info, "node", "nonode@nohost")
    uptime = format_uptime(Map.get(assigns.system_info, "uptime_seconds"))
    otp_release = Map.get(assigns.system_info, "otp_release", System.otp_release())
    elixir_ver = Map.get(assigns.system_info, "elixir_version", System.version())

    assigns =
      assigns
      |> assign(:total_extensions, total_plugins)
      |> assign(:total_plugins, total_plugins)
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
              <h2 class="text-xl font-bold text-gray-900">Extension Manager &amp; Cluster Runtime</h2>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-800">
                Extension Live
              </span>
            </div>
            <p class="text-sm text-gray-500 mt-0.5">
              Manage runtime lifecycle, inspect contracts &amp; actor schemas, and load native C# and Elixir extensions.
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
            phx-click="open_restart_modal"
            phx-target={@myself}
            class="px-3.5 py-2 text-sm font-semibold text-amber-700 bg-amber-50 border border-amber-200 rounded-xl hover:bg-amber-100 transition-colors shadow-sm flex items-center gap-2"
            title="Hot-reload extension supervision trees and clear cache"
          >
            <svg class="w-4 h-4 text-amber-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
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
            Upload Extension
          </button>
        </div>
      </div>

      <!-- Action Success / Notification Banner -->
      <%= if @upload_success || @restart_status || @action_notification do %>
        <div class="bg-emerald-500/10 border border-emerald-500/20 rounded-2xl p-4 shadow-sm flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-lg bg-emerald-600 text-white flex items-center justify-center font-bold text-sm shrink-0">
              ✓
            </div>
            <p class="text-xs font-bold text-emerald-800 dark:text-emerald-300">
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
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <!-- 1. Installed Extensions -->
        <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title="Modular service extensions">
          <div class="w-11 h-11 rounded-xl bg-violet-50 text-violet-600 flex items-center justify-center text-xl shrink-0">
            📦
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Installed Extensions</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-xl font-black text-gray-900"><%= @total_extensions %></span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-violet-50 text-violet-700">Active</span>
            </div>
          </div>
        </div>

        <!-- 2. BEAM Memory & Processes -->
        <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title="Erlang memory allocated">
          <div class="w-11 h-11 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center text-xl shrink-0">
            ⚡
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">BEAM Memory &amp; Load</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-xl font-black text-gray-900"><%= @memory_mb %> MB</span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700">
                <%= Map.get(@system_info, "process_count", "—") %> procs
              </span>
            </div>
          </div>
        </div>

        <!-- 3. Cluster Node & Uptime -->
        <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title={"Node: #{@node_name}"}>
          <div class="w-11 h-11 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center text-xl shrink-0">
            🌐
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Cluster Node</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-sm font-black font-mono text-gray-900 truncate max-w-[120px]"><%= @node_name %></span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700"><%= @uptime %></span>
            </div>
          </div>
        </div>

        <!-- 4. Version & Engine -->
        <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title={"OTP #{@otp_release} • Built #{Map.get(@system_info, "build_date", "—")}"}>
          <div class="w-11 h-11 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center text-xl shrink-0">
            ⚙️
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Cluster Build</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-lg font-black font-mono text-gray-900">v<%= Map.get(@system_info, "version", "0.1.0") %></span>
              <span class="text-[10px] font-bold font-mono px-2 py-0.5 rounded-full bg-purple-50 text-purple-700">
                #<%= Map.get(@system_info, "commit_hash", "dev") %>
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- Filters & Search Toolbar -->
      <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div class="flex items-center gap-3 flex-1 max-w-lg">
          <form id="extension-search-form" phx-change="search" phx-submit="search" phx-target={@myself} class="relative w-full">
            <input
              type="search"
              placeholder="Search extension by name, ID, or provided service..."
              value={@search_query}
              phx-debounce="150"
              name="query"
              class="w-full pl-9 pr-4 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white transition-all"
            />
            <svg class="w-4 h-4 text-gray-400 absolute left-3 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </form>
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

      <!-- Extensions Directory Table -->
      <div class="bg-white rounded-2xl border border-gray-200/80 shadow-sm overflow-hidden">
        <%= if @filtered_plugins == [] do %>
          <div class="p-12 text-center">
            <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl mb-3">
              📦
            </div>
            <h3 class="text-sm font-bold text-gray-900">No extensions match your query</h3>
            <p class="text-xs text-gray-500 mt-1 max-w-sm mx-auto">
              Try adjusting your search terms to locate installed extensions.
            </p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="bg-gray-50/75 border-b border-gray-200 text-[11px] font-bold text-gray-500 uppercase tracking-wider">
                  <th class="py-3 px-4">Extension</th>
                  <th class="py-3 px-4">Version</th>
                  <th class="py-3 px-4">Provided Services</th>
                  <th class="py-3 px-4">Dependencies</th>
                  <th class="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 text-sm">
                <%= for plugin <- @filtered_plugins do %>
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
                      <div class="flex items-center justify-end gap-1.5">
                        <button
                          phx-click="open_focus"
                          phx-value-kind="plugin"
                          phx-value-id={plugin["id"]}
                          title="Inspect manifest, actions, and schemas"
                          class="px-2.5 py-1 text-xs font-semibold text-gray-700 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg transition-colors"
                        >
                          Inspect
                        </button>

                        <details class="exo-menu">
                          <summary class="px-2 py-1 text-xs font-bold text-gray-500 hover:text-gray-800 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg cursor-pointer">
                            ⋯
                          </summary>
                          <div class="exo-menu-panel">
                            <button
                              type="button"
                              phx-click="remove_plugin"
                              phx-value-id={plugin["id"]}
                              phx-target={@myself}
                              data-confirm={"Are you sure you want to unload extension #{plugin["id"]}?"}
                              title="Unload and remove extension from cluster"
                              class="exo-menu-item exo-menu-danger"
                            >
                              <span>🗑</span> <span>Remove</span>
                            </button>
                          </div>
                        </details>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <!-- Slide-over Extension Inspector Drawer -->
      <%= if @selected_plugin do %>
        <Exoforge.Std.DashboardViews.InspectPopup.inspect_popup
          open={true}
          icon="📦"
          title={@selected_plugin["name"]}
          subtitle={"#{@selected_plugin["id"]} (v#{@selected_plugin["version"]})"}
          tabs={pm_inspect_tabs()}
          active_tab={@active_drawer_tab}
          on_close="close_focus"
          on_select_tab="set_drawer_tab"
          target={@myself}
          width="max-w-2xl"
        >
                <%= if @active_drawer_tab == "overview" do %>
                  <div class="space-y-4">
                    <div class="grid grid-cols-2 gap-3">
                      <div class="bg-gray-50 p-3.5 rounded-xl border border-gray-200">
                        <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">Extension Version</span>
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

                <%= if @active_drawer_tab == "csharp" do %>
                  <div class="space-y-3">
                    <p class="text-xs text-gray-500">
                      Invoke this extension directly from Unity or C# clients using <code class="font-mono text-violet-700 font-bold">Exoforge.Client</code>:
                    </p>
                    <pre class="bg-gray-900 text-gray-100 p-4 rounded-xl font-mono text-xs overflow-x-auto select-all leading-relaxed"><%= csharp_snippet(@selected_plugin) %></pre>
                  </div>
                <% end %>

                <%= if @active_drawer_tab == "manifest" do %>
                  <div class="space-y-2">
                    <pre class="bg-gray-900 text-gray-100 p-4 rounded-xl font-mono text-xs overflow-x-auto select-all leading-relaxed max-h-96"><%= Jason.encode!(@selected_plugin, pretty: true) %></pre>
                  </div>
                <% end %>
          <div class="pt-4 border-t border-gray-100 flex items-center justify-between">
                <button
                  phx-click="remove_plugin"
                  phx-value-id={@selected_plugin["id"]}
                  phx-target={@myself}
                  data-confirm={"Are you sure you want to unload extension #{@selected_plugin["id"]}?"}
                  class="px-4 py-2 text-xs font-bold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 rounded-xl transition-colors"
                >
                  Unload &amp; Remove Extension
                </button>
              <button
                phx-click="close_focus"
                class="px-4 py-2 text-xs font-bold text-gray-700 bg-white hover:bg-gray-100 border border-gray-300 rounded-xl transition-colors shadow-sm ml-auto"
              >
                Close
              </button>
          </div>
        </Exoforge.Std.DashboardViews.InspectPopup.inspect_popup>
      <% end %>

      <!-- Upload Extension Modal -->
      <%= if @show_upload_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="fixed inset-0" phx-click="close_upload_modal" phx-target={@myself}></div>
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
                <h3 class="text-lg font-bold text-gray-900"><%= if @upload_form["type"] == "elixir", do: "Upload Elixir Extension", else: "Upload C# Extension" %></h3>
                <p class="text-xs text-gray-500">Deploy a compiled native extension binary or live Elixir extension into the runtime.</p>
              </div>
            </div>

            <%= if @upload_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @upload_error %>
              </div>
            <% end %>

            <form id="upload_plugin_form" phx-submit="submit_upload" phx-change="change_upload_form" phx-target={@myself} class="space-y-4">
              <!-- Extension Type Selector -->
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-2">Extension Type</label>
                <div class="grid grid-cols-2 gap-3">
                  <label class={"flex items-center gap-2 p-3 rounded-xl border cursor-pointer transition-colors #{if @upload_form["type"] != "elixir", do: "border-violet-500 bg-violet-50/50 text-violet-900", else: "border-gray-200 bg-gray-50 text-gray-700"}"}>
                    <input
                      type="radio"
                      name="upload[type]"
                      value="native"
                      checked={@upload_form["type"] != "elixir"}
                      class="text-violet-600 focus:ring-violet-500"
                    />
                    <div>
                      <span class="text-xs font-bold block">C# Native</span>
                      <span class="text-[10px] text-gray-500">A compiled extension binary</span>
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
                      <span class="text-xs font-bold block">Elixir Extension</span>
                      <span class="text-[10px] text-gray-500">Live source module (.ex)</span>
                    </div>
                  </label>
                </div>
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Extension Name / Identifier</label>
                <input
                  type="text"
                  name="upload[name]"
                  value={@upload_form["name"]}
                  placeholder={if @upload_form["type"] == "elixir", do: "e.g. custom_quest", else: "e.g. my_extension"}
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                />
              </div>

              <%= if @upload_form["type"] == "elixir" do %>
                <!-- Elixir Module Code Input -->
                <div>
                  <div class="flex items-center justify-between mb-1">
                    <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider">Elixir Source Code (.ex)</label>
                    <span class="text-[11px] text-gray-400 font-mono">use Exoforge.Extension</span>
                  </div>
                  <textarea
                    name="upload[elixir_code]"
                    rows="6"
                    placeholder={"defmodule MyExtension do\n  use Exoforge.Extension, provides: [:my_service]\n\n  defaction ping(payload) do\n    {:ok, %{pong: payload}}\n  end\nend"}
                    class="w-full px-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                  ><%= @upload_form["elixir_code"] %></textarea>
                </div>
              <% else %>
                <!-- Extension Binary Dropzone / Selector -->
                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Extension Binary</label>
                  <div class="border-2 border-dashed border-gray-300 rounded-xl p-4 text-center hover:border-violet-400 transition-colors bg-gray-50/50">
                    <input
                      type="file"
                      id="extension_file_picker"
                      onchange="
                        const file = this.files[0];
                        if (file) {
                          const reader = new FileReader();
                          reader.onload = (e) => {
                            const base64 = e.target.result.split(',')[1];
                            const input = document.getElementById('binary_base64_input');
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
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Or Paste Base64 Binary Data</label>
                  <textarea
                    id="binary_base64_input"
                    name="upload[binary]"
                    rows="3"
                    placeholder="Base64-encoded extension binary"
                    class="w-full px-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                  ><%= @upload_form["binary"] %></textarea>
                  <p class="text-[11px] text-gray-400 mt-0.5">The published extension binary - the file beside its manifest.json.</p>
                </div>
              <% end %>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Optional Manifest Metadata (JSON)</label>
                <textarea
                  name="upload[manifest_json]"
                  rows="2"
                  placeholder='{"version": "0.1.0", "category": "Gameplay"}'
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
                  phx-disable-with="Uploading..."
                  class="px-5 py-2 text-xs font-bold text-white bg-violet-600 rounded-xl hover:bg-violet-700 transition-colors shadow-sm"
                >
                  Upload &amp; Hot-Load Extension
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Restart Confirmation Modal -->
      <%= if @show_restart_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="fixed inset-0" phx-click="close_restart_modal" phx-target={@myself}></div>
          <div class="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-red-100 text-red-700 flex items-center justify-center text-xl shrink-0">
                ⚠️
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900">Restart Cluster Supervision?</h3>
                <p class="text-xs text-gray-500">Hot-reloads all extension supervision trees and manifests.</p>
              </div>
            </div>

            <p class="text-xs text-gray-600 mb-5 leading-relaxed bg-amber-50 p-3 rounded-xl border border-amber-200">
              This action re-executes topological sorting, re-initializes extension worker registries, and hot-swaps updated extension binaries into memory.
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

      <!-- Extension Dependency Graph Modal -->
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

  # The session's verified scopes (M33 Fix 28): administrative dispatches authorize with
  # the login, not with the dispatcher's internal default.
  defp caller_scopes(socket), do: socket.assigns[:current_scopes] || []
end
