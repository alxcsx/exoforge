defmodule Exoforge.Std.CronTest do
  use ExUnit.Case, async: false

  alias Exoforge.Std.Cron
  alias Exoforge.Std.Cron.Parser
  alias Exoforge.Std.Cron.Scheduler

  describe "Parser" do
    test "matches wildcard (* * * * *)" do
      now = ~U[2026-11-07 14:32:00Z]
      assert Parser.matches?("* * * * *", now)
    end

    test "matches step expression (*/5 * * * *)" do
      at_minute_0 = ~U[2026-11-07 14:00:00Z]
      at_minute_5 = ~U[2026-11-07 14:05:00Z]
      at_minute_12 = ~U[2026-11-07 14:12:00Z]

      assert Parser.matches?("*/5 * * * *", at_minute_0)
      assert Parser.matches?("*/5 * * * *", at_minute_5)
      refute Parser.matches?("*/5 * * * *", at_minute_12)
    end

    test "matches specific midnight time (0 0 * * *) and @daily alias" do
      midnight = ~U[2026-11-07 00:00:00Z]
      noon = ~U[2026-11-07 12:00:00Z]

      assert Parser.matches?("0 0 * * *", midnight)
      assert Parser.matches?("@daily", midnight)
      refute Parser.matches?("0 0 * * *", noon)
      refute Parser.matches?("@daily", noon)
    end

    test "matches range (0 12 * * 1-5) for weekdays" do
      # 2026-11-06 is Friday (dow 5), 2026-11-07 is Saturday (dow 6)
      friday_noon = ~U[2026-11-06 12:00:00Z]
      saturday_noon = ~U[2026-11-07 12:00:00Z]

      assert Parser.matches?("0 12 * * 1-5", friday_noon)
      refute Parser.matches?("0 12 * * 1-5", saturday_noon)
    end
  end

  describe "Scheduler" do
    setup do
      unless Process.whereis(Exoforge.ExtensionRegistry) do
        start_supervised!(Exoforge.ExtensionRegistry)
      end

      Exoforge.ExtensionRegistry.register(%Exoforge.Domain.Manifest{
        id: :cron,
        name: "cron",
        version: "0.1.0",
        entry_point: Exoforge.Std.Cron,
        provides: [:cron]
      })

      start_supervised!({Scheduler, []})
      :ok
    end

    test "can register and list jobs" do
      job = %{
        name: "test_cleanup",
        service: "test_service",
        action: "cleanup",
        schedule: "0 0 * * *",
        description: "Test cleanup job"
      }

      assert {:ok, registered} = Scheduler.register_job(job)
      assert registered.id == "test_service:test_cleanup"

      jobs = Scheduler.list_jobs()
      assert Enum.any?(jobs, &(&1.id == "test_service:test_cleanup"))
    end

    test "can trigger a job by id" do
      job = %{
        name: "manual_job",
        service: "cron",
        action: "status",
        schedule: "@daily"
      }

      {:ok, _} = Scheduler.register_job(job)
      assert {:ok, result} = Scheduler.trigger("cron:manual_job")
      assert result == {:ok, %{active_jobs: length(Scheduler.list_jobs()), status: "online"}}

      # Check updated state
      jobs = Scheduler.list_jobs()
      found = Enum.find(jobs, &(&1.id == "cron:manual_job"))
      assert found.run_count >= 1
      assert found.last_status == "ok"
      assert is_binary(found.last_run)
    end

    test "trigger returns error for non-existent job" do
      assert {:error, :job_not_found} = Scheduler.trigger("unknown:job")
    end
  end

  describe "Cron Extension Actions" do
    test "status action returns active jobs count" do
      assert {:ok, %{status: "online", active_jobs: count}} = Cron.status()
      assert is_integer(count)
    end

    test "list_jobs action returns jobs list" do
      assert {:ok, %{jobs: jobs, count: count}} = Cron.list_jobs()
      assert is_list(jobs)
      assert count == length(jobs)
    end
  end
end
