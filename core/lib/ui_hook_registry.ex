defmodule Exoforge.UIHookRegistry do
  @moduledoc """
  Unified registry for dynamic dashboard and inspector UI hooks.

  UI hooks allow plugins to contribute UI components, tabs, or action buttons
  to extension points across the Producer Studio without hardcoded couplings.

  Common hook points:
    * `:settings` - Tabs rendered in the Project Settings side drawer / modal.
    * `:player_inspect` - Tabs rendered inside the Player Profile inspector drawer.
    * Custom hook points defined by any view or plugin.
  """
  use GenServer

  @table :exo_ui_hooks_mem

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    initialize_ets()
    {:ok, %{}}
  end

  def initialize_ets do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc "Registers a UI hook under a specific hook point (e.g. :settings, :player_inspect)."
  def register_hook(hook_point, hook_id, spec \\ %{})
      when (is_atom(hook_point) or is_binary(hook_point)) and
             (is_atom(hook_id) or is_binary(hook_id)) do
    hp = normalize_id(hook_point)
    hid = normalize_id(hook_id)

    full_spec =
      spec
      |> default_spec(hid)
      |> Map.put(:id, hid)
      |> Map.put(:hook_point, hp)

    :ets.insert(@table, {{hp, hid}, full_spec})
    :ok
  end

  @doc "Unregisters a UI hook."
  def unregister_hook(hook_point, hook_id) do
    hp = normalize_id(hook_point)
    hid = normalize_id(hook_id)
    case :ets.info(@table) do
      :undefined -> :ok
      _ ->
        :ets.delete(@table, {hp, hid})
        :ok
    end
  end

  @doc "Unregisters all hooks registered by a specific plugin."
  def unregister_by_plugin(plugin_id) do
    pid = normalize_id(plugin_id)

    case :ets.info(@table) do
      :undefined ->
        :ok

      _ ->
        hooks = :ets.tab2list(@table)

        for {key, spec} <- hooks, Map.get(spec, :plugin_id) == pid do
          :ets.delete(@table, key)
        end

        :ok
    end
  end

  @doc "Lists all registered hooks for a given hook point, sorted by order."
  def list_hooks(hook_point) do
    hp = normalize_id(hook_point)

    case :ets.info(@table) do
      :undefined ->
        []

      _ ->
        :ets.match_object(@table, {{hp, :_}, :_})
        |> Enum.map(fn {_key, spec} -> spec end)
        |> Enum.sort_by(&Map.get(&1, :order, 100))
    end
  end

  @doc "Fetches a specific hook definition."
  def fetch_hook(hook_point, hook_id) do
    hp = normalize_id(hook_point)
    hid = normalize_id(hook_id)

    case :ets.info(@table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@table, {hp, hid}) do
          [{{^hp, ^hid}, spec}] -> spec
          _ -> nil
        end
    end
  end

  defp normalize_id(id) when is_atom(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_atom(id)

  defp default_spec(spec, id) when is_map(spec) do
    title =
      Map.get(spec, :title) || Map.get(spec, :label) ||
        (id |> to_string() |> String.replace("_", " ") |> String.capitalize())

    Map.merge(
      %{
        title: title,
        label: title,
        icon: "🔌",
        order: 100,
        view_type: :declarative
      },
      spec
    )
  end

  defp default_spec(_spec, id), do: default_spec(%{}, id)
end
