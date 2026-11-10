defmodule Exoforge.Std.Dashboard.ExtensionRegistry do
  @moduledoc """
  The Studio's extension catalogue: search, category filters, UI extension cards, and the
  headless system-plugin table.

  Extracted from `StudioLive` so the LiveView keeps only lifecycle and event handling.
  All `phx-click` handlers bubble to the parent LiveView.
  """
  use Phoenix.Component
  import Exoforge.Std.Dashboard.Components, only: [icon: 1]

  alias Exoforge.Std.Dashboard.ExtensionPresenter

  defp custom_ui?(ext), do: ext[:custom_view_module] != nil || ExtensionPresenter.view_module(ext) != nil

  # Category pills are standardized and derived from extension metadata.
  defp extension_categories(extensions) do
    all_cat = [{"all", "All Extensions", "🌐", length(extensions)}]
    standard_order = ["Gameplay", "Players", "Storage", "Network", "System"]

    pills =
      Enum.map(standard_order, fn cat_name ->
        count =
          Enum.count(extensions, fn ext ->
            ExtensionPresenter.normalize_category(ext[:category]) == cat_name
          end)

        id = String.downcase(cat_name)
        icon = ExtensionPresenter.category_icon(cat_name)
        {id, cat_name, icon, count}
      end)
      |> Enum.filter(fn {_id, _name, _icon, count} -> count > 0 end)

    all_cat ++ pills
  end

  attr(:ext, :map, required: true)
  attr(:pinned, :boolean, default: false)

  defp extension_card(assigns) do
    ~H"""
    <div
      phx-click="switch_tab"
      phx-value-tab={to_string(@ext.id)}
      role="button"
      tabindex="0"
      title={"Open #{ExtensionPresenter.display_name(@ext)} Control Panel"}
      class="h-full bg-white p-5 rounded-xl border border-gray-200/90 hover:border-primary-500 hover:ring-2 hover:ring-primary-500/20 shadow-sm hover:shadow-lg transition-all flex flex-col justify-between space-y-4 group cursor-pointer relative overflow-hidden"
    >
      <div class="space-y-3">
        <div class="flex items-start justify-between gap-2">
          <div class="flex items-center gap-3 min-w-0">
            <span class="w-10 h-10 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center text-xl shadow-xs shrink-0 group-hover:bg-primary-100 group-hover:scale-105 transition-all">
              <%= ExtensionPresenter.icon(@ext) %>
            </span>
            <div class="min-w-0">
              <h4 class="font-bold text-gray-900 text-sm tracking-tight group-hover:text-primary-700 transition-colors flex items-center gap-1.5 truncate">
                <span class="truncate"><%= ExtensionPresenter.display_name(@ext) %></span>
                <%= if custom_ui?(@ext) do %>
                  <span class="text-[10px] text-primary-600 opacity-80 shrink-0" title="Ships its own UI">✦</span>
                <% end %>
              </h4>
              <span class="text-[11px] font-medium text-gray-400 block truncate">
                <%= ExtensionPresenter.normalize_category(@ext[:category]) %> • v<%= to_string(@ext.version) %>
              </span>
            </div>
          </div>
          <div class="flex flex-col items-end gap-1 shrink-0">
            <%= if @ext.system do %>
              <span class="text-[10px] font-bold px-1.5 py-0.2 rounded bg-gray-100 text-gray-600 border border-gray-200" title="System extension">
                ⚙️ System
              </span>
            <% else %>
              <span class="w-2 h-2 rounded-full bg-emerald-500 mt-1.5" title="Active"></span>
            <% end %>
          </div>
        </div>

        <!-- Technical Badges -->
        <div class="flex flex-wrap items-center gap-1.5 text-[10px] text-gray-600 font-semibold">
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-lg bg-primary-50 text-primary-700">
            <span>⚡</span> <%= @ext.actions_count %> actions
          </span>
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-lg bg-blue-50 text-blue-700">
            <span>📦</span> <%= @ext.resources_count %> resources
          </span>
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-lg bg-emerald-50 text-emerald-700">
            <span>📡</span> <%= @ext.events_count %> events
          </span>
        </div>
      </div>

      <div class="pt-3 border-t border-gray-100 flex items-center justify-between text-xs">
        <div class="flex items-center gap-1.5">
          <%= if @pinned do %>
            <button
              type="button"
              phx-click="unpin_extension"
              phx-value-id={to_string(@ext.id)}
              class="px-2.5 py-1 text-[11px] font-semibold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-lg flex items-center gap-1 transition-colors"
              title="Unpin from top bar"
            >
              <.icon name={:pin} class="w-3 h-3" /> <span>Pinned</span>
            </button>
          <% else %>
            <button
              type="button"
              phx-click="pin_extension"
              phx-value-id={to_string(@ext.id)}
              class="px-2.5 py-1 text-[11px] font-semibold text-gray-600 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg flex items-center gap-1 transition-colors"
              title="Pin to top bar"
            >
              <.icon name={:pin} class="w-3 h-3" /> <span>Pin</span>
            </button>
          <% end %>

          <button
            type="button"
            phx-click="inspect_extension"
            phx-value-id={to_string(@ext.id)}
            class="px-2.5 py-1 text-[11px] font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-lg transition-colors flex items-center gap-1"
            title="Inspect extension contracts & metadata"
          >
            <span>🔍</span>
            <span>Inspect</span>
          </button>
        </div>

        <div class="flex items-center gap-2">
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
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab={to_string(@ext.id)}
            class="text-xs font-bold text-primary-600 bg-primary-50 hover:bg-primary-600 hover:text-white px-2.5 py-1 rounded-lg transition-all flex items-center gap-1 shadow-2xs"
            title={"Open #{ExtensionPresenter.display_name(@ext)} Control Panel"}
          >
            <span>Control Panel</span>
            <span class="group-hover:translate-x-0.5 transition-transform">&rarr;</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp filter_extensions(extensions, query, category) do
    q = String.downcase(String.trim(query || ""))

    extensions
    |> Enum.filter(fn ext ->
      cat_match =
        case category do
          "all" -> true
          cat ->
            ExtensionPresenter.normalize_category(ext[:category]) ==
              ExtensionPresenter.normalize_category(cat)
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

  attr(:extensions, :list, required: true)
  attr(:search, :string, default: "")
  attr(:category, :string, default: "all")
  attr(:pinned_extensions, :list, default: [])

  def registry(assigns) do
    assigns =
      assign(
        assigns,
        :filtered,
        filter_extensions(assigns.extensions, assigns.search, assigns.category)
      )

    ~H"""
          <% filtered_exts = filter_extensions(@extensions, @search, @category) %>
          <% ui_exts = filtered_exts |> Enum.reject(& &1.system) |> Enum.sort_by(&ExtensionPresenter.display_name/1) %>
          <% system_exts =
               filtered_exts
               |> Enum.filter(& &1.system)
               |> Enum.sort_by(fn ext ->
                 rank =
                   cond do
                     custom_ui?(ext) -> 0
                     ext.has_dashboard_view -> 1
                     true -> 2
                   end

                 {rank, ExtensionPresenter.display_name(ext)}
               end) %>
          <div class="space-y-6">
            <!-- Header with Title, Search & Category Filters -->
            <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-xl border border-gray-200/90 shadow-sm">
              <div>
                <h3 class="text-xl font-bold text-gray-900 flex items-center gap-2">
                  <span>🧩</span>
                  <span>Extension Registry</span>
                </h3>
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
                      value={@search}
                      placeholder="Search extensions, services..."
                      class="w-full pl-9 pr-3 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:border-primary-500 font-medium"
                    />
                  </div>
                </form>
              </div>
            </div>

            <!-- Category Filter Pills -->
            <div class="flex items-center gap-2 overflow-x-auto pb-1 [scrollbar-width:none]">
              <%= for {cat_id, label, icon, count} <- extension_categories(@extensions) do %>
                <% is_active = @category == cat_id or (@category != "all" and ExtensionPresenter.normalize_category(@category) == label) %>
                <button
                  type="button"
                  phx-click="filter_extension_category"
                  phx-value-category={cat_id}
                  class={"px-3 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 whitespace-nowrap #{if is_active, do: "bg-primary-600 text-white shadow-sm", else: "bg-white text-gray-600 hover:bg-gray-50 border border-gray-200/80"}"}
                >
                  <span><%= icon %></span>
                  <span><%= label %></span>
                  <span class={"text-[10px] px-1.5 py-0.2 rounded-full font-mono #{if is_active, do: "bg-white/20 text-white", else: "bg-gray-100 text-gray-600"}"}>
                    <%= count %>
                  </span>
                </button>
              <% end %>
            </div>

            <!-- Empty State -->
            <%= if Enum.empty?(filtered_exts) do %>
              <div class="bg-white p-12 rounded-xl border border-gray-200 text-center space-y-3">
                <div class="w-12 h-12 rounded-xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl">
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
              <!-- SECTION 1: STUDIO EXTENSIONS & VISUAL CONTROLS -->
              <div class="space-y-3">
                <div class="flex items-center gap-2">
                  <span class="text-base">🎛️</span>
                  <h4 class="text-base font-bold text-gray-900">Studio Extensions &amp; Visual Controls</h4>
                  <span class="text-[11px] font-mono font-bold px-2 py-0.5 rounded-full bg-primary-50 text-primary-700 border border-primary-200">
                    <%= length(ui_exts) %>
                  </span>
                  <span class="hidden sm:inline text-xs text-gray-400">— extensions with interactive dashboards and designer consoles</span>
                </div>

                <%= if Enum.empty?(ui_exts) do %>
                  <p class="p-6 bg-white border border-gray-200 rounded-xl text-xs text-gray-400 italic">No visual control extensions found matching filter.</p>
                <% else %>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 auto-rows-fr">
                    <%= for ext <- ui_exts do %>
                      <.extension_card ext={ext} pinned={to_string(ext.id) in @pinned_extensions} />
                    <% end %>
                  </div>
                <% end %>
              </div>

              <!-- SECTION 2: SYSTEM EXTENSIONS & HEADLESS SERVICES (Table View) -->
              <div class="space-y-3 pt-4 border-t border-gray-200/80">
                <div class="flex items-center gap-2">
                  <span class="text-sm">⚙️</span>
                  <h4 class="text-sm font-bold text-gray-700">System Extensions &amp; Headless Services</h4>
                  <span class="text-[11px] font-mono font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 border border-gray-200">
                    <%= length(system_exts) %>
                  </span>
                </div>

                <%= if Enum.empty?(system_exts) do %>
                  <p class="p-6 bg-white border border-gray-200 rounded-xl text-xs text-gray-400 italic">No system extensions found matching filter.</p>
                <% else %>
                  <div class="bg-white rounded-xl border border-gray-200 shadow-xs overflow-hidden">
                    <div class="overflow-x-auto">
                      <table class="w-full text-left border-collapse text-xs">
                        <thead>
                          <tr class="border-b border-gray-100 bg-gray-50/75 text-[10px] font-bold text-gray-400 uppercase tracking-wider">
                            <th class="py-3 px-4">Extension</th>
                            <th class="py-3 px-4">Category</th>
                            <th class="py-3 px-4">Version</th>
                            <th class="py-3 px-4">Capabilities</th>
                            <th class="py-3 px-4 text-right">Actions</th>
                          </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-100">
                          <%= for ext <- system_exts do %>
                            <% pinned = to_string(ext.id) in @pinned_extensions %>
                            <tr
                              phx-click="switch_tab"
                              phx-value-tab={to_string(ext.id)}
                              class="hover:bg-primary-50/40 transition-colors cursor-pointer group"
                              title={"Open #{ExtensionPresenter.display_name(ext)} Control Panel"}
                            >
                              <td class="py-3 px-4">
                                <div class="flex items-center gap-2.5">
                                  <span class="w-8 h-8 rounded-lg bg-gray-100 text-gray-700 flex items-center justify-center text-sm font-bold shrink-0 group-hover:bg-primary-100 group-hover:text-primary-700 transition-colors">
                                    <%= ExtensionPresenter.icon(ext) %>
                                  </span>
                                  <div class="min-w-0">
                                    <div class="font-bold text-gray-900 group-hover:text-primary-700 transition-colors flex items-center gap-1.5">
                                      <span><%= ExtensionPresenter.display_name(ext) %></span>
                                      <%= if custom_ui?(ext) do %>
                                        <span class="text-[10px] text-primary-600 opacity-80 shrink-0" title="Ships its own UI">✦</span>
                                      <% end %>
                                      <span class="text-[10px] font-bold px-1.5 py-0.2 rounded bg-gray-100 text-gray-600 border border-gray-200">System</span>
                                    </div>
                                    <span class="text-[10px] font-mono text-gray-400 block truncate"><%= ext.id %></span>
                                  </div>
                                </div>
                              </td>
                              <td class="py-3 px-4">
                                <span class="text-[11px] font-medium text-gray-600 bg-gray-100/80 px-2 py-0.5 rounded-lg">
                                  <%= ExtensionPresenter.normalize_category(ext[:category]) %>
                                </span>
                              </td>
                              <td class="py-3 px-4 text-gray-500 font-mono text-[11px]">
                                v<%= to_string(ext.version) %>
                              </td>
                              <td class="py-3 px-4">
                                <div class="flex flex-wrap items-center gap-1 text-[10px] font-semibold">
                                  <span class="px-1.5 py-0.5 rounded bg-primary-50 text-primary-700 font-mono">
                                    ⚡ <%= ext.actions_count %>
                                  </span>
                                  <span class="px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 font-mono">
                                    📦 <%= ext.resources_count %>
                                  </span>
                                  <span class="px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 font-mono">
                                    📡 <%= ext.events_count %>
                                  </span>
                                </div>
                              </td>
                              <td class="py-3 px-4 text-right">
                                <div class="flex items-center justify-end gap-1.5">
                                  <%= if pinned do %>
                                    <button
                                      type="button"
                                      phx-click="unpin_extension"
                                      phx-value-id={to_string(ext.id)}
                                      class="px-2 py-1 text-[10px] font-semibold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-lg flex items-center gap-1 transition-colors"
                                      title="Unpin from top bar"
                                    >
                                      <.icon name={:pin} class="w-3 h-3" /> <span>Pinned</span>
                                    </button>
                                  <% else %>
                                    <button
                                      type="button"
                                      phx-click="pin_extension"
                                      phx-value-id={to_string(ext.id)}
                                      class="px-2 py-1 text-[10px] font-semibold text-gray-600 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg flex items-center gap-1 transition-colors"
                                      title="Pin to top bar"
                                    >
                                      <.icon name={:pin} class="w-3 h-3" /> <span>Pin</span>
                                    </button>
                                  <% end %>

                                  <button
                                    type="button"
                                    phx-click="inspect_extension"
                                    phx-value-id={to_string(ext.id)}
                                    class="px-2 py-1 text-[10px] font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-lg transition-colors flex items-center gap-1"
                                    title="Inspect extension contracts"
                                  >
                                    <.icon name={:search} class="w-3 h-3" /> <span>Inspect</span>
                                  </button>

                                  <button
                                    type="button"
                                    phx-click="switch_tab"
                                    phx-value-tab={to_string(ext.id)}
                                    class="px-2 py-1 text-[10px] font-bold text-primary-600 hover:text-white bg-primary-50 hover:bg-primary-600 rounded-lg transition-all flex items-center gap-1"
                                    title="Open Control Panel"
                                  >
                                    <span>Control Panel &rarr;</span>
                                  </button>
                                </div>
                              </td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
    """
  end
end
