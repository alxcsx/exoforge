defmodule Exoforge.Std.DashboardViews.PlayerDataView do
  @moduledoc """
  Phoenix LiveComponent providing the dynamic Producer & Designer Studio visualization
  for the Player Profiles & LiveOps Data service (:player_data).

  Interacts strictly via service contracts and ActionDispatcher without depending
  on any concrete module implementation.
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       players: [],
       filtered_players: [],
       search_query: "",
       selected_player: nil,
       selected_player_id: nil,
       selected_tab: "profile",
       show_create_modal: false,
       create_error: nil,
       create_form: %{
         "player_id" => "",
         "profile_json" => "{\n  \"level\": 1,\n  \"coins\": 100,\n  \"tier\": \"rookie\"\n}"
       },
       edit_profile_raw: "",
       edit_error: nil,
       action_notification: nil,
       loading: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if connected?(socket) and (socket.assigns.players == [] or assigns[:refresh] == true) do
        load_players(socket)
      else
        socket
      end

    {:ok, socket}
  end

  ## ---- EVENT HANDLERS ----

  @impl true
  def handle_event("refresh_players", _params, socket) do
    {:noreply, load_players(socket)}
  end

  @impl true
  def handle_event("search_players", %{"query" => query}, socket) do
    q = String.trim(query) |> String.downcase()
    filtered = filter_players(socket.assigns.players, q)
    {:noreply, assign(socket, search_query: query, filtered_players: filtered)}
  end

  @impl true
  def handle_event("select_player", %{"id" => id}, socket) do
    player = Enum.find(socket.assigns.players, fn p -> to_string(p["player_id"] || p[:player_id]) == id end)

    raw_json =
      if player do
        Jason.encode!(player, pretty: true)
      else
        ""
      end

    {:noreply,
     assign(socket,
       selected_player: player,
       selected_player_id: id,
       edit_profile_raw: raw_json,
       edit_error: nil,
       action_notification: nil
     )}
  end

  @impl true
  def handle_event("close_player_drawer", _params, socket) do
    {:noreply, assign(socket, selected_player: nil, selected_player_id: nil, edit_error: nil)}
  end

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_modal: true,
       create_error: nil,
       create_form: %{
         "player_id" => "player_#{System.system_time(:second) |> rem(10000)}",
         "profile_json" => "{\n  \"level\": 1,\n  \"coins\": 250,\n  \"tier\": \"explorer\"\n}"
       }
     )}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false, create_error: nil)}
  end

  @impl true
  def handle_event("change_create_form", %{"create" => params}, socket) do
    merged = Map.merge(socket.assigns.create_form, params)
    {:noreply, assign(socket, create_form: merged)}
  end

  @impl true
  def handle_event("submit_create_player", %{"create" => params}, socket) do
    id = String.trim(Map.get(params, "player_id", ""))
    raw_json = String.trim(Map.get(params, "profile_json", "{}"))

    cond do
      id == "" ->
        {:noreply, assign(socket, create_error: "Player ID is required.")}

      true ->
        case Jason.decode(raw_json) do
          {:ok, profile_map} when is_map(profile_map) ->
            case ActionDispatcher.dispatch(:player_data, :create_player, %{
                   player_id: id,
                   profile: profile_map
                 }) do
              {:ok, _result} ->
                socket =
                  socket
                  |> assign(show_create_modal: false, create_error: nil)
                  |> load_players()
                  |> assign(action_notification: "Player '#{id}' successfully created!")

                {:noreply, socket}

              {:error, reason} ->
                {:noreply, assign(socket, create_error: "Creation failed: #{inspect(reason)}")}
            end

          _ ->
            {:noreply, assign(socket, create_error: "Invalid JSON format in profile data.")}
        end
    end
  end

  @impl true
  def handle_event("save_player_profile", %{"profile_raw" => raw_json}, socket) do
    player_id = socket.assigns.selected_player_id

    case Jason.decode(raw_json) do
      {:ok, parsed} when is_map(parsed) ->
        case ActionDispatcher.dispatch(:player_data, :update_player, %{
               player_id: player_id,
               data: parsed
             }) do
          {:ok, %{player: updated}} ->
            socket =
              socket
              |> assign(
                selected_player: updated,
                edit_profile_raw: Jason.encode!(updated, pretty: true),
                edit_error: nil,
                action_notification: "Profile updated successfully!"
              )
              |> load_players()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, edit_error: "Update failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, assign(socket, edit_error: "Invalid JSON. Please correct the syntax.")}
    end
  end

  @impl true
  def handle_event("delete_player", %{"id" => player_id}, socket) do
    case ActionDispatcher.dispatch(:player_data, :delete_player, %{player_id: player_id}) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            selected_player: nil,
            selected_player_id: nil,
            action_notification: "Player '#{player_id}' removed."
          )
          |> load_players()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, action_notification: "Delete failed: #{inspect(reason)}")}
    end
  end

  ## ---- PRIVATE HELPERS ----

  defp load_players(socket) do
    players =
      case ActionDispatcher.dispatch(:player_data, :list_players, %{}) do
        {:ok, %{players: list}} when is_list(list) -> list
        {:ok, %{rows: list}} when is_list(list) -> list
        _ -> []
      end

    filtered = filter_players(players, socket.assigns.search_query)

    assign(socket,
      players: players,
      filtered_players: filtered,
      loading: false
    )
  end

  defp filter_players(players, query) do
    if query == "" do
      players
    else
      Enum.filter(players, fn p ->
        id = to_string(p["player_id"] || p[:player_id] || "")
        data_str = inspect(p)
        String.contains?(String.downcase(id), query) or String.contains?(String.downcase(data_str), query)
      end)
    end
  end

  ## ---- RENDER ----

  @impl true
  def render(assigns) do
    ~H"""
    <div id="player_data_dashboard_view" class="space-y-6">
      <!-- Action Notification Banner -->
      <%= if @action_notification do %>
        <div class="p-3 bg-emerald-50 border border-emerald-200 rounded-xl text-xs text-emerald-800 font-medium flex items-center justify-between animate-in fade-in duration-150">
          <div class="flex items-center gap-2">
            <span>✨</span>
            <span><%= @action_notification %></span>
          </div>
          <button phx-click="dismiss_notification" phx-target={@myself} class="text-emerald-500 hover:text-emerald-700">✕</button>
        </div>
      <% end %>

      <!-- Top Stats & Header -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Registered Players</p>
            <p class="text-2xl font-bold text-gray-900 mt-1"><%= length(@players) %></p>
          </div>
          <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-700 flex items-center justify-center text-lg">
            👥
          </div>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Storage Engine</p>
            <p class="text-lg font-bold text-emerald-600 mt-1">Isolated Schema</p>
          </div>
          <div class="w-10 h-10 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center text-lg">
            🛡️
          </div>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Lifecycle Events</p>
            <p class="text-lg font-bold text-blue-600 mt-1">:player_created, :player_deleted</p>
          </div>
          <div class="w-10 h-10 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center text-lg">
            📡
          </div>
        </div>
      </div>

      <!-- Action Toolbar -->
      <div class="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm flex flex-col md:flex-row items-center justify-between gap-4">
        <div class="relative flex-1 w-full">
          <input
            type="text"
            placeholder="Search players by ID or JSON attributes..."
            value={@search_query}
            phx-keyup="search_players"
            phx-target={@myself}
            class="w-full pl-9 pr-4 py-2 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white transition-all"
          />
          <svg class="w-4 h-4 text-gray-400 absolute left-3 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>

        <div class="flex items-center gap-2 w-full md:w-auto justify-end">
          <button
            phx-click="refresh_players"
            phx-target={@myself}
            class="px-3.5 py-2 text-xs font-semibold text-gray-700 bg-white hover:bg-gray-50 rounded-xl border border-gray-200 transition-colors flex items-center gap-2 shadow-sm"
          >
            <svg class="w-3.5 h-3.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>
          <button
            phx-click="open_create_modal"
            phx-target={@myself}
            class="px-4 py-2 text-xs font-semibold text-white bg-violet-600 hover:bg-violet-700 rounded-xl transition-colors shadow-sm flex items-center gap-2"
          >
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            New Player Profile
          </button>
        </div>
      </div>

      <!-- Players List Table -->
      <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
        <div class="p-4 border-b border-gray-100 flex items-center justify-between bg-gray-50/50">
          <h4 class="text-xs font-bold text-gray-700 uppercase tracking-wider">Player Profiles (<%= length(@filtered_players) %>)</h4>
        </div>

        <%= if @filtered_players == [] do %>
          <div class="p-12 text-center">
            <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 flex items-center justify-center mx-auto mb-3">
              <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
              </svg>
            </div>
            <p class="text-sm font-semibold text-gray-700">No Player Profiles Found</p>
            <p class="text-xs text-gray-400 mt-1">Create a player profile or connect a game client using the C# / Unity SDK.</p>
            <button
              phx-click="open_create_modal"
              phx-target={@myself}
              class="mt-4 px-4 py-2 text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 rounded-xl transition-colors inline-flex items-center gap-1.5"
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Create First Player
            </button>
          </div>
        <% else %>
          <div class="divide-y divide-gray-100">
            <%= for player <- @filtered_players do %>
              <% pid = to_string(player["player_id"] || player[:player_id] || "unknown") %>
              <div class="p-4 hover:bg-gray-50/80 transition-colors flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-xl bg-violet-50 text-violet-600 font-bold text-xs flex items-center justify-center shrink-0 border border-violet-100">
                    <%= String.slice(pid, 0, 2) |> String.upcase() %>
                  </div>
                  <div>
                    <span class="text-xs font-bold text-gray-900 font-mono"><%= pid %></span>
                    <div class="text-[11px] text-gray-500 flex items-center gap-2 mt-0.5">
                      <span class="inline-block w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
                      <span>Active</span>
                      <span class="text-gray-300">•</span>
                      <span><%= map_size(player) %> fields</span>
                    </div>
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <button
                    phx-click="select_player"
                    phx-value-id={pid}
                    phx-target={@myself}
                    class="px-3 py-1.5 text-xs font-semibold text-violet-700 bg-violet-50 hover:bg-violet-100 rounded-lg transition-colors"
                  >
                    Inspect Profile
                  </button>
                  <button
                    phx-click="delete_player"
                    phx-value-id={pid}
                    phx-target={@myself}
                    data-confirm={"Are you sure you want to delete profile '#{pid}'?"}
                    class="p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                    title="Delete Player"
                  >
                    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Player Profile Detail Drawer -->
      <%= if @selected_player do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-2xl w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_player_drawer"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-700 flex items-center justify-center text-xl">
                👤
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900 font-mono"><%= @selected_player_id %></h3>
                <p class="text-xs text-gray-500">Live Player Profile &amp; LiveOps State</p>
              </div>
            </div>

            <%= if @edit_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @edit_error %>
              </div>
            <% end %>

            <form phx-submit="save_player_profile" phx-target={@myself} class="space-y-4">
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Profile JSON Document</label>
                <textarea
                  name="profile_raw"
                  rows="12"
                  class="w-full p-3 text-xs bg-gray-900 text-emerald-400 font-mono rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500"
                ><%= @edit_profile_raw %></textarea>
                <p class="text-[11px] text-gray-400 mt-1">Changes are saved atomically into the isolated player_data schema.</p>
              </div>

              <div class="pt-3 border-t border-gray-100 flex items-center justify-between">
                <button
                  type="button"
                  phx-click="delete_player"
                  phx-value-id={@selected_player_id}
                  phx-target={@myself}
                  data-confirm={"Delete '#{@selected_player_id}'?"}
                  class="px-3 py-2 text-xs font-semibold text-red-600 hover:bg-red-50 rounded-xl transition-colors"
                >
                  Delete Player
                </button>

                <div class="flex items-center gap-2">
                  <button
                    type="button"
                    phx-click="close_player_drawer"
                    phx-target={@myself}
                    class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900"
                  >
                    Close
                  </button>
                  <button
                    type="submit"
                    class="px-5 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl shadow-sm transition-colors"
                  >
                    Save Changes
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Create Player Modal -->
      <%= if @show_create_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_create_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-700 flex items-center justify-center">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900">Create New Player Profile</h3>
                <p class="text-xs text-gray-500">Initializes profile in database and issues token credentials.</p>
              </div>
            </div>

            <%= if @create_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @create_error %>
              </div>
            <% end %>

            <form phx-submit="submit_create_player" phx-change="change_create_form" phx-target={@myself} class="space-y-4">
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Player Identifier</label>
                <input
                  type="text"
                  name="create[player_id]"
                  value={@create_form["player_id"]}
                  placeholder="e.g. player_123"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                />
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Initial Profile Attributes (JSON)</label>
                <textarea
                  name="create[profile_json]"
                  rows="5"
                  class="w-full p-3 text-xs bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                ><%= @create_form["profile_json"] %></textarea>
              </div>

              <div class="pt-3 border-t border-gray-100 flex items-center justify-end gap-2">
                <button
                  type="button"
                  phx-click="close_create_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-5 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl shadow-sm transition-colors"
                >
                  Create Profile
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
