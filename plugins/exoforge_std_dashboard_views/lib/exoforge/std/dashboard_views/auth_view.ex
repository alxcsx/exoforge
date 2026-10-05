defmodule Exoforge.Std.DashboardViews.AuthView do
  @moduledoc """
  Phoenix LiveComponent providing the dynamic Producer & Designer Studio visualization
  for the Authentication and Identity service (:auth).
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.DashboardViews.UserForms

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       users: [],
       filtered_users: [],
       search_query: "",
       scope_filter: "all",
       show_register_modal: false,
       show_reset_password_modal: false,
       show_roles_modal: false,
       reset_password_user: nil,
       reset_password_error: nil,
       roles_user: nil,
       selected_role: "player",
       roles_form_scopes: Exoforge.Auth.Roles.scopes_for_role("player"),
       roles_error: nil,
       issued_token_info: nil,
       selected_user: nil,
       register_form: %{
         "user_id" => "",
         "player_id" => "",
         "name" => "",
         "email" => "",
         "password" => "",
         "role" => "player"
       },
       error_message: nil,
       action_notification: nil,
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
         "user_id" => default_id,
         "player_id" => default_id,
         "name" => "",
         "email" => "",
         "password" => "",
         "role" => "player"
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
    payload = UserForms.registration_payload(params)

    case ActionDispatcher.dispatch(:auth, :register, payload) do
      {:ok, result} ->
        socket =
          socket
          |> assign(
            show_register_modal: false,
            error_message: nil,
            action_notification:
              "User '#{UserForms.display_name(payload.name, result.player_id)}' successfully created!",
            issued_token_info: %{
              name: UserForms.display_name(payload.name, result.player_id),
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
  def handle_event("open_reset_password_modal", %{"player_id" => player_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1["player_id"] == player_id))

    {:noreply,
     assign(socket,
       show_reset_password_modal: true,
       reset_password_user: user,
       reset_password_error: nil
     )}
  end

  @impl true
  def handle_event("close_reset_password_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_reset_password_modal: false,
       reset_password_user: nil,
       reset_password_error: nil
     )}
  end

  @impl true
  def handle_event("submit_reset_password", %{"reset" => %{"password" => new_pw}}, socket) do
    case UserForms.reset_password_for(socket.assigns.reset_password_user, new_pw) do
      {:error, message} ->
        {:noreply, assign(socket, reset_password_error: message)}

      {:ok, payload} ->
        case ActionDispatcher.dispatch(:auth, :reset_password, payload) do
          {:ok, _} ->
            socket =
              socket
              |> assign(
                show_reset_password_modal: false,
                reset_password_user: nil,
                reset_password_error: nil,
                action_notification: "Password for '#{payload.player_id}' successfully updated!"
              )
              |> load_users()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               reset_password_error:
                 "Password reset failed: #{UserForms.failure_message(reason)}"
             )}
        end
    end
  end

  @impl true
  def handle_event("open_roles_modal", %{"player_id" => player_id}, socket) do
    user = Enum.find(socket.assigns.users, &((&1["user_id"] || &1["player_id"]) == player_id))
    scopes = if user, do: user["scopes"] || ["player"], else: ["player"]
    primary_role = Exoforge.Auth.Roles.role_from_scopes(scopes)
    expanded_scopes = Exoforge.Auth.Roles.scopes_for_role(primary_role)

    {:noreply,
     assign(socket,
       show_roles_modal: true,
       roles_user: user,
       selected_role: primary_role,
       roles_form_scopes: expanded_scopes,
       roles_error: nil
     )}
  end

  @impl true
  def handle_event("close_roles_modal", _params, socket) do
    {:noreply, assign(socket, show_roles_modal: false, roles_user: nil, roles_error: nil)}
  end

  @impl true
  def handle_event("select_role", %{"role" => role}, socket) do
    expanded = Exoforge.Auth.Roles.scopes_for_role(role)
    {:noreply, assign(socket, selected_role: role, roles_form_scopes: expanded)}
  end

  @impl true
  def handle_event("submit_roles", params, socket) do
    role = Map.get(params, "role", socket.assigns.selected_role)
    user = socket.assigns.roles_user
    pid = if user, do: user["user_id"] || user["player_id"], else: nil
    scopes = Exoforge.Auth.Roles.scopes_for_role(role)

    case ActionDispatcher.dispatch(:auth, :update_user_roles, %{
           user_id: pid,
           role: role,
           scopes: scopes
         }) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            show_roles_modal: false,
            roles_user: nil,
            action_notification: "Roles updated for '#{pid}' successfully!"
          )
          |> load_users()

        {:noreply, socket}

      {:error, :protected_admin_account} ->
        {:noreply,
         assign(socket, roles_error: "Cannot alter roles of the protected environment admin.")}

      {:error, reason} ->
        {:noreply, assign(socket, roles_error: "Failed to update roles: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_user", %{"player_id" => player_id}, socket) do
    case ActionDispatcher.dispatch(:auth, :delete_user, %{player_id: player_id}) do
      {:ok, _} ->
        socket =
          socket
          |> assign(
            selected_user:
              if(
                socket.assigns.selected_user &&
                  socket.assigns.selected_user["player_id"] == player_id,
                do: nil,
                else: socket.assigns.selected_user
              ),
            action_notification:
              "Account '#{(Enum.find(socket.assigns.users, &(&1["player_id"] == player_id)) || %{})["name"] || player_id}' has been permanently deleted."
          )
          |> load_users()

        {:noreply, socket}

      {:error, :protected_admin_account} ->
        {:noreply,
         assign(socket,
           action_notification: "Cannot delete the hardcoded environment admin account."
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, action_notification: "Failed to delete account: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("dismiss_notification", _params, socket) do
    {:noreply, assign(socket, action_notification: nil)}
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
              name: (user && user["name"]) || result.player_id,
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

      <!-- Action Notification Banner -->
      <%= if @action_notification do %>
        <div class="bg-gradient-to-r from-emerald-50 to-teal-50 border border-emerald-200 rounded-2xl p-4 shadow-sm flex items-center justify-between animate-in fade-in duration-150">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-lg bg-emerald-600 text-white flex items-center justify-center font-bold text-sm shrink-0">
              ✓
            </div>
            <p class="text-xs font-bold text-emerald-900">
              <%= @action_notification %>
            </p>
          </div>
          <button
            phx-click="dismiss_notification"
            phx-target={@myself}
            class="text-emerald-500 hover:text-emerald-800 text-sm font-bold p-1"
          >
            ✕
          </button>
        </div>
      <% end %>

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
                  New Bearer Token Generated for <span class="font-bold text-purple-700"><%= @issued_token_info[:name] || @issued_token_info.player_id %></span>
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
                  <th class="py-3 px-4">User ID & Name</th>
                  <th class="py-3 px-4">Assigned Scopes</th>
                  <th class="py-3 px-4">Active Tokens</th>
                  <th class="py-3 px-4">Status</th>
                  <th class="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 text-sm">
                <%= for user <- @filtered_users do %>
                  <% is_protected = user["is_protected"] == true %>
                  <tr class="hover:bg-purple-50/30 transition-colors group">
                    <td class="py-3.5 px-4">
                      <div class="flex flex-col">
                        <div class="flex items-center gap-2">
                          <span class="font-bold text-gray-900"><%= user["name"] || user["email"] || user["user_id"] || user["player_id"] %></span>
                          <%= if is_protected do %>
                            <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800 border border-amber-300" title="Created via environment variables. Cannot be modified or deleted via UI.">
                              🔒 Env Admin
                            </span>
                          <% end %>
                          <button
                            phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: user["user_id"] || user["player_id"]})}
                            title="Copy User ID"
                            class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-purple-600 transition-opacity text-xs"
                          >
                            📋
                          </button>
                        </div>
                        <span class="text-xs text-gray-500 font-medium mt-0.5"><%= user["email"] || user["user_id"] || user["player_id"] %></span>
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
                      <div class="flex items-center justify-end gap-1.5">
                        <button
                          phx-click="issue_token"
                          phx-value-player_id={user["player_id"]}
                          phx-target={@myself}
                          title="Issue new bearer token"
                          class="px-2 py-1 text-xs font-semibold text-purple-700 bg-purple-50 hover:bg-purple-100 border border-purple-200 rounded-lg transition-colors"
                        >
                          + Token
                        </button>

                        <%= if is_protected do %>
                          <span class="text-[11px] text-gray-400 font-medium px-2 italic" title="System admin managed exclusively via environment variables">
                            Protected
                          </span>
                        <% else %>
                          <button
                            phx-click="open_roles_modal"
                            phx-value-player_id={user["player_id"]}
                            phx-target={@myself}
                            title="Edit user scopes and roles"
                            class="px-2 py-1 text-xs font-semibold text-gray-700 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg transition-colors"
                          >
                            Roles
                          </button>
                          <button
                            phx-click="open_reset_password_modal"
                            phx-value-player_id={user["player_id"]}
                            phx-target={@myself}
                            title="Set or reset account password"
                            class="px-2 py-1 text-xs font-semibold text-indigo-700 bg-indigo-50 hover:bg-indigo-100 border border-indigo-200 rounded-lg transition-colors"
                          >
                            Reset PW
                          </button>
                          <button
                            phx-click="delete_user"
                            phx-value-player_id={user["player_id"]}
                            phx-target={@myself}
                            data-confirm={"Are you sure you want to permanently delete user account '#{user["name"] || user["player_id"]}'?"}
                            title="Delete user account"
                            class="px-2 py-1 text-xs font-semibold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 rounded-lg transition-colors"
                          >
                            Delete
                          </button>
                        <% end %>

                        <button
                          phx-click="inspect_user"
                          phx-value-player_id={user["player_id"]}
                          phx-target={@myself}
                          title="View tokens & details"
                          class="px-2 py-1 text-xs font-semibold text-gray-600 hover:text-gray-900 border border-transparent hover:border-gray-200 rounded-lg transition-colors"
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
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">User ID</label>
                <input
                  type="text"
                  name="register[user_id]"
                  value={@register_form["user_id"] || @register_form["player_id"]}
                  placeholder="e.g. u_94812 (leave blank to auto-generate)"
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
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Initial Password (Optional)</label>
                <input
                  type="password"
                  name="register[password]"
                  value={@register_form["password"]}
                  placeholder="Set password for email/password login (optional)"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white"
                />
                <p class="text-[11px] text-gray-400 mt-1">If set, the user can log into Exoforge Studio or APIs using email + password.</p>
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Account Role & Scopes</label>
                <select
                  name="register[role]"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white font-medium text-gray-900"
                >
                  <option value="player" selected={@register_form["role"] == "player"}>Player / Standard User (Default game access)</option>
                  <option value="studio" selected={@register_form["role"] == "studio"}>Studio / Developer (Producer Studio & Tools)</option>
                  <option value="service" selected={@register_form["role"] == "service"}>Service / Worker (Internal server communications)</option>
                  <option value="admin" selected={@register_form["role"] == "admin"}>Administrator (Full access to all scopes)</option>
                  <option value="guest" selected={@register_form["role"] == "guest"}>Guest (Limited anonymous read-only)</option>
                </select>
                <p class="text-[11px] text-gray-400 mt-1">Multi-scope security profile assigned to this user upon creation.</p>
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
                  Create Account &amp; Issue Token
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Reset Password Modal -->
      <%= if @show_reset_password_modal and @reset_password_user do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_reset_password_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-indigo-100 text-indigo-700 flex items-center justify-center text-xl">
                🔑
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900">Reset User Password</h3>
                <p class="text-xs text-gray-500">
                  Account: <span class="font-bold text-gray-800"><%= @reset_password_user["name"] || @reset_password_user["player_id"] %></span>
                </p>
              </div>
            </div>

            <%= if @reset_password_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @reset_password_error %>
              </div>
            <% end %>

            <form phx-submit="submit_reset_password" phx-target={@myself} class="space-y-4">
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">New Password</label>
                <input
                  type="password"
                  name="reset[password]"
                  required
                  placeholder="Enter new password"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white"
                />
              </div>

              <div class="pt-3 border-t border-gray-100 flex items-center justify-end gap-2">
                <button
                  type="button"
                  phx-click="close_reset_password_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-5 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-sm transition-colors"
                >
                  Save New Password
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Change Roles Modal -->
      <%= if @show_roles_modal and @roles_user do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_roles_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center text-xl">
                🛡️
              </div>
              <div>
                <h3 class="text-base font-bold text-gray-900">Change Account Roles</h3>
                <p class="text-xs text-gray-500">
                  User: <span class="font-bold text-gray-800"><%= @roles_user["name"] || @roles_user["user_id"] || @roles_user["player_id"] %></span>
                </p>
              </div>
            </div>

            <%= if @roles_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 font-medium">
                <%= @roles_error %>
              </div>
            <% end %>

            <form phx-submit="submit_roles" phx-target={@myself} class="space-y-4">
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-2">Authorisation Role</label>
                <select
                  name="role"
                  phx-change="select_role"
                  phx-target={@myself}
                  class="w-full px-3 py-2.5 text-sm bg-gray-50 border border-gray-200 rounded-xl font-medium text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white"
                >
                  <option value="player" selected={@selected_role == "player"}>Player / Standard User</option>
                  <option value="studio" selected={@selected_role == "studio"}>Studio / Developer</option>
                  <option value="service" selected={@selected_role == "service"}>Service / Worker</option>
                  <option value="admin" selected={@selected_role == "admin"}>Administrator (All scopes)</option>
                  <option value="guest" selected={@selected_role == "guest"}>Guest (Limited access)</option>
                </select>
              </div>

              <!-- Granted Multi-Scopes Pill List -->
              <div class="p-3 bg-purple-50/70 border border-purple-200 rounded-xl space-y-1.5">
                <p class="text-[11px] font-bold text-purple-900 uppercase tracking-wider">Multi-Scopes Granted by this Role:</p>
                <div class="flex flex-wrap gap-1.5 pt-1">
                  <%= for scope <- @roles_form_scopes do %>
                    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-mono font-bold bg-white text-purple-800 border border-purple-200 shadow-2xs">
                      <%= scope %>
                    </span>
                  <% end %>
                </div>
              </div>

              <div class="pt-3 border-t border-gray-100 flex items-center justify-end gap-2">
                <button
                  type="button"
                  phx-click="close_roles_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 hover:text-gray-900"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-5 py-2 text-xs font-bold text-white bg-purple-600 hover:bg-purple-700 rounded-xl shadow-sm transition-colors"
                >
                  Update Roles
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- User Inspection Slide-over Drawer -->
      <%= if @selected_user do %>
        <% sel_is_protected = @selected_user["is_protected"] == true %>
        <div class="fixed inset-0 z-50 overflow-hidden bg-black/30 backdrop-blur-xs flex justify-end">
          <div class="bg-white w-full max-w-md h-full shadow-2xl border-l border-gray-200 p-6 flex flex-col justify-between overflow-y-auto animate-in slide-in-from-right duration-200">
            <div>
              <div class="flex items-center justify-between pb-4 border-b border-gray-100">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center font-bold text-lg">
                    👤
                  </div>
                  <div>
                    <h3 class="text-base font-bold text-gray-900"><%= @selected_user["name"] || @selected_user["player_id"] %></h3>
                    <p class="text-xs text-gray-500">Identity details &amp; security tokens</p>
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
                <%= if sel_is_protected do %>
                  <div class="p-3 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-800 flex items-center gap-2">
                    <span>🔒</span>
                    <span>This account is hardcoded via environment variables and cannot be altered or deleted.</span>
                  </div>
                <% end %>

                <%= if @selected_user["email"] do %>
                  <div>
                    <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1">Email</h4>
                    <p class="text-xs font-mono text-gray-800 bg-gray-50 p-2 rounded-lg border border-gray-200">
                      <%= @selected_user["email"] %>
                    </p>
                  </div>
                <% end %>

                <div>
                  <div class="flex items-center justify-between mb-2">
                    <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Granted Scopes</h4>
                    <%= unless sel_is_protected do %>
                      <button
                        phx-click="open_roles_modal"
                        phx-value-player_id={@selected_user["player_id"]}
                        phx-target={@myself}
                        class="text-xs font-semibold text-purple-600 hover:text-purple-800"
                      >
                        Edit Roles
                      </button>
                    <% end %>
                  </div>
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

                <%= unless sel_is_protected do %>
                  <div>
                    <button
                      phx-click="open_reset_password_modal"
                      phx-value-player_id={@selected_user["player_id"]}
                      phx-target={@myself}
                      class="w-full py-2 text-xs font-bold text-indigo-700 bg-indigo-50 hover:bg-indigo-100 border border-indigo-200 rounded-xl transition-colors text-center"
                    >
                      🔑 Reset Password
                    </button>
                  </div>
                <% end %>

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

            <div class="pt-4 border-t border-gray-100 space-y-2">
              <%= unless sel_is_protected do %>
                <button
                  phx-click="delete_user"
                  phx-value-player_id={@selected_user["player_id"]}
                  phx-target={@myself}
                  data-confirm={"Are you sure you want to permanently delete account '#{@selected_user["name"] || @selected_user["player_id"]}'?"}
                  class="w-full py-2 text-xs font-bold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 rounded-xl transition-colors"
                >
                  Delete Account
                </button>
              <% end %>
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
