defmodule Exoforge.BuildInfo do
  @moduledoc """
  Provides build metadata (version, git commit hash, and build timestamp)
  for runtime health checks, telemetry, cluster identification, and UI displays.
  """

  @version (
    case System.get_env("EXOFORGE_VERSION") do
      v when is_binary(v) and byte_size(v) > 0 ->
        v

      _ ->
        case :application.get_key(:exoforge, :vsn) do
          {:ok, vsn} ->
            to_string(vsn)

          _ ->
            case :application.get_key(:exoforge_core, :vsn) do
              {:ok, vsn} -> to_string(vsn)
              _ -> "0.1.31"
            end
        end
    end
  )

  @git_hash (
    case System.get_env("EXOFORGE_BUILD_HASH") || System.get_env("BUILD_HASH") ||
           System.get_env("COMMIT_SHA") do
      hash when is_binary(hash) and byte_size(hash) > 0 ->
        String.slice(hash, 0, 7)

      _ ->
        try do
          case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
            {output, 0} -> String.trim(output)
            _ -> "dev"
          end
        rescue
          _ -> "dev"
        end
    end
  )

  @build_date (
    case System.get_env("EXOFORGE_BUILD_DATE") || System.get_env("BUILD_DATE") do
      date when is_binary(date) and byte_size(date) > 0 ->
        date

      _ ->
        try do
          case System.cmd("git", ["log", "-1", "--format=%cd", "--date=format:%Y-%m-%d %H:%M"],
                 stderr_to_stdout: true
               ) do
            {output, 0} -> String.trim(output)
            _ -> DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
          end
        rescue
          _ -> DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
        end
    end
  )

  @doc "Returns the application version identifier."
  def version, do: @version

  @doc "Returns the short git commit hash."
  def commit_hash, do: @git_hash

  @doc "Returns the build or commit date string."
  def build_date, do: @build_date

  @doc "Returns build metadata map."
  def info do
    %{
      version: version(),
      commit_hash: commit_hash(),
      build_date: build_date(),
      formatted: "v#{version()} (#{commit_hash()}) - #{build_date()}"
    }
  end
end
