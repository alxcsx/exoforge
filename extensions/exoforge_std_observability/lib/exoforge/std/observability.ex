defmodule Exoforge.Std.Observability do
  @moduledoc """
  Standard observability plugin: the durable event store and the queries that join one request
  back together.

  The kernel produces the primitives — `Exoforge.ActionTrace` (bounded, in-memory), `Exoforge.
  ErrorGroups`, `Exoforge.ExtensionLogs`, `Exoforge.Metering`, `Exoforge.EventDispatcher` — because
  `ActionDispatcher` writes to them on every call and cannot depend on an extension. This
  extension owns what the kernel must not: the persisted, queryable history of cluster events,
  and the `observability` contract other surfaces (Studio, Unity, CLI) read.

  The event store subscribes to the global event bus, keeps the most recent ring in ETS for the
  live tail, and persists events to its own isolated database. Retention, roll-ups and the cold
  archive build on this store (M42); the timeline merges the store with the kernel's trace, logs
  and error groups (M41).
  """

  use Exoforge.Extension, provides: [:observability]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database],
    title: "Observability",
    icon: "🔭",
    category: "System",
    dashboard_view: nil
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Observability.Analytics
  alias Exoforge.Std.Observability.Events

  def children, do: [Events]

  @impl true
  defaction recent_events(payload) do
    limit = int(payload, :limit, 50)
    {:ok, %{events: Events.list(limit)}}
  end

  @impl true
  defaction error_groups(payload) do
    limit = int(payload, :limit, 50)
    groups = Exoforge.ErrorGroups.list(payload, limit)
    {:ok, %{groups: groups, count: length(groups)}}
  end

  @impl true
  defaction events(payload), scope: Exoforge.Auth.Roles.studio() do
    {:ok, Events.query(payload, int(payload, :limit, 25), int(payload, :offset, 0))}
  end

  @impl true
  defaction purge_events(payload), scope: Exoforge.Auth.Roles.admin() do
    case value(payload, :origin) do
      origin when is_binary(origin) and origin != "" ->
        Events.purge_origin(origin)
        {:ok, %{status: "purged"}}

      _ ->
        {:error, :invalid_origin}
    end
  end

  @impl true
  defaction capture(payload), scope: Exoforge.Auth.Roles.studio() do
    rule =
      Exoforge.DebugCapture.capture(
        value(payload, :kind) || "player",
        value(payload, :value) || "*",
        int(payload, :seconds, 60)
      )

    {:ok, %{capture: rule}}
  end

  @impl true
  defaction captures, scope: Exoforge.Auth.Roles.studio() do
    {:ok, %{captures: Exoforge.DebugCapture.list()}}
  end

  @impl true
  defaction stop_capture(payload), scope: Exoforge.Auth.Roles.studio() do
    kind = value(payload, :kind) || "player"
    value = value(payload, :value)

    if kind == "global" and value in [nil, "", "*"] do
      Exoforge.DebugCapture.stop_all()
    else
      Exoforge.DebugCapture.stop(kind, value)
    end

    {:ok, %{status: "stopped"}}
  end

  @impl true
  defaction replay(payload), scope: Exoforge.Auth.Roles.studio() do
    case Exoforge.ActionTrace.deep_sample(int(payload, :id, 0)) do
      %{payload: request, service: service, action: action, caller: caller} = sample ->
        rid = Exoforge.RequestContext.new_rid()

        result =
          ActionDispatcher.dispatch(service, action, request,
            caller: caller,
            caller_scopes: :internal,
            rid: rid
          )

        {:ok,
         %{
           source_rid: sample.rid,
           rid: rid,
           status: replay_status(result),
           data: result
         }}

      %{too_large: size} ->
        {:error, {:payload_too_large, size}}

      nil ->
        {:error, :not_captured}
    end
  end

  @impl true
  defaction health(payload), scope: Exoforge.Auth.Roles.studio() do
    {:ok, Analytics.health(int(payload, :limit, 25))}
  end

  @impl true
  defaction timeline(payload), scope: Exoforge.Auth.Roles.studio() do
    nodes =
      Analytics.timeline(%{
        rid: value(payload, :rid),
        player: value(payload, :player),
        since_ms: int(payload, :since_ms, 0),
        limit: int(payload, :limit, 200)
      })

    {:ok, %{nodes: nodes, count: length(nodes)}}
  end

  @impl true
  defaction clear_events, scope: Exoforge.Auth.Roles.studio() do
    Events.clear()
    {:ok, %{status: "cleared"}}
  end

  # The contract passes either atom keys (internal dispatch) or string keys (HTTP/WS).
  defp value(payload, key) when is_map(payload),
    do: Map.get(payload, key) || Map.get(payload, to_string(key))

  defp value(_payload, _key), do: nil

  defp replay_status({:ok, data}), do: %{status: "ok", data: data}
  defp replay_status(:ok), do: %{status: "ok"}
  defp replay_status({:error, reason}), do: %{status: "error", error: inspect(reason)}

  defp int(payload, key, default) do
    case value(payload, key) do
      n when is_integer(n) ->
        n

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> default
        end

      _ ->
        default
    end
  end
end
