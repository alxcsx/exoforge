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

  defp custom_ui?(ext),
    do: ext[:custom_view_module] != nil || ExtensionPresenter.view_module(ext) != nil

  # Category pills are standardized and derived from extension metadata.
  @doc false
  def extension_categories(extensions) do
    all_cat = [{"all", "All Extensions", nil, length(extensions)}]
    standard_order = ["Gameplay", "Players", "Storage", "Network", "System"]

    # A category the standard list does not know (an author's own) still gets its pill, so the pills always add up to "All".
    others =
      extensions
      |> Enum.map(&ExtensionPresenter.normalize_category(&1[:category]))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in standard_order))
      |> Enum.sort()

    pills =
      Enum.map(standard_order ++ others, fn cat_name ->
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
      class="exo-card h-full p-5 hover:border-primary-500 hover:ring-2 hover:ring-primary-500/20 hover:shadow-lg transition-[border-color,box-shadow] flex flex-col justify-between space-y-4 group cursor-pointer relative overflow-hidden"
    >
      <div class="space-y-3">
        <div class="flex items-start justify-between gap-2">
          <div class="flex items-center gap-3 min-w-0">
            <span class="w-10 h-10 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center text-xl shadow-xs shrink-0 group-hover:bg-primary-100 group-hover:scale-105 transition-[background-color,transform]">
              <%= ExtensionPresenter.icon(@ext) %>
            </span>
            <div class="min-w-0">
              <h4 class="font-semibold text-gray-900 text-sm tracking-tight group-hover:text-primary-700 transition-colors flex items-center gap-1.5 truncate">
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
              <span class="text-[10px] font-semibold px-1.5 py-0.2 rounded bg-gray-100 text-gray-600 border border-gray-200" title="System extension">
                System
              </span>
            <% else %>
              <span class="w-2 h-2 rounded-full bg-emerald-500 mt-1.5" title="Active"></span>
            <% end %>
          </div>
        </div>

        <!-- Technical Badges -->
        <div class="flex flex-wrap items-center gap-1.5 text-[10px] text-gray-600 font-semibold">
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-lg bg-primary-50 text-primary-700">
            <.icon name="bolt" class="w-2.5 h-2.5" /> <%= plural(@ext.actions_count, "action") %>
          </span>
          <span :if={@ext.resources_count > 0} class="flex items-center gap-1 px-2 py-0.5 rounded-lg bg-blue-50 text-blue-700">
            <.icon name="box" class="w-2.5 h-2.5" /> <%= plural(@ext.resources_count, "resource") %>
          </span>
          <span :if={@ext.events_count > 0} class="flex items-center gap-1 px-2 py-0.5 rounded-lg bg-emerald-50 text-emerald-700">
            <.icon name="radio" class="w-2.5 h-2.5" /> <%= plural(@ext.events_count, "event") %>
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
            class="px-2.5 py-1 text-[11px] font-semibold text-gray-700 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-lg transition-colors flex items-center gap-1"
            title="Inspect extension contracts & metadata"
          >
            <.icon name="search" class="w-3 h-3" />
            <span>Inspect</span>
          </button>
        </div>

        <div class="flex items-center gap-2">
          <%= if @ext.actions_count > 0 do %>
            <button
              type="button"
              phx-click="open_action_modal"
              phx-value-service={List.first(@ext.provides)}
              class="text-gray-500 hover:text-primary-700 font-semibold flex items-center gap-1 transition-colors text-[11px]"
              title="Execute action in modal runner"
            >
              <span class="inline-flex items-center gap-1"><.icon name="bolt" class="w-3 h-3" /> Run</span>
            </button>
          <% end %>
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab={to_string(@ext.id)}
            class="text-xs font-semibold text-primary-600 bg-primary-50 hover:bg-primary-600 hover:text-white px-2.5 py-1 rounded-lg transition-colors flex items-center gap-1 shadow-2xs"
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

  # The extensions that ship with the server; everything else is the developer's own.
  defp std?(ext), do: String.starts_with?(to_string(ext.id), "exoforge_std_")

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  # What an extension offers, in words a reader does not have to decode ("3a 0r 0e" was one letter per kind).
  defp counts_text(ext) do
    [
      {ext.actions_count, "action", "actions"},
      {ext.resources_count, "resource", "resources"},
      {ext.events_count, "event", "events"}
    ]
    |> Enum.reject(fn {n, _, _} -> n == 0 end)
    |> Enum.map_join(" · ", fn {n, one, many} -> if n == 1, do: "1 #{one}", else: "#{n} #{many}" end)
    |> case do
      "" -> "nothing public"
      text -> text
    end
  end

  defp filter_extensions(extensions, query, category) do
    q = String.downcase(String.trim(query || ""))

    extensions
    |> Enum.filter(fn ext ->
      cat_match =
        case category do
          "all" ->
            true

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
          <% game_exts = filtered_exts |> Enum.reject(&std?/1) |> Enum.sort_by(&ExtensionPresenter.display_name/1) %>
          <% feature_exts = filtered_exts |> Enum.filter(&(std?(&1) and (custom_ui?(&1) or &1.has_dashboard_view))) |> Enum.sort_by(&ExtensionPresenter.display_name/1) %>
          <% internal_exts = filtered_exts |> Enum.filter(&(std?(&1) and not (custom_ui?(&1) or &1.has_dashboard_view))) |> Enum.sort_by(&ExtensionPresenter.display_name/1) %>
          <div class="space-y-5">
            <!-- Header with Title & Search (Flat on Canvas) -->
            <div class="exo-page-header">
              <div>
                <h1 class="exo-page-title flex items-center gap-2">
                  <.icon name="box" class="w-4 h-4 text-gray-400" />
                  <span>Extensions</span>
                </h1>
              </div>

              <!-- Live Search Bar -->
              <div class="w-full md:w-72">
                <form id="extensions_search_form" phx-change="search_extensions" class="m-0">
                  <div class="relative">
                    <span class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-gray-400">
                      <.icon name="search" class="w-3.5 h-3.5" />
                    </span>
                    <input
                      type="text"
                      name="query"
                      value={@search}
                      placeholder="Search extensions, services..."
                      class="exo-input pl-9"
                    />
                  </div>
                </form>
              </div>
            </div>

            <!-- Category Underline Tabs -->
            <div class="exo-tabs" role="tablist">
              <%= for {cat_id, label, icon, count} <- extension_categories(@extensions) do %>
                <% is_active = @category == cat_id or (@category != "all" and ExtensionPresenter.normalize_category(@category) == label) %>
                <button
                  type="button"
                  role="tab"
                  aria-selected={to_string(is_active)}
                  phx-click="filter_extension_category"
                  phx-value-category={cat_id}
                  class={"exo-tab #{if is_active, do: "exo-tab-active"}"}
                >
                  <span :if={icon}><%= icon %></span>
                  <span><%= label %></span>
                  <span class="exo-tab-count"><%= count %></span>
                </button>
              <% end %>
            </div>

            <!-- Empty State -->
            <%= if Enum.empty?(filtered_exts) do %>
              <div class="exo-card p-12 text-center space-y-3">
                <div class="w-10 h-10 rounded-xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center">
                  <.icon name="search" class="w-5 h-5" />
                </div>
                <h4 class="text-sm font-semibold text-gray-900">No extensions match your filter</h4>
                <p class="text-xs text-gray-500">Try changing the category or clearing the search query.</p>
                <button
                  type="button"
                  phx-click="filter_extension_category"
                  phx-value-category="all"
                  class="exo-btn exo-btn-secondary"
                >
                  Reset Filters
                </button>
              </div>
            <% else %>
              <%!-- YOUR GAME: what the developer wrote and deployed --%>
              <section class="space-y-3" aria-labelledby="ext-game">
                <div class="flex items-center gap-2">
                  <h4 id="ext-game" class="text-base font-semibold text-gray-900">Your game</h4>
                  <span class="text-[11px] font-mono font-semibold px-2 py-0.5 rounded-full bg-primary-50 text-primary-700 border border-primary-200"><%= length(game_exts) %></span>
                  <span class="hidden sm:inline text-xs text-gray-400">the extensions you wrote and deployed</span>
                </div>

                <%= if game_exts == [] do %>
                  <div class="rounded-xl border border-dashed border-gray-200 bg-white p-6 space-y-2">
                    <p class="text-sm font-semibold text-gray-900">No game extension is running yet</p>
                    <p class="text-sm text-gray-600">Create one with <code class="font-mono">exo extension new</code> or from the Unity window, then build and deploy it. It appears here as soon as it runs.</p>
                    <button type="button" phx-click="switch_tab" phx-value-tab="exoforge_std_docs" class="exo-btn exo-btn-secondary exo-btn-sm">Open the Developer Guide</button>
                  </div>
                <% else %>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 auto-rows-fr">
                    <%= for ext <- game_exts do %>
                      <.extension_card ext={ext} pinned={to_string(ext.id) in @pinned_extensions} />
                    <% end %>
                  </div>
                <% end %>
              </section>

              <%!-- STUDIO FEATURES: the screens built into the Studio --%>
              <section :if={feature_exts != []} class="space-y-3 pt-4 border-t border-gray-200/80" aria-labelledby="ext-features">
                <div class="flex items-center gap-2">
                  <h4 id="ext-features" class="text-base font-semibold text-gray-900">Studio features</h4>
                  <span class="text-[11px] font-mono font-semibold px-2 py-0.5 rounded-full bg-primary-50 text-primary-700 border border-primary-200"><%= length(feature_exts) %></span>
                  <span class="hidden sm:inline text-xs text-gray-400">screens that come with the server: users, data, releases, usage, debugging</span>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 auto-rows-fr">
                  <%= for ext <- feature_exts do %>
                    <.extension_card ext={ext} pinned={to_string(ext.id) in @pinned_extensions} />
                  <% end %>
                </div>
              </section>

              <%!-- PLATFORM INTERNALS: they run the server; closed unless the reader is searching --%>
              <details :if={internal_exts != []} class="group pt-4 border-t border-gray-200/80" open={@search != "" or @category != "all"}>
                <summary class="flex cursor-pointer select-none list-none items-center gap-2 py-1">
                  <svg class="w-3 h-3 text-gray-400 transition-transform group-open:rotate-90" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" /></svg>
                  <h4 class="text-sm font-semibold text-gray-700">Platform internals</h4>
                  <span class="text-[11px] font-mono font-semibold px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 border border-gray-200"><%= length(internal_exts) %></span>
                  <span class="hidden sm:inline text-xs text-gray-400">storage, transports and drivers that run the server; you rarely need them</span>
                </summary>

                <div class="mt-3 bg-white rounded-xl border border-gray-200 shadow-xs overflow-hidden">
                  <div class="overflow-x-auto">
                    <table class="w-full text-left border-collapse text-xs">
                      <thead>
                        <tr class="border-b border-gray-100 bg-gray-50/75 text-[10px] font-semibold text-gray-400 uppercase tracking-wider">
                          <th class="py-3 px-4">Extension</th>
                          <th class="py-3 px-4">Version</th>
                          <th class="py-3 px-4">Provides</th>
                          <th class="py-3 px-4 text-right">Actions</th>
                        </tr>
                      </thead>
                      <tbody class="divide-y divide-gray-100">
                        <%= for ext <- internal_exts do %>
                          <tr class="hover:bg-primary-50/40 transition-colors">
                            <td class="py-3 px-4">
                              <div class="flex items-center gap-2.5">
                                <span class="w-8 h-8 rounded-lg bg-gray-100 text-gray-700 flex items-center justify-center text-sm font-semibold shrink-0"><%= ExtensionPresenter.icon(ext) %></span>
                                <div class="min-w-0">
                                  <div class="font-semibold text-gray-900"><%= ExtensionPresenter.display_name(ext) %></div>
                                  <span class="text-[10px] font-mono text-gray-400 block truncate"><%= ext.id %></span>
                                </div>
                              </div>
                            </td>
                            <td class="py-3 px-4 text-gray-500 font-mono text-[11px]">v<%= to_string(ext.version) %></td>
                            <td class="py-3 px-4 text-gray-600"><%= counts_text(ext) %></td>
                            <td class="py-3 px-4 text-right">
                              <div class="flex items-center justify-end gap-1.5">
                                <button type="button" phx-click="inspect_extension" phx-value-id={to_string(ext.id)} class="exo-btn exo-btn-secondary exo-btn-sm" title="Inspect extension contracts"><.icon name={:search} class="w-3 h-3" /> Inspect</button>
                                <button type="button" phx-click="switch_tab" phx-value-tab={to_string(ext.id)} class="exo-btn exo-btn-secondary exo-btn-sm" title={"Open " <> ExtensionPresenter.display_name(ext)}>Open</button>
                              </div>
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              </details>
            <% end %>
          </div>
    """
  end
end
