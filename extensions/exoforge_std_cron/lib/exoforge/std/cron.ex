defmodule Exoforge.Std.Cron do
  @moduledoc """
  Standard scheduled background task and cron execution extension for Exoforge.
  Provides the :cron service contract.

  It exists as an extension so recurring work belongs to the cluster, not to any one game's process, and the Studio can list or trigger jobs directly.

  ### How it works
  - `Exoforge.Std.Cron.Scheduler` is the supervised GenServer; it owns the ETS table `exo_cron_jobs_mem`.
  - On boot it scans every service manifest for `crons` entries and inserts one job per entry, keyed by service and name.
  - A one-second timer wakes the scheduler, but each job is evaluated at most once per UTC minute.
  - Schedules are standard five-field cron expressions with aliases such as `@daily`, parsed by `Exoforge.Std.Cron.Parser`.
  - A due job is dispatched with `caller: :cron` and internal trust, then its last run, latency and status are written back to ETS.
  - Jobs marked `run_on_startup` run once during the initial scan instead of waiting for their slot.

  ### Depends on
  Nothing fixed: a job calls whichever service its manifest entry names.
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
  defaction status(), scope: Exoforge.Auth.Roles.studio() do
    jobs = Scheduler.list_jobs()
    {:ok, %{status: "online", active_jobs: length(jobs)}}
  end
end
