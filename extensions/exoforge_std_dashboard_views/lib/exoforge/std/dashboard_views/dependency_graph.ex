defmodule Exoforge.Std.DashboardViews.DependencyGraph do
  @moduledoc """
  Interactive Extension Dependency Architecture & Directed Acyclic Graph (DAG) modal.
  Visualizes service contracts, topological tiers, and inter-extension dependency curves
  with selected/upstream/downstream highlighting and workflow simulation.

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
        type: p["type"] || "elixir",
        provides: p["provides"] || [],
        dependencies: resolved_deps,
        dependents: dependents
      }
    end)
  end

  defp compute_graph_layout(graph_nodes, graph_tiers) do
    col_width = 230
    col_gap = 70
    row_height = 80
    row_gap = 24
    pad_x = 30
    pad_y = 30

    tier_indices =
      graph_tiers
      |> Enum.with_index()
      |> Map.new()

    # Position nodes by tier column and row index
    {positioned_nodes, _counts} =
      Enum.reduce(graph_nodes, {[], %{}}, fn node, {acc, counts} ->
        col_idx = Map.get(tier_indices, node.tier, 0)
        row_idx = Map.get(counts, col_idx, 0)

        x = pad_x + col_idx * (col_width + col_gap)
        y = pad_y + row_idx * (row_height + row_gap)

        pos_node =
          Map.merge(node, %{
            x: x,
            y: y,
            width: col_width,
            height: row_height,
            col: col_idx,
            row: row_idx,
            left_x: x,
            right_x: x + col_width,
            anchor_y: y + div(row_height, 2)
          })

        {[pos_node | acc], Map.put(counts, col_idx, row_idx + 1)}
      end)

    node_map = Map.new(positioned_nodes, fn n -> {n.id, n} end)

    # Compute smooth cubic bezier connection curves
    edges =
      Enum.flat_map(positioned_nodes, fn consumer ->
        Enum.flat_map(consumer.dependencies, fn dep ->
          case Map.get(node_map, dep.provider) do
            nil ->
              []

            provider when provider.id == consumer.id ->
              []

            provider ->
              x1 = provider.right_x
              y1 = provider.anchor_y
              x2 = consumer.left_x
              y2 = consumer.anchor_y

              # Cubic bezier curve with control points
              dx = max(40, abs(x2 - x1) / 2)
              path = "M #{x1} #{y1} C #{x1 + dx} #{y1}, #{x2 - dx} #{y2}, #{x2} #{y2}"

              [
                %{
                  id: "#{provider.id}->#{consumer.id}",
                  from: provider.id,
                  to: consumer.id,
                  service: dep.service,
                  path: path,
                  x1: x1,
                  y1: y1,
                  x2: x2,
                  y2: y2
                }
              ]
          end
        end)
      end)

    total_cols = max(1, length(graph_tiers))
    canvas_width = max(900, pad_x * 2 + total_cols * (col_width + col_gap))
    max_rows = Enum.map(positioned_nodes, & &1.row) |> Enum.max(fn -> 0 end)
    canvas_height = max(520, pad_y * 2 + (max_rows + 1) * (row_height + row_gap) + 40)

    {positioned_nodes, edges, canvas_width, canvas_height}
  end

  attr(:plugins, :list, required: true)
  attr(:selected_plugin_id, :any, default: nil)
  attr(:target, :any, required: true)

  def graph(assigns) do
    graph_nodes = build_dependency_graph(assigns.plugins)
    graph_tiers = graph_nodes |> Enum.map(& &1.tier) |> Enum.uniq() |> Enum.sort()
    selected_node = Enum.find(graph_nodes, &(&1.id == assigns.selected_plugin_id))

    {pos_nodes, edges, canvas_w, canvas_h} =
      compute_graph_layout(graph_nodes, graph_tiers)

    assigns =
      assigns
      |> assign(:graph_nodes, graph_nodes)
      |> assign(:graph_tiers, graph_tiers)
      |> assign(:selected_node, selected_node)
      |> assign(:pos_nodes, pos_nodes)
      |> assign(:edges, edges)
      |> assign(:canvas_width, canvas_w)
      |> assign(:canvas_height, canvas_h)

    ~H"""
    <div class="fixed inset-0 z-50 overflow-y-auto bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div class="bg-white rounded-3xl max-w-7xl w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in zoom-in-95 duration-150 flex flex-col h-[92vh]">
        <!-- Modal Header -->
        <div class="flex items-center justify-between pb-4 border-b border-gray-100">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-2xl bg-violet-100 text-violet-700 flex items-center justify-center text-xl shadow-inner">
              🕸️
            </div>
            <div>
              <div class="flex items-center gap-2">
                <h3 class="text-lg font-bold text-gray-900 tracking-tight">Extension Dependency Architecture</h3>
                <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-violet-50 text-violet-700 border border-violet-200">
                  DAG Graph
                </span>
              </div>
              <p class="text-xs text-gray-500">
                Visual Directed Acyclic Graph (DAG) with bezier dependency routing and actor supervision tiers.
              </p>
            </div>
          </div>

          <!-- Controls & Close -->
          <div class="flex items-center gap-3">
            <div class="hidden sm:flex items-center gap-1.5 p-1 bg-gray-100 rounded-xl border border-gray-200 text-xs font-semibold">
              <button
                type="button"
                onclick="document.getElementById('dep-graph-svg-view').classList.remove('hidden'); document.getElementById('dep-graph-matrix-view').classList.add('hidden'); document.getElementById('btn-dag-graph').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-dag-matrix').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
                id="btn-dag-graph"
                class="px-3 py-1.5 rounded-lg bg-white text-violet-700 shadow-xs transition-all flex items-center gap-1.5 cursor-pointer"
              >
                <span>🕸️</span>
                <span>DAG Graph View</span>
              </button>
              <button
                type="button"
                onclick="document.getElementById('dep-graph-matrix-view').classList.remove('hidden'); document.getElementById('dep-graph-svg-view').classList.add('hidden'); document.getElementById('btn-dag-matrix').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-dag-graph').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
                id="btn-dag-matrix"
                class="px-3 py-1.5 rounded-lg text-gray-600 hover:text-gray-900 transition-all flex items-center gap-1.5 cursor-pointer"
              >
                <span>📊</span>
                <span>Tier Columns</span>
              </button>
            </div>

            <button
              phx-click="close_dependency_graph"
              phx-target={@target}
              class="text-gray-400 hover:text-gray-600 text-xl font-bold p-1 rounded-lg hover:bg-gray-100 transition-colors"
            >
              ✕
            </button>
          </div>
        </div>

        <!-- VIEW 1: INTERACTIVE SVG DAG GRAPH CANVAS -->
        <div id="dep-graph-svg-view" class="overflow-auto py-4 flex-1 border border-gray-100 rounded-2xl bg-slate-900/95 relative shadow-inner">
          <svg
            width={@canvas_width}
            height={@canvas_height}
            viewBox={"0 0 #{@canvas_width} #{@canvas_height}"}
            class="w-full h-auto select-none font-sans"
          >
            <defs>
              <!-- Arrow Markers -->
              <marker id="arrow-default" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b" />
              </marker>
              <marker id="arrow-amber" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
              </marker>
              <marker id="arrow-emerald" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981" />
              </marker>
              <!-- Drop Shadow Filter -->
              <filter id="node-shadow" x="-10%" y="-10%" width="120%" height="120%">
                <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000000" flood-opacity="0.3" />
              </filter>
            </defs>

            <!-- Tier Column Backgrounds & Headers -->
            <%= for {tier_name, col_idx} <- Enum.with_index(@graph_tiers) do %>
              <% col_x = 30 + col_idx * 300 %>
              <g class="tier-column">
                <rect
                  x={col_x - 10}
                  y="10"
                  width="250"
                  height={@canvas_height - 20}
                  rx="16"
                  fill="#0f172a"
                  stroke="#1e293b"
                  stroke-width="1"
                />
                <text
                  x={col_x + 10}
                  y="26"
                  fill="#94a3b8"
                  font-size="11"
                  font-weight="bold"
                  letter-spacing="0.08em"
                  text-transform="uppercase"
                >
                  <%= String.upcase(tier_name) %>
                </text>
              </g>
            <% end %>

            <!-- Connection Edges (Bezier Curves) -->
            <g class="edges">
              <%= for edge <- @edges do %>
                <% is_from_selected = @selected_plugin_id == edge.from %>
                <% is_to_selected = @selected_plugin_id == edge.to %>
                <% edge_class = cond do
                  is_from_selected -> "edge-downstream stroke-emerald-400"
                  is_to_selected -> "edge-upstream stroke-amber-400 stroke-dash"
                  @selected_plugin_id != nil -> "opacity-20 stroke-slate-600"
                  true -> "opacity-50 hover:opacity-100 stroke-slate-500 transition-opacity"
                end %>

                <path
                  d={edge.path}
                  fill="none"
                  stroke={cond do
                    is_from_selected -> "#10b981"
                    is_to_selected -> "#f59e0b"
                    @selected_plugin_id != nil -> "#334155"
                    true -> "#64748b"
                  end}
                  stroke-width={if is_from_selected or is_to_selected, do: "2.5", else: "1.5"}
                  stroke-dasharray={if is_to_selected, do: "5 3", else: "none"}
                  marker-end={cond do
                    is_from_selected -> "url(#arrow-emerald)"
                    is_to_selected -> "url(#arrow-amber)"
                    true -> "url(#arrow-default)"
                  end}
                  class={edge_class}
                />
              <% end %>
            </g>

            <!-- Graph Nodes -->
            <g class="nodes">
              <%= for node <- @pos_nodes do %>
                <% is_selected = @selected_plugin_id == node.id %>
                <% is_dependent = @selected_node && node.id in (@selected_node.dependents || []) %>
                <% is_dependency = @selected_node && Enum.any?(@selected_node.dependencies, fn d -> d.provider == node.id end) %>

                <g
                  class="cursor-pointer group"
                  phx-click="select_graph_plugin"
                  phx-value-id={node.id}
                  phx-target={@target}
                  transform={"translate(#{node.x}, #{node.y})"}
                >
                  <!-- Node Card Box -->
                  <rect
                    width={node.width}
                    height={node.height}
                    rx="12"
                    fill={cond do
                      is_selected -> "#7c3aed"
                      is_dependency -> "#451a03"
                      is_dependent -> "#064e3b"
                      true -> "#1e293b"
                    end}
                    stroke={cond do
                      is_selected -> "#c4b5fd"
                      is_dependency -> "#f59e0b"
                      is_dependent -> "#10b981"
                      true -> "#334155"
                    end}
                    stroke-width={if is_selected or is_dependency or is_dependent, do: "2", else: "1"}
                    filter="url(#node-shadow)"
                  />

                  <!-- Node Title -->
                  <text
                    x="12"
                    y="24"
                    fill={if is_selected, do: "#ffffff", else: "#f8fafc"}
                    font-size="12"
                    font-weight="bold"
                    font-family="monospace"
                  >
                    <%= node.name %>
                  </text>

                  <!-- Runtime Type Badge -->
                  <rect
                    x={node.width - 65}
                    y="10"
                    width="55"
                    height="18"
                    rx="6"
                    fill={if is_selected, do: "#5b21b6", else: "#0f172a"}
                  />
                  <text
                    x={node.width - 38}
                    y="22"
                    fill={if is_selected, do: "#ddd6fe", else: "#94a3b8"}
                    font-size="9"
                    font-weight="bold"
                    font-family="monospace"
                    text-anchor="middle"
                  >
                    <%= node.type %>
                  </text>

                  <!-- Provides Contracts Badges -->
                  <g transform="translate(12, 38)">
                    <%= for {svc, idx} <- Enum.with_index(Enum.take(node.provides, 2)) do %>
                      <rect
                        x={idx * 75}
                        y="0"
                        width="70"
                        height="16"
                        rx="4"
                        fill={if is_selected, do: "#6d28d9", else: "#334155"}
                      />
                      <text
                        x={idx * 75 + 35}
                        y="11"
                        fill={if is_selected, do: "#ffffff", else: "#a78bfa"}
                        font-size="9"
                        font-weight="bold"
                        font-family="monospace"
                        text-anchor="middle"
                      >
                        :<%= svc %>
                      </text>
                    <% end %>
                  </g>

                  <!-- Requirements Summary -->
                  <text
                    x="12"
                    y="68"
                    fill={if is_selected, do: "#ede9fe", else: "#64748b"}
                    font-size="9"
                    font-family="monospace"
                  >
                    <%= if node.dependencies == [], do: "Root service", else: "Requires #{length(node.dependencies)} contracts" %>
                  </text>
                </g>
              <% end %>
            </g>
          </svg>
        </div>

        <!-- VIEW 2: TIER COLUMNS VIEW (ALTERNATIVE) -->
        <div id="dep-graph-matrix-view" class="hidden overflow-y-auto py-5 space-y-6 flex-1 pr-1">
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5 gap-4">
            <%= for tier_name <- @graph_tiers do %>
              <% tier_nodes = Enum.filter(@graph_nodes, &(&1.tier == tier_name)) %>
              <div class="bg-gray-50/80 rounded-2xl p-3 border border-gray-200/80 flex flex-col">
                <div class="flex items-center justify-between mb-3 px-1">
                  <span class="text-[11px] font-bold text-gray-500 uppercase tracking-wider"><%= tier_name %></span>
                  <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-gray-200/80 text-gray-700"><%= length(tier_nodes) %></span>
                </div>

                <div class="space-y-2.5 flex-1">
                  <%= for node <- tier_nodes do %>
                    <% is_selected = @selected_plugin_id == node.id %>
                    <% is_dependent = @selected_node && node.id in (@selected_node.dependents || []) %>
                    <% is_dependency = @selected_node && Enum.any?(@selected_node.dependencies, fn d -> d.provider == node.id end) %>
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
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Node Inspector & Dependency Ledger -->
        <%= if @selected_node do %>
          <div class="mt-4 bg-violet-50/70 border border-violet-200 rounded-2xl p-4 animate-in fade-in duration-150">
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center gap-2">
                <span class="text-base font-bold text-violet-950 font-mono"><%= @selected_node.name %></span>
                <span class="text-xs text-violet-600 font-mono">(<%= @selected_node.id %>)</span>
                <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-violet-200 text-violet-800">
                  <%= @selected_node.tier %>
                </span>
              </div>
              <button phx-click="select_graph_plugin" phx-value-id={@selected_node.id} phx-target={@target} class="text-xs font-semibold text-violet-600 hover:text-violet-800 cursor-pointer">
                Clear selection
              </button>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
              <div class="bg-white p-3 rounded-xl border border-violet-100 shadow-2xs">
                <span class="font-bold text-gray-700 block mb-1">
                  Direct Upstream Dependencies (What this needs):
                </span>
                <%= if @selected_node.dependencies == [] do %>
                  <p class="text-gray-400 italic">None (Independent root service)</p>
                <% else %>
                  <ul class="space-y-1">
                    <%= for dep <- @selected_node.dependencies do %>
                      <li class="flex items-center justify-between text-gray-700">
                        <span class="font-mono font-bold text-amber-700">:<%= dep.service %></span>
                        <span class="text-gray-400">satisfied by: <span class="font-mono text-gray-700 font-semibold"><%= dep.provider || "unresolved" %></span></span>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>

              <div class="bg-white p-3 rounded-xl border border-violet-100 shadow-2xs">
                <span class="font-bold text-gray-700 block mb-1">
                  Downstream Dependents (What depends on this):
                </span>
                <%= if @selected_node.dependents == [] do %>
                  <p class="text-gray-400 italic">No other extensions currently depend on this</p>
                <% else %>
                  <ul class="space-y-1">
                    <%= for dependent_id <- @selected_node.dependents do %>
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
            Click on any extension above to trace its upstream dependencies (amber) and downstream dependents (emerald).
          </div>
        <% end %>

        <!-- Modal Footer -->
        <div class="pt-3 border-t border-gray-100 flex items-center justify-between">
          <div class="flex items-center gap-4 text-[11px] text-gray-500">
            <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-violet-600 inline-block"></span> Selected</span>
            <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-amber-400 inline-block"></span> Upstream Dependency</span>
            <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-emerald-400 inline-block"></span> Downstream Dependent</span>
          </div>
          <button
            type="button"
            phx-click="close_dependency_graph"
            phx-target={@target}
            class="px-4 py-2 text-xs font-semibold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end
end
