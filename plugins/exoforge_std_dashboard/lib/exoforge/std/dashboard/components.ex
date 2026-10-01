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
end
