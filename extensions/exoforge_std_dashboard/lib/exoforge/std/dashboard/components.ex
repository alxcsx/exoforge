defmodule Exoforge.Std.Dashboard.Components do
  @moduledoc """
  Reusable Phoenix LiveView functional component library for Exoforge Game Producer & Designer Studio.
  Visually and functionally aligned with the Exoforge Studio design system.
  """
  use Phoenix.Component

  @doc """
  Renders a compact, icon-forward status card with title, value, and optional badge.
  """
  attr(:title, :string, required: true)
  attr(:value, :string, required: true)
  attr(:delta, :string, default: nil)
  attr(:delta_positive, :boolean, default: true)
  attr(:subtitle, :string, default: nil)
  attr(:icon, :string, default: nil)
  attr(:icon_svg, :string, default: nil)
  slot(:inner_block)

  def metric_card(assigns) do
    ~H"""
    <div
      class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-card hover:border-purple-300 transition-all flex items-center gap-3.5"
      title={@subtitle}
    >
      <div class="w-11 h-11 rounded-xl bg-primary-50 text-primary-600 flex items-center justify-center shrink-0 text-lg border border-primary-200">
        <%= cond do %>
          <% @icon_svg -> %>
            <%= Phoenix.HTML.raw(Exoforge.Std.Dashboard.IconSanitizer.sanitize(@icon_svg)) %>
          <% @icon -> %>
            <span><%= @icon %></span>
          <% true -> %>
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
            </svg>
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <div class="flex items-center justify-between gap-2">
          <span class="text-[11px] font-bold text-gray-500 uppercase tracking-wider truncate"><%= @title %></span>
          <%= if @delta do %>
            <span class={"text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0 border #{if @delta_positive, do: "bg-emerald-50 text-emerald-700 border-emerald-200", else: "bg-red-50 text-red-700 border-red-200"}"}>
              <%= @delta %>
            </span>
          <% end %>
        </div>
        <div class="text-lg font-extrabold text-gray-900 tracking-tight truncate mt-0.5"><%= @value %></div>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a progressive-disclosure collapsible fold for technical metadata and diagnostics.
  """
  attr(:title, :string, default: "Technical Details")
  attr(:icon, :string, default: "⚙️")
  attr(:badge, :string, default: nil)
  attr(:open, :boolean, default: false)
  slot(:inner_block, required: true)

  def tech_fold(assigns) do
    ~H"""
    <details class="exo-fold" open={@open}>
      <summary>
        <span class="flex items-center gap-1.5">
          <span><%= @icon %></span>
          <span><%= @title %></span>
          <%= if @badge do %>
            <span class="px-1.5 py-0.2 rounded-full bg-gray-100 text-gray-600 font-mono text-[10px]"><%= @badge %></span>
          <% end %>
        </span>
        <span class="exo-fold-chevron">▶</span>
      </summary>
      <div class="exo-fold-body">
        <%= render_slot(@inner_block) %>
      </div>
    </details>
    """
  end

  @doc """
  Renders astatus badge with matching color scheme.
  """
  attr(:status, :string, default: "active")
  attr(:label, :string, default: nil)
  attr(:size, :string, default: "sm")

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

        s when s in ["native", "c#", "dotnet"] ->
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
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:columns, :list, required: true)
  attr(:row_click_event, :string, default: nil)
  attr(:empty_text, :string, default: "No items match your criteria.")

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
        safe_val =
          Phoenix.HTML.html_escape(to_string(val || "active")) |> Phoenix.HTML.safe_to_string()

        Phoenix.HTML.raw("""
        <span class="inline-flex items-center text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
          #{safe_val}
        </span>
        """)

      :code ->
        safe_val = Phoenix.HTML.html_escape(to_string(val || "")) |> Phoenix.HTML.safe_to_string()

        Phoenix.HTML.raw("""
        <code class="px-1.5 py-0.5 rounded bg-gray-100 font-mono text-[11px] text-gray-700">#{safe_val}</code>
        """)

      _ ->
        to_string(val || "—")
    end
  end

  @doc """
  SVG polyline for a per-minute series.

  The charts share one geometry: x spans `x0..x1`, y is `base` at zero and `base - height` at
  `max_val`. Used by the small throughput cards and the expanded telemetry chart.
  """
  def series_points(counts, x0, x1, base, height, max_val) do
    last = max(length(counts) - 1, 1)

    counts
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {count, index} ->
      x = x0 + round(index * (x1 - x0) / last)
      y = base - round(count / max(max_val, 1) * height)
      "#{x},#{max(base - height, y)}"
    end)
  end

  @doc """
  Renders the side inspector slide-over drawer with tabs from `Exoforge.DrawerRegistry`.
  """
  attr(:open, :boolean, default: false)
  attr(:title, :string, default: "Entity Inspector")
  attr(:subtitle, :string, default: "Detailed account and telemetry properties")
  attr(:tabs, :list, default: [])
  attr(:active_tab, :string, default: "overview")
  attr(:on_close, :string, default: "close_drawer")
  attr(:on_select_tab, :string, default: "select_drawer_tab")
  slot(:inner_block)

  def side_drawer(assigns) do
    ~H"""
    <%= if @open do %>
      <div class="fixed inset-0 z-[70] overflow-hidden" role="dialog" aria-modal="true">
        <!-- Backdrop -->
        <div
          class="fixed inset-0 bg-slate-950/60 backdrop-blur-sm transition-opacity animate-fade-in"
          phx-click={@on_close}
        ></div>

        <div class="fixed inset-y-0 right-0 max-w-full flex pl-10">
          <div class="w-screen max-w-2xl bg-white shadow-2xl flex flex-col border-l border-gray-200 ring-1 ring-black/5 animate-slide-left">
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
                class="w-8 h-8 shrink-0 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-500 hover:text-gray-800 flex items-center justify-center transition-colors text-xs font-bold"
                title="Close (Esc)"
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
  attr(:attributes, :list, default: [])
  attr(:on_add, :string, default: "add_attribute")
  attr(:on_delete, :string, default: "delete_attribute")
  attr(:on_save, :string, default: "save_attributes")

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
  A line icon from the Studio's small icon set. Buttons use these instead of emoji: an emoji is a
  font glyph that changes shape per platform and reads as decoration, an icon is a control.
  """
  attr(:name, :atom, required: true)
  attr(:class, :string, default: "w-4 h-4")
  attr(:stroke_width, :string, default: "1.8")

  @icons %{
    timeline:
      "M2.04 12.32a1.01 1.01 0 010-.64C3.42 7.51 7.36 4.5 12 4.5s8.57 3.01 9.96 7.18c.07.21.07.43 0 .64C20.58 16.49 16.64 19.5 12 19.5s-8.57-3.01-9.96-7.18z M15 12a3 3 0 11-6 0 3 3 0 016 0z",
    replay: "M3 3v6h6 M3.51 15a9 9 0 102.13-9.36L3 9",
    capture: "M12 3v3 M12 18v3 M3 12h3 M18 12h3 M12 8a4 4 0 100 8 4 4 0 000-8z",
    bolt: "M13 2L3 14h6l-2 8 10-12h-6l2-8z",
    pin: "M12 17v5 M9 3h6l-1 7 4 4H6l4-4-1-7z",
    search: "M21 21l-6-6 M17 11a6 6 0 11-12 0 6 6 0 0112 0z",
    download: "M12 3v12 M7 11l5 5 5-5 M4 20h16",
    close: "M6 6l12 12 M18 6L6 18",
    check: "M4 12l5 5L20 6",
    alert: "M12 9v4 M12 17h.01 M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z",
    moon:
      "M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z",
    sun:
      "M12 4V2 M12 22v-2 M4 12H2 M22 12h-2 M5.64 5.64L4.22 4.22 M19.78 19.78l-1.42-1.42 M5.64 18.36l-1.42 1.42 M19.78 4.22l-1.42 1.42 M12 7a5 5 0 100 10 5 5 0 000-10z",
    gear:
      "M12 15a3 3 0 100-6 3 3 0 000 6z M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 11-4 0v-.09A1.65 1.65 0 008 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 003.6 15a1.65 1.65 0 00-1.51-1H2a2 2 0 110-4h.09A1.65 1.65 0 003.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6 1.65 1.65 0 0010 3.09V3a2 2 0 114 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0020.4 9c.14.36.48.62.87.7H21a2 2 0 110 4h-.09a1.65 1.65 0 00-1.51 1z",
    trash: "M3 6h18 M8 6V4h8v2 M6 6l1 14h10l1-14 M10 11v6 M14 11v6",
    save: "M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z M17 21v-8H7v8 M7 3v5h8",
    folder: "M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z",
    graph: "M3 3v18h18 M7 14l4-4 3 3 5-6",
    console:
      "M4 17l6-6-6-6 M12 19h8"
  }

  def icon(assigns) do
    assigns = assign(assigns, :path, Map.get(@icons, assigns.name, @icons.close))

    ~H"""
    <svg
      class={@class}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width={@stroke_width}
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d={@path} />
    </svg>
    """
  end

  @doc """
  Renders a modal dialog: one shell for every dialog, so the header, the close button and the
  scroll behaviour are the same everywhere. Escape closes it (the global key handler reads
  `data-exo-modal` / `data-close-event`), and so does the backdrop.
  """
  attr(:id, :string, required: true)
  attr(:open, :boolean, default: false)
  attr(:icon, :string, default: nil)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:on_close, :string, default: "close_modal")
  attr(:max_width, :string, default: "max-w-lg")
  slot(:inner_block)
  slot(:footer)

  def modal(assigns) do
    ~H"""
    <%= if @open do %>
      <div
        id={@id}
        data-exo-modal
        data-close-event={@on_close}
        class="fixed inset-0 z-[70] overflow-y-auto"
        role="dialog"
        aria-modal="true"
      >
        <div class="min-h-full p-4 sm:p-6 flex items-center justify-center">
          <div
            class="fixed inset-0 bg-slate-950/60 backdrop-blur-sm"
            phx-click={@on_close}
          ></div>

          <div class={"relative bg-white rounded-2xl #{@max_width} w-full text-left shadow-2xl border border-gray-200 ring-1 ring-black/5 z-10 animate-fade-in flex flex-col max-h-[calc(100vh-2.5rem)] sm:max-h-[calc(100vh-4rem)] overflow-hidden"}>
            <div class="flex items-start justify-between gap-3 px-5 sm:px-6 py-4 border-b border-gray-100 shrink-0">
              <div class="flex items-center gap-3 min-w-0">
                <%= if @icon do %>
                  <div class="w-9 h-9 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center text-base shrink-0 ring-1 ring-primary-200/60">
                    <%= @icon %>
                  </div>
                <% end %>
                <div class="min-w-0">
                  <h3 class="font-bold text-gray-900 text-base leading-tight truncate"><%= @title %></h3>
                  <%= if @subtitle do %>
                    <p class="text-[11px] text-gray-500 mt-0.5 truncate"><%= @subtitle %></p>
                  <% end %>
                </div>
              </div>
              <button
                type="button"
                phx-click={@on_close}
                class="w-8 h-8 shrink-0 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-500 hover:text-gray-800 flex items-center justify-center transition-colors text-xs font-bold"
                title="Close (Esc)"
              >
                ✕
              </button>
            </div>

            <div class="px-5 sm:px-6 py-4 overflow-y-auto min-h-0 flex-1 custom-scrollbar">
              <%= render_slot(@inner_block) %>
            </div>

            <%= if @footer != [] do %>
              <div class="px-5 sm:px-6 py-3 border-t border-gray-100 bg-gray-50/60 flex items-center justify-end gap-2 shrink-0">
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
  The standard inspector popup: a centered dialog with a header, an optional left tab rail, and
  the caller's content. Mirrors `Exoforge.Std.DashboardViews.InspectPopup` — the two packages do
  not share a compile dependency, so the markup is kept in step by hand.
  """
  attr(:open, :boolean, default: false)
  attr(:icon, :string, default: "🔍")
  attr(:title, :string, default: "Inspector")
  attr(:subtitle, :string, default: nil)
  attr(:tabs, :list, default: [])
  attr(:active_tab, :string, default: "overview")
  attr(:on_close, :string, default: "close_focus")
  attr(:on_select_tab, :string, default: nil)
  attr(:target, :any, default: nil)
  attr(:width, :string, default: "max-w-3xl")
  slot(:inner_block, required: true)

  def inspect_popup(assigns) do
    ~H"""
    <%= if @open do %>
      <div
        class="fixed inset-0 z-[70] overflow-y-auto bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 sm:p-6"
        role="dialog"
        aria-modal="true"
      >
        <div class="fixed inset-0" phx-click={@on_close} phx-target={@target}></div>

        <div class={"relative bg-white rounded-2xl #{@width} w-full shadow-2xl border border-gray-200 ring-1 ring-black/5 animate-fade-in overflow-hidden flex flex-col max-h-[calc(100vh-3.5rem)]"}>
          <button
            type="button"
            phx-click={@on_close}
            phx-target={@target}
            class="absolute top-4 right-5 z-10 w-8 h-8 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-400 hover:text-gray-700 flex items-center justify-center transition-colors text-xs font-bold"
            title="Close"
          >
            ✕
          </button>

          <div class="flex items-center gap-3 px-6 py-4 border-b border-gray-100 shrink-0">
            <div class="w-10 h-10 rounded-xl bg-primary-50 text-primary-700 ring-1 ring-primary-200/60 flex items-center justify-center text-xl shrink-0">
              <%= @icon %>
            </div>
            <div class="min-w-0 pr-8">
              <h3 class="text-base font-bold text-gray-900 truncate"><%= @title %></h3>
              <%= if @subtitle do %>
                <p class="text-xs text-gray-500 truncate"><%= @subtitle %></p>
              <% end %>
            </div>
          </div>

          <div class="flex flex-col md:flex-row min-h-[360px] flex-1 min-h-0 divide-y md:divide-y-0 md:divide-x divide-gray-100 overflow-hidden">
            <%= if @tabs != [] do %>
              <div class="w-full md:w-48 p-2 bg-gray-50/70 space-y-0.5 shrink-0 overflow-y-auto custom-scrollbar">
                <%= for tab <- @tabs do %>
                  <button
                    type="button"
                    phx-click={@on_select_tab}
                    phx-value-tab={to_string(tab[:id])}
                    phx-target={@target}
                    class={"w-full text-left px-2.5 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition-all #{if to_string(tab[:id]) == to_string(@active_tab), do: "bg-primary-600 text-white shadow-sm border border-primary-600", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                  >
                    <span :if={tab[:icon]}><%= tab[:icon] %></span>
                    <span class="truncate"><%= tab[:title] || tab[:label] || tab[:id] %></span>
                  </button>
                <% end %>
              </div>
            <% end %>

            <div class="flex-1 p-5 min-w-0 space-y-4 overflow-y-auto custom-scrollbar">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end

# The icon arrives in extension metadata, not from us, so it does not get to execute. Script
# blocks are dropped whole; handler attributes, URL attributes and dangerous elements are dropped
# with them (M33 Fix 35).
# ponytail: blocklist, not a parser — icons come from plugins the operator deployed; a full
# SVG sanitizer is warranted only if third parties author Studio metadata.
defmodule Exoforge.Std.Dashboard.IconSanitizer do
  @unsafe [
    ~r/<script[\s\S]*?<\/script>/i,
    ~r/<\/?(?:script|iframe|object|embed|link|style|foreignObject)\b[^>]*>/i,
    ~r/\son\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/i,
    ~r/(?:javascript|vbscript)\s*:/i
  ]

  @spec sanitize(term()) :: String.t()
  def sanitize(svg) when is_binary(svg),
    do: Enum.reduce(@unsafe, svg, fn pattern, acc -> String.replace(acc, pattern, "") end)

  def sanitize(_), do: ""
end

defimpl Phoenix.HTML.Safe, for: Version do
  def to_iodata(%Version{} = version), do: Version.to_string(version)
end
