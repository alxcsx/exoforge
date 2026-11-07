defmodule Exoforge.Std.Cron do
  @moduledoc """
  Standard scheduled background task and cron execution extension for Exoforge.
  Provides the :cron service contract.
  """
  use Exoforge.Extension, provides: [:cron]

  alias Exoforge.Std.Cron.Scheduler

  @manifest %{
    title: "Cron & Scheduled Tasks",
    icon: "⏱️",
    category: "Operations",
    system: true,
    dashboard_view: nil
  }

  def children do
    [
      {Scheduler, []}
    ]
  end

  # ---- Actions ----

  @impl true
  defaction list_jobs(), scope: "studio" do
    jobs = Scheduler.list_jobs()
    {:ok, %{jobs: jobs, count: length(jobs)}}
  end

  @impl true
  defaction trigger_job(payload), scope: "studio" do
    job_id = Map.get(payload, "job_id") || Map.get(payload, :job_id)

    case Scheduler.trigger(job_id) do
      {:ok, result} ->
        {:ok, %{status: "triggered", result: result}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  defaction status() do
    jobs = Scheduler.list_jobs()
    {:ok, %{status: "online", active_jobs: length(jobs)}}
  end
end
