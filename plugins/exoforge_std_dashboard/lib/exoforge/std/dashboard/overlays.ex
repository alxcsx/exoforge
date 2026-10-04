defmodule Exoforge.Std.Dashboard.Overlays do
  @moduledoc """
  Modal, command palette, and dock overlays for the Exoforge Studio.
  """
  use Phoenix.Component
  import Exoforge.Std.Dashboard.Components
  alias Exoforge.Std.Dashboard.ExtensionPresenter

  @doc """
  Command Palette (Cmd+K) modal component.
  """
  attr(:open, :boolean, default: false)
  attr(:query, :string, default: "")
  attr(:results, :list, default: [])
  attr(:on_close, :string, default: "close_cmd_palette")
  attr(:on_search, :string, default: "search_cmd_palette")
  attr(:on_select, :string, default: "select_cmd_item")

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
  attr(:open, :boolean, default: false)
  attr(:catalog, :list, default: [])
  attr(:selected_service, :string, default: nil)
  attr(:selected_action, :string, default: nil)
  attr(:action_params, :map, default: %{})
  attr(:caller_scopes, :string, default: "admin, player")
  attr(:result, :any, default: nil)
  attr(:latency_ms, :any, default: nil)
  attr(:on_close, :string, default: "close_action_modal")
  attr(:on_select_service, :string, default: "select_action_service")
  attr(:on_select_action, :string, default: "select_action_name")
  attr(:on_change_form, :string, default: "change_action_form")
  attr(:on_dispatch, :string, default: "dispatch_action")

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
                  <p class="text-xs text-gray-500">Execute backend service actions across installed plugins</p>
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
                      <% p_type = normalize_param_type(param.type) %>
                      <% p_optional = Map.get(param, :optional, false) || is_param_optional?(param.type) %>
                      <div>
                        <label class="flex items-center justify-between text-xs font-semibold text-gray-700 mb-1">
                          <span class="font-mono text-gray-900"><%= param.name %></span>
                          <div class="flex items-center gap-1.5">
                            <%= if p_optional do %>
                              <span class="text-[9px] text-gray-400 font-bold uppercase bg-gray-100 px-1 py-0.2 rounded">optional</span>
                            <% else %>
                              <span class="text-[9px] text-purple-700 font-bold uppercase bg-purple-50 px-1 py-0.2 rounded">required</span>
                            <% end %>
                            <span class="text-[10px] text-gray-500 font-mono bg-gray-100 px-1.5 py-0.2 rounded">
                              <%= p_type %>
                            </span>
                          </div>
                        </label>

                        <%= case p_type do %>
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
  attr(:open, :boolean, default: false)
  attr(:events, :list, default: [])
  attr(:paused, :boolean, default: false)
  attr(:filter_topic, :string, default: "")
  attr(:on_toggle, :string, default: "toggle_event_dock")
  attr(:on_pause, :string, default: "toggle_event_pause")
  attr(:on_clear, :string, default: "clear_events")
  attr(:on_filter, :string, default: "filter_event_dock")
  attr(:on_simulate, :string, default: "simulate_test_event")

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

  defp format_action_runner_result(:ok), do: Jason.encode!(%{status: "ok"}, pretty: true)

  defp format_action_runner_result({:ok, val}) do
    case Jason.encode(sanitize_data(val), pretty: true) do
      {:ok, json} -> json
      _ -> inspect(val, pretty: true)
    end
  end

  defp format_action_runner_result({:error, reason}) do
    case Jason.encode(sanitize_data(reason), pretty: true) do
      {:ok, json} -> json
      _ -> inspect(reason, pretty: true)
    end
  end

  defp format_action_runner_result(other) do
    inspect(other, pretty: true)
  end

  @doc """
  Renders the project settings modal with side navigation tabs.
  """
  attr(:id, :string, default: "project_settings_modal")
  attr(:open, :boolean, default: false)
  attr(:project_name, :string, default: "Exoforge")
  attr(:studio_name, :string, default: "Exoforge Studio")
  attr(:settings_tab, :string, default: "project")
  attr(:settings_hooks, :list, default: [])
  attr(:environments, :list, default: [])
  attr(:current_env, :string, default: "dev")
  attr(:overview, :map, default: %{extensions: []})
  attr(:active_entities, :list, default: [])
  attr(:node_name, :string, default: "")
  attr(:on_close, :string, default: "close_settings")

  def project_settings_modal(assigns) do
    ~H"""
    <.modal
      id={@id}
      open={@open}
      max_width="max-w-4xl"
      title="Project Settings & Topology"
      subtitle={"#{@project_name} cluster configuration & plugin options"}
      on_close={@on_close}
    >
      <div class="flex flex-col md:flex-row min-h-[380px] -mx-6 -my-4 divide-y md:divide-y-0 md:divide-x divide-gray-100 text-xs">
        <!-- Left Sidebar Navigation -->
        <div class="w-full md:w-56 p-3 bg-gray-50/70 flex flex-col justify-between">
          <div class="space-y-4">
            <!-- Cluster & Core Settings -->
            <div>
              <span class="px-2 text-[10px] font-bold text-gray-400 uppercase tracking-wider">Cluster &amp; Core</span>
              <div class="mt-1.5 space-y-0.5">
                <button
                  type="button"
                  phx-click="set_settings_tab"
                  phx-value-tab="project"
                  class={"w-full text-left px-2.5 py-2 rounded-xl font-bold flex items-center gap-2 transition-all #{if @settings_tab == "project", do: "bg-white text-primary-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                >
                  <span>⚙️</span>
                  <span>Metadata</span>
                </button>
                <button
                  type="button"
                  phx-click="set_settings_tab"
                  phx-value-tab="environments"
                  class={"w-full text-left px-2.5 py-2 rounded-xl font-bold flex items-center gap-2 transition-all #{if @settings_tab == "environments", do: "bg-white text-primary-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                >
                  <span>🌐</span>
                  <span>Environments</span>
                </button>
              </div>
            </div>

            <!-- Plugin Settings Tabs -->
            <div>
              <div class="flex items-center justify-between px-2">
                <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Plugin Settings</span>
                <span class="text-[10px] font-mono px-1.5 py-0.2 rounded-full bg-gray-200/80 text-gray-600">
                  <%= length(@settings_hooks) %>
                </span>
              </div>
              <div class="mt-1.5 space-y-0.5">
                <%= if Enum.empty?(@settings_hooks) do %>
                  <p class="px-2 py-1 text-[11px] text-gray-400 italic">No plugin settings registered</p>
                <% else %>
                  <%= for hook <- @settings_hooks do %>
                    <button
                      type="button"
                      phx-click="set_settings_tab"
                      phx-value-tab={to_string(hook.id)}
                      class={"w-full text-left px-2.5 py-2 rounded-xl font-bold flex items-center gap-2 transition-all #{if @settings_tab == to_string(hook.id), do: "bg-white text-primary-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                    >
                      <span><%= hook.icon %></span>
                      <span class="truncate"><%= hook.title %></span>
                    </button>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <div class="pt-3 border-t border-gray-200/60 px-2 text-[10px] text-gray-400">
            <span>Node: </span><span class="font-mono text-gray-600"><%= @node_name %></span>
          </div>
        </div>

        <!-- Right Content Pane -->
        <div class="flex-1 p-6 space-y-4 overflow-y-auto">
          <%= if @settings_tab == "project" do %>
            <div class="space-y-4">
              <div>
                <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                  <span>⚙️</span>
                  <span>Project &amp; Cluster Metadata</span>
                </h4>
                <p class="text-xs text-gray-500 mt-0.5">Global configuration and runtime identifiers.</p>
              </div>

              <div class="space-y-3 bg-gray-50 p-4 rounded-xl border border-gray-200/80">
                <div>
                  <label class="block font-bold text-gray-700 mb-1">Studio Name</label>
                  <input type="text" value={@studio_name} readonly class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg font-mono text-xs" />
                </div>
                <div>
                  <label class="block font-bold text-gray-700 mb-1">Project Title</label>
                  <input type="text" value={@project_name} readonly class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg font-mono text-xs" />
                </div>
                <div class="grid grid-cols-2 gap-3 pt-2">
                  <div class="p-2.5 bg-white border border-gray-200 rounded-lg">
                    <span class="text-[10px] font-bold text-gray-400 uppercase">Registered Extensions</span>
                    <p class="text-sm font-bold text-gray-800 font-mono mt-0.5"><%= length(@overview.extensions) %></p>
                  </div>
                  <div class="p-2.5 bg-white border border-gray-200 rounded-lg">
                    <span class="text-[10px] font-bold text-gray-400 uppercase">Active Virtual Actors</span>
                    <p class="text-sm font-bold text-gray-800 font-mono mt-0.5"><%= length(@active_entities) %></p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @settings_tab == "environments" do %>
            <div class="space-y-4">
              <div>
                <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                  <span>🌐</span>
                  <span>Cluster Environments</span>
                </h4>
                <p class="text-xs text-gray-500 mt-0.5">Switch active cluster deployment environment profile.</p>
              </div>

              <div class="space-y-3 bg-gray-50 p-4 rounded-xl border border-gray-200/80">
                <p class="text-gray-600 font-medium">Select active environment profile:</p>
                <div class="flex flex-wrap gap-2">
                  <%= for env <- @environments do %>
                    <button
                      phx-click="switch_env"
                      phx-value-env={env}
                      class={"px-4 py-2 rounded-xl font-bold border transition-all #{if @current_env == env, do: "bg-emerald-500 text-white border-emerald-600 shadow-sm", else: "bg-white text-gray-700 border-gray-200 hover:bg-gray-100"}"}
                    >
                      <%= env %>
                    </button>
                  <% end %>
                </div>
                <div class="pt-2 text-[11px] text-gray-500">
                  Current active environment: <strong class="text-emerald-700"><%= @current_env %></strong>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @settings_tab == "database" do %>
            <div class="space-y-4">
              <div>
                <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                  <span>🗄️</span>
                  <span>Database Engine &amp; Multi-Tenancy</span>
                </h4>
                <p class="text-xs text-gray-500 mt-0.5">Per-plugin schema isolation with PostgreSQL or SQLite adapter.</p>
              </div>

              <div class="space-y-3 bg-gray-50 p-4 rounded-xl border border-gray-200/80">
                <div class="flex items-center justify-between p-3 bg-white border border-gray-200 rounded-lg">
                  <div>
                    <span class="font-bold text-gray-800">Storage Engine Mode</span>
                    <p class="text-[11px] text-gray-500">SQLite (Test/Dev) with automatic PostgreSQL fallback</p>
                  </div>
                  <span class="px-2.5 py-1 text-[10px] font-bold rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
                    Active
                  </span>
                </div>

                <div class="flex items-center justify-between p-3 bg-white border border-gray-200 rounded-lg">
                  <div>
                    <span class="font-bold text-gray-800">Plugin Isolation</span>
                    <p class="text-[11px] text-gray-500">Each plugin accesses exclusively its own tenant namespace</p>
                  </div>
                  <span class="px-2.5 py-1 text-[10px] font-bold rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                    Isolated
                  </span>
                </div>

                <div class="pt-2 flex gap-2">
                  <button
                    type="button"
                    phx-click="open_action_modal"
                    phx-value-service="database"
                    class="px-3 py-1.5 bg-primary-600 hover:bg-primary-700 text-white font-bold rounded-lg transition-colors flex items-center gap-1.5"
                  >
                    <span>⚡</span>
                    <span>Execute Database Action</span>
                  </button>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @settings_tab == "auth" do %>
            <div class="space-y-4">
              <div>
                <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                  <span>🔐</span>
                  <span>Authentication &amp; Security Policies</span>
                </h4>
                <p class="text-xs text-gray-500 mt-0.5">Token lifecycle, authorization scopes, and session rules.</p>
              </div>

              <div class="space-y-3 bg-gray-50 p-4 rounded-xl border border-gray-200/80">
                <div class="p-3 bg-white border border-gray-200 rounded-lg space-y-1">
                  <span class="font-bold text-gray-800">Token Strategy</span>
                  <p class="text-[11px] text-gray-500">Bearer Token with cross-port cookie extraction (<code class="font-mono text-purple-700">exo_auth_token</code> on ports 4005, 4001, 4000).</p>
                </div>

                <div class="p-3 bg-white border border-gray-200 rounded-lg space-y-1">
                  <span class="font-bold text-gray-800">Role Multi-Scope Mapping</span>
                  <div class="flex flex-wrap gap-1.5 pt-1">
                    <span class="px-2 py-0.5 rounded bg-purple-50 text-purple-700 text-[10px] font-mono">admin &rarr; admin, studio, service, player, guest</span>
                    <span class="px-2 py-0.5 rounded bg-blue-50 text-blue-700 text-[10px] font-mono">studio &rarr; studio, service, player, guest</span>
                    <span class="px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 text-[10px] font-mono">player &rarr; player, guest</span>
                  </div>
                </div>

                <div class="pt-2 flex gap-2">
                  <button
                    type="button"
                    phx-click="switch_tab"
                    phx-value-tab="auth"
                    class="px-3 py-1.5 bg-primary-600 hover:bg-primary-700 text-white font-bold rounded-lg transition-colors flex items-center gap-1.5"
                  >
                    <span>🛡️</span>
                    <span>Open Users &amp; Auth View</span>
                  </button>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Dynamic Plugin Settings Tab Fallback -->
          <%= if @settings_tab not in ["project", "environments", "database", "auth"] do %>
            <% active_hook = Enum.find(@settings_hooks, fn h -> to_string(h.id) == @settings_tab end) %>
            <%= if active_hook do %>
              <%= if active_hook[:component] && Code.ensure_loaded?(active_hook[:component]) do %>
                <.live_component module={active_hook[:component]} id={"settings_#{active_hook.id}"} />
              <% else %>
                <div class="space-y-4">
                  <div>
                    <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                      <span><%= active_hook.icon %></span>
                      <span><%= active_hook.title %></span>
                    </h4>
                    <p class="text-xs text-gray-500 mt-0.5">Settings contributed by <%= active_hook[:plugin_id] || "plugin" %>.</p>
                  </div>

                  <div class="bg-gray-50 p-4 rounded-xl border border-gray-200/80 space-y-2">
                    <div class="flex items-center justify-between p-3 bg-white border border-gray-200 rounded-lg">
                      <span class="font-bold text-gray-800">Hook ID</span>
                      <span class="font-mono text-purple-700 font-bold"><%= active_hook.id %></span>
                    </div>
                    <div class="flex items-center justify-between p-3 bg-white border border-gray-200 rounded-lg">
                      <span class="font-bold text-gray-800">Origin Plugin</span>
                      <span class="font-mono text-gray-600"><%= active_hook[:plugin_id] || "n/a" %></span>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </.modal>
    """
  end

  @doc """
  Renders the modal for inspecting a plugin, including services, dependencies, and actions.
  """
  attr(:extension, :map, default: nil)
  attr(:auth_token, :string, default: nil)
  attr(:on_close, :string, default: "close_inspect_extension")

  def plugin_inspector_modal(assigns) do
    ~H"""
    <%= if @extension do %>
      <.modal
        id="plugin_inspector_modal"
        open={true}
        max_width="max-w-2xl"
        title={"Inspect: #{display_name(@extension)}"}
        subtitle={"Plugin #{@extension.id} (v#{@extension.version})"}
        on_close={@on_close}
      >
        <div class="space-y-4 text-xs">
          <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl border border-gray-200">
            <span class="w-12 h-12 rounded-xl bg-purple-50 text-purple-700 flex items-center justify-center text-2xl">
              <%= (is_map(@extension.dashboard_view) && @extension.dashboard_view[:icon]) || default_extension_icon(@extension) %>
            </span>
            <div class="flex-1">
              <div class="flex items-center justify-between">
                <h4 class="font-bold text-gray-900 text-sm"><%= display_name(@extension) %></h4>
                <span class="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 font-bold">
                  <%= @extension.status %>
                </span>
              </div>
              <p class="text-[11px] text-gray-500 font-mono mt-0.5"><%= @extension.id %> &bull; <%= @extension.type %></p>
            </div>
          </div>

          <!-- HTTP Gateway Swagger Documentation -->
          <%= if provides_service?(@extension, :http) do %>
            <div class="p-3.5 bg-emerald-50/80 border border-emerald-200 rounded-xl flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div>
                <span class="font-bold text-emerald-900 text-xs flex items-center gap-1.5">
                  <span>📖</span>
                  <span>Interactive Swagger / OpenAPI Explorer</span>
                </span>
                <p class="text-[11px] text-emerald-700 mt-0.5">Explore REST routes, view OpenAPI 3.0 schema, and test endpoints live with pre-authorized session token.</p>
              </div>
              <a
                href={"http://localhost:#{Exoforge.Endpoints.http_port()}/api/docs" <> if(@auth_token, do: "?token=" <> URI.encode_www_form(@auth_token), else: "")}
                target="_blank"
                class="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs rounded-lg transition-colors flex items-center justify-center gap-1 shadow-xs whitespace-nowrap flex-shrink-0"
              >
                <span>Open Swagger</span>
                <span>↗</span>
              </a>
            </div>
          <% end %>

          <!-- Provides & Dependencies -->
          <div class="grid grid-cols-2 gap-3">
            <div class="p-3 bg-gray-50 rounded-xl border border-gray-200 space-y-1">
              <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Provides Services</span>
              <div class="flex flex-wrap gap-1 pt-1">
                <%= for s <- @extension.provides do %>
                  <span class="px-2 py-0.5 rounded bg-purple-50 text-purple-700 font-mono font-bold text-[10px]">
                    <%= s %>
                  </span>
                <% end %>
              </div>
            </div>
            <div class="p-3 bg-gray-50 rounded-xl border border-gray-200 space-y-1">
              <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Dependencies</span>
              <div class="flex flex-wrap gap-1 pt-1">
                <%= if Enum.empty?(@extension.dependencies) do %>
                  <span class="text-gray-400 italic text-[11px]">None (Root service)</span>
                <% else %>
                  <%= for d <- @extension.dependencies do %>
                    <span class="px-2 py-0.5 rounded bg-gray-200 text-gray-700 font-mono text-[10px]">
                      <%= d %>
                    </span>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Services and Actions -->
          <div class="space-y-2">
            <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">
              Exported Actions (<%= length(@extension.actions) %>)
            </span>
            <%= if Enum.empty?(@extension.actions) do %>
              <p class="p-3 bg-gray-50 rounded-xl text-gray-400 italic">No actions exposed by this plugin.</p>
            <% else %>
              <div class="space-y-1.5 max-h-48 overflow-y-auto pr-1">
                <%= for act <- @extension.actions do %>
                  <div class="flex items-center justify-between p-2.5 bg-gray-50 border border-gray-200 rounded-lg">
                    <div>
                      <span class="font-mono font-bold text-gray-900"><%= act.service %>.<%= act.name %></span>
                      <%= if act.doc do %>
                        <p class="text-[10px] text-gray-500 mt-0.5"><%= act.doc %></p>
                      <% end %>
                    </div>
                    <button
                      type="button"
                      phx-click="open_action_modal"
                      phx-value-service={act.service}
                      phx-value-action={act.name}
                      class="px-2.5 py-1 text-[11px] font-bold text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors flex items-center gap-1 shadow-xs"
                    >
                      <span>⚡ Run</span>
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </.modal>
    <% end %>
    """
  end

  @doc """
  Renders the login modal.
  """
  attr(:open, :boolean, default: false)
  attr(:error, :string, default: nil)
  attr(:on_close, :string, default: "close_login_modal")

  def login_modal(assigns) do
    csrf = Plug.CSRFProtection.get_csrf_token()
    assigns = assign(assigns, :csrf_token, csrf)

    ~H"""
    <.modal
      id="studio_login_modal"
      open={@open}
      max_width="max-w-md"
      title="Sign in to Exoforge Studio"
      subtitle="Authenticate with registered account credentials or developer admin token."
      on_close={@on_close}
    >
      <div class="space-y-4 text-xs">
        <%= if @error do %>
          <div class="p-3 bg-red-50 border border-red-200 text-red-700 rounded-xl text-xs font-semibold">
            <%= @error %>
          </div>
        <% end %>

        <form action="/login" method="post" class="space-y-3">
          <input type="hidden" name="_csrf_token" value={@csrf_token} />

          <div>
            <label class="block font-bold text-gray-700 mb-1">Email / Account ID</label>
            <input
              type="text"
              name="email"
              required
              placeholder="admin@exoforge.io or username"
              class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-xs focus:bg-white focus:outline-none focus:border-primary-500 font-medium"
            />
          </div>

          <div>
            <label class="block font-bold text-gray-700 mb-1">Password</label>
            <input
              type="password"
              name="password"
              required
              placeholder="••••••••"
              class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-xs focus:bg-white focus:outline-none focus:border-primary-500 font-medium"
            />
          </div>

          <div class="pt-2">
            <button
              type="submit"
              class="w-full py-2 bg-primary-600 hover:bg-primary-700 text-white font-bold rounded-xl text-xs transition-colors shadow-xs"
            >
              Sign In
            </button>
          </div>
        </form>

        <div class="relative flex py-2 items-center">
          <div class="flex-grow border-t border-gray-200"></div>
          <span class="flex-shrink mx-3 text-gray-400 text-[10px] font-bold uppercase tracking-wider">Or</span>
          <div class="flex-grow border-t border-gray-200"></div>
        </div>

        <form action="/login" method="post">
          <input type="hidden" name="_csrf_token" value={@csrf_token} />
          <input type="hidden" name="dev_admin" value="true" />
          <button
            type="submit"
            class="w-full py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 font-bold rounded-xl text-xs transition-colors border border-gray-200/80 flex items-center justify-center gap-1.5"
          >
            <span>⚡</span>
            <span>Quick Dev Sign-In (Studio Admin)</span>
          </button>
        </form>
      </div>
    </.modal>
    """
  end

  defp display_name(ext_or_id), do: ExtensionPresenter.display_name(ext_or_id)
  defp default_extension_icon(ext), do: ExtensionPresenter.icon(ext)

  defp provides_service?(extension, service) do
    target = to_string(service)

    extension
    |> Map.get(:provides, [])
    |> Enum.any?(fn p ->
      p |> to_string() |> String.split(".") |> List.last() |> String.downcase() == target
    end)
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

  defp normalize_param_type([{:type, t} | _]), do: t
  defp normalize_param_type(t) when is_atom(t), do: t
  defp normalize_param_type(_), do: :string

  defp is_param_optional?(kw) when is_list(kw), do: Keyword.get(kw, :optional, false)
  defp is_param_optional?(_), do: false
end
