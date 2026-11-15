defmodule Exoforge.Std.DashboardViews.InspectPopup do
  @moduledoc """
  The standard Studio inspector popup: a centered dialog with a header, an optional left tab
  rail, and the caller's content. Every inspector uses it so they look and behave the same —
  same backdrop, same close affordances, same tab placement.
  """
  use Phoenix.Component
  import Exoforge.Std.DashboardViews.Icons, only: [studio_icon: 1]

  attr(:open, :boolean, default: false)
  attr(:icon, :string, default: "search")
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
        data-exo-modal
        data-close-event={@on_close}
        class="fixed inset-0 z-[70] overflow-y-auto bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 sm:p-6"
        role="dialog"
        aria-modal="true"
      >
        <div class="fixed inset-0" phx-click={@on_close} phx-target={@target}></div>

        <div class={"relative bg-white rounded-xl #{@width} w-full shadow-2xl border border-gray-200 ring-1 ring-black/5 animate-fade-in overflow-hidden flex flex-col max-h-[calc(100vh-3.5rem)]"}>
          <div class="exo-modal-header">
            <div class="flex items-center gap-2.5 min-w-0">
              <span class="text-primary-600 shrink-0"><.studio_icon icon={@icon} class="w-4 h-4" /></span>
              <div class="min-w-0">
                <h3 class="exo-modal-title truncate"><%= @title %></h3>
                <%= if @subtitle do %>
                  <p class="exo-modal-subtitle truncate"><%= @subtitle %></p>
                <% end %>
              </div>
            </div>
            <button
              type="button"
              phx-click={@on_close}
              phx-target={@target}
              class="exo-btn exo-btn-icon shrink-0"
              title="Close (Esc)"
            >
              <.studio_icon icon="close" class="w-4 h-4" />
            </button>
          </div>

          <div class="flex flex-col md:flex-row min-h-[360px] flex-1 min-h-0 divide-y md:divide-y-0 md:divide-x divide-gray-200/80 overflow-hidden">
            <%= if @tabs != [] do %>
              <div class="w-full md:w-48 p-2 bg-gray-50/70 space-y-0.5 shrink-0 overflow-y-auto custom-scrollbar">
                <%= for tab <- @tabs do %>
                  <% active? = to_string(tab[:id]) == to_string(@active_tab) %>
                  <button
                    type="button"
                    phx-click={@on_select_tab}
                    phx-value-tab={to_string(tab[:id])}
                    phx-target={@target}
                    class={"w-full text-left px-2.5 py-1.5 rounded-lg text-xs font-medium flex items-center gap-2 transition-colors #{if active?, do: "bg-white text-gray-900 shadow-2xs border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-100/70"}"}
                  >
                    <.studio_icon :if={tab[:icon]} icon={tab[:icon]} class="w-3.5 h-3.5" />
                    <span class="truncate"><%= tab[:title] || tab[:label] || tab[:id] %></span>
                  </button>
                <% end %>
              </div>
            <% end %>

            <div class="flex-1 p-5 min-w-0 space-y-4 overflow-y-auto overscroll-contain custom-scrollbar">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
