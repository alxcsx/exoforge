defmodule Exoforge.Std.Dashboard.ExtensionRegistry do
  @moduledoc """
  The Studio's extension catalogue: search, category filters, UI extension cards, and the
  headless system-plugin table.

  Extracted from `StudioLive` so the LiveView keeps only lifecycle and event handling.
  All `phx-click` handlers bubble to the parent LiveView.
  """
  use Phoenix.Component

  alias Exoforge.Std.Dashboard.ExtensionPresenter

  defp custom_ui?(ext), do: ext[:custom_view_module] != nil || ExtensionPresenter.view_module(ext) != nil

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
      "liveops" -> "🎯"
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
              <%= (is_map(@ext.dashboard_view) && @ext.dashboard_view[:icon]) || ExtensionPresenter.icon(@ext) %>
            </span>
            <div>
              <h4 class="font-bold text-gray-900 text-sm tracking-tight group-hover:text-primary-700 transition-colors">
                <%= ExtensionPresenter.display_name(@ext) %>
              </h4>
              <span class="text-[11px] font-mono text-gray-400"><%= @ext.id %></span>
            </div>
          </div>
          <div class="flex flex-col items-end gap-1">
            <%= if @ext.has_dashboard_view do %>
              <%= if custom_ui?(@ext) do %>
                <span
                  class="text-[10px] font-bold px-1.5 py-0.2 rounded bg-indigo-50 text-indigo-700 border border-indigo-200"
                  title="This extension provides its own custom LiveView"
                >
                  ✨ Custom UI
                </span>
              <% else %>
                <span class="text-[10px] font-bold px-1.5 py-0.2 rounded bg-purple-50 text-purple-700 border border-purple-200">
                  🎛️ Controls
                </span>
              <% end %>
            <% else %>
              <span class="text-[10px] font-bold px-1.5 py-0.2 rounded bg-gray-100 text-gray-600 border border-gray-200" title="Headless service without dedicated UI">
                ⚙️ Headless
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

          <%= if @ext.has_dashboard_view do %>
            <button
              type="button"
              phx-click="switch_tab"
              phx-value-tab={to_string(@ext.id)}
              class="px-3 py-1 text-[11px] font-bold text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors flex items-center gap-1 shadow-xs"
            >
              <span>Open Controls</span>
              <span>&rarr;</span>
            </button>
          <% else %>
            <button
              type="button"
              phx-click="inspect_extension"
              phx-value-id={to_string(@ext.id)}
              class="px-3 py-1 text-[11px] font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-lg transition-colors flex items-center gap-1"
            >
              <span>🔍</span>
              <span>Inspect</span>
            </button>
          <% end %>
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
          <% ui_exts = Enum.filter(filtered_exts, & &1.has_dashboard_view) |> Enum.sort_by(&ExtensionPresenter.display_name/1) %>
          <% headless_exts = Enum.reject(filtered_exts, & &1.has_dashboard_view) |> Enum.sort_by(&ExtensionPresenter.display_name/1) %>
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
              <%= for {cat_id, label, icon} <- extension_categories(@extensions) do %>
                <button
                  type="button"
                  phx-click="filter_extension_category"
                  phx-value-category={cat_id}
                  class={"px-3 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 whitespace-nowrap #{if @category == cat_id, do: "bg-primary-600 text-white shadow-sm", else: "bg-white text-gray-600 hover:bg-gray-50 border border-gray-200/80"}"}
                >
                  <span><%= icon %></span>
                  <span><%= label %></span>
                  <%= if cat_id == "all" do %>
                    <span class={"text-[10px] px-1.5 py-0.2 rounded-full font-mono #{if @category == cat_id, do: "bg-white/20 text-white", else: "bg-gray-100 text-gray-600"}"}>
                      <%= length(@extensions) %>
                    </span>
                  <% end %>
                </button>
              <% end %>
            </div>

            <!-- Empty State -->
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
              <!-- SECTION 1: STUDIO EXTENSIONS & VISUAL CONTROLS -->
              <div class="space-y-3">
                <div class="flex items-center gap-2">
                  <span class="text-base">🎛️</span>
                  <h4 class="text-base font-bold text-gray-900">Studio Extensions &amp; Visual Controls</h4>
                  <span class="text-[11px] font-mono font-bold px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200">
                    <%= length(ui_exts) %>
                  </span>
                  <span class="hidden sm:inline text-xs text-gray-400">— extensions with interactive dashboards and designer consoles</span>
                </div>

                <%= if Enum.empty?(ui_exts) do %>
                  <p class="p-6 bg-white border border-gray-200 rounded-2xl text-xs text-gray-400 italic">No visual control extensions found matching filter.</p>
                <% else %>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                    <%= for ext <- ui_exts do %>
                      <.extension_card ext={ext} pinned={to_string(ext.id) in @pinned_extensions} />
                    <% end %>
                  </div>
                <% end %>
              </div>

              <!-- SECTION 2: SYSTEM PLUGINS (headless) -->
              <div class="space-y-3 pt-4 border-t border-gray-200/80">
                <div class="flex items-center gap-2">
                  <h4 class="text-base font-bold text-gray-900">System Plugins</h4>
                  <span class="text-[11px] font-mono font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 border border-gray-200">
                    <%= length(headless_exts) %>
                  </span>
                </div>

                <%= if Enum.empty?(headless_exts) do %>
                  <p class="p-6 bg-white border border-gray-200 rounded-2xl text-xs text-gray-400 italic">No system plugins found matching filter.</p>
                <% else %>
                  <div class="bg-white border border-gray-200/90 rounded-2xl shadow-sm overflow-x-auto">
                    <table class="w-full text-xs text-left">
                      <thead class="bg-gray-50 text-[10px] uppercase tracking-wider text-gray-400">
                        <tr>
                          <th class="px-4 py-2.5 font-bold">Plugin</th>
                          <th class="px-4 py-2.5 font-bold hidden md:table-cell">Provides</th>
                          <th class="px-4 py-2.5 font-bold hidden lg:table-cell">Version</th>
                          <th class="px-4 py-2.5 font-bold">Status</th>
                          <th class="px-4 py-2.5 font-bold text-right">Actions</th>
                        </tr>
                      </thead>
                      <tbody class="divide-y divide-gray-100">
                        <%= for ext <- headless_exts do %>
                          <tr class="hover:bg-gray-50/60">
                            <td class="px-4 py-3">
                              <div class="font-bold text-gray-900"><%= ExtensionPresenter.display_name(ext) %></div>
                              <div class="font-mono text-[10px] text-gray-400"><%= ext.id %></div>
                            </td>
                            <td class="px-4 py-3 hidden md:table-cell">
                              <div class="flex flex-wrap gap-1">
                                <%= for s <- ext.provides do %>
                                  <span class="px-1.5 py-0.5 rounded bg-purple-50 text-purple-700 font-mono text-[10px]"><%= s %></span>
                                <% end %>
                              </div>
                            </td>
                            <td class="px-4 py-3 hidden lg:table-cell font-mono text-gray-500">v<%= ext.version %></td>
                            <td class="px-4 py-3">
                              <span class="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 font-bold"><%= ext.status %></span>
                            </td>
                            <td class="px-4 py-3 text-right">
                              <button
                                type="button"
                                phx-click="inspect_extension"
                                phx-value-id={ext.id}
                                class="px-2.5 py-1 text-[11px] font-bold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-lg transition-colors"
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
            <% end %>
          </div>
    """
  end
end
