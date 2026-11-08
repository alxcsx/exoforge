defmodule Exoforge.Std.Cron.Scheduler do
  @moduledoc """
  Lightweight OTP cron scheduler for Exoforge.
  Periodically evaluates registered cron jobs against UTC wall clock time and
  dispatches actions via ActionDispatcher.
  """
  use GenServer
  require Logger

  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry
  alias Exoforge.Std.Cron.Parser

  @interval_ms 1_000
  @tab :exo_cron_jobs_mem

  defstruct [
    last_evaluated_minute: nil
  ]

  # ---- Client API ----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Lists all registered jobs directly from ETS for zero-latency concurrent reads."
  def list_jobs do
    case :ets.info(@tab) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(@tab)
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort_by(& &1.id)
    end
  end

  def trigger(job_id) do
    GenServer.call(__MODULE__, {:trigger, job_id})
  end

  def register_job(job) when is_map(job) do
    GenServer.call(__MODULE__, {:register_job, job})
  end

  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # ---- Server Callbacks ----

  @impl true
  def init(_opts) do
    if :ets.info(@tab) == :undefined do
      :ets.new(@tab, [:named_table, :public, :set, read_concurrency: true])
    end

    send(self(), :initial_scan)
    schedule_tick()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:trigger, job_id}, _from, state) do
    target_id = to_string(job_id)

    job =
      case :ets.lookup(@tab, target_id) do
        [{^target_id, j}] ->
          j

        _ ->
          list_jobs()
          |> Enum.find(fn j -> j.name == target_id end)
      end

    case job do
      nil ->
        {:reply, {:error, :job_not_found}, state}

      found_job ->
        {result, updated_job} = execute_job(found_job)
        :ets.insert(@tab, {found_job.id, updated_job})
        {:reply, {:ok, result}, state}
    end
  end

  @impl true
  def handle_call({:register_job, job_params}, _from, state) do
    job = normalize_job(job_params)
    :ets.insert(@tab, {job.id, job})
    {:reply, {:ok, job}, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    scanned_jobs = scan_all_jobs()

    Enum.each(scanned_jobs, fn {id, job} ->
      case :ets.lookup(@tab, id) do
        [] -> :ets.insert(@tab, {id, job})
        _ -> :ok
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:initial_scan, state) do
    scanned_jobs = scan_all_jobs()

    Enum.each(scanned_jobs, fn {id, job} ->
      if job.run_on_startup do
        Logger.info("[Cron] Running startup job: #{job.id} (#{job.service}.#{job.action})")
        {_res, updated} = execute_job(job)
        :ets.insert(@tab, {id, updated})
      else
        :ets.insert(@tab, {id, job})
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    now = DateTime.utc_now()
    current_minute = {now.year, now.month, now.day, now.hour, now.minute}

    # Only evaluate matching jobs once per minute
    if state.last_evaluated_minute != current_minute do
      for job <- list_jobs() do
        if Parser.matches?(job.schedule, now) do
          Logger.info("[Cron] Triggering scheduled job #{job.id} (#{job.schedule})")
          {_res, updated} = execute_job(job)
          :ets.insert(@tab, {job.id, updated})
        end
      end

      {:noreply, %{state | last_evaluated_minute: current_minute}}
    else
      {:noreply, state}
    end
  end

  # ---- Private Helpers ----

  defp schedule_tick do
    Process.send_after(self(), :tick, @interval_ms)
  end

  defp execute_job(job) do
    t0 = System.monotonic_time(:millisecond)
    service = parse_atom(job.service)
    action = parse_atom(job.action)

    res =
      try do
        ActionDispatcher.dispatch(service, action, %{}, caller_scopes: :internal)
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, inspect(reason)}
      end

    latency = System.monotonic_time(:millisecond) - t0
    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    status =
      case res do
        {:ok, _} -> "ok"
        :ok -> "ok"
        {:error, reason} -> "error: #{inspect(reason)}"
      end

    updated_job = %{
      job
      | last_run: now_iso,
        last_latency_ms: latency,
        last_status: status,
        run_count: (job.run_count || 0) + 1
    }

    {res, updated_job}
  end

  defp normalize_job(raw) when is_map(raw) do
    id = Map.get(raw, "id") || Map.get(raw, :id) || Map.get(raw, "name") || Map.get(raw, :name)
    name = Map.get(raw, "name") || Map.get(raw, :name) || id
    service = Map.get(raw, "service") || Map.get(raw, :service) || "global"
    action = Map.get(raw, "action") || Map.get(raw, :action) || name
    schedule = Map.get(raw, "schedule") || Map.get(raw, :schedule) || "* * * * *"
    run_on_startup = Map.get(raw, "run_on_startup") || Map.get(raw, :run_on_startup) || false
    description = Map.get(raw, "description") || Map.get(raw, :description) || ""

    job_id = "#{service}:#{name}"

    %{
      id: to_string(job_id),
      name: to_string(name),
      service: to_string(service),
      action: to_string(action),
      schedule: to_string(schedule),
      run_on_startup: !!run_on_startup,
      description: to_string(description),
      last_run: nil,
      last_latency_ms: nil,
      last_status: nil,
      run_count: 0
    }
  end

  defp scan_all_jobs do
    try do
      ExtensionRegistry.all_manifests()
      |> Enum.flat_map(fn manifest ->
        services = ExtensionRegistry.manifest_services(manifest)

        Enum.flat_map(services, fn svc_meta ->
          svc_name = Map.get(svc_meta, :name) || Map.get(svc_meta, "name")
          crons = Map.get(svc_meta, :crons) || Map.get(svc_meta, "crons") || []

          Enum.map(crons, fn cron_def ->
            cron_def
            |> Map.put_new(:service, svc_name)
            |> Map.put_new("service", svc_name)
            |> normalize_job()
          end)
        end)
      end)
      |> Map.new(fn job -> {job.id, job} end)
    rescue
      _ -> %{}
    end
  end

  defp parse_atom(val) when is_atom(val), do: val
  defp parse_atom(val) when is_binary(val), do: Exoforge.Atoms.existing(val, String.to_atom(val))
  defp parse_atom(other), do: other
end
