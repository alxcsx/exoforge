defmodule Exoforge.Std.DashboardViews.AuthView do
  @moduledoc """
  Phoenix LiveComponent providing the dynamic Producer & Designer Studio visualization
  for the Authentication and Identity service (:auth).
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       users: [],
       filtered_users: [],
       search_query: "",
       scope_filter: "all",
       show_register_modal: false,
       issued_token_info: nil,
       selected_user: nil,
       register_form: %{
         "player_id" => "",
         "name" => "",
         "email" => "",
         "scopes" => "player"
       },
       error_message: nil,
       loaded: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.loaded do
        socket
      else
        socket
        |> assign(:loaded, true)
        |> load_users()
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(search_query: query)
      |> apply_filters()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_scope", %{"scope" => scope}, socket) do
    socket =
      socket
      |> assign(scope_filter: scope)
      |> apply_filters()

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_users(socket)}
  end

  @impl true
  def handle_event("open_register_modal", _params, socket) do
    default_id = "p_#{System.unique_integer([:positive]) |> rem(100_000)}"

    {:noreply,
     assign(socket,
       show_register_modal: true,
       error_message: nil,
       register_form: %{
         "player_id" => default_id,
         "name" => "",
         "email" => "",
         "scopes" => "player"
       }
     )}
  end

  @impl true
  def handle_event("close_register_modal", _params, socket) do
    {:noreply, assign(socket, show_register_modal: false, error_message: nil)}
  end

  @impl true
  def handle_event("change_register_form", %{"register" => params}, socket) do
    {:noreply, assign(socket, register_form: Map.merge(socket.assigns.register_form, params))}
  end

  @impl true
  def handle_event("submit_register", %{"register" => params}, socket) do
    player_id = String.trim(Map.get(params, "player_id", ""))
    name = String.trim(Map.get(params, "name", ""))
    email = String.trim(Map.get(params, "email", ""))
    raw_scopes = String.trim(Map.get(params, "scopes", "player"))

    scopes =
      raw_scopes
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    payload = %{
      player_id: if(player_id != "", do: player_id, else: nil),
      name: if(name != "", do: name, else: nil),
      email: if(email != "", do: email, else: nil),
      scopes: if(scopes != [], do: scopes, else: ["player"])
    }

    case ActionDispatcher.dispatch(:auth, :register, payload) do
      {:ok, result} ->
        socket =
          socket
          |> assign(
            show_register_modal: false,
            error_message: nil,
            issued_token_info: %{
              player_id: result.player_id,
              token: result.token,
              scopes: result.scopes
            }
          )
          |> load_users()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Registration failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("issue_token", %{"player_id" => player_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1["player_id"] == player_id))
    scopes = if user, do: user["scopes"], else: ["player"]

    case ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: player_id, scopes: scopes}) do
      {:ok, result} ->
        socket =
          socket
          |> assign(
            issued_token_info: %{
              player_id: result.player_id,
              token: result.token,
              scopes: scopes
            }
          )
          |> load_users()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Failed to issue token: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("dismiss_token_banner", _params, socket) do
    {:noreply, assign(socket, issued_token_info: nil)}
  end

  @impl true
  def handle_event("inspect_user", %{"player_id" => player_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1["player_id"] == player_id))
    {:noreply, assign(socket, selected_user: user)}
  end

  @impl true
  def handle_event("close_user_drawer", _params, socket) do
    {:noreply, assign(socket, selected_user: nil)}
  end

  ## ---- PRIVATE HELPERS ----

  defp load_users(socket) do
    case ActionDispatcher.dispatch(:auth, :list_users, %{}) do
      {:ok, %{users: users}} ->
        socket
        |> assign(users: users)
        |> apply_filters()

      _ ->
        socket
        |> assign(users: [])
        |> apply_filters()
    end
  end

  defp apply_filters(socket) do
    query = String.downcase(String.trim(socket.assigns.search_query))
    filter = socket.assigns.scope_filter

    filtered =
      Enum.filter(socket.assigns.users, fn user ->
        pid = String.downcase(to_string(user["player_id"] || ""))
        scopes = Enum.map(user["scopes"] || [], &to_string/1)

        matches_query =
          query == "" or
            String.contains?(pid, query) or
            Enum.any?(scopes, &String.contains?(String.downcase(&1), query))

        matches_filter =
          filter == "all" or Enum.member?(scopes, filter)

        matches_query and matches_filter
      end)

    assign(socket, filtered_users: filtered)
  end

  ## ---- TEMPLATE RENDERING ----

  @impl true
  def render(assigns) do
    total_users = length(assigns.users)
    total_tokens = Enum.sum(Enum.map(assigns.users, & &1["tokens_count"]))
    admin_count = Enum.count(assigns.users, &("admin" in &1["scopes"]))
    player_count = Enum.count(assigns.users, &("player" in &1["scopes"]))

    assigns =
      assigns
      |> assign(:total_users, total_users)
      |> assign(:total_tokens, total_tokens)
      |> assign(:admin_count, admin_count)
      |> assign(:player_count, player_count)

    ~H"""
    <div class="space-y-6" id={@id}>
      <!-- Top Header & Actions -->
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200/80 shadow-sm">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-2xl bg-purple-100 text-purple-700 flex items-center justify-center text-2xl shadow-inner">
            🛡️
          </div>
          <div>
            <div class="flex items-center gap-3">
              <h2 class="text-xl font-bold text-gray-900">Users & Authentication</h2>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-800">
                Extension Live
              </span>
            </div>
            <p class="text-sm text-gray-500 mt-0.5">
              Inspect registered accounts, manage security scopes, and issue bearer tokens for client sessions.
            </p>
          </div>
        </div>

        <div class="flex items-center gap-3">
          <button
            phx-click="refresh"
            phx-target={@myself}
            class="px-3.5 py-2 text-sm font-semibold text-gray-700 bg-white border border-gray-300 rounded-xl hover:bg-gray-50 transition-colors shadow-sm flex items-center gap-2"
          >
            <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>
          <button
            phx-click="open_register_modal"
            phx-target={@myself}
            class="px-4 py-2 text-sm font-semibold text-white bg-purple-600 rounded-xl hover:bg-purple-700 transition-colors shadow-sm flex items-center gap-2"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            Register User
          </button>
        </div>
      </div>

      <!-- Issued Token Alert Banner -->
      <%= if @issued_token_info do %>
        <div class="bg-gradient-to-r from-purple-50 to-indigo-50 border border-purple-200 rounded-2xl p-5 shadow-sm">
          <div class="flex items-start justify-between">
            <div class="flex items-start gap-3">
              <div class="w-8 h-8 rounded-lg bg-purple-600 text-white flex items-center justify-center font-bold text-sm shrink-0 mt-0.5">
                🔑
              </div>
              <div class="space-y-1">
                <h4 class="text-sm font-bold text-purple-950">
                  New Bearer Token Generated for <span class="font-mono text-purple-700"><%= @issued_token_info.player_id %></span>
                </h4>
                <p class="text-xs text-purple-700">
                  Save this token securely. It grants client authentication with scopes:
                  <span class="font-semibold"><%= Enum.join(@issued_token_info.scopes, ", ") %></span>.
                </p>
                <div class="mt-2 flex items-center gap-2">
                  <input
                    type="text"
                    readonly
                    value={@issued_token_info.token}
                    class="font-mono text-xs bg-white text-gray-800 border border-purple-300 rounded-lg px-3 py-1.5 w-full max-w-xl shadow-inner select-all"
                  />
                  <button
                    phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: @issued_token_info.token})}
                    class="text-xs font-semibold px-3 py-1.5 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors shadow-sm"
                  >
                    Copy
                  </button>
                </div>
              </div>
            </div>
            <button
              phx-click="dismiss_token_banner"
              phx-target={@myself}
              class="text-purple-400 hover:text-purple-700 text-sm font-bold p-1"
            >
              ✕
            </button>
          </div>
        </div>
      <% end %>

      <!-- Metric Cards Grid -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-5">
        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Registered Accounts</span>
            <span class="text-lg">👥</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @total_users %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-purple-50 text-purple-700">Auth DB</span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Distinct identity profiles</p>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Active Tokens</span>
            <span class="text-lg">🎟️</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @total_tokens %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-emerald-50 text-emerald-700">In Pool</span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Active bearer tokens</p>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Admin Roles</span>
            <span class="text-lg">👑</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @admin_count %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-amber-50 text-amber-700">Elevated</span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Admin & superuser scopes</p>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Player Scopes</span>
            <span class="text-lg">🎮</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-black text-gray-900"><%= @player_count %></span>
            <span class="text-xs font-bold px-1.5 py-0.5 rounded-md bg-blue-50 text-blue-700">Standard</span>
          </div>
          <p class="text-[11px] text-gray-400 mt-1 font-medium">Verified gameplay accounts</p>
        </div>
      </div>

      <!-- Filters & Search Toolbar -->
      <div class="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div class="flex items-center gap-3 flex-1 max-w-md">
          <div class="relative w-full">
            <input
              type="text"
              placeholder="Search user ID or scope..."
              value={@search_query}
              phx-input="search"
              phx-target={@myself}
              phx-debounce="200"
              name="query"
              class="w-full pl-9 pr-4 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white transition-all"
            />
            <svg class="w-4 h-4 text-gray-400 absolute left-3 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider mr-1">Scope:</span>
          <%= for {label, key} <- [{"All", "all"}, {"Admin", "admin"}, {"Player", "player"}, {"Guest", "guest"}] do %>
            <button
              phx-click="filter_scope"
              phx-value-scope={key}
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors #{if @scope_filter == key, do: "bg-purple-600 text-white shadow-sm", else: "bg-gray-100 text-gray-600 hover:bg-gray-200"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>
      </div>

      <!-- Users Directory Table -->
      <div class="bg-white rounded-2xl border border-gray-200/80 shadow-sm overflow-hidden">
        <%= if @filtered_users == [] do %>
          <div class="p-12 text-center">
            <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl mb-3">
              🔍
            </div>
            <h3 class="text-sm font-bold text-gray-900">No accounts found</h3>
            <p class="text-xs text-gray-500 mt-1 max-w-sm mx-auto">
              <%= if @users == [] do %>
                No user identities have been registered in the auth database yet. Click "Register User" above to create the first account.
              <% else %>
                No accounts match the search query or scope filter. Try clearing your filters.
              <% end %>
            </p>
            <%= if @users == [] do %>
              <button
                phx-click="open_register_modal"
                phx-target={@myself}
                class="mt-4 px-4 py-2 text-xs font-semibold text-white bg-purple-600 rounded-xl hover:bg-purple-700 transition-colors shadow-sm inline-flex items-center gap-1.5"
              >
                + Register First User
              </button>
            <% end %>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="bg-gray-50/75 border-b border-gray-200 text-[11px] font-bold text-gray-500 uppercase tracking-wider">
                  <th class="py-3 px-4">Player ID</th>
                  <th class="py-3 px-4">Assigned Scopes</th>
                  <th class="py-3 px-4">Active Tokens</th>
                  <th class="py-3 px-4">Status</th>
                  <th class="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 text-sm">
                <%= for user <- @filtered_users do %>
                  <tr class="hover:bg-purple-50/30 transition-colors group">
                    <td class="py-3.5 px-4">
                      <div class="flex items-center gap-2">
                        <span class="font-mono font-bold text-gray-900"><%= user["player_id"] %></span>
                        <button
                          phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: user["player_id"]})}
                          title="Copy Player ID"
                          class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-purple-600 transition-opacity text-xs"
                        >
                          📋
                        </button>
                      </div>
                    </td>
                    <td class="py-3.5 px-4">
                      <div class="flex flex-wrap gap-1.5">
                        <%= for scope <- user["scopes"] || [] do %>
                          <span class={"inline-flex items-center px-2 py-0.5 rounded-md text-xs font-semibold #{case scope do
                            "admin" -> "bg-purple-100 text-purple-800 border border-purple-200"
                            "player" -> "bg-emerald-100 text-emerald-800 border border-emerald-200"
                            "guest" -> "bg-gray-100 text-gray-800 border border-gray-200"
                            _ -> "bg-blue-100 text-blue-800 border border-blue-200"
                          end}"}>
                            <%= scope %>
                          </span>
                        <% end %>
                      </div>
                    </td>
                    <td class="py-3.5 px-4">
                      <div class="flex items-center gap-2">
                        <span class="inline-flex items-center justify-center px-2 py-0.5 rounded-full text-xs font-bold bg-gray-100 text-gray-700">
                          <%= user["tokens_count"] %> tokens
                        </span>
                      </div>
                    </td>
                    <td class="py-3.5 px-4">
                      <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700">
                        <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
                        <%= user["status"] || "Active" %>
                      </span>
                    </td>
                    <td class="py-3.5 px-4 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <button
                          phx-click="issue_token"
                          phx-value-player_id={user["player_id"]}
                          phx-target={@myself}
                          title="Issue new token"
                          class="px-2.5 py-1 text-xs font-semibold text-purple-700 bg-purple-50 hover:bg-purple-100 border border-purple-200 rounded-lg transition-colors"
                        >
                          + Issue Token
                        </button>
                        <button
                          phx-click="inspect_user"
                          phx-value-player_id={user["player_id"]}
                          phx-target={@myself}
                          title="View tokens & details"
                          class="px-2.5 py-1 text-xs font-semibold text-gray-700 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg transition-colors"
                        >
                          Inspect
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <!-- Register User Modal -->
      <%= if @show_register_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_register_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-5">
              <div class="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center text-xl">
                👤
              </div>
              <div>
                <h3 class="text-lg font-bold text-gray-900">Register New User Account</h3>
                <p class="text-xs text-gray-500">Creates an identity credential in the Auth database and canonical profile store.</p>
              </div>
            </div>

            <%= if @error_message do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @error_message %>
              </div>
            <% end %>

            <form phx-submit="submit_register" phx-change="change_register_form" phx-target={@myself} class="space-y-4">
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Player ID</label>
                <input
                  type="text"
                  name="register[player_id]"
                  value={@register_form["player_id"]}
                  placeholder="e.g. p_94812 (leave blank to auto-generate)"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white font-mono"
                />
              </div>

              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Display Name</label>
                  <input
                    type="text"
                    name="register[name]"
                    value={@register_form["name"]}
                    placeholder="e.g. ShadowBlade"
                    class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white"
                  />
                </div>
                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Email</label>
                  <input
                    type="email"
                    name="register[email]"
                    value={@register_form["email"]}
                    placeholder="e.g. player@domain.com"
                    class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white"
                  />
                </div>
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Authorization Scopes</label>
                <input
                  type="text"
                  name="register[scopes]"
                  value={@register_form["scopes"]}
                  placeholder="player, admin, guest (comma separated)"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white font-mono"
                />
                <p class="text-[11px] text-gray-400 mt-1">Comma-separated list of scopes. Default is "player".</p>
              </div>

              <div class="pt-4 flex items-center justify-end gap-3 border-t border-gray-100">
                <button
                  type="button"
                  phx-click="close_register_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-5 py-2 text-xs font-bold text-white bg-purple-600 rounded-xl hover:bg-purple-700 transition-colors shadow-sm"
                >
                  Create Account & Issue Token
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- User Inspection Slide-over Drawer -->
      <%= if @selected_user do %>
        <div class="fixed inset-0 z-50 overflow-hidden bg-black/30 backdrop-blur-xs flex justify-end">
          <div class="bg-white w-full max-w-md h-full shadow-2xl border-l border-gray-200 p-6 flex flex-col justify-between overflow-y-auto animate-in slide-in-from-right duration-200">
            <div>
              <div class="flex items-center justify-between pb-4 border-b border-gray-100">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center font-bold text-lg">
                    👤
                  </div>
                  <div>
                    <h3 class="text-base font-bold text-gray-900 font-mono"><%= @selected_user["player_id"] %></h3>
                    <p class="text-xs text-gray-500">Identity details & security tokens</p>
                  </div>
                </div>
                <button
                  phx-click="close_user_drawer"
                  phx-target={@myself}
                  class="text-gray-400 hover:text-gray-600 text-lg font-bold p-1"
                >
                  ✕
                </button>
              </div>

              <div class="mt-5 space-y-5">
                <div>
                  <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Granted Scopes</h4>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for scope <- @selected_user["scopes"] || [] do %>
                      <span class={"inline-flex items-center px-2.5 py-1 rounded-md text-xs font-semibold #{case scope do
                        "admin" -> "bg-purple-100 text-purple-800 border border-purple-200"
                        "player" -> "bg-emerald-100 text-emerald-800 border border-emerald-200"
                        "guest" -> "bg-gray-100 text-gray-800 border border-gray-200"
                        _ -> "bg-blue-100 text-blue-800 border border-blue-200"
                      end}"}>
                        <%= scope %>
                      </span>
                    <% end %>
                  </div>
                </div>

                <div>
                  <div class="flex items-center justify-between mb-2">
                    <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Active Bearer Tokens</h4>
                    <button
                      phx-click="issue_token"
                      phx-value-player_id={@selected_user["player_id"]}
                      phx-target={@myself}
                      class="text-xs font-semibold text-purple-600 hover:text-purple-800"
                    >
                      + Generate Token
                    </button>
                  </div>

                  <%= if (@selected_user["active_tokens"] || []) == [] do %>
                    <p class="text-xs text-gray-400 italic bg-gray-50 p-3 rounded-xl border border-gray-200">
                      No active tokens found for this account.
                    </p>
                  <% else %>
                    <div class="space-y-2">
                      <%= for token <- @selected_user["active_tokens"] do %>
                        <div class="p-2.5 bg-gray-50 rounded-xl border border-gray-200 flex items-center justify-between">
                          <span class="font-mono text-xs text-gray-800 truncate mr-2 select-all"><%= token %></span>
                          <button
                            phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: token})}
                            title="Copy Token"
                            class="text-xs text-purple-600 hover:text-purple-800 font-bold shrink-0"
                          >
                            Copy
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="pt-4 border-t border-gray-100">
              <button
                phx-click="close_user_drawer"
                phx-target={@myself}
                class="w-full py-2 text-xs font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
              >
                Close Drawer
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

defmodule Exoforge.Std.Dashboard.Views.AuthView do
  @moduledoc false
  use Phoenix.LiveComponent
  def render(assigns), do: Exoforge.Std.DashboardViews.AuthView.render(assigns)
  def mount(socket), do: Exoforge.Std.DashboardViews.AuthView.mount(socket)
  def update(assigns, socket), do: Exoforge.Std.DashboardViews.AuthView.update(assigns, socket)
  def handle_event(event, params, socket), do: Exoforge.Std.DashboardViews.AuthView.handle_event(event, params, socket)
end
