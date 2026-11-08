defmodule Exoforge.Std.Dashboard.Overlays do
  @moduledoc """
  Modal, command palette, and dock overlays for the Exoforge Studio.
  """
  use Phoenix.Component
  import Exoforge.Std.Dashboard.Components
  import Exoforge.Std.Dashboard.InputTypes, only: [widget: 1]
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

                        <% custom_spec = Exoforge.Std.Dashboard.InputTypes.resolve(param) %>

                        <%= if is_map(custom_spec) do %>
                          <.widget spec={custom_spec} name={"param_#{param.name}"} value={Map.get(@action_params, param.name, "")} />
                        <% else %>
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
                  Caller Scopes (verified session scopes)
                </label>
                <div class="w-full px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-500">
                  <%= @caller_scopes %>
                </div>
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
  attr(:project_metadata, :map, default: %{})
  attr(:settings_tab, :string, default: "project")
  attr(:settings_hooks, :list, default: [])
  attr(:cors_config, :map, default: %{})
  attr(:overview, :map, default: %{extensions: []})
  attr(:node_name, :string, default: "")
  attr(:activity_events, :list, default: [])
  attr(:events_paused, :boolean, default: false)
  attr(:event_filter_topic, :string, default: "")
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
      {project_settings_panel(assigns)}
    </.modal>
    """
  end

  attr(:project_name, :string, default: "Exoforge")
  attr(:studio_name, :string, default: "Exoforge Studio")
  attr(:project_metadata, :map, default: %{})
  attr(:settings_tab, :string, default: "project")
  attr(:settings_hooks, :list, default: [])
  attr(:cors_config, :map, default: %{})
  attr(:overview, :map, default: %{extensions: []})
  attr(:node_name, :string, default: "")
  attr(:activity_events, :list, default: [])
  attr(:events_paused, :boolean, default: false)
  attr(:event_filter_topic, :string, default: "")
  attr(:on_close, :string, default: "close_settings")

  def project_settings_panel(assigns) do
    assigns =
      assigns
      |> assign_new(:project_name, fn -> "Exoforge" end)
      |> assign_new(:studio_name, fn -> "Exoforge Studio" end)
      |> assign_new(:project_metadata, fn -> %{} end)
      |> assign_new(:settings_tab, fn -> "project" end)
      |> assign_new(:settings_hooks, fn -> [] end)
      |> assign_new(:cors_config, fn -> %{} end)
      |> assign_new(:overview, fn -> %{extensions: []} end)
      |> assign_new(:node_name, fn -> to_string(node()) end)
      |> assign_new(:activity_events, fn -> [] end)
      |> assign_new(:events_paused, fn -> false end)
      |> assign_new(:event_filter_topic, fn -> "" end)
      |> assign_new(:on_close, fn -> "close_settings" end)
    ~H"""
    <div class="flex flex-col md:flex-row min-h-[380px] md:h-[540px] md:max-h-[calc(85vh-7rem)] -mx-6 -my-4 divide-y md:divide-y-0 md:divide-x divide-gray-100 text-xs">
        <!-- Left Sidebar Navigation -->
        <div class="w-full md:w-56 p-3 bg-gray-50/70 flex flex-col justify-between shrink-0 overflow-y-auto custom-scrollbar">
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
                  phx-value-tab="visual"
                  class={"w-full text-left px-2.5 py-2 rounded-xl font-bold flex items-center gap-2 transition-all #{if @settings_tab == "visual", do: "bg-white text-primary-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                >
                  <span>🌓</span>
                  <span>Visual Settings</span>
                </button>
                <button
                  type="button"
                  phx-click="set_settings_tab"
                  phx-value-tab="console"
                  class={"w-full text-left px-2.5 py-2 rounded-xl font-bold flex items-center gap-2 transition-all #{if @settings_tab == "console", do: "bg-white text-primary-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                >
                  <span>📟</span>
                  <span>Console</span>
                </button>
                <button
                  type="button"
                  phx-click="set_settings_tab"
                  phx-value-tab="guide"
                  class={"w-full text-left px-2.5 py-2 rounded-xl font-bold flex items-center gap-2 transition-all #{if @settings_tab == "guide", do: "bg-white text-primary-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                >
                  <span>📖</span>
                  <span>Developer Guide</span>
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

          <div class="pt-3 border-t border-gray-200/60 px-2 text-[10px] text-gray-400 space-y-1">
            <div class="truncate"><span>Node: </span><span class="font-mono text-gray-600"><%= @node_name %></span></div>
            <div class="truncate" title={@overview[:commit_hash]}>
              <span>Cluster: </span><span class="font-mono text-gray-600">v<%= @overview[:version] || Exoforge.BuildInfo.version() %> (<%= String.slice(to_string(@overview[:commit_hash] || "dev"), 0, 7) %>)</span>
            </div>
          </div>
        </div>

        <!-- Right Content Pane -->
        <div class="flex-1 p-6 space-y-4 overflow-y-auto min-w-0 custom-scrollbar">
          <%= if @settings_tab == "project" do %>
            <% meta = @project_metadata || %{} %>
            <% desc = to_string(meta["description"] || meta[:description] || "") %>
            <% url = to_string(meta["website_url"] || meta[:website_url] || "") %>
            <% custom = meta["custom"] || meta[:custom] || %{} %>
            <% custom_json = (if is_map(custom) and map_size(custom) > 0, do: Jason.encode!(custom, pretty: true), else: "") %>
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <div>
                  <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                    <span>⚙️</span>
                    <span>Project &amp; Cluster Metadata</span>
                  </h4>
                  <p class="text-xs text-gray-500 mt-0.5">Global configuration, studio identity, and runtime telemetry.</p>
                </div>
                <span class="px-2.5 py-1 text-[10px] font-bold rounded-full bg-primary-50 text-primary-700 border border-primary-200">
                  Cluster-wide
                </span>
              </div>

              <form id="project_metadata_form" phx-submit="save_project_metadata" class="space-y-4">
                <div class="space-y-3 bg-gray-50 p-4 rounded-xl border border-gray-200/80">
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <label class="block font-bold text-gray-700 mb-1">Studio Name</label>
                      <input
                        type="text"
                        name="studio_name"
                        value={@studio_name}
                        placeholder="e.g. Acme Game Studio"
                        class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-xs font-semibold focus:ring-2 focus:ring-primary-500 focus:border-primary-500 transition-all"
                      />
                    </div>
                    <div>
                      <label class="block font-bold text-gray-700 mb-1">Project Title</label>
                      <input
                        type="text"
                        name="project_name"
                        value={@project_name}
                        placeholder="e.g. Cyber Snake Arena"
                        class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-xs font-semibold focus:ring-2 focus:ring-primary-500 focus:border-primary-500 transition-all"
                      />
                    </div>
                  </div>

                  <div>
                    <label class="block font-bold text-gray-700 mb-1">Description</label>
                    <input
                      type="text"
                      name="description"
                      value={desc}
                      placeholder="e.g. Multiplayer competitive arcade backend"
                      class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-xs focus:ring-2 focus:ring-primary-500 focus:border-primary-500 transition-all"
                    />
                  </div>

                  <div>
                    <label class="block font-bold text-gray-700 mb-1">Website / Docs URL</label>
                    <input
                      type="text"
                      name="website_url"
                      value={url}
                      placeholder="e.g. https://mygame.com or https://docs.mygame.com"
                      class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-xs font-mono focus:ring-2 focus:ring-primary-500 focus:border-primary-500 transition-all"
                    />
                  </div>

                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <label class="block font-bold text-gray-700">Custom Metadata (JSON)</label>
                      <span class="text-[10px] text-gray-400">Extensible key-value properties</span>
                    </div>
                    <textarea
                      name="custom_json"
                      rows="3"
                      placeholder='{"genre": "arcade", "region": "us-east", "discord": "https://..."}'
                      class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-xs font-mono focus:ring-2 focus:ring-primary-500 focus:border-primary-500 transition-all"
                    ><%= custom_json %></textarea>
                  </div>

                  <div class="flex justify-end pt-1">
                    <button
                      type="submit"
                      class="px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white font-bold rounded-xl transition-all shadow-sm hover:shadow flex items-center gap-1.5"
                    >
                      <span>💾</span>
                      <span>Save Metadata</span>
                    </button>
                  </div>
                </div>
              </form>

              <div class="space-y-2 bg-gray-50/70 p-4 rounded-xl border border-gray-200/80">
                <span class="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">Runtime Identifiers</span>
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 pt-1">
                  <div class="p-2.5 bg-white border border-gray-200 rounded-lg min-w-0">
                    <span class="text-[10px] font-bold text-gray-400 uppercase block">Version</span>
                    <p class="text-sm font-bold text-gray-800 font-mono mt-0.5 truncate">v<%= @overview[:version] || Exoforge.BuildInfo.version() %></p>
                  </div>
                  <div class="p-2.5 bg-white border border-gray-200 rounded-lg min-w-0 overflow-hidden">
                    <span class="text-[10px] font-bold text-gray-400 uppercase block">Commit Hash</span>
                    <p class="text-sm font-bold text-primary-700 font-mono mt-0.5 truncate" title={@overview[:commit_hash]}>
                      <%= String.slice(to_string(@overview[:commit_hash] || "dev"), 0, 7) %>
                    </p>
                  </div>
                  <div class="p-2.5 bg-white border border-gray-200 rounded-lg min-w-0">
                    <span class="text-[10px] font-bold text-gray-400 uppercase block">Build Date</span>
                    <p class="text-xs font-bold text-gray-800 font-mono mt-1 truncate" title={@overview[:build_date]}><%= @overview[:build_date] || "—" %></p>
                  </div>
                  <div class="p-2.5 bg-white border border-gray-200 rounded-lg min-w-0">
                    <span class="text-[10px] font-bold text-gray-400 uppercase block">Extensions</span>
                    <p class="text-sm font-bold text-gray-800 font-mono mt-0.5 truncate"><%= length(@overview.extensions) %></p>
                  </div>
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
                  <p class="text-[11px] text-gray-500">Bearer Token with cross-port cookie extraction (<code class="font-mono text-purple-700">{hd(Exoforge.Auth.Request.cookie_names())}</code> on ports {Exoforge.Endpoints.dashboard_port()}, {Exoforge.Endpoints.http_port()}, {Exoforge.Endpoints.ws_port()}).</p>
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

          <%= if @settings_tab == "visual" do %>
            <div class="space-y-4">
              <div>
                <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                  <span>🌓</span>
                  <span>Visual Settings &amp; Theme</span>
                </h4>
                <p class="text-xs text-gray-500 mt-0.5">Configure the Studio interface appearance and color scheme.</p>
              </div>

              <div class="space-y-3 bg-gray-50 p-4 rounded-xl border border-gray-200/80">
                <div class="flex items-center justify-between p-3.5 bg-white border border-gray-200 rounded-xl">
                  <div>
                    <span class="font-bold text-gray-800 block">Studio Color Theme</span>
                    <p class="text-[11px] text-gray-500 mt-0.5">Switch between Unity-inspired Dark Mode and Daylight Mode.</p>
                  </div>
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      onclick="window.ExoforgeTheme && window.ExoforgeTheme.set('dark')"
                      class="px-3 py-1.5 rounded-lg font-bold text-xs bg-gray-900 text-white hover:bg-gray-800 border border-gray-700 transition-colors flex items-center gap-1.5"
                    >
                      <span>🌙</span>
                      <span>Dark</span>
                    </button>
                    <button
                      type="button"
                      onclick="window.ExoforgeTheme && window.ExoforgeTheme.set('light')"
                      class="px-3 py-1.5 rounded-lg font-bold text-xs bg-white text-gray-800 hover:bg-gray-100 border border-gray-300 transition-colors flex items-center gap-1.5"
                    >
                      <span>☀️</span>
                      <span>Light</span>
                    </button>
                    <button
                      type="button"
                      onclick="window.ExoforgeTheme && window.ExoforgeTheme.toggle()"
                      title="Toggle Dark / Light Theme"
                      class="px-3 py-1.5 rounded-lg font-bold text-xs bg-primary-600 hover:bg-primary-700 text-white transition-colors flex items-center gap-1.5"
                    >
                      <span>🌓</span>
                      <span>Toggle Theme</span>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @settings_tab == "console" do %>
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <div>
                  <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                    <span>📟</span>
                    <span>Cluster Event Stream &amp; Console</span>
                  </h4>
                  <p class="text-xs text-gray-500 mt-0.5">Real-time cluster event stream via <code class="font-mono text-primary-600">EventDispatcher</code> &amp; <code class="font-mono text-primary-600">:pg</code></p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="px-2 py-0.5 rounded-full bg-gray-100 font-mono font-bold text-[10px] text-gray-600 border border-gray-200">
                    <%= length(@activity_events) %> captured
                  </span>
                  <%= if @events_paused do %>
                    <span class="px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 text-[10px] font-bold border border-amber-200">
                      STREAM PAUSED
                    </span>
                  <% end %>
                </div>
              </div>

              <!-- Console Controls Toolbar -->
              <div class="flex flex-wrap items-center justify-between gap-2 p-2.5 bg-gray-50 rounded-xl border border-gray-200/80 text-xs">
                <form id="settings_console_filter_form" phx-change="filter_event_dock" class="m-0">
                  <input
                    type="text"
                    name="topic"
                    value={@event_filter_topic}
                    placeholder="Filter event or payload..."
                    class="px-2.5 py-1 bg-white border border-gray-300 rounded-lg text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-primary-500 w-44 sm:w-56 font-mono"
                  />
                </form>

                <div class="flex items-center gap-1.5">
                  <button
                    type="button"
                    phx-click="toggle_event_pause"
                    class={"px-2.5 py-1 rounded-lg font-bold text-xs flex items-center gap-1 transition-colors #{if @events_paused, do: "bg-emerald-600 hover:bg-emerald-500 text-white", else: "bg-white hover:bg-gray-100 text-gray-700 border border-gray-200"}"}
                  >
                    <%= if @events_paused, do: "▶ Resume", else: "⏸ Pause" %>
                  </button>

                  <button
                    type="button"
                    phx-click="clear_events"
                    class="px-2.5 py-1 bg-white hover:bg-gray-100 text-gray-600 border border-gray-200 rounded-lg font-bold text-xs transition-colors"
                  >
                    Clear
                  </button>
                </div>
              </div>

              <!-- Console Terminal Window -->
              <div class="bg-gray-950 rounded-xl p-3.5 border border-gray-800 text-gray-100 max-h-72 overflow-y-auto space-y-2 font-mono text-xs custom-scrollbar">
                <%= if Enum.empty?(@activity_events) do %>
                  <div class="py-8 flex flex-col items-center justify-center text-center space-y-1.5">
                    <span class="text-xl">📡</span>
                    <p class="text-xs text-gray-400 font-sans">Waiting for live cluster events on <code class="text-primary-400">EventDispatcher</code> bus...</p>
                    <p class="text-[11px] text-gray-500 font-sans">Click "⚡ Simulate Event" above or dispatch an action to test.</p>
                  </div>
                <% else %>
                  <%= for ev <- @activity_events do %>
                    <div class="p-2.5 bg-gray-900/90 rounded-lg border border-gray-800/80 flex flex-col gap-1.5">
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
                      <pre class="text-[10px] text-emerald-400 overflow-x-auto p-2 bg-black/60 rounded border border-gray-800/60 font-mono"><%= Jason.encode!(ev.payload, pretty: true) %></pre>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @settings_tab in ["http", "cors"] do %>
            <% mode = to_string(@cors_config["mode"] || @cors_config[:mode] || "relaxed") %>
            <% origins = to_string(@cors_config["allowed_origins"] || @cors_config[:allowed_origins] || "*") %>
            <% allow_creds = Map.get(@cors_config, "allow_credentials", Map.get(@cors_config, :allow_credentials, true)) != false %>
            <div class="space-y-4">
              <div>
                <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                  <span>🌐</span>
                  <span>HTTP Ingress &amp; CORS Policy</span>
                </h4>
                <p class="text-xs text-gray-500 mt-0.5">Control Cross-Origin Resource Sharing (CORS) for Unity WebGL, browser clients, and external web APIs.</p>
              </div>

              <form id="cors_settings_form" phx-change="change_cors_settings" phx-submit="save_cors_settings" class="space-y-4">
                <div class="bg-gray-50 p-4 rounded-xl border border-gray-200/80 space-y-3">
                  <span class="font-bold text-gray-800 text-xs uppercase tracking-wider">CORS Access Policy</span>

                  <div class="grid grid-cols-1 md:grid-cols-3 gap-2.5 pt-1">
                    <!-- Relaxed Mode -->
                    <label id="cors-policy-relaxed" class={"relative flex flex-col p-3 rounded-xl border cursor-pointer transition-all #{if mode == "relaxed", do: "bg-purple-50 border-purple-500 ring-2 ring-purple-500 shadow-xs", else: "bg-white border-gray-200 hover:border-gray-300 opacity-80 hover:opacity-100"}"}>
                      <div class="flex items-center gap-2">
                        <input type="radio" name="mode" value="relaxed" checked={mode == "relaxed"} class="text-purple-600 focus:ring-purple-500" />
                        <span class={"font-bold text-xs #{if mode == "relaxed", do: "text-purple-700", else: "text-gray-900"}"}>Relaxed (Wildcard)</span>
                      </div>
                      <p class="text-[11px] text-gray-500 mt-1.5 leading-snug">
                        Accepts requests from any origin. Recommended for <strong>Unity WebGL builds</strong>, itch.io, and external web dev.
                      </p>
                    </label>

                    <!-- Whitelist Mode -->
                    <label id="cors-policy-whitelist" class={"relative flex flex-col p-3 rounded-xl border cursor-pointer transition-all #{if mode == "whitelist", do: "bg-purple-50 border-purple-500 ring-2 ring-purple-500 shadow-xs", else: "bg-white border-gray-200 hover:border-gray-300 opacity-80 hover:opacity-100"}"}>
                      <div class="flex items-center gap-2">
                        <input type="radio" name="mode" value="whitelist" checked={mode == "whitelist"} class="text-purple-600 focus:ring-purple-500" />
                        <span class={"font-bold text-xs #{if mode == "whitelist", do: "text-purple-700", else: "text-gray-900"}"}>Allowed Origins</span>
                      </div>
                      <p class="text-[11px] text-gray-500 mt-1.5 leading-snug">
                        Restricts cross-origin requests to explicitly allowed domains.
                      </p>
                    </label>

                    <!-- Strict Mode -->
                    <label id="cors-policy-strict" class={"relative flex flex-col p-3 rounded-xl border cursor-pointer transition-all #{if mode == "strict", do: "bg-purple-50 border-purple-500 ring-2 ring-purple-500 shadow-xs", else: "bg-white border-gray-200 hover:border-gray-300 opacity-80 hover:opacity-100"}"}>
                      <div class="flex items-center gap-2">
                        <input type="radio" name="mode" value="strict" checked={mode == "strict"} class="text-purple-600 focus:ring-purple-500" />
                        <span class={"font-bold text-xs #{if mode == "strict", do: "text-purple-700", else: "text-gray-900"}"}>Strict (Disabled)</span>
                      </div>
                      <p class="text-[11px] text-gray-500 mt-1.5 leading-snug">
                        Blocks all cross-origin requests. Only same-origin calls are permitted.
                      </p>
                    </label>
                  </div>

                  <!-- Whitelist Origin Field -->
                  <div class="pt-2">
                    <label class="block font-bold text-gray-700 text-xs mb-1">
                      Allowed Origins (Comma-separated)
                    </label>
                    <input
                      type="text"
                      name="allowed_origins"
                      value={origins}
                      disabled={mode in ["strict", "relaxed"]}
                      placeholder="e.g. https://mygame.com, https://play.itch.io, http://localhost:3000"
                      class={"w-full text-xs px-3 py-2 border rounded-lg font-mono transition-opacity #{if mode in ["strict", "relaxed"], do: "bg-gray-100 border-gray-200 text-gray-400 cursor-not-allowed opacity-60", else: "bg-white border-gray-300 focus:ring-2 focus:ring-purple-500 focus:border-purple-500"}"}
                    />
                    <p class="text-[11px] text-gray-500 mt-1">
                      <%= if mode in ["strict", "relaxed"] do %>
                        Select <strong>Allowed Origins</strong> mode above to edit custom origin domains.
                      <% else %>
                        Specify comma-separated origin URLs allowed to access HTTP endpoints.
                      <% end %>
                    </p>
                  </div>

                  <!-- Credentials Checkbox -->
                  <div class="pt-2 border-t border-gray-200/60">
                    <label class="flex items-start gap-2.5 cursor-pointer">
                      <input
                        type="checkbox"
                        name="allow_credentials"
                        value="true"
                        checked={allow_creds}
                        class="mt-0.5 rounded text-purple-600 focus:ring-purple-500 border-gray-300"
                      />
                      <div>
                        <span class="font-bold text-gray-800 text-xs">Allow Credentials &amp; Auth Headers</span>
                        <p class="text-[11px] text-gray-500 mt-0.5">
                          Enables <code class="font-mono text-purple-700">Access-Control-Allow-Credentials: true</code> so browser clients can transmit cookies and Authorization tokens cross-origin.
                        </p>
                      </div>
                    </label>
                  </div>
                </div>

                <div class="flex justify-between items-center pt-2">
                  <span class="text-[11px] text-gray-500">
                    HTTP Listener: Port <strong>{Exoforge.Endpoints.http_port()}</strong> • Preflight: <strong>204 No Content</strong>
                  </span>
                  <button
                    type="submit"
                    class="px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white font-bold rounded-xl transition-all shadow-sm hover:shadow flex items-center gap-1.5"
                  >
                    <span>💾</span>
                    <span>Save CORS Policy</span>
                  </button>
                </div>
              </form>
            </div>
          <% end %>

          <!-- Developer Guide Tab -->
          <%= if @settings_tab == "guide" do %>
            <div class="space-y-4">
              <div class="flex items-center justify-between pb-3 border-b border-gray-100">
                <div>
                  <h4 class="text-sm font-bold text-gray-900 flex items-center gap-2">
                    <span>📖</span>
                    <span>Exoforge Developer Guide</span>
                  </h4>
                  <p class="text-xs text-gray-500 mt-0.5">Quick reference for C# extension development, live cluster contracts, and platform architecture.</p>
                </div>
                <button
                  type="button"
                  phx-click="open_guide_from_settings"
                  class="px-3.5 py-1.5 bg-primary-600 hover:bg-primary-700 text-white font-bold text-xs rounded-xl transition-all shadow-xs flex items-center gap-1.5 shrink-0"
                >
                  <span>Open Full Guide</span>
                  <span>&rarr;</span>
                </button>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="p-3.5 bg-gray-50 rounded-xl border border-gray-200/80 space-y-1.5">
                  <div class="flex items-center gap-2 text-primary-700 font-bold text-xs">
                    <span>🚀</span>
                    <span>Quickstart Flow</span>
                  </div>
                  <p class="text-[11px] text-gray-600 leading-relaxed">
                    Step-by-step multiplayer integration: Anonymous auth, Player Data sync, custom C# extensions, and client stubs.
                  </p>
                </div>

                <div class="p-3.5 bg-gray-50 rounded-xl border border-gray-200/80 space-y-1.5">
                  <div class="flex items-center gap-2 text-purple-700 font-bold text-xs">
                    <span>🧩</span>
                    <span>C# Attributes Reference</span>
                  </div>
                  <p class="text-[11px] text-gray-600 leading-relaxed">
                    Declarative attributes for native .NET extensions: <code class="font-mono text-purple-700 font-bold">[ExoAction]</code>, <code class="font-mono text-purple-700 font-bold">[ExoEvent]</code>, <code class="font-mono text-purple-700 font-bold">[ExoResource]</code>.
                  </p>
                </div>

                <div class="p-3.5 bg-gray-50 rounded-xl border border-gray-200/80 space-y-1.5">
                  <div class="flex items-center gap-2 text-indigo-700 font-bold text-xs">
                    <span>🏗️</span>
                    <span>Interactive Architecture</span>
                  </div>
                  <p class="text-[11px] text-gray-600 leading-relaxed">
                    Live UML topology diagram, kernel pub/sub bus fanout (&lt; 0.1ms), native process runners, and OTP supervisors.
                  </p>
                </div>

                <div class="p-3.5 bg-gray-50 rounded-xl border border-gray-200/80 space-y-1.5">
                  <div class="flex items-center gap-2 text-emerald-700 font-bold text-xs">
                    <span>⚡</span>
                    <span>Live Dynamic API Reference</span>
                  </div>
                  <p class="text-[11px] text-gray-600 leading-relaxed">
                    Real-time contract explorer dynamically built from registered extensions with copy-pasteable client calling code.
                  </p>
                </div>
              </div>

              <!-- Banner with CTA to full guide extension -->
              <div class="p-4 bg-gradient-to-r from-gray-900 via-primary-950 to-indigo-950 rounded-2xl text-white flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-sm border border-primary-500/20">
                <div class="space-y-0.5 min-w-0">
                  <span class="text-xs font-bold block">Need the comprehensive interactive guide &amp; PDF export?</span>
                  <p class="text-[11px] text-gray-300">Open the full-screen Developer Guide extension tab for deep interactive UML exploration and full code samples.</p>
                </div>
                <button
                  type="button"
                  phx-click="open_guide_from_settings"
                  class="px-4 py-2 bg-white hover:bg-gray-100 text-primary-900 font-bold rounded-xl text-xs transition-colors shrink-0 flex items-center justify-center gap-1.5 shadow-xs"
                >
                  <span>Launch Guide Tab</span>
                  <span>&rarr;</span>
                </button>
              </div>
            </div>
          <% end %>

          <!-- Dynamic Plugin Settings Tab Fallback -->
          <%= if @settings_tab not in ["project", "visual", "console", "database", "auth", "http", "guide"] do %>
            <% active_hook = Enum.find(@settings_hooks, fn h -> to_string(h.id) == @settings_tab end) %>
            <%= if active_hook do %>
              <%= cond do %>
                <% active_hook[:element] || active_hook["element"] || active_hook[:type] == "iframe" -> %>
                  <Exoforge.Std.Dashboard.Microfrontend.render_widget
                    spec={active_hook}
                    context={%{tab: @settings_tab}}
                  />

                <% active_hook[:component] && Code.ensure_loaded?(active_hook[:component]) -> %>
                  <.live_component module={active_hook[:component]} id={"settings_#{active_hook.id}"} />

                <% true -> %>
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
      <.inspect_popup
        open={true}
        icon={(is_map(@extension.dashboard_view) && @extension.dashboard_view[:icon]) || ExtensionPresenter.icon(@extension)}
        title={display_name(@extension)}
        subtitle={"Extension #{@extension.id} (v#{@extension.version})"}
        on_close={@on_close}
        width="max-w-2xl"
      >
        <div class="space-y-4 text-xs">
          <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl border border-gray-200">
            <span class="w-12 h-12 rounded-xl bg-purple-50 text-purple-700 flex items-center justify-center text-2xl">
              <%= (is_map(@extension.dashboard_view) && @extension.dashboard_view[:icon]) || ExtensionPresenter.icon(@extension) %>
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
              <p class="p-3 bg-gray-50 rounded-xl text-gray-400 italic">No actions exposed by this extension.</p>
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
      </.inspect_popup>
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

        <div class="pt-2 text-center text-[10px] text-gray-400 font-mono">
          Exoforge v<%= Exoforge.BuildInfo.version() %> (<%= Exoforge.BuildInfo.commit_hash() %>) • Built <%= Exoforge.BuildInfo.build_date() %>
        </div>
      </div>
    </.modal>
    """
  end

  @doc """
  Renders the Download SDK modal with available SDK packages and installation instructions.
  """
  attr(:open, :boolean, default: false)
  attr(:on_close, :string, default: "close_sdk_modal")

  def sdk_download_modal(assigns) do
    sdk_files =
      if assigns.open do
        case Exoforge.ActionDispatcher.dispatch(:file_bucket, :list_files, %{"bucket" => "sdk"}) do
          {:ok, %{files: files}} when is_list(files) -> files
          _ -> []
        end
      else
        []
      end

    sorted_files =
      Enum.sort_by(sdk_files, fn f ->
        f["created_at"] || f[:created_at] || f["filename"] || ""
      end, :desc)

    latest_file = List.first(sorted_files)
    older_files = Enum.drop(sorted_files, 1)

    assigns =
      assigns
      |> assign(:sdk_files, sorted_files)
      |> assign(:latest_file, latest_file)
      |> assign(:older_files, older_files)

    ~H"""
    <.modal
      id="sdk_download_modal"
      open={@open}
      max_width="max-w-2xl"
      title="Download Engine & Client SDKs"
      subtitle="Connect Unity or custom C# game clients to this Exoforge cluster."
      on_close={@on_close}
    >
      <div class="space-y-4 text-xs">
        <div class="space-y-2.5">
          <div class="flex items-center justify-between">
            <span class="font-bold text-gray-800 uppercase tracking-wider text-[11px]">Available SDK Packages (<%= length(@sdk_files) %>)</span>
            <button
              type="button"
              phx-click="switch_tab"
              phx-value-tab="file_bucket"
              class="text-[11px] font-bold text-primary-600 hover:text-primary-700"
            >
              Open File Bucket &rarr;
            </button>
          </div>

          <%= if @sdk_files == [] do %>
            <div class="bg-gray-50 p-5 rounded-xl border border-gray-200/80 text-center space-y-1.5">
              <p class="font-bold text-gray-800">No SDK packages in the <code class="font-mono">sdk</code> bucket yet</p>
              <p class="text-[11px] text-gray-500">
                Run <code class="font-mono bg-white px-1.5 py-0.5 rounded border">just pack-unity</code> or upload an engine archive to the <code class="font-mono">sdk</code> bucket.
              </p>
            </div>
          <% else %>
            <div class="space-y-2.5">
              <!-- Latest Version (Prominently Shown) -->
              <%= if @latest_file do %>
                <% engine = get_in(@latest_file, ["metadata", "engine"]) || "unity" %>
                <div class="p-3.5 bg-primary-50/50 rounded-xl border border-primary-200/80 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-xs">
                  <div class="space-y-1 min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="px-2 py-0.5 rounded text-[10px] font-bold uppercase bg-primary-600 text-white font-mono shadow-2xs">
                        Latest
                      </span>
                      <span class="px-2 py-0.5 rounded text-[10px] font-bold uppercase bg-white text-primary-800 border border-primary-200 font-mono">
                        <%= engine %>
                      </span>
                      <span class="font-bold text-gray-900 font-mono truncate"><%= @latest_file["filename"] %></span>
                    </div>
                    <p class="text-[11px] text-gray-500 font-mono truncate">
                      URL: <code class="text-gray-700 select-all">/api/files/sdk/<%= engine %></code> &bull; <code class="text-gray-700 select-all"><%= @latest_file["url"] %></code>
                    </p>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <a
                      href={@latest_file["url"]}
                      download={@latest_file["filename"]}
                      target="_blank"
                      class="px-3.5 py-2 bg-primary-600 hover:bg-primary-700 text-white font-bold rounded-lg transition-colors flex items-center gap-1.5 shadow-xs"
                    >
                      <svg class="w-3.5 h-3.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="7 10 12 15 17 10"></polyline>
                        <line x1="12" y1="15" x2="12" y2="3"></line>
                      </svg>
                      <span>Download Latest</span>
                    </a>
                  </div>
                </div>
              <% end %>

              <!-- Older Versions Fold / Accordion -->
              <%= if @older_files != [] do %>
                <details class="group border border-gray-200/80 rounded-xl overflow-hidden bg-gray-50/60">
                  <summary class="p-2.5 px-3.5 flex items-center justify-between cursor-pointer text-[11px] font-bold text-gray-700 hover:text-gray-900 select-none">
                    <div class="flex items-center gap-2">
                      <span class="w-1.5 h-1.5 rounded-full bg-gray-400"></span>
                      <span>Older Versions (<%= length(@older_files) %>)</span>
                    </div>
                    <span class="text-xs text-gray-400 group-open:rotate-180 transition-transform">&darr;</span>
                  </summary>
                  <div class="p-3 border-t border-gray-200/70 space-y-2 max-h-48 overflow-y-auto custom-scrollbar">
                    <%= for file <- @older_files do %>
                      <% engine = get_in(file, ["metadata", "engine"]) || "unity" %>
                      <div class="p-2.5 bg-white rounded-lg border border-gray-200 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
                        <div class="min-w-0 space-y-0.5">
                          <div class="flex items-center gap-2">
                            <span class="px-1.5 py-0.5 rounded text-[9px] font-bold uppercase bg-gray-100 text-gray-600 border border-gray-200 font-mono">
                              <%= engine %>
                            </span>
                            <span class="font-medium text-gray-800 font-mono truncate"><%= file["filename"] %></span>
                          </div>
                          <p class="text-[10px] text-gray-400 font-mono truncate"><%= file["url"] %></p>
                        </div>
                        <a
                          href={file["url"]}
                          download={file["filename"]}
                          target="_blank"
                          class="px-2.5 py-1 bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold rounded text-[11px] transition-colors shrink-0 flex items-center gap-1 self-start sm:self-auto"
                        >
                          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                            <polyline points="7 10 12 15 17 10"></polyline>
                            <line x1="12" y1="15" x2="12" y2="3"></line>
                          </svg>
                          <span>Download</span>
                        </a>
                      </div>
                    <% end %>
                  </div>
                </details>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Installation Instructions -->
        <div class="p-4 bg-gray-50 rounded-xl border border-gray-200/80 space-y-3">
          <span class="font-bold text-gray-800 uppercase tracking-wider text-[11px] block">Installation Instructions</span>

          <div class="space-y-2 text-[11px] text-gray-600">
            <div>
              <span class="font-bold text-gray-800">1. Unity Package Manager (UPM)</span>
              <p class="mt-0.5">Download the <code class="font-mono text-primary-700">com.exoforge.sdk-*.tgz</code> tarball above, then in Unity open <strong>Window &rarr; Package Manager &rarr; + &rarr; Add package from tarball...</strong> and select the downloaded file.</p>
            </div>
            <div>
              <span class="font-bold text-gray-800">2. Configure Cluster Endpoint &amp; Generate Stubs</span>
              <p class="mt-0.5">Open <strong>Exoforge &rarr; Studio</strong> in the Unity Editor toolbar, point the cluster URL to this server, and click <strong>Sync &amp; Generate Stubs</strong>.</p>
            </div>
            <div>
              <span class="font-bold text-gray-800">3. Quick Connect in C#</span>
              <pre class="mt-1 p-2.5 bg-gray-900 text-emerald-300 rounded-lg font-mono text-[10px] overflow-x-auto"><%= "var session = await ExoforgeSDK.Auth.LoginAnonymously();\nawait ExoforgeSDK.ConnectAsync();" %></pre>
            </div>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  @doc """
  Renders the action invocations & telemetry details modal (expand mode for Overview graphs).
  Includes the expanded high-resolution multi-line SVG chart and detailed per-action metrics table.
  """
  attr(:open, :boolean, default: false)
  attr(:mode, :string, default: "actions")
  attr(:search, :string, default: "")
  attr(:filter_tab, :string, default: "all")
  attr(:catalog, :list, default: [])
  attr(:telemetry, :map, default: %{})
  attr(:on_close, :string, default: "close_actions_detail_modal")
  attr(:on_search, :string, default: "search_actions_detail")
  attr(:on_filter_tab, :string, default: "filter_actions_detail_tab")
  attr(:on_run_action, :string, default: "open_action_modal")
  attr(:on_switch_mode, :string, default: "open_actions_detail_modal")

  def actions_detail_modal(assigns) do
    if not assigns.open do
      ~H"""
      """
    else
      telemetry = assigns[:telemetry] || %{}
      catalog = assigns[:catalog] || []

      # Flatten catalog into a list of {svc, act, key}
      all_items =
        for svc <- catalog, act <- (Map.get(svc, :actions) || Map.get(svc, "actions") || []) do
          svc_name = to_string(Map.get(svc, :name) || Map.get(svc, "name") || "")
          act_name = to_string(Map.get(act, :name) || Map.get(act, "name") || "")
          key = "#{svc_name}.#{act_name}"
          invocations = Map.get(telemetry[:action_invocations] || %{}, key, 0)
          errors = Map.get(telemetry[:action_errors] || %{}, key, 0)

          err_rate =
            if invocations > 0 do
              Float.round(errors / invocations * 100, 1)
            else
              0.0
            end

          %{
            service: svc,
            action: act,
            key: key,
            invocations: invocations,
            errors: errors,
            error_rate: err_rate
          }
        end

      q = String.downcase(String.trim(assigns.search || ""))

      filtered =
        all_items
        |> Enum.filter(fn item ->
          if q == "" do
            true
          else
            svc_name = to_string(Map.get(item.service, :name) || Map.get(item.service, "name") || "")
            act_name = to_string(Map.get(item.action, :name) || Map.get(item.action, "name") || "")
            String.contains?(String.downcase(item.key), q) or
              String.contains?(String.downcase(svc_name), q) or
              String.contains?(String.downcase(act_name), q)
          end
        end)
        |> Enum.filter(fn item ->
          case assigns.filter_tab do
            "active" -> item.invocations > 0
            "errors_only" -> item.errors > 0
            _ -> true
          end
        end)
        |> Enum.sort_by(
          fn item ->
            if assigns.mode == "errors" do
              {-item.errors, -item.invocations, item.key}
            else
              {-item.invocations, -item.errors, item.key}
            end
          end
        )

      is_error_mode = assigns.mode == "errors"
      chart_series =
        if is_error_mode do
          Enum.filter(telemetry[:error_series] || [], &((&1[:latest_count] || 0) > 0))
        else
          telemetry[:action_series] || []
        end

      chart_max =
        if is_error_mode do
          telemetry[:error_max_val] || 10
        else
          telemetry[:action_max_val] || 10
        end

      # Expanded 760px wide chart coordinates
      expanded_x_coords = [60, 188, 316, 444, 572, 700]

      expanded_series =
        Enum.map(chart_series, fn s ->
          dots_list = Map.get(s, :dots, [])
          pts =
            for {x, d} <- Enum.zip(expanded_x_coords, dots_list) do
              count = Map.get(d, :count, 0)
              y = 135 - round(count / max(chart_max, 1) * 105)
              {x, max(25, min(135, y))}
            end

          poly_str = Enum.map_join(pts, " ", fn {x, y} -> "#{x},#{y}" end)
          dots = Enum.map(pts, fn {x, y} -> %{x: x, y: y} end)
          Map.merge(s, %{expanded_points: poly_str, expanded_dots: dots})
        end)

      assigns =
        assigns
        |> assign(:items, filtered)
        |> assign(:total_count, length(all_items))
        |> assign(:is_error_mode, is_error_mode)
        |> assign(:chart_max, chart_max)
        |> assign(:expanded_x_coords, expanded_x_coords)
        |> assign(:expanded_series, expanded_series)

      ~H"""
      <div id="actions_detail_modal" class="fixed inset-0 z-50 overflow-y-auto" role="dialog" aria-modal="true">
        <div class="min-h-screen px-4 text-center flex items-center justify-center py-8">
          <!-- Backdrop -->
          <div
            class="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity cursor-pointer"
            phx-click={@on_close}
          ></div>

          <!-- Dialog Box -->
          <div class="relative bg-white dark:bg-gray-900 rounded-2xl max-w-4xl w-full p-6 text-left shadow-2xl border border-gray-200 z-10 animate-fade-in space-y-4">
            <!-- Modal Header with Mode Switcher -->
            <div class="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-gray-100 gap-3">
              <div>
                <h3 class="font-bold text-gray-900 text-base flex items-center gap-2">
                  <span><%= if @is_error_mode, do: "⚠️", else: "📈" %></span>
                  <span><%= if @is_error_mode, do: "Action Exceptions & Error Breakdown", else: "Action Invocations & Telemetry Details" %></span>
                </h3>
                <p class="text-xs text-gray-500 mt-0.5">
                  <%= if @is_error_mode, do: "Expanded error spikes, failure rates, and execution triggers.", else: "Expanded throughput graph and deep telemetry across all monitored cluster actions." %>
                </p>
              </div>

              <div class="flex items-center gap-2">
                <!-- Mode Toggle Pills -->
                <div class="flex items-center p-1 bg-gray-100 rounded-xl text-xs">
                  <button
                    type="button"
                    phx-click={@on_switch_mode}
                    phx-value-mode="actions"
                    class={"px-2.5 py-1 rounded-lg font-bold transition-all flex items-center gap-1 #{if not @is_error_mode, do: "bg-white text-primary-700 shadow-xs", else: "text-gray-500 hover:text-gray-900"}"}
                  >
                    <span>📈 Throughput</span>
                  </button>
                  <button
                    type="button"
                    phx-click={@on_switch_mode}
                    phx-value-mode="errors"
                    class={"px-2.5 py-1 rounded-lg font-bold transition-all flex items-center gap-1 #{if @is_error_mode, do: "bg-white text-red-700 shadow-xs", else: "text-gray-500 hover:text-gray-900"}"}
                  >
                    <span>⚠️ Errors</span>
                  </button>
                </div>

                <button
                  type="button"
                  phx-click={@on_close}
                  class="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-500 flex items-center justify-center transition-colors text-xs font-bold"
                  title="Close Modal (Esc)"
                >
                  ✕
                </button>
              </div>
            </div>

            <!-- EXPANDED HIGH-RESOLUTION SVG GRAPH -->
            <div class="p-3 bg-gray-50/70 rounded-xl border border-gray-200/80 space-y-2">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-gray-700 uppercase tracking-wider text-[10px]">
                  <%= if @is_error_mode, do: "Expanded Error Spikes (Last 25 Minutes)", else: "Expanded Action Throughput (Last 25 Minutes)" %>
                </span>
                <span class="font-mono text-[11px] text-gray-500">
                  Peak: <strong class="text-gray-900"><%= @chart_max %></strong> <%= if @is_error_mode, do: "errors/interval", else: "calls/interval" %>
                </span>
              </div>

              <div class="w-full bg-white rounded-xl p-2.5 border border-gray-200/90 shadow-2xs overflow-hidden">
                <svg viewBox="0 0 760 160" class="w-full h-44 overflow-visible">
                  <!-- Grid horizontal lines & Y-axis labels -->
                  <line x1="50" y1="25" x2="730" y2="25" stroke="#f1f5f9" stroke-width="1" stroke-dasharray="3 3" />
                  <text x="44" y="28" text-anchor="end" font-size="10" font-family="monospace" fill="#94a3b8"><%= @chart_max %></text>

                  <line x1="50" y1="80" x2="730" y2="80" stroke="#f1f5f9" stroke-width="1" stroke-dasharray="3 3" />
                  <text x="44" y="83" text-anchor="end" font-size="10" font-family="monospace" fill="#94a3b8"><%= round(@chart_max / 2) %></text>

                  <line x1="50" y1="135" x2="730" y2="135" stroke="#e2e8f0" stroke-width="1.5" />
                  <text x="44" y="138" text-anchor="end" font-size="10" font-family="monospace" fill="#94a3b8">0</text>

                  <!-- X-axis ticks & Time labels -->
                  <%= for {lbl, x} <- Enum.zip(Map.get(@telemetry, :time_labels, []), @expanded_x_coords) do %>
                    <line x1={x} y1="135" x2={x} y2="140" stroke="#cbd5e1" stroke-width="1" />
                    <text x={x} y="152" text-anchor="middle" font-size="10" font-family="monospace" fill="#94a3b8"><%= lbl %></text>
                  <% end %>

                  <!-- Multi-line series with high-resolution coordinates -->
                  <%= for s <- @expanded_series do %>
                    <polyline
                      fill="none"
                      stroke={Map.get(s, :color, "#8b5cf6")}
                      stroke-width="2.5"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      points={s.expanded_points}
                    />
                    <%= for d <- s.expanded_dots do %>
                      <circle cx={d.x} cy={d.y} r="3.5" fill={Map.get(s, :color, "#8b5cf6")} stroke="#ffffff" stroke-width="1.5" />
                    <% end %>
                  <% end %>
                </svg>
              </div>

              <!-- Expanded Color Legend -->
              <%= if @expanded_series != [] do %>
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5 pt-1 text-[11px]">
                  <%= for s <- @expanded_series do %>
                    <div class="flex items-center gap-1.5">
                      <span class="w-2.5 h-2.5 rounded-full shrink-0 shadow-2xs" style={"background-color: #{Map.get(s, :color, "#8b5cf6")}"}></span>
                      <span class="font-mono text-gray-800 font-semibold"><%= if s[:id] == "idle", do: "Cluster Idle", else: s[:id] %></span>
                      <span class="text-gray-400 font-mono text-[10px]">(<%= s[:latest_count] %> <%= if @is_error_mode, do: "errors", else: "calls" %>)</span>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="flex items-center gap-2 pt-1 text-xs text-emerald-600 font-semibold">
                  <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
                  <span>Zero errors detected across all monitored actions.</span>
                </div>
              <% end %>
            </div>

            <!-- Controls: Search and Filter Tabs -->
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-2 text-xs">
              <div class="flex items-center gap-1.5 p-1 bg-gray-100 rounded-xl">
                <button
                  type="button"
                  phx-click={@on_filter_tab}
                  phx-value-tab="all"
                  class={"px-3 py-1.5 rounded-lg font-bold text-xs transition-colors #{if @filter_tab == "all", do: "bg-white text-gray-900 shadow-xs", else: "text-gray-500 hover:text-gray-900"}"}
                >
                  All (<%= @total_count %>)
                </button>
                <button
                  type="button"
                  phx-click={@on_filter_tab}
                  phx-value-tab="active"
                  class={"px-3 py-1.5 rounded-lg font-bold text-xs transition-colors #{if @filter_tab == "active", do: "bg-white text-emerald-700 shadow-xs", else: "text-gray-500 hover:text-gray-900"}"}
                >
                  Active Traffic
                </button>
                <button
                  type="button"
                  phx-click={@on_filter_tab}
                  phx-value-tab="errors_only"
                  class={"px-3 py-1.5 rounded-lg font-bold text-xs transition-colors #{if @filter_tab == "errors_only", do: "bg-white text-red-700 shadow-xs", else: "text-gray-500 hover:text-gray-900"}"}
                >
                  With Errors
                </button>
              </div>

              <form id="actions_detail_search_form" phx-change={@on_search} class="m-0">
                <input
                  type="text"
                  name="query"
                  value={@search}
                  placeholder="Filter actions by name or service..."
                  class="w-full sm:w-64 px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-xl text-xs placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-primary-500 font-mono"
                />
              </form>
            </div>

            <!-- Actions Table -->
            <div class="max-h-72 overflow-y-auto border border-gray-200 rounded-xl custom-scrollbar text-xs">
              <%= if Enum.empty?(@items) do %>
                <div class="p-8 text-center text-gray-400">
                  <p>No actions match your search or filter.</p>
                </div>
              <% else %>
                <table class="w-full text-left border-collapse">
                  <thead class="bg-gray-50 sticky top-0 border-b border-gray-200 text-[10px] font-bold text-gray-400 uppercase tracking-wider">
                    <tr>
                      <th class="py-2.5 px-3">Service &amp; Action</th>
                      <th class="py-2.5 px-3">Scope / Transport</th>
                      <th class="py-2.5 px-3 text-right">Invocations</th>
                      <th class="py-2.5 px-3 text-right">Errors</th>
                      <th class="py-2.5 px-3 text-right">Error Rate</th>
                      <th class="py-2.5 px-3 text-right">Action</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-100 text-xs">
                    <%= for item <- @items do %>
                      <tr class="hover:bg-gray-50/80 transition-colors">
                        <td class="py-2.5 px-3">
                          <div class="flex items-center gap-2">
                            <span class="w-6 h-6 rounded-md bg-purple-50 text-purple-700 flex items-center justify-center text-xs shrink-0">
                              <%= Map.get(item.service, :icon) || "⚡" %>
                            </span>
                            <div class="min-w-0">
                              <span class="font-bold text-gray-900 font-mono block truncate"><%= item.key %></span>
                              <span class="text-[10px] text-gray-400 block"><%= Map.get(item.service, :title) || Map.get(item.service, :name, "") %></span>
                            </div>
                          </div>
                        </td>
                        <td class="py-2.5 px-3">
                          <div class="flex items-center gap-1.5">
                            <span class="px-1.5 py-0.5 rounded text-[10px] font-mono bg-gray-100 text-gray-600">
                              <%= Map.get(item.action, :scope) || "player" %>
                            </span>
                            <span class="px-1.5 py-0.5 rounded text-[10px] font-mono bg-gray-100 text-gray-600">
                              <%= Map.get(item.action, :transport) || "auto" %>
                            </span>
                          </div>
                        </td>
                        <td class="py-2.5 px-3 text-right font-mono font-bold text-gray-800">
                          <%= item.invocations %>
                        </td>
                        <td class={"py-2.5 px-3 text-right font-mono font-bold #{if item.errors > 0, do: "text-red-600", else: "text-gray-400"}"}>
                          <%= item.errors %>
                        </td>
                        <td class="py-2.5 px-3 text-right font-mono text-[11px]">
                          <%= if item.error_rate > 0 do %>
                            <span class="text-red-600 font-bold"><%= item.error_rate %>%</span>
                          <% else %>
                            <span class="text-emerald-600">0%</span>
                          <% end %>
                        </td>
                        <td class="py-2.5 px-3 text-right">
                          <button
                            type="button"
                            phx-click={@on_run_action}
                            phx-value-service={to_string(Map.get(item.service, :name, ""))}
                            phx-value-action={to_string(Map.get(item.action, :name, ""))}
                            class="px-2.5 py-1 text-[11px] font-bold text-primary-700 bg-primary-50 hover:bg-primary-100 rounded-lg transition-colors inline-flex items-center gap-1 shadow-2xs"
                          >
                            <span>⚡ Run</span>
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      """
    end
  end

  @doc """
  Renders the full cluster events history modal ("More" button on Latest Dispatched Events).
  """
  attr(:open, :boolean, default: false)
  attr(:events, :list, default: [])
  attr(:paused, :boolean, default: false)
  attr(:filter_topic, :string, default: "")
  attr(:on_close, :string, default: "close_events_modal")
  attr(:on_pause, :string, default: "toggle_event_pause")
  attr(:on_clear, :string, default: "clear_events")
  attr(:on_filter, :string, default: "filter_event_dock")
  attr(:on_simulate, :string, default: "simulate_test_event")

  def events_modal(assigns) do
    ~H"""
    <%= if @open do %>
      <div id="events_history_modal" class="fixed inset-0 z-50 overflow-y-auto" role="dialog" aria-modal="true">
        <div class="min-h-screen px-4 text-center flex items-center justify-center py-8">
          <!-- Backdrop -->
          <div
            class="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
            phx-click={@on_close}
          ></div>

          <!-- Dialog Box -->
          <div class="relative bg-white rounded-2xl max-w-3xl w-full p-6 text-left shadow-2xl border border-gray-200 z-10 animate-fade-in space-y-4">
            <div class="flex items-center justify-between pb-3 border-b border-gray-100">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-xl bg-purple-50 text-purple-700 flex items-center justify-center font-bold text-sm">
                  📡
                </div>
                <div>
                  <h3 class="font-bold text-gray-900 text-base">Cluster Event Stream &amp; History</h3>
                  <p class="text-xs text-gray-500">Live pub/sub stream captured across all nodes via EventDispatcher (:pg)</p>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class="px-2 py-0.5 rounded-full bg-gray-100 font-mono font-bold text-[10px] text-gray-600 border border-gray-200">
                  <%= length(@events) %> captured
                </span>
                <button
                  type="button"
                  phx-click={@on_close}
                  class="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-500 flex items-center justify-center transition-colors text-xs font-bold"
                  title="Close Modal (Esc)"
                >
                  ✕
                </button>
              </div>
            </div>

            <!-- Controls Toolbar -->
            <div class="flex flex-wrap items-center justify-between gap-2 p-2.5 bg-gray-50 rounded-xl border border-gray-200/80 text-xs">
              <form id="events_modal_filter_form" phx-change={@on_filter} class="m-0">
                <input
                  type="text"
                  name="topic"
                  value={@filter_topic}
                  placeholder="Filter event or payload..."
                  class="px-2.5 py-1 bg-white border border-gray-300 rounded-lg text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-primary-500 w-44 sm:w-64 font-mono"
                />
              </form>

              <div class="flex items-center gap-1.5">
                <button
                  type="button"
                  phx-click={@on_pause}
                  class={"px-2.5 py-1 rounded-lg font-bold text-xs flex items-center gap-1 transition-colors #{if @paused, do: "bg-emerald-600 hover:bg-emerald-500 text-white", else: "bg-white hover:bg-gray-100 text-gray-700 border border-gray-200"}"}
                >
                  <%= if @paused, do: "▶ Resume", else: "⏸ Pause" %>
                </button>

                <button
                  type="button"
                  phx-click={@on_clear}
                  class="px-2.5 py-1 bg-white hover:bg-gray-100 text-gray-600 border border-gray-200 rounded-lg font-bold text-xs transition-colors"
                >
                  Clear
                </button>
              </div>
            </div>

            <!-- Events List Window -->
            <div class="bg-gray-950 rounded-xl p-3.5 border border-gray-800 text-gray-100 max-h-96 overflow-y-auto space-y-2 font-mono text-xs custom-scrollbar">
              <%= if Enum.empty?(@events) do %>
                <div class="py-10 flex flex-col items-center justify-center text-center space-y-1.5">
                  <span class="text-2xl">📡</span>
                  <p class="text-xs text-gray-400 font-sans">No cluster events captured yet.</p>
                  <p class="text-[11px] text-gray-500 font-sans">Dispatch an action, log in, or upload a file to see live events stream in real time.</p>
                </div>
              <% else %>
                <%= for ev <- @events do %>
                  <div class="p-2.5 bg-gray-900/90 rounded-lg border border-gray-800/80 flex flex-col gap-1.5 hover:border-gray-700 transition-colors">
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
                    <pre class="text-[10px] text-emerald-400 overflow-x-auto p-2 bg-black/60 rounded border border-gray-800/60 font-mono"><%= Jason.encode!(ev.payload, pretty: true) %></pre>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp display_name(ext_or_id), do: ExtensionPresenter.display_name(ext_or_id)

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
