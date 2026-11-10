defmodule Exoforge.Std.Dashboard.Preferences do
  @moduledoc """
  Per-account Studio preferences, stored through the resource store.

  The backing table is declared by the `studio_preference` resource in the
  `:dashboard` contract (`source: {:table, "studio_preferences"}`), so the
  resource store owns its DDL and CRUD — no hand-written SQL here.
  """
  alias Exoforge.ActionDispatcher

  @resource "studio_preference"

  @doc "Returns the pinned extension ids for an account."
  def pinned(player_id) when is_binary(player_id) and player_id != "" do
    case fetch_prefs(player_id) do
      %{"pinned" => list} when is_list(list) -> Enum.map(list, &to_string/1)
      list when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  def pinned(_player_id), do: []

  @doc "Persists the pinned extension ids for an account."
  def put_pinned(player_id, pinned)
      when is_binary(player_id) and player_id != "" and is_list(pinned) do
    prefs =
      case fetch_prefs(player_id) do
        %{} = map -> Map.put(map, "pinned", Enum.map(pinned, &to_string/1))
        _ -> Enum.map(pinned, &to_string/1)
      end

    save_prefs(player_id, prefs)
  end

  def put_pinned(_player_id, _pinned), do: :ok

  @doc "Returns the overview grid slot order for an account."
  def overview_order(player_id) when is_binary(player_id) and player_id != "" do
    case fetch_prefs(player_id) do
      %{"overview_order" => list} when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  def overview_order(_player_id), do: []

  @doc "Persists the overview grid slot order for an account."
  def put_overview_order(player_id, order)
      when is_binary(player_id) and player_id != "" and is_list(order) do
    current =
      case fetch_prefs(player_id) do
        %{} = map -> map
        list when is_list(list) -> %{"pinned" => Enum.map(list, &to_string/1)}
        _ -> %{}
      end

    save_prefs(player_id, Map.put(current, "overview_order", Enum.map(order, &to_string/1)))
  end

  def put_overview_order(_player_id, _order), do: :ok

  @doc """
  Services whose actions this account tracks in the console and the telemetry graphs.

  An empty list means "all" — the default, and the only sane one for a fresh account, since
  narrowing it hides traffic instead of reducing it.
  """
  def tracked_services(player_id) when is_binary(player_id) and player_id != "" do
    case fetch_prefs(player_id) do
      %{"tracked_services" => list} when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  def tracked_services(_player_id), do: []

  @doc "Persists the tracked service list (empty means all)."
  def put_tracked_services(player_id, services)
      when is_binary(player_id) and player_id != "" and is_list(services) do
    current =
      case fetch_prefs(player_id) do
        %{} = map -> map
        list when is_list(list) -> %{"pinned" => Enum.map(list, &to_string/1)}
        _ -> %{}
      end

    save_prefs(player_id, Map.put(current, "tracked_services", Enum.map(services, &to_string/1)))
  end

  def put_tracked_services(_player_id, _services), do: :ok

  defp fetch_prefs(player_id) do
    case store(:get, %{resource: @resource, id: player_id, optional: true}) do
      {:ok, %{row: row}} when is_map(row) ->
        raw = Map.get(row, "data") || Map.get(row, :data) || "[]"

        case Jason.decode(raw) do
          {:ok, decoded} -> decoded
          _ -> []
        end

      _ ->
        []
    end
  end

  defp save_prefs(player_id, data) do
    store(:upsert, %{
      resource: @resource,
      attributes: %{
        "player_id" => player_id,
        "data" => Jason.encode!(data)
      }
    })
  end

  defp store(action, payload), do: ActionDispatcher.dispatch_internal(:resource_store, action, payload)
end
