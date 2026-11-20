defmodule Exoforge.Std.Versioning.Policy do
  @moduledoc """
  The status rules for game versions, as pure functions over a list of rows.

  A row is `%{version, status, created_at}` with `status` one of `"dev"`, `"live"`, `"outdated"`,
  `"blocked"`. Each function returns the rows' new statuses as a `%{version => status}` map holding
  only what changed, so the caller writes them in one statement.
  """

  @default_max_active 3

  def max_active, do: Application.get_env(:exoforge_std_versioning, :max_active_versions, @default_max_active)

  @doc "A new version enters as `dev`; past the cap, the oldest `outdated` ones are blocked."
  def register(rows, version) do
    if Enum.any?(rows, &(&1.version == version)) do
      {:error, :already_exists}
    else
      rows = rows ++ [%{version: version, status: "dev", created_at: next_created_at(rows)}]
      enforce_cap(rows, %{version => "dev"})
    end
  end

  @doc "A `dev` version becomes `live`; the version that was live becomes `outdated`."
  def promote(rows, version) do
    case Enum.find(rows, &(&1.version == version)) do
      nil ->
        {:error, :not_found}

      %{status: "dev"} ->
        changes =
          rows
          |> Enum.filter(&(&1.status == "live"))
          |> Map.new(&{&1.version, "outdated"})
          |> Map.put(version, "live")

        enforce_cap(apply_changes(rows, changes), changes)

      _ ->
        {:error, :invalid_transition}
    end
  end

  @doc "Any version can be blocked; blocking a blocked one changes nothing."
  def block(rows, version) do
    case Enum.find(rows, &(&1.version == version)) do
      nil -> {:error, :not_found}
      %{status: "blocked"} -> {:ok, %{}}
      _ -> {:ok, %{version => "blocked"}}
    end
  end

  # Keep at most `max_active` versions that are not blocked, dropping the oldest `outdated` first.
  # When only `dev` and `live` ones remain over the cap there is nothing safe to drop.
  defp enforce_cap(rows, changes) do
    active = Enum.reject(rows, &(&1.status == "blocked"))

    if length(active) <= max_active() do
      {:ok, changes}
    else
      case active |> Enum.filter(&(&1.status == "outdated")) |> Enum.min_by(& &1.created_at, fn -> nil end) do
        nil -> {:error, :too_many_active}
        oldest -> enforce_cap(apply_changes(rows, %{oldest.version => "blocked"}), Map.put(changes, oldest.version, "blocked"))
      end
    end
  end

  defp apply_changes(rows, changes), do: Enum.map(rows, &%{&1 | status: Map.get(changes, &1.version, &1.status)})

  defp next_created_at(rows), do: Enum.reduce(rows, 0, &max(&1.created_at, &2)) + 1
end
