defmodule Exoforge.Std.Dashboard.Components do
  @moduledoc """
  Reusable Phoenix LiveView functional component library for Exoforge Game Producer & Designer Studio.
  Visually and functionally aligned with game_producer_studio_fixed.html.
  """
  use Phoenix.Component

  @doc """
  Renders a top metric card with value, delta change, and iconography.
  """
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :delta, :string, default: nil
  attr :delta_positive, :boolean, default: true
  attr :subtitle, :string, default: nil
  attr :icon_svg, :string, default: nil
  slot :inner_block

  def metric_card(assigns) do
    ~H"""
    <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-card hover:shadow-md transition-shadow">
      <div class="flex items-center justify-between mb-2">
        <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider"><%= @title %></span>
        <div class="w-8 h-8 rounded-xl bg-primary-50 text-primary-600 flex items-center justify-center">
          <%= if @icon_svg do %>
            <%= Phoenix.HTML.raw(@icon_svg) %>
          <% else %>
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
            </svg>
          <% end %>
        </div>
      </div>
      <div class="flex items-baseline gap-2">
        <span class="text-2xl font-black text-gray-900 tracking-tight"><%= @value %></span>
        <%= if @delta do %>
          <span class={"text-xs font-bold px-1.5 py-0.5 rounded-md #{if @delta_positive, do: "bg-emerald-50 text-emerald-700", else: "bg-red-50 text-red-700"}"}>
            <%= @delta %>
          </span>
        <% end %>
      </div>
      <%= if @subtitle do %>
        <p class="text-[11px] text-gray-400 mt-1 font-medium"><%= @subtitle %></p>
      <% end %>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders a status badge with matching color scheme.
  """
  attr :status, :string, default: "active"
  attr :label, :string, default: nil
  attr :size, :string, default: "sm"

  def badge(assigns) do
    label = assigns.label || assigns.status

    badge_classes =
      case String.downcase(to_string(assigns.status)) do
        s when s in ["active", "healthy", "ok", "operational", "live"] ->
          "bg-emerald-50 text-emerald-700 border-emerald-200"

        s when s in ["warning", "flagged", "pending"] ->
          "bg-amber-50 text-amber-700 border-amber-200"

        s when s in ["suspended", "banned", "error", "failed"] ->
          "bg-red-50 text-red-700 border-red-200"

        s when s in ["wasm", "c# wasm", "wasi"] ->
          "bg-violet-50 text-violet-700 border-violet-200"

        s when s in ["beam", "elixir", "standard"] ->
          "bg-primary-50 text-primary-800 border-primary-200"

        _ ->
          "bg-gray-50 text-gray-700 border-gray-200"
      end

    assigns = assign(assigns, :badge_classes, badge_classes)
    assigns = assign(assigns, :computed_label, label)

    ~H"""
    <span class={"inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full border shadow-xs #{@badge_classes}"}>
      <span class="w-1.5 h-1.5 rounded-full bg-current opacity-80"></span>
      <span><%= @computed_label %></span>
    </span>
    """
  end

  @doc """
  Renders a data table with search, columns, and row click actions.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :columns, :list, required: true
  attr :row_click_event, :string, default: nil
  attr :empty_text, :string, default: "No items match your criteria."

  def data_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-2xl border border-gray-200/80 bg-white shadow-card">
      <table class="w-full text-left text-xs border-collapse">
        <thead>
          <tr class="border-b border-gray-100 bg-gray-50/70 text-gray-500 font-bold uppercase tracking-wider text-[10px]">
            <%= for col <- @columns do %>
              <th class="py-3 px-4"><%= col.label %></th>
            <% end %>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <%= if Enum.empty?(@rows) do %>
            <tr>
              <td colspan={length(@columns)} class="py-8 text-center text-gray-400">
                <%= @empty_text %>
              </td>
            </tr>
          <% else %>
            <%= for row <- @rows do %>
              <tr
                class={"transition-colors hover:bg-gray-50/80 #{if @row_click_event, do: "cursor-pointer"}"}
                phx-click={@row_click_event}
                phx-value-id={row[:id] || row["id"] || row["player_id"]}
              >
                <%= for col <- @columns do %>
                  <td class="py-3 px-4">
                    <%= render_col_value(row, col) %>
                  </td>
                <% end %>
              </tr>
            <% end %>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_col_value(row, col) do
    key = col.key
    val = Map.get(row, key) || Map.get(row, to_string(key))

    case col[:type] do
      :badge ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
          #{val || "active"}
        </span>
        """)

      :code ->
        Phoenix.HTML.raw("""
        <code class="px-1.5 py-0.5 rounded bg-gray-100 font-mono text-[11px] text-gray-700">#{val}</code>
        """)

      _ ->
        to_string(val || "—")
    end
  end

  @doc """
  Renders the 7-tab side inspector slide-over drawer matching game_producer_studio_fixed.html.
  """
  attr :open, :boolean, default: false
  attr :title, :string, default: "Entity Inspector"
  attr :subtitle, :string, default: "Detailed account and telemetry properties"
  attr :tabs, :list, default: []
  attr :active_tab, :string, default: "overview"
  attr :on_close, :string, default: "close_drawer"
  attr :on_select_tab, :string, default: "select_drawer_tab"
  slot :inner_block

  def side_drawer(assigns) do
    ~H"""
    <%= if @open do %>
      <div class="fixed inset-0 z-50 overflow-hidden" role="dialog" aria-modal="true">
        <!-- Backdrop -->
        <div
          class="fixed inset-0 bg-gray-900/40 backdrop-blur-sm transition-opacity animate-fade-in"
          phx-click={@on_close}
        ></div>

        <div class="fixed inset-y-0 right-0 max-w-full flex pl-10">
          <div class="w-screen max-w-2xl bg-white shadow-2xl flex flex-col border-l border-gray-200 animate-slide-left">
            <!-- Drawer Header -->
            <div class="px-6 py-4 border-b border-gray-100 flex items-center justify-between bg-gray-50/50">
              <div>
                <h3 class="font-bold text-gray-900 text-base flex items-center gap-2">
                  <span><%= @title %></span>
                </h3>
                <p class="text-xs text-gray-500 mt-0.5"><%= @subtitle %></p>
              </div>
              <button
                type="button"
                phx-click={@on_close}
                class="w-8 h-8 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-500 hover:text-gray-700 flex items-center justify-center transition-colors text-sm font-bold"
              >
                ✕
              </button>
            </div>

            <!-- Drawer Tabs -->
            <%= if not Enum.empty?(@tabs) do %>
              <div class="flex items-center gap-1 px-6 py-2 border-b border-gray-100 bg-white overflow-x-auto custom-scrollbar">
                <%= for tab <- @tabs do %>
                  <button
                    type="button"
                    phx-click={@on_select_tab}
                    phx-value-tab={tab.id}
                    class={"px-3 py-1.5 rounded-lg text-xs font-bold transition-all whitespace-nowrap #{if to_string(tab.id) == to_string(@active_tab), do: "bg-primary-50 text-primary-800 border border-primary-200", else: "text-gray-500 hover:text-gray-900 hover:bg-gray-50"}"}
                  >
                    <%= tab.label %>
                  </button>
                <% end %>
              </div>
            <% end %>

            <!-- Drawer Content Body -->
            <div class="flex-1 overflow-y-auto p-6 space-y-6 custom-scrollbar">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Dynamic <Key, Value> attribute editor component.
  """
  attr :attributes, :list, default: []
  attr :on_add, :string, default: "add_attribute"
  attr :on_delete, :string, default: "delete_attribute"
  attr :on_save, :string, default: "save_attributes"

  def attribute_editor(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h4 class="text-xs font-bold text-gray-700 uppercase tracking-wider">Dynamic Attributes &lt;Key, Value&gt;</h4>
        <button
          type="button"
          phx-click={@on_add}
          class="px-2.5 py-1 text-xs font-bold bg-primary-50 hover:bg-primary-100 text-primary-700 rounded-lg border border-primary-200 transition-colors flex items-center gap-1"
        >
          <span>+ Add Field</span>
        </button>
      </div>

      <div class="space-y-2 border border-gray-100 rounded-xl p-3 bg-gray-50/50">
        <%= if Enum.empty?(@attributes) do %>
          <p class="text-xs text-gray-400 py-2 text-center">No custom attributes assigned to this entity.</p>
        <% else %>
          <%= for {attr, idx} <- Enum.with_index(@attributes) do %>
            <div class="flex items-center gap-2">
              <input
                type="text"
                value={attr[:key] || attr["key"]}
                name={"attr_key_#{idx}"}
                placeholder="attribute_name"
                class="flex-1 px-3 py-1.5 bg-white border border-gray-200 rounded-lg text-xs font-mono text-gray-800 focus:outline-none focus:border-primary-500"
              />
              <span class="text-gray-300 font-bold">:</span>
              <input
                type="text"
                value={attr[:value] || attr["value"]}
                name={"attr_val_#{idx}"}
                placeholder="value"
                class="flex-1 px-3 py-1.5 bg-white border border-gray-200 rounded-lg text-xs text-gray-800 focus:outline-none focus:border-primary-500"
              />
              <button
                type="button"
                phx-click={@on_delete}
                phx-value-index={idx}
                class="w-7 h-7 rounded-lg text-gray-400 hover:text-red-600 hover:bg-red-50 flex items-center justify-center transition-colors text-xs"
              >
                ✕
              </button>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal dialog.
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :on_close, :string, default: "close_modal"
  slot :inner_block
  slot :footer

  def modal(assigns) do
    ~H"""
    <%= if @open do %>
      <div id={@id} class="fixed inset-0 z-50 overflow-y-auto" role="dialog" aria-modal="true">
        <div class="min-h-screen px-4 text-center flex items-center justify-center">
          <!-- Backdrop -->
          <div
            class="fixed inset-0 bg-gray-900/40 backdrop-blur-sm transition-opacity"
            phx-click={@on_close}
          ></div>

          <!-- Dialog Box -->
          <div class="relative bg-white rounded-2xl max-w-lg w-full p-6 text-left shadow-2xl border border-gray-100 z-10 animate-fade-in">
            <div class="flex items-center justify-between pb-3 border-b border-gray-100">
              <div>
                <h3 class="font-bold text-gray-900 text-base"><%= @title %></h3>
                <%= if @subtitle do %>
                  <p class="text-xs text-gray-500 mt-0.5"><%= @subtitle %></p>
                <% end %>
              </div>
              <button
                type="button"
                phx-click={@on_close}
                class="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-500 flex items-center justify-center transition-colors text-xs font-bold"
              >
                ✕
              </button>
            </div>

            <div class="py-4 space-y-4">
              <%= render_slot(@inner_block) %>
            </div>

            <%= if @footer != [] do %>
              <div class="pt-3 border-t border-gray-100 flex items-center justify-end gap-2">
                <%= render_slot(@footer) %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Command Palette (Cmd+K) modal component.
  """
  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :on_close, :string, default: "close_cmd_palette"
  attr :on_search, :string, default: "search_cmd_palette"
  attr :on_select, :string, default: "select_cmd_item"

  def command_palette(assigns) do
    ~H"""
    <%= if @open do %>
      <div class="fixed inset-0 z-50 overflow-y-auto" role="dialog" aria-modal="true">
        <div class="min-h-screen px-4 text-center flex items-start justify-center pt-20">
          <div
            class="fixed inset-0 bg-gray-900/40 backdrop-blur-sm transition-opacity"
            phx-click={@on_close}
          ></div>

          <div class="relative bg-white rounded-2xl max-w-xl w-full text-left shadow-2xl border border-gray-200 z-10 overflow-hidden">
            <div class="p-3 border-b border-gray-100 flex items-center gap-2">
              <svg class="w-5 h-5 text-gray-400 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
              <form id="cmd_palette_form" phx-change={@on_search} class="flex-1">
                <input
                  type="text"
                  name="query"
                  value={@query}
                  placeholder="Search plugins, resources, players, actions... (Cmd+K)"
                  class="w-full px-2 py-2 text-sm text-gray-900 placeholder-gray-400 focus:outline-none"
                  autofocus
                />
              </form>
              <kbd class="px-2 py-1 bg-gray-100 text-gray-500 rounded text-[10px] font-mono border">ESC</kbd>
            </div>

            <div class="max-h-80 overflow-y-auto p-2 divide-y divide-gray-50 custom-scrollbar">
              <%= if Enum.empty?(@results) do %>
                <div class="py-8 text-center text-xs text-gray-400">
                  Type to search across registered extensions, resources, and live actions.
                </div>
              <% else %>
                <%= for item <- @results do %>
                  <button
                    type="button"
                    phx-click={@on_select}
                    phx-value-id={item.id}
                    phx-value-type={item.type}
                    class="w-full text-left p-3 rounded-xl hover:bg-primary-50/70 transition-colors flex items-center justify-between group"
                  >
                    <div>
                      <span class="text-xs font-bold text-gray-800 group-hover:text-primary-800"><%= item.title %></span>
                      <p class="text-[11px] text-gray-400"><%= item.subtitle %></p>
                    </div>
                    <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-gray-100 group-hover:bg-primary-100 text-gray-600 group-hover:text-primary-700">
                      <%= item.type %>
                    </span>
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Action Execution Modal & Form Generator component.
  Renders interactive service/action selection, dynamically generated parameter inputs,
  caller scopes configuration, and formatted execution feedback.
  """
  attr :open, :boolean, default: false
  attr :catalog, :list, default: []
  attr :selected_service, :string, default: nil
  attr :selected_action, :string, default: nil
  attr :action_params, :map, default: %{}
  attr :caller_scopes, :string, default: "admin, player"
  attr :result, :any, default: nil
  attr :latency_ms, :any, default: nil
  attr :on_close, :string, default: "close_action_modal"
  attr :on_select_service, :string, default: "select_action_service"
  attr :on_select_action, :string, default: "select_action_name"
  attr :on_change_form, :string, default: "change_action_form"
  attr :on_dispatch, :string, default: "dispatch_action"

  def action_runner_modal(assigns) do
    current_svc =
      Enum.find(assigns.catalog, &(&1.name == assigns.selected_service)) ||
        List.first(assigns.catalog)

    current_act =
      if current_svc do
        Enum.find(current_svc.actions, &(&1.name == assigns.selected_action)) ||
          List.first(current_svc.actions)
      end

    assigns =
      assigns
      |> assign(:current_svc, current_svc)
      |> assign(:current_act, current_act)

    ~H"""
    <%= if @open do %>
      <div id="action_runner_modal" class="fixed inset-0 z-50 overflow-y-auto" role="dialog" aria-modal="true">
        <div class="min-h-screen px-4 text-center flex items-center justify-center py-8">
          <!-- Backdrop -->
          <div
            class="fixed inset-0 bg-gray-900/40 backdrop-blur-sm transition-opacity animate-fade-in"
            phx-click={@on_close}
          ></div>

          <!-- Dialog Box -->
          <div class="relative bg-white rounded-2xl max-w-xl w-full p-6 text-left shadow-2xl border border-gray-100 z-10 animate-fade-in space-y-4">
            <!-- Modal Header -->
            <div class="flex items-center justify-between pb-3 border-b border-gray-100">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-xl bg-primary-100 text-primary-700 flex items-center justify-center font-bold text-sm">
                  ⚡
                </div>
                <div>
                  <h3 class="font-bold text-gray-900 text-base">Action Dispatcher &amp; Form Generator</h3>
                  <p class="text-xs text-gray-500">Execute backend service actions across BEAM &amp; WASM plugins</p>
                </div>
              </div>
              <button
                type="button"
                phx-click={@on_close}
                class="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-500 flex items-center justify-center transition-colors text-xs font-bold"
              >
                ✕
              </button>
            </div>

            <!-- Service & Action Selection Pickers -->
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label class="block text-[11px] font-bold text-gray-600 uppercase mb-1">Target Service</label>
                <form id="action_service_picker_form" phx-change={@on_select_service}>
                  <select
                    name="service"
                    class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-xl text-xs font-semibold text-gray-800 focus:outline-none focus:border-primary-500"
                  >
                    <%= for svc <- @catalog do %>
                      <option value={svc.name} selected={@current_svc && svc.name == @current_svc.name}>
                        <%= svc.name %> (<%= length(svc.actions) %> actions)
                      </option>
                    <% end %>
                  </select>
                </form>
              </div>

              <div>
                <label class="block text-[11px] font-bold text-gray-600 uppercase mb-1">Target Action</label>
                <form id="action_name_picker_form" phx-change={@on_select_action}>
                  <select
                    name="action"
                    class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-xl text-xs font-semibold text-gray-800 focus:outline-none focus:border-primary-500"
                  >
                    <%= if @current_svc do %>
                      <%= for act <- @current_svc.actions do %>
                        <option value={act.name} selected={@current_act && act.name == @current_act.name}>
                          <%= act.name %> [<%= act.mode %>]
                        </option>
                      <% end %>
                    <% end %>
                  </select>
                </form>
              </div>
            </div>

            <!-- Action Description & Meta Banner -->
            <%= if @current_act do %>
              <div class="p-3 bg-gray-50/80 rounded-xl border border-gray-100 text-xs space-y-1">
                <div class="flex items-center justify-between">
                  <span class="font-bold text-gray-800 font-mono text-xs">
                    <%= @current_svc.name %>.<%= @current_act.name %>
                  </span>
                  <span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-primary-100 text-primary-800 uppercase">
                    <%= @current_act.mode %>
                  </span>
                </div>
                <p class="text-[11px] text-gray-500"><%= @current_act.doc %></p>
              </div>
            <% end %>

            <!-- Dynamic Form Generator -->
            <form id="action_execution_form" phx-change={@on_change_form} phx-submit={@on_dispatch} class="space-y-4">
              <%= if @current_act && @current_act.params != [] do %>
                <div class="space-y-2.5">
                  <span class="block text-[11px] font-bold text-gray-600 uppercase tracking-wider">
                    Parameters (<%= length(@current_act.params) %>)
                  </span>
                  <div class="space-y-2">
                    <%= for param <- @current_act.params do %>
                      <div>
                        <label class="flex items-center justify-between text-xs font-semibold text-gray-700 mb-1">
                          <span class="font-mono text-gray-900"><%= param.name %></span>
                          <span class="text-[10px] text-gray-400 font-mono bg-gray-100 px-1.5 py-0.2 rounded">
                            <%= param.type %>
                          </span>
                        </label>

                        <%= case param.type do %>
                          <% t when t in [:integer, :float] -> %>
                            <input
                              type="number"
                              name={"param_#{param.name}"}
                              value={Map.get(@action_params, param.name, if(t == :integer, do: "1", else: "1.0"))}
                              step={if t == :float, do: "0.1", else: "1"}
                              class="w-full px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-800 focus:outline-none focus:border-primary-500"
                            />
                          <% :boolean -> %>
                            <select
                              name={"param_#{param.name}"}
                              class="w-full px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-800 focus:outline-none focus:border-primary-500"
                            >
                              <option value="true" selected={Map.get(@action_params, param.name) in ["true", true]}>true</option>
                              <option value="false" selected={Map.get(@action_params, param.name) in ["false", false]}>false</option>
                            </select>
                          <% :map -> %>
                            <textarea
                              name={"param_#{param.name}"}
                              rows="2"
                              class="w-full px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-800 focus:outline-none focus:border-primary-500"
                              placeholder="{}"
                            ><%= Map.get(@action_params, param.name, "{}") %></textarea>
                          <% _ -> %>
                            <input
                              type="text"
                              name={"param_#{param.name}"}
                              value={Map.get(@action_params, param.name, "")}
                              placeholder={"Enter #{param.name}..."}
                              class="w-full px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-800 focus:outline-none focus:border-primary-500"
                            />
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div class="p-3 bg-gray-50/70 border border-dashed border-gray-200 rounded-xl text-center text-xs text-gray-400">
                  This action takes no parameters.
                </div>
              <% end %>

              <div>
                <label class="block text-[11px] font-bold text-gray-600 uppercase mb-1">
                  Caller Scopes (comma-separated RBAC scopes)
                </label>
                <input
                  type="text"
                  name="caller_scopes"
                  value={@caller_scopes}
                  placeholder="admin, player"
                  class="w-full px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-800 focus:outline-none focus:border-primary-500"
                />
              </div>

              <div class="pt-2 border-t border-gray-100 flex items-center justify-end gap-2">
                <button
                  type="button"
                  phx-click={@on_close}
                  class="px-3 py-1.5 rounded-xl text-xs font-semibold text-gray-500 hover:bg-gray-100 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 rounded-xl text-xs font-bold bg-primary-600 hover:bg-primary-700 text-white shadow-sm transition-all flex items-center gap-1.5 active:scale-95"
                >
                  <span>Dispatch Action</span>
                  <span>⚡</span>
                </button>
              </div>
            </form>

            <!-- Execution Result Panel -->
            <%= if @result != nil do %>
              <div class="mt-4 pt-4 border-t border-gray-100 space-y-2 animate-fade-in">
                <div class="flex items-center justify-between">
                  <span class="text-xs font-bold text-gray-700 uppercase">Execution Output</span>
                  <div class="flex items-center gap-2">
                    <%= if match?({:ok, _}, @result) or @result == :ok do %>
                      <span class="px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 text-[10px] font-bold border border-emerald-200">
                        SUCCESS (200)
                      </span>
                    <% else %>
                      <span class="px-2 py-0.5 rounded-full bg-red-50 text-red-700 text-[10px] font-bold border border-red-200">
                        ERROR
                      </span>
                    <% end %>
                    <%= if @latency_ms do %>
                      <span class="px-2 py-0.5 rounded-full bg-gray-100 text-gray-600 text-[10px] font-mono font-bold">
                        ⚡ <%= @latency_ms %> ms
                      </span>
                    <% end %>
                  </div>
                </div>

                <pre class="p-3 bg-gray-900 text-emerald-300 rounded-xl font-mono text-xs overflow-x-auto max-h-48 custom-scrollbar border border-gray-800"><%= format_action_runner_result(@result) %></pre>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Live Cluster Event Stream Dock component.
  Renders a real-time console dock listening to :pg / EventDispatcher with
  pause/resume, topic search, payload viewer, and test simulator.
  """
  attr :open, :boolean, default: false
  attr :events, :list, default: []
  attr :paused, :boolean, default: false
  attr :filter_topic, :string, default: ""
  attr :on_toggle, :string, default: "toggle_event_dock"
  attr :on_pause, :string, default: "toggle_event_pause"
  attr :on_clear, :string, default: "clear_events"
  attr :on_filter, :string, default: "filter_event_dock"
  attr :on_simulate, :string, default: "simulate_test_event"

  def event_stream_dock(assigns) do
    ~H"""
    <%= if @open do %>
      <div class="fixed bottom-0 inset-x-0 z-40 bg-gray-950/95 text-gray-100 border-t border-gray-800 shadow-2xl backdrop-blur flex flex-col h-80 sm:h-96 transition-all duration-300 animate-fade-in">
        <!-- Dock Top Bar -->
        <div class="px-4 py-2.5 bg-gray-900 border-b border-gray-800 flex flex-wrap items-center justify-between gap-3 text-xs">
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-2">
              <span class={"w-2.5 h-2.5 rounded-full #{if @paused, do: "bg-amber-400", else: "bg-emerald-400 animate-pulse"}"}></span>
              <span class="font-bold text-gray-200 tracking-tight">Cluster Event Stream (:pg / EventDispatcher)</span>
            </div>
            <span class="px-2 py-0.5 rounded-full bg-gray-800 font-mono font-bold text-[10px] text-gray-300 border border-gray-700">
              <%= length(@events) %> captured
            </span>
            <%= if @paused do %>
              <span class="px-2 py-0.5 rounded-full bg-amber-500/20 text-amber-300 text-[10px] font-bold border border-amber-500/30">
                STREAM PAUSED
              </span>
            <% end %>
          </div>

          <!-- Filter input & Controls -->
          <div class="flex items-center gap-2">
            <form id="event_dock_filter_form" phx-change={@on_filter} class="m-0">
              <input
                type="text"
                name="topic"
                value={@filter_topic}
                placeholder="Filter event / payload..."
                class="px-2.5 py-1 bg-gray-900 border border-gray-700 rounded-lg text-xs text-gray-200 placeholder-gray-500 focus:outline-none focus:border-primary-500 w-36 sm:w-48 font-mono"
              />
            </form>

            <button
              type="button"
              phx-click={@on_pause}
              class={"px-2.5 py-1 rounded-lg font-bold text-xs flex items-center gap-1 transition-colors #{if @paused, do: "bg-emerald-600 hover:bg-emerald-500 text-white", else: "bg-gray-800 hover:bg-gray-700 text-gray-300"}"}
            >
              <%= if @paused, do: "▶ Resume", else: "⏸ Pause" %>
            </button>

            <button
              type="button"
              phx-click={@on_simulate}
              class="px-2.5 py-1 bg-primary-600 hover:bg-primary-500 text-white rounded-lg font-bold text-xs transition-colors flex items-center gap-1 shadow-sm"
              title="Broadcast simulated event to cluster"
            >
              <span>⚡ Simulate Event</span>
            </button>

            <button
              type="button"
              phx-click={@on_clear}
              class="px-2.5 py-1 bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-gray-200 rounded-lg font-bold text-xs transition-colors"
            >
              Clear
            </button>

            <button
              type="button"
              phx-click={@on_toggle}
              class="w-7 h-7 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-white flex items-center justify-center transition-colors text-xs font-bold"
              title="Close Event Console"
            >
              ✕
            </button>
          </div>
        </div>

        <!-- Dock Event Log Stream Window -->
        <div class="flex-1 overflow-y-auto p-4 space-y-2 font-mono text-xs custom-scrollbar">
          <%= if Enum.empty?(@events) do %>
            <div class="h-full flex flex-col items-center justify-center text-gray-500 text-center py-12 space-y-2">
              <svg class="w-8 h-8 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              <p class="text-xs font-sans text-gray-400">Waiting for live cluster events on <code class="text-primary-400">EventDispatcher</code> bus...</p>
              <p class="text-[11px] font-sans text-gray-500">Dispatch an action or click "Simulate Event" above to verify.</p>
            </div>
          <% else %>
            <%= for ev <- @events do %>
              <div class="p-3 bg-gray-900/90 rounded-xl border border-gray-800/80 flex flex-col gap-1.5 hover:border-gray-700 transition-colors">
                <div class="flex items-center justify-between text-[11px]">
                  <div class="flex items-center gap-2">
                    <span class="px-2 py-0.5 rounded bg-primary-950 text-primary-300 font-bold border border-primary-800/60 font-mono">
                      <%= ev.event %>
                    </span>
                    <span class="text-gray-500 text-[10px]"><%= ev.time %></span>
                    <%= if Map.get(ev, :context) do %>
                      <span class="text-gray-600 text-[10px] hidden sm:inline">ctx: <%= inspect(ev.context) %></span>
                    <% end %>
                  </div>
                  <span class="text-[10px] text-gray-500 font-mono">#<%= ev.id %></span>
                </div>
                <pre class="text-[11px] text-emerald-400 overflow-x-auto p-2.5 bg-black/60 rounded-lg border border-gray-800/60 font-mono"><%= Jason.encode!(ev.payload, pretty: true) %></pre>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp format_action_runner_result({:ok, val}) do
    case Jason.encode(sanitize_data(val), pretty: true) do
      {:ok, json} -> json
      _ -> inspect(val, pretty: true)
    end
  end

  defp format_action_runner_result(:ok), do: Jason.encode!(%{status: "ok"}, pretty: true)

  defp format_action_runner_result({:error, reason}) do
    case Jason.encode(sanitize_data(reason), pretty: true) do
      {:ok, json} -> json
      _ -> inspect(reason, pretty: true)
    end
  end

  defp format_action_runner_result(other) do
    inspect(other, pretty: true)
  end

  defp sanitize_data(data) do
    cond do
      is_map(data) -> Map.new(data, fn {k, v} -> {to_string(k), sanitize_data(v)} end)
      is_list(data) -> Enum.map(data, &sanitize_data/1)
      is_tuple(data) -> Tuple.to_list(data) |> Enum.map(&sanitize_data/1)
      is_atom(data) -> to_string(data)
      true -> data
    end
  end
end

