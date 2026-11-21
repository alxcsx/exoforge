defmodule Exoforge.Std.Versioning do
  @moduledoc """
  Standard game-version registry: which game version is live, which is still served, which is
  blocked, and the extension versions each one locks.

  Persisted in the instance database. The status rules are `Exoforge.Std.Versioning.Policy`; this
  module reads the rows, asks the policy what moves, and writes the moves in one statement.

  Clients declare their game version at sign-in, and the ingress layers ask this extension whether that version may be served; that is why the registry is separate from any one game's code.

  ### How it works
  - Rows live in the game_versions table (version, status, locks, created_at), written through `:database` in this extension's own namespace.
  - A new version registers as dev; promoting it makes the previous live version outdated.
  - At most three versions are served: past the cap the oldest outdated one is blocked, configurable through the max_active_versions application setting.
  - Locks of a dev version can still change; live, outdated and blocked versions are immutable.
  - `Exoforge.Std.Versioning.Serializer` is a GenServer that serializes every mutation, so two changes never decide from the same stale row list.
  - Status changes are applied with one UPDATE built from a VALUES list, so a promotion and the demotion that goes with it are never half-written.
  - With no registered versions at all, resolution answers live with empty locks: versioning is off and every client is served.

  ### Depends on
  `:database`.
  """

  use Exoforge.Extension, provides: [:versioning]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database],
    title: "Game Versions",
    icon: "🏷️",
    dashboard_view: %{id: :versioning, title: "Game Versions", icon: "🏷️"},
    category: "System"
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Versioning.{Policy, Serializer}

  def children, do: [Serializer]

  def on_init(_manifest) do
    init_schema()
    :ok
  end

  @doc "Deletes every registered game version (instance reset). Returns how many there were."
  def wipe do
    init_schema()
    count = length(rows())
    _ = execute("DELETE FROM game_versions")
    count
  end

  @doc "Creates the game-version table in this extension's isolated database."
  def init_schema do
    _ =
      execute("""
      CREATE TABLE IF NOT EXISTS game_versions (
        version text PRIMARY KEY,
        status text NOT NULL,
        locks jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at bigint NOT NULL
      )
      """)

    :ok
  end

  @impl true
  defaction register(payload), scope: Exoforge.Auth.Roles.studio() do
    version = payload |> field(:version) |> to_string() |> String.trim()
    locks = field(payload, :locks) || %{}

    cond do
      version == "" or not is_map(locks) ->
        {:error, :invalid_version}

      true ->
        Serializer.run(fn ->
          rows = rows()

          with {:ok, changes} <- Policy.register(rows, version) do
            created_at = Enum.reduce(rows, 0, &max(&1.created_at, &2)) + 1

            execute(
              "INSERT INTO game_versions (version, status, locks, created_at) VALUES ($1, 'dev', $2::jsonb, $3)",
              [version, Jason.encode!(locks), created_at]
            )

            blocked = apply_changes(Map.delete(changes, version))
            {:ok, %{version: version, status: "dev", blocked: blocked}}
          end
        end)
    end
  end

  # Locks of a pre-production version can still change, because no player has been served by them. A live,
  # outdated or blocked version is immutable: its clients already depend on what it resolved to.
  @impl true
  defaction set_locks(payload), scope: Exoforge.Auth.Roles.studio() do
    version = payload |> field(:version) |> to_string()
    locks = field(payload, :locks)

    Serializer.run(fn ->
      case Enum.find(rows(), &(&1.version == version)) do
        nil ->
          {:error, :not_found}

        %{status: "dev", locks: current} when is_map(locks) ->
          merged = Map.merge(current, Map.new(locks, fn {k, v} -> {to_string(k), v} end))
          execute("UPDATE game_versions SET locks = $2::jsonb WHERE version = $1", [version, Jason.encode!(merged)])
          {:ok, %{version: version, status: "dev"}}

        %{status: "dev"} ->
          {:error, :invalid_locks}

        _ ->
          {:error, :locks_immutable}
      end
    end)
  end

  @impl true
  defaction promote(payload), scope: Exoforge.Auth.Roles.studio() do
    version = payload |> field(:version) |> to_string()

    Serializer.run(fn ->
      with {:ok, changes} <- Policy.promote(rows(), version) do
        blocked = apply_changes(changes)
        {:ok, %{version: version, status: "live", blocked: blocked}}
      end
    end)
  end

  @impl true
  defaction block(payload), scope: Exoforge.Auth.Roles.studio() do
    version = payload |> field(:version) |> to_string()

    Serializer.run(fn ->
      with {:ok, changes} <- Policy.block(rows(), version) do
        apply_changes(changes)
        {:ok, %{version: version, status: "blocked"}}
      end
    end)
  end

  @impl true
  defaction list(), scope: Exoforge.Auth.Roles.studio() do
    {:ok, %{versions: rows() |> Enum.sort_by(& &1.created_at, :desc) |> Enum.map(&Map.take(&1, [:version, :status, :locks, :created_at]))}}
  end

  @impl true
  defaction resolve(payload), scope: Exoforge.Auth.Roles.player() do
    version = payload |> field(:version) |> to_string()

    all = rows()

    case Enum.find(all, &(&1.version == version)) do
      # Nothing registered at all: versioning is not in use for this instance, so every client is served.
      nil when all == [] -> {:ok, %{version: version, status: "live", locks: %{}}}
      nil -> {:error, :not_found}
      row -> {:ok, %{version: row.version, status: row.status, locks: row.locks}}
    end
  end

  # -- storage --

  defp rows do
    "SELECT version, status, locks, created_at FROM game_versions"
    |> execute([])
    |> case do
      {:ok, %{rows: rows}} when is_list(rows) ->
        Enum.map(rows, fn row ->
          %{
            version: row["version"],
            status: row["status"],
            locks: decode_locks(row["locks"]),
            created_at: row["created_at"]
          }
        end)

      _ ->
        []
    end
  end

  # One statement, so a promotion and the demotion that goes with it are never half-written.
  # Returns the versions that ended up blocked by the change.
  defp apply_changes(changes) when map_size(changes) == 0, do: []

  defp apply_changes(changes) do
    {values, args} =
      changes
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {{version, status}, i}, acc ->
        {"($#{i * 2 + 1}::text, $#{i * 2 + 2}::text)", acc ++ [version, status]}
      end)

    execute(
      "UPDATE game_versions g SET status = c.status FROM (VALUES #{Enum.join(values, ", ")}) AS c(version, status) WHERE g.version = c.version",
      args
    )

    for {version, "blocked"} <- changes, do: version
  end

  defp decode_locks(locks) when is_map(locks), do: locks

  defp decode_locks(locks) when is_binary(locks) do
    case Jason.decode(locks) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_locks(_), do: %{}

  defp execute(operation, arguments \\ []) do
    ActionDispatcher.dispatch_internal(:database, :execute, %{
      plugin: :versioning,
      operation: operation,
      arguments: arguments
    })
  end

  defp field(payload, key), do: Map.get(payload, key) || Map.get(payload, to_string(key))
end
