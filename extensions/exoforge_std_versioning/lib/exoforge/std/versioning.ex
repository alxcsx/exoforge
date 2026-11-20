defmodule Exoforge.Std.Versioning do
  @moduledoc """
  Standard game-version registry: which game version is live, which is still served, which is
  blocked, and the extension versions each one locks.

  Persisted in the instance database. The status rules are `Exoforge.Std.Versioning.Policy`; this
  module reads the rows, asks the policy what moves, and writes the moves in one statement.
  """

  use Exoforge.Extension, provides: [:versioning]

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.Database],
    title: "Game Versions",
    icon: "🏷️",
    category: "System"
  }

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Versioning.{Policy, Serializer}

  def children, do: [Serializer]

  def on_init(_manifest) do
    init_schema()
    :ok
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

    case Enum.find(rows(), &(&1.version == version)) do
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
