defmodule Exoforge.Std.DashboardViews.UserPlayersTab do
  @moduledoc """
  User-inspector tab contributed by the player data plugin through the `:user_inspect` UI hook:
  the game players linked to an account, each a deep link into that player's own inspector.
  """
  use Phoenix.LiveComponent

  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket) do
    {:ok, assign(socket, players: [], loaded_user_id: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    user_id = user_id(socket.assigns[:user])

    if user_id && socket.assigns.loaded_user_id != user_id do
      {:ok, socket |> assign(:loaded_user_id, user_id) |> load_players(user_id)}
    else
      {:ok, socket}
    end
  end

  defp user_id(nil), do: nil

  defp user_id(user) when is_map(user) do
    user["user_id"] || user["player_id"] || user["id"] ||
      user[:user_id] || user[:player_id] || user[:id]
  end

  defp user_id(id) when is_binary(id), do: id
  defp user_id(_), do: nil

  defp load_players(socket, user_id) do
    players =
      case ActionDispatcher.dispatch(
             :player_data,
             :list_players,
             %{user_id: user_id},
             caller_scopes: [Exoforge.Auth.Roles.studio()]
           ) do
        {:ok, %{players: p}} when is_list(p) -> p
        {:ok, %{"players" => p}} when is_list(p) -> p
        _ -> []
      end

    assign(socket, :players, players)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-5 space-y-3">
      <div class="flex items-center justify-between">
        <h4 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Linked Players</h4>
        <span class="text-[10px] font-mono text-gray-400"><%= length(@players) %></span>
      </div>

      <%= if @players == [] do %>
        <p class="text-xs text-gray-400 italic bg-gray-50 p-3 rounded-xl border border-gray-200">
          No game players are linked to this account.
        </p>
      <% else %>
        <div class="space-y-2">
          <%= for player <- @players do %>
            <% pid = player[:player_id] || player["player_id"] %>
            <% name = player[:name] || player["name"] || pid %>
            <% status = player[:status] || player["status"] || "Active" %>
            <% total_spent = player[:total_spent] || player["total_spent"] || "$0.00" %>
            <% time_in_game = player[:time_in_game] || player["time_in_game"] || "0m" %>
            <.link
              patch={"/tab/exoforge_std_player_data?focus=player:#{URI.encode_www_form(to_string(pid))}"}
              class="block p-3 bg-gray-50 hover:bg-purple-50 border border-gray-200 hover:border-purple-200 rounded-xl transition-colors"
            >
              <div class="flex items-center justify-between">
                <span class="text-xs font-bold text-gray-900"><%= name %></span>
                <span class="text-[10px] font-bold text-emerald-700"><%= status %></span>
              </div>
              <div class="text-[10px] font-mono text-gray-500 mt-0.5"><%= pid %></div>
              <div class="text-[10px] text-gray-500 mt-1">
                Spent <span class="font-semibold"><%= total_spent %></span>
                · Played <span class="font-semibold"><%= time_in_game %></span>
              </div>
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
