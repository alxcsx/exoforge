defmodule Exoforge.Std.Dashboard.ProjectMetadata do
  @moduledoc """
  Global cluster and project metadata, stored through the resource store.

  Reuses the `studio_preference` resource with a reserved key `"__project__"`
  so project metadata is durably persisted with zero extra migrations or tables.
  Synchronizes runtime configuration with `Application.get_env(:exoforge, :instance)`
  so metering, telemetry, and system info reflect live metadata changes.
  """
  alias Exoforge.ActionDispatcher
  alias Exoforge.EventDispatcher

  @resource "studio_preference"
  @project_key "__project__"

  @default_project_name "Exoforge Cluster"
  @default_studio_name "Exoforge Studio"

  @doc "Initializes project metadata at boot and synchronizes application environment."
  def init do
    get()
    :ok
  end

  @doc "Returns the global project and studio metadata map."
  def get do
    stored = fetch_raw_stored()
    defaults = default_metadata()

    metadata =
      defaults
      |> Map.merge(stored)
      |> normalize_metadata()

    sync_instance_env(metadata)
    metadata
  end

  @doc "Persists updated project metadata, syncs environment, and broadcasts the update event."
  def put(attrs) when is_map(attrs) or is_list(attrs) do
    attrs_map = if is_list(attrs), do: Map.new(attrs), else: attrs

    current = get()

    updated =
      current
      |> update_field(attrs_map, :project_name, "project_name")
      |> update_field(attrs_map, :studio_name, "studio_name")
      |> update_field(attrs_map, :description, "description")
      |> update_field(attrs_map, :website_url, "website_url")
      |> update_custom(attrs_map)
      |> Map.put("updated_at", System.system_time(:second))
      |> normalize_metadata()

    save_payload = %{
      resource: @resource,
      attributes: %{
        "player_id" => @project_key,
        "data" => Jason.encode!(updated)
      }
    }

    _ = ActionDispatcher.dispatch_internal(:resource_store, :upsert, save_payload)

    sync_instance_env(updated)

    EventDispatcher.broadcast(
      :"project.metadata_updated",
      %{metadata: updated},
      topic: "system"
    )

    {:ok, updated}
  end

  def put(_), do: {:error, :invalid_attributes}

  # --- Helpers ---

  defp default_metadata do
    instance = Application.get_env(:exoforge, :instance, [])

    %{
      "project_name" => Keyword.get(instance, :project_name, @default_project_name),
      "studio_name" => Keyword.get(instance, :studio_name, @default_studio_name),
      "description" => Keyword.get(instance, :description, ""),
      "website_url" => Keyword.get(instance, :website_url, ""),
      "custom" => %{},
      "updated_at" => System.system_time(:second)
    }
  end

  defp fetch_raw_stored do
    case ActionDispatcher.dispatch_internal(:resource_store, :get, %{
           resource: @resource,
           id: @project_key,
           optional: true
         }) do
      {:ok, %{row: row}} when is_map(row) ->
        raw = Map.get(row, "data") || Map.get(row, :data) || "{}"

        case Jason.decode(raw) do
          {:ok, decoded} when is_map(decoded) -> decoded
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp update_field(current, incoming, atom_key, string_key) do
    case Map.fetch(incoming, atom_key) do
      {:ok, val} when is_binary(val) ->
        Map.put(current, string_key, String.trim(val))

      _ ->
        case Map.fetch(incoming, string_key) do
          {:ok, val} when is_binary(val) ->
            Map.put(current, string_key, String.trim(val))

          _ ->
            current
        end
    end
  end

  defp update_custom(current, incoming) do
    custom_val = Map.get(incoming, :custom) || Map.get(incoming, "custom")

    case custom_val do
      map when is_map(map) ->
        normalized =
          map
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
          |> Map.new()

        Map.put(current, "custom", normalized)

      _ ->
        current
    end
  end

  defp normalize_metadata(map) do
    %{
      "project_name" =>
        non_empty_string(map["project_name"] || map[:project_name], @default_project_name),
      "studio_name" =>
        non_empty_string(map["studio_name"] || map[:studio_name], @default_studio_name),
      "description" => to_string(map["description"] || map[:description] || ""),
      "website_url" => to_string(map["website_url"] || map[:website_url] || ""),
      "custom" => normalize_custom_map(map["custom"] || map[:custom] || %{}),
      "updated_at" => map["updated_at"] || map[:updated_at] || System.system_time(:second)
    }
  end

  defp non_empty_string(val, default) do
    s = to_string(val || "") |> String.trim()
    if s == "", do: default, else: s
  end

  defp normalize_custom_map(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Map.new()
  end

  defp normalize_custom_map(_), do: %{}

  defp sync_instance_env(metadata) do
    current = Application.get_env(:exoforge, :instance, [])

    updated =
      current
      |> Keyword.put(:project_name, metadata["project_name"])
      |> Keyword.put(:studio_name, metadata["studio_name"])
      |> Keyword.put(:description, metadata["description"])
      |> Keyword.put(:website_url, metadata["website_url"])

    Application.put_env(:exoforge, :instance, updated)
  end
end
