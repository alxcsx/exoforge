defmodule Exoforge.Std.DashboardViews.DependencyGraph do
  @moduledoc """
  Interactive Extension Dependency Architecture & Directed Acyclic Graph (DAG) modal.
  Visualizes service contracts, topological tiers, and inter-extension dependency curves
  with selected/upstream/downstream highlighting and workflow simulation.

  Extracted from `PluginManagerView` so the component keeps only lifecycle and events.
  `target` is the parent LiveComponent's `@myself`, so the `phx-target` clicks route back.
  """
  use Phoenix.Component

  defp get_val(map, key) when is_map(map) do
    Map.get(map, to_string(key)) || Map.get(map, String.to_atom(to_string(key)))
  end
  defp get_val(_other, _key), do: nil

  defp build_dependency_graph(plugins) when is_list(plugins) do
    # Map service names (string) to the plugin id providing it
    provider_map =
      Enum.reduce(plugins, %{}, fn p, acc ->
        provides = get_val(p, :provides) || []
        pid = to_string(get_val(p, :id) || "")
        Enum.reduce(provides, acc, fn svc, m ->
          clean_svc = svc |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
          Map.put(m, clean_svc, pid)
        end)
      end)

    Enum.map(plugins, fn p ->
      pid = to_string(get_val(p, :id) || "")
      name = to_string(get_val(p, :title) || get_val(p, :name) || pid)
      deps = get_val(p, :dependencies) || []
      provides = get_val(p, :provides) || []
      tier = to_string(get_val(p, :category) || "Extension")
      type = to_string(get_val(p, :type) || "elixir")
      icon = to_string(get_val(p, :icon) || "🧩")

      resolved_deps =
        Enum.map(deps, fn d ->
          clean_d = d |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
          provider = Map.get(provider_map, clean_d)
          %{service: clean_d, provider: provider}
        end)

      dependents =
        Enum.filter(plugins, fn other ->
          other_deps =
            Enum.map(get_val(other, :dependencies) || [], fn d ->
              d |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
            end)

          my_provides =
            Enum.map(provides, fn s ->
              s |> to_string() |> String.replace_prefix(":", "") |> String.downcase()
            end)

          Enum.any?(other_deps, &(&1 in my_provides))
        end)
        |> Enum.map(&to_string(get_val(&1, :id)))

      upstream_ids =
        resolved_deps
        |> Enum.map(& &1.provider)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      %{
        id: pid,
        name: name,
        tier: tier,
        type: type,
        icon: icon,
        provides: provides,
        dependencies: resolved_deps,
        dependents: dependents,
        upstream_ids: upstream_ids
      }
    end)
  end
  defp build_dependency_graph(_), do: []

  defp compute_graph_layout(graph_nodes, graph_tiers) do
    col_width = 240
    col_gap = 70
    row_height = 85
    row_gap = 24
    pad_x = 30
    pad_y = 35

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
    canvas_width = max(980, pad_x * 2 + total_cols * (col_width + col_gap))
    max_rows = Enum.map(positioned_nodes, & &1.row) |> Enum.max(fn -> 0 end)
    canvas_height = max(560, pad_y * 2 + (max_rows + 1) * (row_height + row_gap) + 40)

    {positioned_nodes, edges, canvas_width, canvas_height}
  end

  attr(:plugins, :list, required: true)
  attr(:selected_plugin_id, :any, default: nil)
  attr(:target, :any, required: true)

  def graph(assigns) do
    plugins = assigns.plugins || []
    graph_nodes = build_dependency_graph(plugins)
    graph_tiers = graph_nodes |> Enum.map(& &1.tier) |> Enum.uniq() |> Enum.sort()
    selected_node = Enum.find(graph_nodes, &(&1.id == assigns.selected_plugin_id))

    {pos_nodes, edges, canvas_w, canvas_h} =
      compute_graph_layout(graph_nodes, graph_tiers)

    assigns =
      Map.merge(assigns, %{
        graph_nodes: graph_nodes,
        graph_tiers: graph_tiers,
        selected_node: selected_node,
        pos_nodes: pos_nodes,
        edges: edges,
        canvas_width: canvas_w,
        canvas_height: canvas_h
      })

    ~H"""
    <div class="fixed inset-0 z-50 overflow-hidden bg-black/75 backdrop-blur-md flex items-center justify-center p-3 sm:p-5">
      <div class="bg-slate-950 rounded-xl max-w-7xl w-full p-5 shadow-2xl border border-slate-800 relative animate-in fade-in zoom-in-95 duration-150 flex flex-col h-[94vh] text-white">
        <!-- Modal Header -->
        <div class="flex items-center justify-between pb-4 border-b border-slate-800">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-primary-500/20 text-primary-400 border border-primary-500/30 flex items-center justify-center text-xl shadow-inner">
              🕸️
            </div>
            <div>
              <div class="flex items-center gap-2">
                <h3 class="text-lg font-black text-white tracking-tight">Extension Dependency Architecture</h3>
                <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-primary-400/20 text-primary-300 border border-primary-400/30">
                  DAG Engine
                </span>
                <span class="text-[10px] font-mono text-slate-400">
                  <%= length(@graph_nodes) %> Extensions
                </span>
              </div>
              <p class="text-xs text-slate-400">
                Topological supervision tiers, 1-hop dependency spotlighting, and service interconnect contracts.
              </p>
            </div>
          </div>

          <!-- Controls & Close -->
          <div class="flex items-center gap-3">
            <!-- View Switcher -->
            <div class="hidden sm:flex items-center gap-1.5 p-1 bg-slate-900 rounded-xl border border-slate-800 text-xs font-semibold">
              <button
                type="button"
                onclick="document.getElementById('dep-graph-svg-view').classList.remove('hidden'); document.getElementById('dep-graph-matrix-view').classList.add('hidden'); document.getElementById('btn-dag-graph').classList.add('bg-primary-600', 'text-white'); document.getElementById('btn-dag-graph').classList.remove('text-slate-400'); document.getElementById('btn-dag-matrix').classList.remove('bg-primary-600', 'text-white'); document.getElementById('btn-dag-matrix').classList.add('text-slate-400');"
                id="btn-dag-graph"
                class="px-3 py-1.5 rounded-lg bg-primary-600 text-white shadow-xs transition-all flex items-center gap-1.5 cursor-pointer"
              >
                <span>🕸️</span>
                <span>DAG Graph</span>
              </button>
              <button
                type="button"
                onclick="document.getElementById('dep-graph-matrix-view').classList.remove('hidden'); document.getElementById('dep-graph-svg-view').classList.add('hidden'); document.getElementById('btn-dag-matrix').classList.add('bg-primary-600', 'text-white'); document.getElementById('btn-dag-matrix').classList.remove('text-slate-400'); document.getElementById('btn-dag-graph').classList.remove('bg-primary-600', 'text-white'); document.getElementById('btn-dag-graph').classList.add('text-slate-400');"
                id="btn-dag-matrix"
                class="px-3 py-1.5 rounded-lg text-slate-400 hover:text-white transition-all flex items-center gap-1.5 cursor-pointer"
              >
                <span>📊</span>
                <span>Tier Columns</span>
              </button>
            </div>

            <!-- Close Modal -->
            <button
              phx-click="close_dependency_graph"
              phx-target={@target}
              class="w-8 h-8 rounded-full bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white flex items-center justify-center font-bold text-sm transition-colors cursor-pointer"
              title="Close Modal"
            >
              ✕
            </button>
          </div>
        </div>

        <!-- VIEW 1: INTERACTIVE SVG DAG GRAPH CANVAS -->
        <div id="dep-graph-svg-view" class="overflow-auto py-3 flex-1 border border-slate-800/80 rounded-xl bg-slate-950 relative shadow-inner">
          <svg
            width={@canvas_width}
            height={@canvas_height}
            viewBox={"0 0 #{@canvas_width} #{@canvas_height}"}
            class="w-full h-auto select-none font-sans"
          >
            <defs>
              <!-- Arrow Markers -->
              <marker id="dep-arrow-default" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b" />
              </marker>
              <marker id="dep-arrow-amber" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
              </marker>
              <marker id="dep-arrow-emerald" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981" />
              </marker>
              <!-- Drop Shadow Filter -->
              <filter id="dep-node-shadow" x="-10%" y="-10%" width="120%" height="120%">
                <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000000" flood-opacity="0.45" />
              </filter>
            </defs>

            <!-- Tier Column Backgrounds & Headers -->
            <%= for {tier_name, col_idx} <- Enum.with_index(@graph_tiers) do %>
              <% col_x = 30 + col_idx * 310 %>
              <g class="tier-column">
                <rect
                  x={col_x - 10}
                  y="12"
                  width="260"
                  height={@canvas_height - 24}
                  rx="18"
                  fill="#0b0f19"
                  stroke="#1e293b"
                  stroke-width="1.2"
                  stroke-dasharray="4 3"
                />
                <path d={"M #{col_x - 10} 38 L #{col_x + 130} 38 L #{col_x + 142} 24 L #{col_x + 142} 12 L #{col_x - 10} 12 Z"} fill="#1e293b" />
                <text
                  x={col_x + 8}
                  y="28"
                  fill="#94a3b8"
                  font-size="10.5"
                  font-weight="bold"
                  font-family="monospace"
                  letter-spacing="0.06em"
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

                <path
                  d={edge.path}
                  fill="none"
                  stroke={cond do
                    is_from_selected -> "#10b981"
                    is_to_selected -> "#f59e0b"
                    @selected_plugin_id != nil -> "#334155"
                    true -> "#64748b"
                  end}
                  stroke-width={if is_from_selected || is_to_selected, do: "2.8", else: "1.6"}
                  stroke-dasharray={if is_to_selected, do: "5 3", else: "none"}
                  marker-end={cond do
                    is_from_selected -> "url(#dep-arrow-emerald)"
                    is_to_selected -> "url(#dep-arrow-amber)"
                    true -> "url(#dep-arrow-default)"
                  end}
                  opacity={if @selected_plugin_id != nil and not (is_from_selected or is_to_selected), do: "0.15", else: "0.65"}
                  class="transition-all duration-150"
                />
              <% end %>
            </g>

            <!-- Graph Nodes -->
            <g class="nodes">
              <%= for node <- @pos_nodes do %>
                <% is_selected = @selected_plugin_id == node.id %>
                <% is_dependent = not is_nil(@selected_node) and node.id in (@selected_node.dependents || []) %>
                <% is_dependency = not is_nil(@selected_node) and node.id in (@selected_node.upstream_ids || []) %>
                <% is_dimmed = not is_nil(@selected_plugin_id) and not (is_selected or is_dependent or is_dependency) %>

                <g
                  class="cursor-pointer group"
                  phx-click="select_graph_plugin"
                  phx-value-id={node.id}
                  phx-target={@target}
                  opacity={if is_dimmed, do: "0.2", else: "1.0"}
                  transform={"translate(#{node.x}, #{node.y})"}
                >
                  <!-- Node Card Box -->
                  <rect
                    width={node.width}
                    height={node.height}
                    rx="16"
                    fill={cond do
                      is_selected -> "#4c1d95"
                      is_dependency -> "#451a03"
                      is_dependent -> "#064e3b"
                      true -> "#1e293b"
                    end}
                    stroke={cond do
                      is_selected -> "#c4b5fd"
                      is_dependency -> "#f59e0b"
                      is_dependent -> "#10b981"
                      true -> "#475569"
                    end}
                    stroke-width={if is_selected || is_dependency || is_dependent, do: "2.4", else: "1.2"}
                    filter="url(#dep-node-shadow)"
                  />

                  <!-- Icon -->
                  <text x="12" y="32" font-size="18"><%= node.icon %></text>

                  <!-- Node Title -->
                  <text
                    x="38"
                    y="27"
                    fill={if is_selected, do: "#ffffff", else: "#f8fafc"}
                    font-size="12"
                    font-weight="bold"
                    font-family="system-ui, -apple-system, sans-serif"
                  >
                    <%= node.name %>
                  </text>

                  <!-- Runtime Type Badge -->
                  <rect
                    x={node.width - 64}
                    y="12"
                    width="52"
                    height="18"
                    rx="6"
                    fill={if is_selected, do: "#6d28d9", else: "#0f172a"}
                  />
                  <text
                    x={node.width - 38}
                    y="24"
                    fill={if is_selected, do: "#ddd6fe", else: "#94a3b8"}
                    font-size="9"
                    font-weight="bold"
                    font-family="monospace"
                    text-anchor="middle"
                  >
                    <%= node.type %>
                  </text>

                  <!-- Provides Contracts Badges -->
                  <g transform="translate(12, 42)">
                    <%= for {svc, idx} <- Enum.with_index(Enum.take(node.provides, 2)) do %>
                      <rect
                        x={idx * 80}
                        y="0"
                        width="74"
                        height="18"
                        rx="5"
                        fill={if is_selected, do: "#7c3aed", else: "#334155"}
                      />
                      <text
                        x={idx * 80 + 37}
                        y="12"
                        fill={if is_selected, do: "#ffffff", else: "#c4b5fd"}
                        font-size="9.5"
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
                    y="74"
                    fill={if is_selected, do: "#ddd6fe", else: "#94a3b8"}
                    font-size="9.5"
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
        <div id="dep-graph-matrix-view" class="hidden overflow-y-auto py-4 space-y-4 flex-1 pr-1">
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5 gap-4">
            <%= for tier_name <- @graph_tiers do %>
              <% tier_nodes = Enum.filter(@graph_nodes, &(&1.tier == tier_name)) %>
              <div class="bg-slate-900 rounded-xl p-3.5 border border-slate-800 flex flex-col">
                <div class="flex items-center justify-between mb-3 px-1">
                  <span class="text-[11px] font-bold text-slate-400 uppercase tracking-wider font-mono"><%= tier_name %></span>
                  <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 font-mono"><%= length(tier_nodes) %></span>
                </div>

                <div class="space-y-2.5 flex-1">
                  <%= for node <- tier_nodes do %>
                    <% is_selected = @selected_plugin_id == node.id %>
                    <% is_dependent = not is_nil(@selected_node) and node.id in (@selected_node.dependents || []) %>
                    <% is_dependency = not is_nil(@selected_node) and node.id in (@selected_node.upstream_ids || []) %>
                    <div
                      phx-click="select_graph_plugin"
                      phx-value-id={node.id}
                      phx-target={@target}
                      class={"p-3 rounded-xl border cursor-pointer transition-all #{cond do
                        is_selected -> "bg-primary-900/90 text-white border-primary-400 shadow-md ring-2 ring-primary-400"
                        is_dependency -> "bg-amber-950/60 border-amber-400 text-amber-200 ring-1 ring-amber-400"
                        is_dependent -> "bg-emerald-950/60 border-emerald-400 text-emerald-200 ring-1 ring-emerald-400"
                        true -> "bg-slate-950 border-slate-800 hover:border-primary-400 text-slate-200"
                      end}"}
                    >
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-xs truncate max-w-[140px]" title={node.name}>
                          <%= node.icon %> <%= node.name %>
                        </span>
                        <span class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-slate-800 text-slate-300">
                          <%= if node.dependencies == [], do: "Root", else: "#{length(node.dependencies)} deps" %>
                        </span>
                      </div>

                      <div class="mt-2 flex flex-wrap gap-1">
                        <%= for s <- node.provides do %>
                          <span class="text-[10px] font-mono font-bold px-1.5 py-0.5 rounded bg-primary-500/20 text-primary-300 border border-primary-500/30">
                            :<%= s %>
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

        <!-- Node Inspector & Dependency Ledger -->
        <%= if @selected_node do %>
          <div class="mt-3 bg-slate-900 border border-primary-500/40 rounded-xl p-4 animate-in fade-in duration-150">
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center gap-2">
                <span class="text-xl"><%= @selected_node.icon %></span>
                <span class="text-base font-bold text-white font-mono"><%= @selected_node.name %></span>
                <span class="text-xs text-primary-400 font-mono">(<%= @selected_node.id %>)</span>
                <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-primary-400/20 text-primary-300 border border-primary-400/30">
                  <%= @selected_node.tier %>
                </span>
              </div>
              <button phx-click="select_graph_plugin" phx-value-id={@selected_node.id} phx-target={@target} class="text-xs font-semibold text-primary-400 hover:text-primary-300 cursor-pointer">
                Clear selection
              </button>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs">
              <div class="bg-slate-950 p-3.5 rounded-xl border border-slate-800">
                <span class="font-bold text-amber-400 block mb-1.5 flex items-center gap-1 font-mono text-[11px]">
                  <span>▲</span> <span>Direct Upstream Dependencies (What this needs):</span>
                </span>
                <%= if @selected_node.dependencies == [] do %>
                  <p class="text-slate-500 italic">None (Independent root service)</p>
                <% else %>
                  <ul class="space-y-1">
                    <%= for dep <- @selected_node.dependencies do %>
                      <li class="flex items-center justify-between text-slate-300 font-mono">
                        <span class="font-bold text-amber-400">:<%= dep.service %></span>
                        <span class="text-slate-500 text-[11px]">satisfied by: <span class="text-slate-200 font-semibold"><%= dep.provider || "unresolved" %></span></span>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>

              <div class="bg-slate-950 p-3.5 rounded-xl border border-slate-800">
                <span class="font-bold text-emerald-400 block mb-1.5 flex items-center gap-1 font-mono text-[11px]">
                  <span>▼</span> <span>Downstream Dependents (What depends on this):</span>
                </span>
                <%= if @selected_node.dependents == [] do %>
                  <p class="text-slate-500 italic">No other extensions currently depend on this</p>
                <% else %>
                  <ul class="space-y-1">
                    <%= for dependent_id <- @selected_node.dependents do %>
                      <li class="flex items-center gap-1.5 text-slate-300 font-mono">
                        <span class="text-emerald-400 font-bold">▲</span>
                        <span class="font-semibold text-slate-200"><%= dependent_id %></span>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center py-2 text-xs text-slate-500 font-mono">
            Click on any extension card above to spotlight upstream dependencies (amber) and downstream dependents (emerald).
          </div>
        <% end %>

        <!-- Modal Footer -->
        <div class="pt-3 border-t border-slate-800 flex items-center justify-between">
          <div class="flex items-center gap-4 text-[11px] text-slate-400">
            <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-primary-500 inline-block"></span> Selected</span>
            <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-amber-400 inline-block"></span> Upstream Dependency</span>
            <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-emerald-400 inline-block"></span> Downstream Dependent</span>
          </div>
          <button
            type="button"
            phx-click="close_dependency_graph"
            phx-target={@target}
            class="px-4 py-2 text-xs font-semibold text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-xl transition-colors cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end
end
