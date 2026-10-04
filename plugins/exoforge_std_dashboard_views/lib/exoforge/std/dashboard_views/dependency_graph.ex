defmodule Exoforge.Std.DashboardViews.DependencyGraph do
  @moduledoc """
  Plugin dependency-architecture modal: tiers derived from manifest category, with
  selected/upstream/downstream highlighting.

  Extracted from `PluginManagerView` so the component keeps only lifecycle and events.
  `target` is the parent LiveComponent's `@myself`, so the `phx-target` clicks route back.
  """
  use Phoenix.Component

  defp build_dependency_graph(plugins) do
    # Map service names (string) to the plugin id providing it
    provider_map =
      Enum.reduce(plugins, %{}, fn p, acc ->
        Enum.reduce(p["provides"] || [], acc, fn svc, m ->
          clean_svc = svc |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
          Map.put(m, clean_svc, p["id"])
        end)
      end)

    Enum.map(plugins, fn p ->
      pid = p["id"]
      deps = p["dependencies"] || []

      resolved_deps =
        Enum.map(deps, fn d ->
          clean_d = d |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
          provider = Map.get(provider_map, clean_d)
          %{service: clean_d, provider: provider}
        end)

      dependents =
        Enum.filter(plugins, fn other ->
          other_deps =
            Enum.map(other["dependencies"] || [], fn d ->
              d |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
            end)

          my_provides =
            Enum.map(p["provides"] || [], fn s ->
              s |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
            end)

          Enum.any?(other_deps, &(&1 in my_provides))
        end)
        |> Enum.map(& &1["id"])

      tier = p["category"] || "Extension"

      %{
        id: pid,
        name: p["name"] || pid,
        tier: tier,
        provides: p["provides"] || [],
        dependencies: resolved_deps,
        dependents: dependents
      }
    end)
  end

  attr(:plugins, :list, required: true)
  attr(:selected_plugin_id, :any, default: nil)
  attr(:target, :any, required: true)

  def graph(assigns) do
    assigns = assign(assigns, :selected_plugin_id, assigns.selected_plugin_id)

    ~H"""
        <% graph_nodes = build_dependency_graph(@plugins) %>
        <% graph_tiers = graph_nodes |> Enum.map(& &1.tier) |> Enum.uniq() |> Enum.sort() %>
        <% selected_node = Enum.find(graph_nodes, &(&1.id == @graph_selected_plugin_id)) %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/50 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-3xl max-w-4xl w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in zoom-in-95 duration-150 flex flex-col max-h-[90vh]">
            <!-- Modal Header -->
            <div class="flex items-center justify-between pb-4 border-b border-gray-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-2xl bg-violet-100 text-violet-700 flex items-center justify-center text-xl shadow-inner">
                  🕸️
                </div>
                <div>
                  <h3 class="text-lg font-bold text-gray-900">Plugin Dependency Architecture</h3>
                  <p class="text-xs text-gray-500">Visual Directed Acyclic Graph (DAG) of cluster service contracts and plugin dependencies.</p>
                </div>
              </div>
              <button
                phx-click="close_dependency_graph"
                phx-target={@target}
                class="text-gray-400 hover:text-gray-600 text-xl font-bold p-1 rounded-lg hover:bg-gray-100 transition-colors"
              >
                ✕
              </button>
            </div>

            <!-- Graph Canvas / Architecture Tiers -->
            <div class="overflow-y-auto py-5 space-y-6 flex-1 pr-1">
              <!-- Tier Pipeline View -->
              <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
                <%= for tier_name <- graph_tiers do %>
                  <% tier_nodes = Enum.filter(graph_nodes, &(&1.tier == tier_name)) %>
                  <div class="bg-gray-50/80 rounded-2xl p-3 border border-gray-200/80 flex flex-col">
                    <div class="flex items-center justify-between mb-3 px-1">
                      <span class="text-[11px] font-bold text-gray-500 uppercase tracking-wider"><%= tier_name %></span>
                      <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-gray-200/80 text-gray-700"><%= length(tier_nodes) %></span>
                    </div>

                    <div class="space-y-2.5 flex-1">
                      <%= for node <- tier_nodes do %>
                        <% is_selected = @graph_selected_plugin_id == node.id %>
                        <% is_dependent = selected_node && node.id in (selected_node.dependents || []) %>
                        <% is_dependency = selected_node && Enum.any?(selected_node.dependencies, fn d -> d.provider == node.id end) %>
                        <div
                          phx-click="select_graph_plugin"
                          phx-value-id={node.id}
                          phx-target={@target}
                          class={"p-3 rounded-xl border cursor-pointer transition-all #{cond do
                            is_selected -> "bg-violet-600 text-white border-violet-700 shadow-md ring-2 ring-violet-400"
                            is_dependency -> "bg-amber-50 border-amber-300 shadow-sm ring-1 ring-amber-300"
                            is_dependent -> "bg-emerald-50 border-emerald-300 shadow-sm ring-1 ring-emerald-300"
                            true -> "bg-white border-gray-200 hover:border-violet-300 hover:shadow-xs text-gray-800"
                          end}"}
                        >
                          <div class="flex items-center justify-between">
                            <span class={"font-bold text-xs truncate max-w-[140px] #{if is_selected, do: "text-white", else: "text-gray-900"}"} title={node.name}>
                              <%= node.name %>
                            </span>
                            <span class={"text-[9px] font-mono px-1.5 py-0.5 rounded #{if is_selected, do: "bg-violet-700 text-violet-100", else: "bg-gray-100 text-gray-500"}"}>
                              <%= if node.dependencies == [], do: "Root", else: "#{length(node.dependencies)} deps" %>
                            </span>
                          </div>

                          <div class="mt-2 space-y-1">
                            <div class="flex flex-wrap gap-1">
                              <%= for s <- node.provides do %>
                                <span class={"text-[9px] font-mono font-bold px-1 rounded #{if is_selected, do: "bg-violet-500 text-white", else: "bg-violet-50 text-violet-700 border border-violet-200"}"}>
                                  :<%= s %>
                                </span>
                              <% end %>
                            </div>

                            <%= if node.dependencies != [] do %>
                              <div class="pt-1 flex items-center gap-1 text-[9px] text-gray-500">
                                <span class={if is_selected, do: "text-violet-200", else: "text-gray-400"}>requires:</span>
                                <div class="flex flex-wrap gap-1">
                                  <%= for dep <- node.dependencies do %>
                                    <span class={"font-mono font-semibold px-1 rounded #{if is_selected, do: "bg-violet-700 text-violet-100", else: "bg-gray-100 text-gray-600"}"}>
                                      :<%= dep.service %>
                                    </span>
                                  <% end %>
                                </div>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Node Inspector & Dependency Ledger -->
              <%= if selected_node do %>
                <div class="bg-violet-50/60 border border-violet-200 rounded-2xl p-4 animate-in fade-in duration-150">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <span class="text-base font-bold text-violet-950 font-mono"><%= selected_node.name %></span>
                      <span class="text-xs text-violet-600 font-mono">(<%= selected_node.id %>)</span>
                    </div>
                    <button phx-click="select_graph_plugin" phx-value-id={selected_node.id} phx-target={@target} class="text-xs font-semibold text-violet-600 hover:text-violet-800">
                      Clear selection
                    </button>
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
                    <div class="bg-white p-3 rounded-xl border border-violet-100">
                      <span class="font-bold text-gray-700 block mb-1">Direct Upstream Dependencies (What this needs):</span>
                      <%= if selected_node.dependencies == [] do %>
                        <p class="text-gray-400 italic">None (Independent root service)</p>
                      <% else %>
                        <ul class="space-y-1">
                          <%= for dep <- selected_node.dependencies do %>
                            <li class="flex items-center justify-between text-gray-700">
                              <span class="font-mono font-bold text-violet-700">:<%= dep.service %></span>
                              <span class="text-gray-400">satisfied by: <span class="font-mono text-gray-700 font-semibold"><%= dep.provider || "unresolved" %></span></span>
                            </li>
                          <% end %>
                        </ul>
                      <% end %>
                    </div>

                    <div class="bg-white p-3 rounded-xl border border-violet-100">
                      <span class="font-bold text-gray-700 block mb-1">Downstream Dependents (What depends on this):</span>
                      <%= if selected_node.dependents == [] do %>
                        <p class="text-gray-400 italic">No other plugins currently depend on this</p>
                      <% else %>
                        <ul class="space-y-1">
                          <%= for dependent_id <- selected_node.dependents do %>
                            <li class="flex items-center gap-1.5 text-gray-700">
                              <span class="text-emerald-500 font-bold">▲</span>
                              <span class="font-mono font-semibold"><%= dependent_id %></span>
                            </li>
                          <% end %>
                        </ul>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="text-center py-2 text-xs text-gray-400">
                  Click on any plugin above to highlight its upstream dependencies and downstream dependents.
                </div>
              <% end %>
            </div>

            <!-- Modal Footer -->
            <div class="pt-4 border-t border-gray-100 flex items-center justify-between">
              <div class="flex items-center gap-4 text-[11px] text-gray-500">
                <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-violet-600 inline-block"></span> Selected</span>
                <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-amber-400 inline-block"></span> Upstream Dependency</span>
                <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-emerald-400 inline-block"></span> Downstream Dependent</span>
              </div>
              <button
                type="button"
                phx-click="close_dependency_graph"
                phx-target={@target}
                class="px-4 py-2 text-xs font-semibold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
    """
  end
end
