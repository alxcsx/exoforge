defmodule Exoforge.Std.DashboardViews.PlayerDataView do
  @moduledoc """
  Phoenix LiveComponent providing the dynamic Producer & Designer Studio visualization
  for the Player Profiles & LiveOps Data service (:player_data).

  Interacts strictly via service contracts and ActionDispatcher without depending
  on any concrete module implementation. Supports user linking, data retention filters,
  and fine-grained Key-Value JSON storage inspection.
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
       retention_filter: "all",
       selected_player: nil,
       selected_player_id: nil,
       selected_tab: "kv_store",
       player_kv_data: %{},
       player_inspect_tab: "kv_store",
       player_inspect_hooks: [],
       new_kv_key: "",
       new_kv_val: "",
       show_create_modal: false,
       create_error: nil,
       create_form: %{
         "player_id" => "",
         "user_id" => "",
         "profile_json" => "{}"
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
  def handle_event("switch_player_inspect_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, player_inspect_tab: tab)}
  end

  @impl true
  def handle_event("set_retention_filter", %{"filter" => filter}, socket) do
    filtered = apply_filters(socket.assigns.players, filter, socket.assigns.search_query)
    {:noreply, assign(socket, retention_filter: filter, filtered_players: filtered)}
  end

  @impl true
  def handle_event("search_players", %{"query" => query}, socket) do
    q = String.trim(query) |> String.downcase()
    filtered = apply_filters(socket.assigns.players, socket.assigns.retention_filter, q)
    {:noreply, assign(socket, search_query: query, filtered_players: filtered)}
  end

  @impl true
  def handle_event("select_player", %{"id" => id}, socket) do
    player =
      Enum.find(socket.assigns.players, fn p ->
        to_string(p["player_id"] || p[:player_id] || p.player_id) == id
      end)

    raw_json =
      if player do
        profile_map = player[:profile] || player["profile"] || player
        Jason.encode!(profile_map, pretty: true)
      else
        ""
      end

    kv_data =
      case ActionDispatcher.dispatch(:player_data, :get_all_data, %{player_id: id}) do
        {:ok, %{data: data}} when is_map(data) -> data
        _ -> %{}
      end

    hooks = Exoforge.UIHookRegistry.list_hooks(:player_inspect)

    hooks =
      if Enum.empty?(hooks) do
        [
          %{id: :kv_store, title: "Key-Value Database", icon: "🔑", order: 10},
          %{id: :profile, title: "Profile (Raw JSON)", icon: "👤", order: 20}
        ]
      else
        hooks
      end

    {:noreply,
     assign(socket,
       selected_player: player,
       selected_player_id: id,
       player_inspect_tab: "kv_store",
       player_inspect_hooks: hooks,
       player_kv_data: kv_data,
       new_kv_key: "",
       new_kv_val: "",
       edit_profile_raw: raw_json,
       edit_error: nil,
       action_notification: nil
     )}
  end

  @impl true
  def handle_event("close_player_drawer", _params, socket) do
    {:noreply,
     assign(socket,
       selected_player: nil,
       selected_player_id: nil,
       player_kv_data: %{},
       edit_error: nil
     )}
  end

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    rnd = System.system_time(:second) |> rem(10_000)

    {:noreply,
     assign(socket,
       show_create_modal: true,
       create_error: nil,
       create_form: %{
         "player_id" => "player_#{rnd}",
         "user_id" => "u_#{rnd}",
         "profile_json" => "{}"
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
    user_id = String.trim(Map.get(params, "user_id", ""))
    raw_json = String.trim(Map.get(params, "profile_json", "{}"))

    cond do
      id == "" ->
        {:noreply, assign(socket, create_error: "Player ID is required.")}

      true ->
        case Jason.decode(raw_json) do
          {:ok, profile_map} when is_map(profile_map) ->
            payload = %{
              player_id: id,
              user_id: if(user_id != "", do: user_id, else: nil),
              profile: profile_map
            }

            case ActionDispatcher.dispatch(:player_data, :create_player, payload) do
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
  def handle_event("retain_player", %{"id" => player_id}, socket) do
    case ActionDispatcher.dispatch(:player_data, :retain_player, %{player_id: player_id}) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            selected_player: nil,
            selected_player_id: nil,
            action_notification: "Player '#{player_id}' marked as retained (user unlinked)."
          )
          |> load_players()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, action_notification: "Retention failed: #{inspect(reason)}")}
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

  @impl true
  def handle_event("set_kv_state", params, socket) do
    player_id = socket.assigns.selected_player_id
    key = String.trim(Map.get(params, "key", socket.assigns.new_kv_key))
    raw_val = String.trim(Map.get(params, "value", socket.assigns.new_kv_val))

    if key != "" do
      val =
        case Jason.decode(raw_val) do
          {:ok, parsed} -> parsed
          _ -> raw_val
        end

      _ =
        ActionDispatcher.dispatch(:player_data, :set_data, %{
          player_id: player_id,
          key: key,
          value: val
        })

      kv_data =
        case ActionDispatcher.dispatch(:player_data, :get_all_data, %{player_id: player_id}) do
          {:ok, %{data: data}} when is_map(data) -> data
          _ -> %{}
        end

      {:noreply,
       assign(socket,
         player_kv_data: kv_data,
         new_kv_key: "",
         new_kv_val: "",
         action_notification: "Key '#{key}' updated!"
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_kv_state", %{"key" => key}, socket) do
    player_id = socket.assigns.selected_player_id
    _ = ActionDispatcher.dispatch(:player_data, :delete_data, %{player_id: player_id, key: key})

    kv_data =
      case ActionDispatcher.dispatch(:player_data, :get_all_data, %{player_id: player_id}) do
        {:ok, %{data: data}} when is_map(data) -> data
        _ -> %{}
      end

    {:noreply,
     assign(socket, player_kv_data: kv_data, action_notification: "Key '#{key}' removed.")}
  end

  @impl true
  def handle_event("dismiss_notification", _params, socket) do
    {:noreply, assign(socket, action_notification: nil)}
  end

  ## ---- PRIVATE HELPERS ----

  defp load_players(socket) do
    players =
      case ActionDispatcher.dispatch(:player_data, :list_players, %{filter: "all"}) do
        {:ok, %{players: list}} when is_list(list) -> list
        {:ok, %{rows: list}} when is_list(list) -> list
        _ -> []
      end

    filtered =
      apply_filters(players, socket.assigns.retention_filter, socket.assigns.search_query)

    user_names =
      case ActionDispatcher.dispatch(:auth, :list_users, %{}) do
        {:ok, %{users: users}} ->
          Map.new(users, fn u ->
            id = to_string(u["user_id"] || u["player_id"])
            {id, u["name"] || id}
          end)

        _ ->
          %{}
      end

    assign(socket,
      players: players,
      filtered_players: filtered,
      user_names: user_names,
      loading: false
    )
  end

  defp apply_filters(players, retention_filter, query) do
    # 1. Filter by retention status
    step1 =
      case retention_filter do
        "valid" ->
          Enum.filter(players, fn p -> p[:linked] == true or p["linked"] == true end)

        "retained" ->
          Enum.filter(players, fn p -> p[:linked] == false or p["linked"] == false end)

        _ ->
          players
      end

    # 2. Filter by search query
    q = String.trim(query) |> String.downcase()

    if q == "" do
      step1
    else
      Enum.filter(step1, fn p ->
        id = to_string(p[:player_id] || p["player_id"] || "")
        uid = to_string(p[:user_id] || p["user_id"] || "")
        name = to_string(p[:name] || p["name"] || "")

        String.contains?(String.downcase(id), q) or
          String.contains?(String.downcase(uid), q) or
          String.contains?(String.downcase(name), q)
      end)
    end
  end

  ## ---- RENDER ----

  @impl true
  def render(assigns) do
    valid_count =
      Enum.count(assigns.players, fn p -> p[:linked] == true or p["linked"] == true end)

    retained_count =
      Enum.count(assigns.players, fn p -> p[:linked] == false or p["linked"] == false end)

    assigns =
      assign(assigns,
        valid_count: valid_count,
        retained_count: retained_count
      )

    ~H"""
    <div id="player_data_dashboard_view" class="space-y-6">
      <!-- Action Notification Banner -->
      <%= if @action_notification do %>
        <div class="p-3 bg-emerald-50 border border-emerald-200 rounded-xl text-xs text-emerald-800 font-medium flex items-center justify-between animate-in fade-in duration-150">
          <div class="flex items-center gap-2">
            <span>✓</span>
            <span><%= @action_notification %></span>
          </div>
          <button phx-click="dismiss_notification" phx-target={@myself} class="text-emerald-500 hover:text-emerald-700 font-bold">&times;</button>
        </div>
      <% end %>

      <!-- Top Stats & Header -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Registered Players</p>
            <p class="text-2xl font-bold text-gray-900 mt-1"><%= length(@players) %></p>
            <p class="text-[11px] text-gray-400 mt-0.5"><%= @valid_count %> Active • <%= @retained_count %> Retained</p>
          </div>
          <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-700 flex items-center justify-center text-lg">
            👥
          </div>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wider">User Linked Accounts</p>
            <p class="text-2xl font-bold text-emerald-600 mt-1"><%= @valid_count %></p>
            <p class="text-[11px] text-gray-400 mt-0.5">Authorised client ingress active</p>
          </div>
          <div class="w-10 h-10 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center text-lg">
            🔐
          </div>
        </div>

        <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wider">GDPR &amp; Retained Data</p>
            <p class="text-2xl font-bold text-amber-600 mt-1"><%= @retained_count %></p>
            <p class="text-[11px] text-gray-400 mt-0.5">Telemetry kept, user unlinked</p>
          </div>
          <div class="w-10 h-10 rounded-xl bg-amber-100 text-amber-700 flex items-center justify-center text-lg">
            📁
          </div>
        </div>
      </div>

      <!-- Action Toolbar with Filter Tabs -->
      <div class="bg-white p-4 rounded-2xl border border-gray-100 shadow-sm flex flex-col md:flex-row items-center justify-between gap-4">
        <!-- Retention Filter Tabs -->
        <div class="flex items-center gap-1.5 w-full md:w-auto bg-gray-100/90 p-1 rounded-xl">
          <button
            phx-click="set_retention_filter"
            phx-value-filter="all"
            phx-target={@myself}
            class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all #{if @retention_filter == "all", do: "bg-white text-gray-900 shadow-xs", else: "text-gray-500 hover:text-gray-800"}"}
          >
            All (<%= length(@players) %>)
          </button>
          <button
            phx-click="set_retention_filter"
            phx-value-filter="valid"
            phx-target={@myself}
            class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1 #{if @retention_filter == "valid", do: "bg-white text-emerald-700 shadow-xs", else: "text-gray-500 hover:text-gray-800"}"}
          >
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
            Active (<%= @valid_count %>)
          </button>
          <button
            phx-click="set_retention_filter"
            phx-value-filter="retained"
            phx-target={@myself}
            class={"px-3 py-1.5 text-xs font-bold rounded-lg transition-all flex items-center gap-1 #{if @retention_filter == "retained", do: "bg-white text-amber-700 shadow-xs", else: "text-gray-500 hover:text-gray-800"}"}
          >
            <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span>
            Retained (<%= @retained_count %>)
          </button>
        </div>

        <div class="relative flex-1 w-full max-w-md">
          <input
            type="text"
            placeholder="Search by Player ID, User ID, or Name..."
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
          <h4 class="text-xs font-bold text-gray-700 uppercase tracking-wider">
            Matching Players (<%= length(@filtered_players) %>)
          </h4>
        </div>

        <%= if @filtered_players == [] do %>
          <div class="p-12 text-center">
            <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 flex items-center justify-center mx-auto mb-3">
              <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
              </svg>
            </div>
            <p class="text-sm font-semibold text-gray-700">No Players Matching Filter</p>
            <p class="text-xs text-gray-400 mt-1">Create a player profile or connect a game client using the C# / Unity SDK.</p>
            <button
              phx-click="open_create_modal"
              phx-target={@myself}
              class="mt-4 px-4 py-2 text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 rounded-xl transition-colors inline-flex items-center gap-1.5"
            >
              <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Create Player
            </button>
          </div>
        <% else %>
          <div class="divide-y divide-gray-100">
            <%= for player <- @filtered_players do %>
              <% pid = to_string(player[:player_id] || player["player_id"] || "unknown") %>
              <% uid = player[:user_id] || player["user_id"] %>
              <% is_linked = player[:linked] == true or player["linked"] == true %>

              <div class="p-4 hover:bg-gray-50/80 transition-colors flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <div class={"w-9 h-9 rounded-xl font-bold text-xs flex items-center justify-center shrink-0 border #{if is_linked, do: "bg-violet-50 text-violet-600 border-violet-100", else: "bg-amber-50 text-amber-600 border-amber-200"}"}>
                    <%= String.slice(pid, 0, 2) |> String.upcase() %>
                  </div>
                  <div>
                    <div class="flex items-center gap-2">
                      <span class="text-xs font-bold text-gray-900"><%= player[:name] || player["name"] || pid %></span>
                      <%= if is_linked and uid do %>
                        <span class="px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-blue-50 text-blue-700 border border-blue-200">
                          User: <%= Map.get(@user_names, to_string(uid), player[:name] || player["name"] || uid) %>
                        </span>
                      <% else %>
                        <span class="px-2 py-0.5 rounded text-[10px] font-bold bg-amber-50 text-amber-800 border border-amber-300">
                          Retained (No User)
                        </span>
                      <% end %>
                    </div>
                    <div class="text-[11px] text-gray-500 flex items-center gap-2 mt-0.5">
                      <span class={"inline-block w-1.5 h-1.5 rounded-full #{if is_linked, do: "bg-emerald-500", else: "bg-amber-500"}"}></span>
                      <span class="font-mono"><%= pid %></span>
                      <span class="text-gray-300">•</span>
                      <span><%= if is_linked, do: "Active Access", else: "Inaccessible (Retention)" %></span>
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
                    Inspect Profile &amp; KV
                  </button>
                  <%= if is_linked do %>
                    <button
                      phx-click="retain_player"
                      phx-value-id={pid}
                      phx-target={@myself}
                      data-confirm={"Unlink user account and retain player '#{pid}' for telemetry data retention?"}
                      class="px-2.5 py-1.5 text-xs font-semibold text-amber-700 bg-amber-50 hover:bg-amber-100 rounded-lg transition-colors border border-amber-200"
                      title="Unlink User & Retain Telemetry"
                    >
                      Retain
                    </button>
                  <% end %>
                  <button
                    phx-click="delete_player"
                    phx-value-id={pid}
                    phx-target={@myself}
                    data-confirm={"Hard delete player '#{pid}' completely from database?"}
                    class="p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                    title="Hard Delete"
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

      <!-- Player Profile & Key-Value Drawer -->
      <%= if @selected_player do %>
        <% p_name = @selected_player[:name] || @selected_player["name"] || @selected_player_id %>
        <% p_uid = @selected_player[:user_id] || @selected_player["user_id"] %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-3xl w-full shadow-2xl border border-gray-200 relative animate-in fade-in duration-150 overflow-hidden">
            <button
              phx-click="close_player_drawer"
              phx-target={@myself}
              class="absolute top-4 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 px-6 py-4 border-b border-gray-100">
              <div class="w-10 h-10 rounded-xl bg-violet-100 text-violet-700 flex items-center justify-center text-xl">
                👤
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900"><%= p_name %></h3>
                <p class="text-xs text-gray-500">
                  <%= if p_uid && p_uid != "" do %>
                    Linked user: <span class="font-bold text-blue-700"><%= Map.get(@user_names, to_string(p_uid), p_name) %></span>
                  <% else %>
                    <span class="text-amber-700 font-bold">Unlinked / Retained Account (Inaccessible from regular ingress)</span>
                  <% end %>
                </p>
              </div>
            </div>

            <%= if @edit_error do %>
              <div class="mx-6 mt-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @edit_error %>
              </div>
            <% end %>

            <div class="flex flex-col md:flex-row min-h-[360px] divide-y md:divide-y-0 md:divide-x divide-gray-100">
              <!-- Side tabs (UI hooks) -->
              <div class="w-full md:w-52 p-3 bg-gray-50/70 space-y-0.5 shrink-0">
                <%= for hook <- @player_inspect_hooks do %>
                  <button
                    type="button"
                    phx-click="switch_player_inspect_tab"
                    phx-value-tab={to_string(hook.id)}
                    phx-target={@myself}
                    class={"w-full text-left px-2.5 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition-all #{if @player_inspect_tab == to_string(hook.id), do: "bg-white text-violet-700 shadow-sm border border-gray-200/80", else: "text-gray-600 hover:text-gray-900 hover:bg-white/60"}"}
                  >
                    <span><%= hook.icon %></span>
                    <span class="truncate"><%= hook.title %></span>
                  </button>
                <% end %>
              </div>

              <div class="flex-1 p-5 space-y-4 min-w-0">

            <!-- Tab 1: Key-Value Database Hook -->
            <%= if @player_inspect_tab == "kv_store" do %>
              <div class="border border-gray-200 rounded-xl p-4 bg-gray-50/60 space-y-3">
                <div class="flex items-center justify-between">
                  <span class="text-xs font-bold text-gray-800 uppercase tracking-wider">Key-Value JSON State (<%= map_size(@player_kv_data) %> keys)</span>
                  <span class="text-[10px] text-gray-400 font-mono">player_kv table</span>
                </div>

                <%= if map_size(@player_kv_data) == 0 do %>
                  <p class="text-xs text-gray-400 italic">No fine-grained key-value state saved yet for this player.</p>
                <% else %>
                  <div class="space-y-1.5 max-h-56 overflow-y-auto pr-1">
                    <%= for {k, v} <- @player_kv_data do %>
                      <div class="flex items-center justify-between p-2 bg-white rounded-lg border border-gray-200 text-xs">
                        <span class="font-mono font-bold text-purple-800"><%= k %></span>
                        <div class="flex items-center gap-2">
                          <span class="font-mono text-gray-600 truncate max-w-xs"><%= inspect(v) %></span>
                          <button
                            type="button"
                            phx-click="delete_kv_state"
                            phx-value-key={k}
                            phx-target={@myself}
                            class="text-gray-400 hover:text-red-500 font-bold text-xs"
                            title="Delete Key"
                          >
                            ✕
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Quick Add KV Form -->
                <form phx-submit="set_kv_state" phx-target={@myself} class="flex items-center gap-2 pt-1">
                  <input
                    type="text"
                    name="key"
                    placeholder="Key (e.g. inventory)"
                    required
                    class="flex-1 px-2.5 py-1.5 text-xs bg-white border border-gray-200 rounded-lg focus:outline-none focus:ring-1 focus:ring-purple-500 font-mono"
                  />
                  <input
                    type="text"
                    name="value"
                    placeholder='JSON Value (e.g. {"gold": 100})'
                    required
                    class="flex-1 px-2.5 py-1.5 text-xs bg-white border border-gray-200 rounded-lg focus:outline-none focus:ring-1 focus:ring-purple-500 font-mono"
                  />
                  <button
                    type="submit"
                    class="px-3 py-1.5 text-xs font-bold text-white bg-purple-600 hover:bg-purple-700 rounded-lg transition-colors whitespace-nowrap"
                  >
                    Set KV
                  </button>
                </form>
              </div>

            <% end %>

            <!-- Tab 2: Profile Attributes Document -->
            <%= if @player_inspect_tab == "profile" do %>
              <form phx-submit="save_player_profile" phx-target={@myself} class="space-y-4">
                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Profile Attributes JSON</label>
                  <textarea
                    name="profile_raw"
                    rows="8"
                    class="w-full p-3 text-xs bg-gray-900 text-emerald-400 font-mono rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500"
                  ><%= @edit_profile_raw %></textarea>
                </div>

                <div class="pt-3 border-t border-gray-100 flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <%= if @selected_player[:linked] == true or @selected_player["linked"] == true do %>
                      <button
                        type="button"
                        phx-click="retain_player"
                        phx-value-id={@selected_player_id}
                        phx-target={@myself}
                        data-confirm={"Unlink user account and retain telemetry for '#{@selected_player_id}'?"}
                        class="px-3 py-2 text-xs font-semibold text-amber-700 bg-amber-50 hover:bg-amber-100 rounded-xl border border-amber-200 transition-colors"
                      >
                        Unlink &amp; Retain
                      </button>
                    <% end %>
                    <button
                      type="button"
                      phx-click="delete_player"
                      phx-value-id={@selected_player_id}
                      phx-target={@myself}
                      data-confirm={"Hard delete '#{@selected_player_id}'?"}
                      class="px-3 py-2 text-xs font-semibold text-red-600 hover:bg-red-50 rounded-xl transition-colors"
                    >
                      Hard Delete
                    </button>
                  </div>

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
            <% end %>

            <!-- Dynamic Hook Panel -->
            <%= if @player_inspect_tab not in ["profile", "kv_store"] do %>
              <% active_hook = Enum.find(@player_inspect_hooks, fn h -> to_string(h.id) == @player_inspect_tab end) %>
              <%= if active_hook && active_hook[:component] && Code.ensure_loaded?(active_hook[:component]) do %>
                <.live_component
                  module={active_hook[:component]}
                  id={"hook_#{active_hook.id}_#{@selected_player_id}"}
                  player_id={@selected_player_id}
                  player={@selected_player}
                />
              <% else %>
                <div class="p-6 bg-gray-50 border border-gray-200 rounded-xl text-center space-y-2">
                  <p class="text-xs text-gray-500">Custom inspection tab for player <strong class="font-mono text-gray-700"><%= @selected_player_id %></strong>.</p>
                  <p class="text-[11px] text-gray-400">Contributed by <span class="font-mono"><%= (active_hook && active_hook[:plugin_id]) || "extension" %></span></p>
                  <div class="pt-2">
                    <button
                      type="button"
                      phx-click="close_player_drawer"
                      phx-target={@myself}
                      class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900"
                    >
                      Close
                    </button>
                  </div>
                </div>
              <% end %>
            <% end %>
              </div>
            </div>
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
                <p class="text-xs text-gray-500">Optionally linked to a user account, or created as retained telemetry.</p>
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
                  required
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                />
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">User ID (Linked Account)</label>
                <input
                  type="text"
                  name="create[user_id]"
                  value={@create_form["user_id"]}
                  placeholder="e.g. u_123 (leave empty to create unlinked/retained)"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 focus:bg-white font-mono"
                />
                <p class="text-[11px] text-gray-400 mt-1">Leave blank to create as an inaccessible retained player record.</p>
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Initial Profile Attributes (JSON)</label>
                <textarea
                  name="create[profile_json]"
                  rows="4"
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
