defmodule Exoforge.Std.DashboardViews.InspectPopup do
  @moduledoc """
  The standard Studio inspector popup: a centered dialog with a header, an optional left tab
  rail, and the caller's content. Every inspector uses it so they look and behave the same —
  same backdrop, same close affordances, same tab placement.
  """
  use Phoenix.Component

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

        <div class={"relative bg-white rounded-xl #{@width} w-full shadow-2xl border border-gray-200 ring-1 ring-black/5 animate-fade-in overflow-hidden flex flex-col max-h-[calc(100vh-3.5rem)]"}>
          <button
            type="button"
            phx-click={@on_close}
            phx-target={@target}
            class="absolute top-4 right-5 z-10 w-8 h-8 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-400 hover:text-gray-700 flex items-center justify-center transition-colors text-xs font-bold"
          >
            ✕
          </button>

          <div class="flex items-center gap-3 px-6 py-4 border-b border-gray-100">
            <div class="w-10 h-10 rounded-xl bg-primary-50 text-primary-700 border border-primary-200 flex items-center justify-center text-xl shrink-0">
              <%= @icon %>
            </div>
            <div class="min-w-0">
              <h3 class="text-base font-bold text-gray-900 truncate"><%= @title %></h3>
              <%= if @subtitle do %>
                <p class="text-xs text-gray-500 truncate"><%= @subtitle %></p>
              <% end %>
            </div>
          </div>

          <div class="flex flex-col md:flex-row min-h-[360px] flex-1 min-h-0 divide-y md:divide-y-0 md:divide-x divide-gray-100 overflow-hidden">
            <%= if @tabs != [] do %>
              <div class="w-full md:w-48 p-2 bg-gray-50/70 space-y-0.5 shrink-0">
                <%= for tab <- @tabs do %>
                  <button
                    type="button"
                    phx-click={@on_select_tab}
                    phx-value-tab={to_string(tab[:id])}
                    phx-target={@target}
                    class={"w-full text-left px-2.5 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition-all #{if to_string(tab[:id]) == to_string(@active_tab), do: "bg-primary-600 text-white shadow-sm border border-primary-600", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-100"}"}
                  >
                    <span :if={tab[:icon]}><%= tab[:icon] %></span>
                    <span class="truncate"><%= tab[:title] || tab[:label] || tab[:id] %></span>
                  </button>
                <% end %>
              </div>
            <% end %>

            <div class="flex-1 p-5 min-w-0 space-y-4">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
