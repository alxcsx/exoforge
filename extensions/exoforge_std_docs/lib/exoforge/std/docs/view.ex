defmodule Exoforge.Std.Docs.View do
  @moduledoc """
  The Developer Guide: a sidebar of pages (`Exoforge.Std.Docs.Pages`), the page itself with an "On this
  page" list and previous/next links, and 1-click Print/PDF export. A chapter is rendered from its
  Markdown file under `priv/docs` and nothing else; the two live pages are the architecture map and the
  API catalog.
  """
  use Phoenix.Component
  import Exoforge.Std.Docs.Icons, only: [studio_icon: 1]

  alias Exoforge.Std.Docs.Markdown
  alias Exoforge.Std.Docs.Pages

  defp scope_badge_class(scope) do
    case to_string(scope || "guest") |> String.downcase() do
      "admin" ->
        "bg-red-50 text-red-700 border-red-200"

      "studio" ->
        "bg-primary-50 text-primary-700 border-primary-200"

      "global" ->
        "bg-blue-50 text-blue-800 border-blue-200"

      "player" ->
        "bg-emerald-50 text-emerald-700 border-emerald-200"

      "guest" ->
        "bg-gray-100 text-gray-700 border-gray-200"

      "server" ->
        "bg-primary-50 text-primary-700 border-primary-200"

      _other ->
        "bg-emerald-50 text-emerald-700 border-emerald-200"
    end
  end

  defp mode_badge_class("async"),
    do: "bg-amber-50 text-amber-700 border-amber-200"

  defp mode_badge_class("cast"),
    do: "bg-primary-50 text-primary-700 border-primary-200"

  defp mode_badge_class(_),
    do: "bg-gray-100 text-gray-700 border-gray-200"

  attr(:action_catalog, :list, default: [])
  attr(:extensions, :list, default: [])
  attr(:project_name, :string, default: "Game")
  attr(:studio_name, :string, default: "Studio")
  attr(:subpage, :string, default: "flow")
  attr(:myself, :any, default: nil)

  def view(assigns) do
    assigns = assign_new(assigns, :myself, fn -> nil end)

    # Fallback to dynamic catalog if not supplied
    action_catalog =
      if assigns.action_catalog == [] do
        Exoforge.Std.Docs.build_api_catalog()
      else
        assigns.action_catalog
      end

    # Ensure services and actions are strictly deduplicated by name and sanitized
    action_catalog =
      action_catalog
      |> Enum.uniq_by(fn svc -> svc[:name] || svc["name"] end)
      |> Enum.map(fn svc ->
        actions =
          (svc[:actions] || svc["actions"] || [])
          |> Enum.uniq_by(fn act -> act[:name] || act["name"] end)
          |> Enum.map(fn act ->
            %{
              name: to_string(act[:name] || act["name"]),
              mode: to_string(act[:mode] || act["mode"] || "sync"),
              scope: to_string(act[:scope] || act["scope"] || "guest"),
              doc: act[:doc] || act["doc"] || "No description provided.",
              params: act[:params] || act["params"] || [],
              returns: act[:returns] || act["returns"]
            }
          end)

        Map.put(svc, :actions, actions)
      end)

    assigns = assign(assigns, :action_catalog, action_catalog)

    pages = Pages.all()
    page = Pages.fetch(assigns.subpage, pages)
    {previous, next} = Pages.neighbours(page, pages)

    assigns =
      assigns
      |> assign(:pages, Pages.grouped(pages))
      |> assign(:page, page)
      |> assign(:previous, previous)
      |> assign(:next, next)
      |> assign(:toc, if(page.kind == :chapter, do: Pages.toc(page.content), else: []))

    ~H"""
    <div id="developer-guide-container" phx-hook="GuideNavigator" class="max-w-7xl mx-auto pb-16 print:p-0 print:max-w-none print:pb-0">
      <style>
        @media print {
          body { background: white !important; color: black !important; font-size: 11pt !important; }
          .print\:hidden { display: none !important; }
          .print\:break-inside-avoid { break-inside: avoid !important; page-break-inside: avoid !important; }
          .print\:shadow-none { box-shadow: none !important; }
          .print\:border-gray-300 { border-color: #d1d5db !important; }
          .print\:p-0 { padding: 0 !important; }
          .print\:bg-white { background-color: white !important; }
          pre, code { white-space: pre-wrap !important; word-break: break-word !important; }
        }
      </style>

      <div class="print:hidden exo-page-header">
        <div>
          <span class="exo-page-title block">Developer Guide</span>
          <span class="exo-page-subtitle">Build, version and run your game's extensions</span>
        </div>
        <div class="exo-page-actions">
          <a
            href="/api/docs/manual.pdf"
            download="exoforge-developer-manual.pdf"
            title="Download the Developer Guide as a PDF"
            class="exo-btn exo-btn-secondary exo-btn-sm no-underline"
          >
            <.studio_icon icon="download" class="w-3.5 h-3.5" />
            <span>Export to PDF</span>
          </a>
        </div>
      </div>

      <div class="mt-6 grid gap-8 lg:grid-cols-[14rem_minmax(0,1fr)] xl:grid-cols-[14rem_minmax(0,1fr)_13rem]">
        <nav aria-label="Developer Guide pages" class="print:hidden lg:sticky lg:top-4 lg:self-start lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto space-y-5 pr-1">
          <%= for {group, group_pages} <- @pages do %>
            <div>
              <p class="px-2 mb-1 text-[11px] font-semibold uppercase tracking-wider text-gray-400"><%= group %></p>
              <ul class="space-y-0.5">
                <%= for p <- group_pages do %>
                  <li>
                    <button
                      type="button"
                      phx-click="set_guide_subpage"
                      phx-target={@myself}
                      phx-value-subpage={p.id}
                      onclick="window.exoScrollTop && window.exoScrollTop()"
                      aria-current={if p.id == @page.id, do: "page"}
                      class={[
                        "w-full flex items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition-colors",
                        if(p.id == @page.id,
                          do: "bg-primary-50 text-primary-700 font-semibold",
                          else: "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
                        )
                      ]}
                    >
                      <.studio_icon icon={p.icon} class="w-3.5 h-3.5 shrink-0" />
                      <span class="truncate"><%= p.nav %></span>
                    </button>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </nav>

        <main class="min-w-0">
          <%= case @page.kind do %>
            <% :architecture -> %>
              <.subpage_architecture />
            <% :catalog -> %>
              <.subpage_catalog action_catalog={@action_catalog} myself={@myself} />
            <% :chapter -> %>
              <article id={"guide-" <> @page.id} class="bg-white rounded-xl border border-gray-200/90 px-6 py-8 sm:px-10 shadow-sm print:border-0 print:shadow-none print:p-0">
                <p class="text-xs font-semibold uppercase tracking-wider text-primary-700 mb-2"><%= @page.group %></p>
                <%= Markdown.to_html(@page.content) %>
              </article>
          <% end %>

          <nav :if={@previous || @next} aria-label="Previous and next page" class="print:hidden mt-6 grid gap-3 sm:grid-cols-2">
            <button
              :if={@previous}
              type="button"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage={@previous.id}
              onclick="window.exoScrollTop && window.exoScrollTop()"
              class="rounded-xl border border-gray-200 bg-white px-4 py-3 text-left hover:border-primary-300 transition-colors"
            >
              <span class="block text-[11px] uppercase tracking-wider text-gray-400">Previous</span>
              <span class="block text-sm font-semibold text-gray-900"><%= @previous.nav %></span>
            </button>
            <span :if={!@previous}></span>
            <button
              :if={@next}
              type="button"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage={@next.id}
              onclick="window.exoScrollTop && window.exoScrollTop()"
              class="rounded-xl border border-gray-200 bg-white px-4 py-3 text-right hover:border-primary-300 transition-colors sm:col-start-2"
            >
              <span class="block text-[11px] uppercase tracking-wider text-gray-400">Next</span>
              <span class="block text-sm font-semibold text-gray-900"><%= @next.nav %></span>
            </button>
          </nav>
        </main>

        <aside :if={@toc != []} class="hidden xl:block print:hidden">
          <div class="sticky top-4 max-h-[calc(100vh-2rem)] overflow-y-auto">
            <p class="mb-2 text-[11px] font-semibold uppercase tracking-wider text-gray-400">On this page</p>
            <ul class="space-y-1 border-l border-gray-200">
              <%= for {level, text, id} <- @toc do %>
                <li>
                  <a
                    href={"#" <> id}
                    class={[
                      "block -ml-px border-l border-transparent py-0.5 text-xs text-gray-500 hover:border-primary-400 hover:text-gray-900",
                      if(level == 2, do: "pl-3", else: "pl-6")
                    ]}
                  ><%= text %></a>
                </li>
              <% end %>
            </ul>
          </div>
        </aside>
      </div>

      <button
        type="button"
        onclick="window.exoScrollTop && window.exoScrollTop()"
        title="Back to Top"
        class="fixed bottom-6 right-6 z-50 print:hidden p-3 rounded-full bg-primary-600 hover:bg-primary-700 text-white shadow-lg shadow-primary-900/30 transition-colors"
      >
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 15l7-7 7 7" />
        </svg>
      </button>
    </div>
    """
  end

  # ===========================================================================
  # PAGE: ARCHITECTURE MAP (live)
  # ===========================================================================
  defp subpage_architecture(assigns) do
    ~H"""
    <div id="architecture-graph" data-guide-section class="bg-white rounded-xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none">
      <Exoforge.Std.Docs.ArchitectureGraph.visualizer />
    </div>
    """
  end


  # ===========================================================================
  # SUBPAGE: DYNAMIC API REFERENCE & CATALOG
  # ===========================================================================
  defp subpage_catalog(assigns) do
    ~H"""
    <section id="catalog" data-guide-section class="bg-white rounded-xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 text-[10px] font-semibold">
            
            <span>Live Cluster Contracts</span>
          </div>
          <h2 class="text-xl font-semibold text-gray-900 tracking-tight mt-1">
            Live Services &amp; Action Catalog
          </h2>
          <p class="text-xs text-gray-500">
            Dynamically extracted from currently loaded extensions on this cluster. Foldable by extension and action.
          </p>
        </div>
        <span class="text-xs font-semibold text-gray-500 bg-gray-100 px-3 py-1.5 rounded-xl self-start md:self-auto font-mono">
          <%= length(@action_catalog) %> Services Loaded
        </span>
      </div>

      <div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 pt-2 border-t border-gray-100">
        <div class="relative flex-1">
          <input
            type="text"
            id="catalog-search"
            placeholder="Search services, actions, parameters..."
            oninput="const q = this.value.toLowerCase().trim(); document.querySelectorAll('#catalog-list > details').forEach(d => { const text = d.innerText.toLowerCase(); d.style.display = (!q || text.includes(q)) ? '' : 'none'; if (q && text.includes(q)) d.open = true; });"
            class="w-full pl-9 pr-4 py-2 bg-gray-50 hover:bg-gray-100/80 focus:bg-white border border-gray-200 rounded-xl text-xs text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500 transition-colors font-mono"
          />
          <svg class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button
            type="button"
            onclick="document.querySelectorAll('#catalog-list details').forEach(d => d.open = true);"
            class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-semibold transition-colors cursor-pointer"
          >
            Expand All
          </button>
          <button
            type="button"
            onclick="document.querySelectorAll('#catalog-list details').forEach(d => d.open = false);"
            class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-semibold transition-colors cursor-pointer"
          >
            Collapse All
          </button>
        </div>
      </div>

      <%= if @action_catalog == [] do %>
        <div class="text-center py-12 px-6 bg-gray-50 rounded-xl border border-dashed border-gray-200 space-y-3">
          <p class="font-medium text-gray-700">No callable services yet</p>
          <p class="text-xs text-gray-500 max-w-md mx-auto">
            Build and deploy an extension, then sync its contracts. The Quickstart walks through scaffolding, building, and deploying your first service.
          </p>
          <button
            type="button"
            phx-click="set_guide_subpage"
            phx-target={@myself}
            phx-value-subpage="flow"
            class="exo-btn exo-btn-secondary exo-btn-sm inline-flex"
          >
            Open the Quickstart
          </button>
        </div>
      <% else %>
        <div id="catalog-list" class="space-y-4">
          <%= for svc <- @action_catalog do %>
            <details class="group bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden transition-colors duration-200 print:border-gray-300 print:shadow-none print:break-inside-avoid">
              <summary class="flex items-center justify-between gap-3 p-5 cursor-pointer select-none bg-white hover:bg-gray-50 transition-colors list-none">
                <div class="flex items-center gap-3">
                  <span class="w-9 h-9 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center font-semibold text-base shadow-xs">
                    <.studio_icon icon={svc[:icon] || "gear"} class="w-5 h-5" />
                  </span>
                  <div>
                    <h3 class="font-semibold text-gray-900 text-sm tracking-tight font-mono">
                      <%= svc[:name] %>
                    </h3>
                    <%= if svc[:title] do %>
                      <p class="text-[11px] text-gray-500"><%= svc[:title] %></p>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center gap-3">
                  <span class="text-[11px] font-semibold px-2.5 py-1 rounded-full bg-gray-100 text-gray-600 font-mono">
                    <%= length(svc[:actions] || []) %> <%= if length(svc[:actions] || []) == 1, do: "action", else: "actions" %>
                  </span>
                  <svg class="print:hidden w-5 h-5 text-gray-400 group-open:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </div>
              </summary>

              <div class="p-5 pt-3 border-t border-gray-100 space-y-3 bg-gray-50/50 print:bg-white">
                <%= for act <- (svc[:actions] || []) do %>
                  <details class="group/act bg-white rounded-xl border border-gray-200/80 p-4 space-y-3 shadow-2xs transition-colors print:border-gray-300 print:break-inside-avoid">
                    <summary class="flex items-center justify-between gap-2 cursor-pointer select-none list-none">
                      <div class="flex items-center gap-2">
                        <span class="font-semibold text-primary-800 text-xs font-mono">
                          <%= format_action_signature(act) %>
                        </span>
                        <%= if act.mode in ["async", "cast"] do %>
                          <span class={"text-[10px] font-semibold px-1.5 py-0.5 rounded border uppercase font-mono " <> mode_badge_class(act.mode)}><%= act.mode %></span>
                        <% end %>
                        <%= if act.scope do %>
                          <span class={"text-[10px] font-semibold px-1.5 py-0.5 rounded border uppercase font-mono " <> scope_badge_class(act.scope)}><%= act.scope %></span>
                        <% end %>
                      </div>

                      <div class="flex items-center gap-2">
                        <span class="text-[11px] text-gray-400 font-mono hidden sm:inline">
                          <%= length(act.params || []) %> params
                        </span>
                        <svg class="print:hidden w-4 h-4 text-gray-400 group-open/act:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                        </svg>
                      </div>
                    </summary>

                    <div class="pt-2 border-t border-gray-100 space-y-3">
                      <p class="text-xs text-gray-600 leading-relaxed"><%= act.doc %></p>

                      <%= if is_list(act.params) and act.params != [] do %>
                        <div class="space-y-1.5">
                          <div class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">Parameters</div>
                          <div class="overflow-x-auto rounded-lg border border-gray-200">
                            <table class="w-full text-left text-xs bg-white">
                              <thead>
                                <tr class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                                  <th class="py-1.5 px-3">Name</th>
                                  <th class="py-1.5 px-3">Type</th>
                                  <th class="py-1.5 px-3">Status</th>
                                  <th class="py-1.5 px-3">Description</th>
                                </tr>
                              </thead>
                              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                                <%= for p <- act.params do %>
                                  <tr>
                                    <td class="py-1.5 px-3 font-semibold text-gray-900"><%= p.name %></td>
                                    <td class="py-1.5 px-3 text-primary-700"><%= p.type %></td>
                                    <td class="py-1.5 px-3">
                                      <%= if Map.get(p, :optional, false) do %>
                                        <span class="text-gray-400 text-[10px]">Optional</span>
                                      <% else %>
                                        <span class="text-red-600 font-semibold text-[10px]">Required</span>
                                      <% end %>
                                    </td>
                                    <td class="py-1.5 px-3 font-sans text-xs text-gray-600">
                                      <%= Map.get(p, :doc) || "—" %>
                                    </td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        </div>
                      <% end %>

                      <div class="space-y-2 pt-1 print:break-inside-avoid">
                        <div class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">Unity Calling Styles</div>
                        
                        <div class="space-y-1">
                          <div class="text-[10px] text-gray-500 font-semibold">Unity Callback (Non-Async / Main Thread):</div>
                          <pre class="bg-gray-950 text-gray-200 p-3 rounded-xl font-mono text-[10px] overflow-x-auto border border-gray-800 max-w-full"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_callback(svc[:name], act))) %></code></pre>
                        </div>

                        <div class="space-y-1">
                          <div class="text-[10px] text-gray-500 font-semibold">Task Async/Await:</div>
                          <pre class="bg-gray-950 text-gray-200 p-3 rounded-xl font-mono text-[10px] overflow-x-auto border border-gray-800 max-w-full"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_async(svc[:name], act))) %></code></pre>
                        </div>
                      </div>
                    </div>
                  </details>
                <% end %>
              </div>
            </details>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  defp format_action_signature(act) do
    name = act[:name] || act.name
    params = act[:params] || act.params || []

    sorted_params =
      Enum.sort_by(params, fn p ->
        optional? = p[:optional] || p["optional"] || false
        if optional?, do: 1, else: 0
      end)

    params_str =
      sorted_params
      |> Enum.map(fn p ->
        p_name = p[:name] || p["name"] || ""
        optional? = p[:optional] || p["optional"] || false

        if optional? do
          "#{p_name}?"
        else
          "#{p_name}"
        end
      end)
      |> Enum.join(", ")

    ".#{name}(#{params_str})"
  end

  # ===========================================================================
  # C# SNIPPET GENERATORS
  # ===========================================================================

  defp snippet_callback(svc_name, act) do
    service_pascal = Macro.camelize(to_string(svc_name))
    action_pascal = Macro.camelize(to_string(act.name))
    params = act.params || []

    args =
      if params == [] do
        ""
      else
        req_name = "#{action_pascal}Request"
        "new #{req_name}(/* parameters */), "
      end

    """
    Exo.#{service_pascal}.#{action_pascal}(
        #{args}onComplete: result => Debug.Log($"Success: {result}"),
        onError: err => Debug.LogError($"Error: {err.Message}")
    );
    """
    |> String.trim()
  end

  defp snippet_async(svc_name, act) do
    service_pascal = Macro.camelize(to_string(svc_name))
    action_pascal = Macro.camelize(to_string(act.name))
    params = act.params || []

    args =
      if params == [] do
        ""
      else
        req_name = "#{action_pascal}Request"
        "new #{req_name}(/* parameters */)"
      end

    """
    var result = await Exo.#{service_pascal}.#{action_pascal}Async(#{args});
    Debug.Log($"Success: {result}");
    """
    |> String.trim()
  end

end
