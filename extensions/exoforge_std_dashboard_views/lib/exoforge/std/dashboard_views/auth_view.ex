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
       users_total: 0,
       user_page: 1,
       user_pages: 1,
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
       user_inspect_tab: "overview",
       user_inspect_hooks: [],
       user_events: [],
       user_events_total: 0,
       user_events_page: 1,
       user_events_pages: 1,
       user_events_capped: false,
       user_events_archive: false,
       capture_notice: nil,
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

    {:ok, sync_focus(socket)}
  end

  @impl true
  def handle_event("search", params, socket) do
    query = Map.get(params, "query") || Map.get(params, "value") || ""

    socket =
      socket
      |> assign(search_query: query, user_page: 1)
      |> load_users()

    {:noreply, socket}
  end

  @impl true
  def handle_event("user_page", %{"page" => page}, socket) do
    target =
      if page == "next", do: socket.assigns.user_page + 1, else: socket.assigns.user_page - 1

    socket =
      socket
      |> assign(user_page: max(target, 1))
      |> load_users()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_scope", %{"scope" => scope}, socket) do
    socket =
      socket
      |> assign(scope_filter: scope, user_page: 1)
      |> load_users()

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

    case ActionDispatcher.dispatch(:auth, :register, payload,
           caller_scopes: caller_scopes(socket)
         ) do
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
        case ActionDispatcher.dispatch(:auth, :reset_password, payload,
               caller_scopes: caller_scopes(socket)
             ) do
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
               reset_password_error: "Password reset failed: #{UserForms.failure_message(reason)}"
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

    case ActionDispatcher.dispatch(
           :auth,
           :update_user_roles,
           %{
             user_id: pid,
             role: role,
             scopes: scopes
           },
           caller_scopes: caller_scopes(socket)
         ) do
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
    case ActionDispatcher.dispatch(:auth, :delete_user, %{player_id: player_id},
           caller_scopes: caller_scopes(socket)
         ) do
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

    case ActionDispatcher.dispatch(:auth, :issue_token, %{player_id: player_id, scopes: scopes},
           caller_scopes: caller_scopes(socket)
         ) do
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
  def handle_event("switch_user_inspect_tab", %{"tab" => tab}, socket) do
    socket = assign(socket, :user_inspect_tab, tab)
    socket = if tab == "events", do: socket |> assign(user_events_page: 1) |> load_user_events(), else: socket
    {:noreply, socket}
  end

  def handle_event("user_events_page", %{"page" => page}, socket) do
    target = if page == "next", do: socket.assigns.user_events_page + 1, else: socket.assigns.user_events_page - 1

    {:noreply,
     socket |> assign(user_events_page: max(target, 1)) |> load_user_events()}
  end

  def handle_event("toggle_user_events_archive", _params, socket) do
    {:noreply,
     socket
     |> assign(user_events_archive: !socket.assigns.user_events_archive, user_events_page: 1)
     |> load_user_events()}
  end

  def handle_event("refresh_user_events", _params, socket) do
    {:noreply, load_user_events(socket)}
  end

  # A capture is a debugging session, not a setting: sixty seconds of full payloads in memory.
  def handle_event("capture_player", %{"player" => player}, socket) do
    _ =
      ActionDispatcher.dispatch_internal(:observability, :capture, %{
        kind: "player",
        value: player,
        seconds: 60
      })

    {:noreply,
     assign(socket, :capture_notice, "Capturing #{player} for 60s — full payloads stay in memory.")}
  end

  def handle_event("stop_capture_player", %{"player" => player}, socket) do
    _ =
      ActionDispatcher.dispatch_internal(:observability, :stop_capture, %{
        kind: "player",
        value: player
      })

    {:noreply, assign(socket, :capture_notice, "Capture stopped.")}
  end

  @impl true
  def handle_event("close_focus", _params, socket) do
    tab = (socket.assigns[:extension] && socket.assigns.extension.id) || "exoforge_std_auth"

    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> push_patch(to: "/tab/#{tab}")}
  end

  ## ---- PRIVATE HELPERS ----

  # Opens a user's inspector drawer, resetting it to the Overview tab and picking up whatever
  # tabs plugins contribute through the `:user_inspect` hook point.
  @user_events_per_page 25

  defp event_errored?(ev) do
    payload = Map.get(ev, :payload) || %{}
    status = to_string(payload[:status] || payload["status"] || "")

    String.starts_with?(status, "error") or Map.has_key?(payload, :error) or
      Map.has_key?(payload, "error")
  end

  defp event_json(payload) do
    case Jason.encode(payload, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(payload, pretty: true)
    end
  end

  # The tab reads history through the observability contract: the live tail is the console's job,
  # and a support question is about what happened earlier.
  defp load_user_events(socket) do
    player = socket.assigns[:selected_user] && socket.assigns.selected_user["player_id"]

    if is_nil(player) do
      assign(socket, user_events: [], user_events_total: 0, user_events_pages: 1)
    else
      page = max(socket.assigns.user_events_page, 1)

      payload = %{
        player: to_string(player),
        limit: @user_events_per_page,
        offset: (page - 1) * @user_events_per_page
      }

      payload = if socket.assigns.user_events_archive, do: Map.put(payload, :since_ms, 1), else: payload

      case ActionDispatcher.dispatch_internal(:observability, :events, payload) do
        {:ok, %{events: events, total: total} = result} ->
          pages = max(ceil(total / @user_events_per_page), 1)

          assign(socket,
            user_events: events,
            user_events_total: total,
            user_events_pages: pages,
            user_events_page: min(page, pages),
            user_events_capped: Map.get(result, :capped, false)
          )

        _ ->
          assign(socket, user_events: [], user_events_total: 0, user_events_pages: 1, user_events_capped: false)
      end
    end
  end

  # Overview and Events are always present; hooked tabs come after them.
  defp user_inspect_tabs(hooks) do
    [
      %{id: :overview, title: "Overview", icon: "🧭"},
      %{id: :events, title: "Events", icon: "📡"}
    ] ++ hooks
  end

  defp select_user(socket, player_id) do
    current =
      case socket.assigns[:selected_user] do
        %{"player_id" => pid} -> to_string(pid)
        _ -> nil
      end

    if current == to_string(player_id) do
      socket
    else
      case Enum.find(socket.assigns.users, &(to_string(&1["player_id"]) == to_string(player_id))) do
        nil ->
          assign(socket, :selected_user, nil)

        user ->
          socket
          |> assign(:selected_user, user)
          |> assign(:user_inspect_tab, "overview")
          |> assign(:capture_notice, nil)
          |> assign(:user_inspect_hooks, Exoforge.UIHookRegistry.list_hooks(:user_inspect))
      end
    end
  end

  # The drawer is a URL (`/tab/exoforge_std_auth?focus=user:<id>`), not component state, so the
  # browser back button closes it and a deep link opens it.
  defp sync_focus(socket) do
    case socket.assigns[:focus] do
      %{kind: "user", id: id} -> select_user(socket, id)
      _ -> assign(socket, :selected_user, nil)
    end
  end

  # 25 accounts a page: a game directory is not a list you scroll to the end of.
  @per_page 25

  defp load_users(socket) do
    page = max(socket.assigns.user_page, 1)

    payload = %{
      limit: @per_page,
      offset: (page - 1) * @per_page,
      search: socket.assigns.search_query,
      scope: socket.assigns.scope_filter
    }

    case ActionDispatcher.dispatch_internal(:auth, :list_users, payload) do
      {:ok, %{users: users, count: total}} ->
        pages = max(ceil(total / @per_page), 1)

        assign(socket,
          users: users,
          filtered_users: users,
          users_total: total,
          user_pages: pages,
          user_page: min(page, pages)
        )

      _ ->
        assign(socket, users: [], filtered_users: [], users_total: 0, user_pages: 1, user_page: 1)
    end
  end

  ## ---- TEMPLATE RENDERING ----

  @impl true
  def render(assigns) do
    total_users = assigns.users_total
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
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-xl border border-gray-200/80 shadow-sm">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-xl bg-primary-100 text-primary-700 flex items-center justify-center text-2xl shadow-inner">
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
            class="px-4 py-2 text-sm font-semibold text-white bg-primary-600 rounded-xl hover:bg-primary-700 transition-colors shadow-sm flex items-center gap-2"
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
        <div class="bg-emerald-500/10 border border-emerald-500/20 rounded-xl p-4 shadow-sm flex items-center justify-between animate-in fade-in duration-150">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-lg bg-emerald-600 text-white flex items-center justify-center font-bold text-sm shrink-0">
              ✓
            </div>
            <p class="text-xs font-bold text-emerald-800">
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
        <div class="bg-primary-500/10 border border-primary-500/20 rounded-xl p-5 shadow-sm">
          <div class="flex items-start justify-between">
            <div class="flex items-start gap-3">
              <div class="w-8 h-8 rounded-lg bg-primary-600 text-white flex items-center justify-center font-bold text-sm shrink-0 mt-0.5">
                🔑
              </div>
              <div class="space-y-1">
                <h4 class="text-sm font-bold text-primary-900">
                  New Bearer Token Generated for <span class="font-bold text-primary-600"><%= @issued_token_info[:name] || @issued_token_info.player_id %></span>
                </h4>
                <p class="text-xs text-primary-700">
                  Save this token securely. It grants client authentication with scopes:
                  <span class="font-semibold"><%= Enum.join(@issued_token_info.scopes, ", ") %></span>.
                </p>
                <div class="mt-2 flex items-center gap-2">
                  <input
                    type="text"
                    readonly
                    value={@issued_token_info.token}
                    class="font-mono text-xs bg-white text-gray-800 border border-primary-300 rounded-lg px-3 py-1.5 w-full max-w-xl shadow-inner select-all"
                  />
                  <button
                    phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: @issued_token_info.token})}
                    class="text-xs font-semibold px-3 py-1.5 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors shadow-sm"
                  >
                    Copy
                  </button>
                </div>
              </div>
            </div>
            <button
              phx-click="dismiss_token_banner"
              phx-target={@myself}
              class="text-primary-400 hover:text-primary-700 text-sm font-bold p-1"
            >
              ✕
            </button>
          </div>
        </div>
      <% end %>

      <!-- Metric Cards Grid -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div class="bg-white p-4 rounded-xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title="Distinct identity profiles">
          <div class="w-11 h-11 rounded-xl bg-primary-50 text-primary-600 flex items-center justify-center text-xl shrink-0">
            👥
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Registered Accounts</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-xl font-black text-gray-900"><%= @total_users %></span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-primary-50 text-primary-700">Auth DB</span>
            </div>
          </div>
        </div>

        <div class="bg-white p-4 rounded-xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title="Active bearer tokens (this page)">
          <div class="w-11 h-11 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center text-xl shrink-0">
            🎟️
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Active Tokens</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-xl font-black text-gray-900"><%= @total_tokens %></span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700">In Pool</span>
            </div>
          </div>
        </div>

        <div class="bg-white p-4 rounded-xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title="Admin & superuser scopes (this page)">
          <div class="w-11 h-11 rounded-xl bg-amber-50 text-amber-600 flex items-center justify-center text-xl shrink-0">
            👑
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Admin Roles</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-xl font-black text-gray-900"><%= @admin_count %></span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-50 text-amber-700">Elevated</span>
            </div>
          </div>
        </div>

        <div class="bg-white p-4 rounded-xl border border-gray-200/80 shadow-sm flex items-center gap-3.5" title="Verified gameplay accounts (this page)">
          <div class="w-11 h-11 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center text-xl shrink-0">
            🎮
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-xs font-semibold text-gray-500 truncate">Player Scopes</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-xl font-black text-gray-900"><%= @player_count %></span>
              <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700">Standard</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Filters & Search Toolbar -->
      <div class="bg-white p-4 rounded-xl border border-gray-200/80 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div class="flex items-center gap-3 flex-1 max-w-md">
          <form id="auth-search-form" phx-change="search" phx-submit="search" phx-target={@myself} class="relative w-full">
            <input
              type="search"
              placeholder="Search user ID or scope..."
              value={@search_query}
              phx-debounce="200"
              name="query"
              class="w-full pl-9 pr-4 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white transition-all"
            />
            <svg class="w-4 h-4 text-gray-400 absolute left-3 top-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </form>
        </div>

        <div class="flex items-center gap-2">
          <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider mr-1">Scope:</span>
          <%= for {label, key} <- [{"All", "all"}, {"Admin", "admin"}, {"Player", "player"}, {"Guest", "guest"}] do %>
            <button
              phx-click="filter_scope"
              phx-value-scope={key}
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors #{if @scope_filter == key, do: "bg-primary-600 text-white shadow-sm", else: "bg-gray-100 text-gray-600 hover:bg-gray-200"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>
      </div>

      <div class="flex items-center justify-between px-1 text-xs text-gray-500">
        <span>
          <%= if @user_pages > 1 do %>
            Page <%= @user_page %> of <%= @user_pages %> &bull; <%= @users_total %> accounts
          <% else %>
            <%= @users_total %> account(s)
          <% end %>
        </span>
        <%= if @user_pages > 1 do %>
          <div class="flex items-center gap-1.5">
            <button
              type="button"
              phx-click="user_page"
              phx-value-page="prev"
              phx-target={@myself}
              disabled={@user_page <= 1}
              class="px-2.5 py-1 rounded-lg bg-white border border-gray-200 text-gray-600 disabled:opacity-40 disabled:cursor-not-allowed"
            >‹ Prev</button>
            <button
              type="button"
              phx-click="user_page"
              phx-value-page="next"
              phx-target={@myself}
              disabled={@user_page >= @user_pages}
              class="px-2.5 py-1 rounded-lg bg-white border border-gray-200 text-gray-600 disabled:opacity-40 disabled:cursor-not-allowed"
            >Next ›</button>
          </div>
        <% end %>
      </div>

      <!-- Users Directory Table -->
      <div class="bg-white rounded-xl border border-gray-200/80 shadow-sm overflow-hidden">
        <%= if @filtered_users == [] do %>
          <div class="p-12 text-center">
            <div class="w-12 h-12 rounded-xl bg-gray-100 text-gray-400 mx-auto flex items-center justify-center text-xl mb-3">
              🔍
            </div>
            <h3 class="text-sm font-bold text-gray-900">No accounts found</h3>
            <p class="text-xs text-gray-500 mt-1 max-w-sm mx-auto">
              <%= if @search_query == "" and @scope_filter == "all" do %>
                No user identities have been registered in the auth database yet. Click "Register User" above to create the first account.
              <% else %>
                No accounts match the search query or scope filter. Try clearing your filters.
              <% end %>
            </p>
            <%= if @search_query == "" and @scope_filter == "all" do %>
              <button
                phx-click="open_register_modal"
                phx-target={@myself}
                class="mt-4 px-4 py-2 text-xs font-semibold text-white bg-primary-600 rounded-xl hover:bg-primary-700 transition-colors shadow-sm inline-flex items-center gap-1.5"
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
                  <tr class="hover:bg-primary-50/30 transition-colors group">
                    <td class="py-3.5 px-4">
                      <div class="flex items-center gap-3">
                        <div class="w-9 h-9 rounded-xl bg-primary-50 text-primary-700 font-bold text-xs flex items-center justify-center shrink-0 border border-primary-100">
                          <%= String.slice(to_string(user["name"] || user["email"] || user["player_id"]), 0, 2) |> String.upcase() %>
                        </div>
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
                              class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-primary-600 transition-opacity text-xs"
                            >
                              📋
                            </button>
                          </div>
                          <span class="text-xs text-gray-500 font-medium mt-0.5"><%= user["email"] || user["user_id"] || user["player_id"] %></span>
                        </div>
                      </div>
                    </td>
                    <td class="py-3.5 px-4">
                      <div class="flex flex-wrap gap-1.5">
                        <%= for scope <- user["scopes"] || [] do %>
                          <span class={"inline-flex items-center px-2 py-0.5 rounded-lg text-xs font-semibold #{case scope do
                            "admin" -> "bg-primary-100 text-primary-800 border border-primary-200"
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
                          phx-click="open_focus"
                          phx-value-kind="user"
                          phx-value-id={user["player_id"]}
                          title="View tokens & details"
                          class="px-2.5 py-1 text-xs font-semibold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-lg transition-colors"
                        >
                          Inspect
                        </button>

                        <details class="exo-menu">
                          <summary class="px-2 py-1 text-xs font-bold text-gray-500 hover:text-gray-800 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-lg cursor-pointer">
                            ⋯
                          </summary>
                          <div class="exo-menu-panel">
                            <button
                              type="button"
                              phx-click="issue_token"
                              phx-value-player_id={user["player_id"]}
                              phx-target={@myself}
                              title="Issue new bearer token"
                              class="exo-menu-item"
                            >
                              <span>🎟️</span> <span>+ Token</span>
                            </button>

                            <%= if is_protected do %>
                              <div class="px-3 py-1.5 text-[11px] text-gray-400 italic">
                                🔒 Protected Env Admin
                              </div>
                            <% else %>
                              <button
                                type="button"
                                phx-click="open_roles_modal"
                                phx-value-player_id={user["player_id"]}
                                phx-target={@myself}
                                title="Edit user scopes and roles"
                                class="exo-menu-item"
                              >
                                <span>🛡️</span> <span>Roles</span>
                              </button>
                              <button
                                type="button"
                                phx-click="open_reset_password_modal"
                                phx-value-player_id={user["player_id"]}
                                phx-target={@myself}
                                title="Set or reset account password"
                                class="exo-menu-item"
                              >
                                <span>🔑</span> <span>Reset PW</span>
                              </button>
                              <button
                                type="button"
                                phx-click="delete_user"
                                phx-value-player_id={user["player_id"]}
                                phx-target={@myself}
                                data-confirm={"Are you sure you want to permanently delete user account '#{user["name"] || user["player_id"]}'?"}
                                title="Delete user account"
                                class="exo-menu-item exo-menu-danger"
                              >
                                <span>🗑</span> <span>Delete</span>
                              </button>
                            <% end %>
                          </div>
                        </details>
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
          <div class="fixed inset-0" phx-click="close_register_modal" phx-target={@myself}></div>
          <div class="bg-white rounded-xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_register_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-5">
              <div class="w-10 h-10 rounded-xl bg-primary-100 text-primary-700 flex items-center justify-center text-xl">
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
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white font-mono"
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
                    class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white"
                  />
                </div>
                <div>
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Email</label>
                  <input
                    type="email"
                    name="register[email]"
                    value={@register_form["email"]}
                    placeholder="e.g. player@domain.com"
                    class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white"
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
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white"
                />
                <p class="text-[11px] text-gray-400 mt-1">If set, the user can log into Exoforge Studio or APIs using email + password.</p>
              </div>

              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Account Role & Scopes</label>
                <select
                  name="register[role]"
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white font-medium text-gray-900"
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
                  phx-disable-with="Creating..."
                  class="px-5 py-2 text-xs font-bold text-white bg-primary-600 rounded-xl hover:bg-primary-700 transition-colors shadow-sm"
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
        <div class="fixed inset-0 z-[60] overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="fixed inset-0" phx-click="close_reset_password_modal" phx-target={@myself}></div>
          <div class="bg-white rounded-xl max-w-md w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_reset_password_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-primary-100 text-primary-700 flex items-center justify-center text-xl">
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
                  class="w-full px-3 py-2 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white"
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
                  class="px-5 py-2 text-xs font-bold text-white bg-primary-600 hover:bg-primary-700 rounded-xl shadow-sm transition-colors"
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
        <div class="fixed inset-0 z-[60] overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="fixed inset-0" phx-click="close_roles_modal" phx-target={@myself}></div>
          <div class="bg-white rounded-xl max-w-md w-full p-6 shadow-2xl border border-gray-200 relative animate-in fade-in duration-150">
            <button
              phx-click="close_roles_modal"
              phx-target={@myself}
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 text-lg font-bold"
            >
              ✕
            </button>

            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-xl bg-primary-100 text-primary-700 flex items-center justify-center text-xl">
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
                  class="w-full px-3 py-2.5 text-sm bg-gray-50 border border-gray-200 rounded-xl font-medium text-gray-900 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:bg-white"
                >
                  <option value="player" selected={@selected_role == "player"}>Player / Standard User</option>
                  <option value="studio" selected={@selected_role == "studio"}>Studio / Developer</option>
                  <option value="service" selected={@selected_role == "service"}>Service / Worker</option>
                  <option value="admin" selected={@selected_role == "admin"}>Administrator (All scopes)</option>
                  <option value="guest" selected={@selected_role == "guest"}>Guest (Limited access)</option>
                </select>
              </div>

              <!-- Granted Multi-Scopes Pill List -->
              <div class="p-3 bg-primary-50/70 border border-primary-200 rounded-xl space-y-1.5">
                <p class="text-[11px] font-bold text-primary-900 uppercase tracking-wider">Multi-Scopes Granted by this Role:</p>
                <div class="flex flex-wrap gap-1.5 pt-1">
                  <%= for scope <- @roles_form_scopes do %>
                    <span class="inline-flex items-center px-2 py-0.5 rounded-lg text-xs font-mono font-bold bg-white text-primary-800 border border-primary-200 shadow-2xs">
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
                  phx-disable-with="Updating..."
                  class="px-5 py-2 text-xs font-bold text-white bg-primary-600 hover:bg-primary-700 rounded-xl shadow-sm transition-colors"
                >
                  Update Roles
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- User Inspection Popup -->
      <%= if @selected_user do %>
        <% sel_is_protected = @selected_user["is_protected"] == true %>
        <Exoforge.Std.DashboardViews.InspectPopup.inspect_popup
          open={true}
          icon="👤"
          title={@selected_user["name"] || @selected_user["player_id"]}
          subtitle="Identity details & security tokens"
          tabs={user_inspect_tabs(@user_inspect_hooks)}
          active_tab={@user_inspect_tab}
          on_close="close_focus"
          on_select_tab="switch_user_inspect_tab"
          target={@myself}
        >
          <%= if @user_inspect_tab in ["overview", "", nil] do %>
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

            <div class="flex flex-wrap items-center gap-2">
              <button
                type="button"
                phx-click="capture_player"
                phx-value-player={@selected_user["player_id"]}
                phx-target={@myself}
                class="px-2.5 py-1.5 text-xs font-bold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-xl transition-colors inline-flex items-center gap-1.5"
                title="Keep this account's full action payloads in memory for 60 seconds"
              >
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path d="M12 3v3 M12 18v3 M3 12h3 M18 12h3 M12 8a4 4 0 100 8 4 4 0 000-8z" />
                </svg>
                Capture 60s
              </button>
              <button
                type="button"
                phx-click="stop_capture_player"
                phx-value-player={@selected_user["player_id"]}
                phx-target={@myself}
                class="px-2.5 py-1.5 text-xs font-bold text-gray-600 bg-gray-100 hover:bg-gray-200 border border-gray-200 rounded-xl transition-colors"
              >
                Stop capture
              </button>
              <%= if @capture_notice do %>
                <span class="text-[11px] text-gray-500"><%= @capture_notice %></span>
              <% end %>
            </div>

            <div>
              <div class="flex items-center justify-between mb-2">
                <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Granted Scopes</h4>
                <%= unless sel_is_protected do %>
                  <button
                    phx-click="open_roles_modal"
                    phx-value-player_id={@selected_user["player_id"]}
                    phx-target={@myself}
                    class="text-xs font-semibold text-primary-600 hover:text-primary-800"
                  >
                    Edit Roles
                  </button>
                <% end %>
              </div>
              <div class="flex flex-wrap gap-1.5">
                <%= for scope <- @selected_user["scopes"] || [] do %>
                  <span class={"inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-semibold #{case scope do
                    "admin" -> "bg-primary-100 text-primary-800 border border-primary-200"
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
              <button
                phx-click="open_reset_password_modal"
                phx-value-player_id={@selected_user["player_id"]}
                phx-target={@myself}
                class="w-full py-2 text-xs font-bold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-xl transition-colors text-center"
              >
                🔑 Reset Password
              </button>
            <% end %>

            <div>
              <div class="flex items-center justify-between mb-2">
                <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Active Bearer Tokens</h4>
                <button
                  phx-click="issue_token"
                  phx-value-player_id={@selected_user["player_id"]}
                  phx-target={@myself}
                  class="text-xs font-semibold text-primary-600 hover:text-primary-800"
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
                        class="text-xs text-primary-600 hover:text-primary-800 font-bold shrink-0"
                      >
                        Copy
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% else %>
            <%= if @user_inspect_tab == "events" do %>
              <div class="space-y-2">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Events triggered by this account</h4>
                  <div class="flex items-center gap-1.5 text-[10px] text-gray-400">
                    <span class="font-mono"><%= @user_events_total %> stored</span>
                    <button
                      type="button"
                      phx-click="refresh_user_events"
                      phx-target={@myself}
                      class="px-1.5 py-0.5 rounded bg-gray-100 hover:bg-gray-200 text-gray-600 font-bold"
                      title="Reload the page"
                    >
                      ↻
                    </button>
                    <button
                      type="button"
                      phx-click="toggle_user_events_archive"
                      phx-target={@myself}
                      class={"px-1.5 py-0.5 rounded font-bold border #{if @user_events_archive, do: "bg-primary-50 border-primary-200 text-primary-700", else: "bg-gray-100 border-gray-200 text-gray-600"}"}
                      title="Search archived days too (capped)"
                    >
                      📦 Archive
                    </button>
                  </div>
                </div>

                <%= if @user_events == [] do %>
                  <p class="text-xs text-gray-400 italic bg-gray-50 p-3 rounded-xl border border-gray-200">
                    Nothing yet. An event is attributed to this account when the action chain that raised it started with them — including the internal calls that chain makes.
                  </p>
                <% else %>
                  <div class="space-y-1.5 max-h-[320px] overflow-y-auto custom-scrollbar">
                    <%= for ev <- @user_events do %>
                      <% errored? = event_errored?(ev) %>
                      <div class={"p-2.5 rounded-xl border text-xs #{if errored?, do: "bg-red-50/70 border-red-200", else: "bg-gray-50 border-gray-200"}"}>
                        <div class="flex flex-wrap items-center justify-between gap-2">
                          <div class="flex items-center gap-2 min-w-0">
                            <span class={"px-1.5 py-0.5 rounded font-mono font-bold text-[10px] border #{if errored?, do: "bg-red-100 text-red-700 border-red-200", else: "bg-white text-primary-700 border-primary-200"}"}>
                              <%= ev.event %>
                            </span>
                            <%= if ev[:origin] not in [nil, ""] and to_string(ev[:origin]) != to_string(@selected_user["player_id"]) do %>
                              <span class="text-[10px] text-gray-500 font-mono truncate">via <%= ev.origin %></span>
                            <% end %>
                            <%= if ev[:rid] not in [nil, ""] do %>
                              <button
                                type="button"
                                phx-click="open_timeline"
                                phx-value-rid={ev.rid}
                                class="px-1 py-0.5 rounded bg-primary-50 border border-primary-200 text-primary-700 hover:bg-primary-100"
                                aria-label="Open this event's request timeline"
                                title="Open this event's request timeline"
                              >
                                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                  <path d="M2.04 12.32a1.01 1.01 0 010-.64C3.42 7.51 7.36 4.5 12 4.5s8.57 3.01 9.96 7.18c.07.21.07.43 0 .64C20.58 16.49 16.64 19.5 12 19.5s-8.57-3.01-9.96-7.18z M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                </svg>
                              </button>
                            <% end %>
                          </div>
                          <span class="text-[10px] text-gray-400 font-mono"><%= ev[:time] %></span>
                        </div>

                        <details class="group mt-1">
                          <summary class="cursor-pointer select-none text-[10px] font-bold text-gray-500 uppercase tracking-wider list-none">
                            <span class="group-open:hidden">▸ Payload</span>
                            <span class="hidden group-open:inline">▾ Payload</span>
                          </summary>
                          <pre class="mt-1 p-2 bg-gray-950 text-emerald-300 rounded-lg overflow-x-auto font-mono text-[10px] leading-relaxed custom-scrollbar"><%= event_json(ev[:payload]) %></pre>
                        </details>
                      </div>
                    <% end %>
                  </div>

                  <div class="flex items-center justify-between text-[10px] text-gray-400 font-mono">
                    <span>
                      Page <%= @user_events_page %> of <%= @user_events_pages %><%= if @user_events_capped, do: " (capped by the archive search)" %>
                    </span>
                    <%= if @user_events_pages > 1 do %>
                      <div class="flex items-center gap-1.5">
                        <button
                          type="button"
                          phx-click="user_events_page"
                          phx-value-page="prev"
                          phx-target={@myself}
                          disabled={@user_events_page <= 1}
                          class="px-2 py-0.5 rounded bg-white border border-gray-200 disabled:opacity-40"
                        >‹</button>
                        <button
                          type="button"
                          phx-click="user_events_page"
                          phx-value-page="next"
                          phx-target={@myself}
                          disabled={@user_events_page >= @user_events_pages}
                          class="px-2 py-0.5 rounded bg-white border border-gray-200 disabled:opacity-40"
                        >›</button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <%= for hook <- @user_inspect_hooks, to_string(hook.id) == @user_inspect_tab do %>
                <% mod = hook[:module] || hook["module"] %>
                <% mod_atom = cond do
                     is_atom(mod) -> mod
                     is_binary(mod) ->
                       try do
                         String.to_existing_atom(mod)
                       rescue
                         _ -> nil
                       end
                     true -> nil
                   end %>
                <%= if mod_atom && Code.ensure_loaded?(mod_atom) do %>
                  <.live_component
                    module={mod_atom}
                    id={"user_inspect_#{hook.id}"}
                    user={@selected_user}
                  />
                <% else %>
                  <p class="text-xs text-gray-400 italic">This tab does not provide a view.</p>
                <% end %>
              <% end %>
            <% end %>
          <% end %>

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
              phx-click="close_focus"
              class="w-full py-2 text-xs font-bold text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
            >
              Close
            </button>
          </div>
        </Exoforge.Std.DashboardViews.InspectPopup.inspect_popup>
      <% end %>
    </div>
    """
  end

  # The session's verified scopes (M33 Fix 28): administrative dispatches authorize with
  # the login, not with the dispatcher's internal default.
  defp caller_scopes(socket), do: socket.assigns[:current_scopes] || []
end
