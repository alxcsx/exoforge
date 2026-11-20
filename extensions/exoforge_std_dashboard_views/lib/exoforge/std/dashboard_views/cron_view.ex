defmodule Exoforge.Std.DashboardViews.CronView do
  @moduledoc """
  The Studio screen for scheduled jobs (service `:cron`): every `[ExoCron]` the running extensions declare, when it
  runs, what happened the last time, and a way to run it now.

  Running a job calls the action it names with the cluster's trust, so Run now asks first and names the action.
  """
  use Phoenix.LiveComponent
  import Exoforge.Std.DashboardViews.Icons, only: [studio_icon: 1]
  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket), do: {:ok, assign(socket, jobs: [], confirm: nil, notice: nil, error: nil, loaded: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns.loaded, do: socket, else: socket |> assign(:loaded, true) |> load())}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, socket |> assign(confirm: nil, notice: nil, error: nil) |> load()}
  def handle_event("ask", %{"id" => id}, socket), do: {:noreply, assign(socket, confirm: id, notice: nil, error: nil)}
  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :confirm, nil)}

  def handle_event("run", _params, %{assigns: %{confirm: id}} = socket) when is_binary(id) do
    socket =
      case ActionDispatcher.dispatch_internal(:cron, :trigger_job, %{job_id: id}) do
        {:ok, _} -> assign(socket, notice: "#{id} ran.", error: nil)
        {:error, reason} -> assign(socket, error: "#{id} could not run: #{inspect(reason)}.", notice: nil)
      end

    {:noreply, socket |> assign(:confirm, nil) |> load()}
  end

  def handle_event("run", _params, socket), do: {:noreply, socket}

  defp load(socket) do
    case ActionDispatcher.dispatch_internal(:cron, :list_jobs, %{}) do
      {:ok, %{jobs: jobs}} when is_list(jobs) -> assign(socket, :jobs, jobs)
      _ -> assign(socket, :jobs, [])
    end
  end

  ## ---- pure helpers (tested directly) ----

  @doc "A common five-field schedule in words; anything else is shown as written."
  def describe("* * * * *"), do: "every minute"
  def describe("*/" <> _ = schedule), do: describe_step(schedule)
  def describe("0 * * * *"), do: "every hour"
  def describe("0 0 * * *"), do: "every day at 00:00"
  def describe("@" <> _ = alias_), do: alias_

  def describe(schedule) do
    case String.split(schedule, " ") do
      [minute, hour, "*", "*", "*"] ->
        if Regex.match?(~r/^\d+$/, minute) and Regex.match?(~r/^\d+$/, hour),
          do: "every day at #{String.pad_leading(hour, 2, "0")}:#{String.pad_leading(minute, 2, "0")}",
          else: schedule

      _ ->
        schedule
    end
  end

  defp describe_step(schedule) do
    case Regex.run(~r{^\*/(\d+) \* \* \* \*$}, schedule) do
      [_, n] -> "every #{n} minutes"
      _ -> schedule
    end
  end

  @doc "How long ago an ISO 8601 time was, in words; `Not yet` when there is none."
  def ago(nil, _now), do: "Not yet"

  def ago(iso, now) when is_binary(iso) do
    with {:ok, at, _} <- DateTime.from_iso8601(iso) do
      seconds = max(DateTime.diff(now, at), 0)

      cond do
        seconds < 60 -> "#{seconds}s ago"
        seconds < 3_600 -> "#{div(seconds, 60)} min ago"
        seconds < 86_400 -> "#{div(seconds, 3_600)} h ago"
        true -> "#{div(seconds, 86_400)} d ago"
      end
    else
      _ -> iso
    end
  end

  def ago(other, _now), do: to_string(other)

  defp status_classes(status) when status in ["ok", "success", :ok], do: "bg-emerald-50 text-emerald-700 border-emerald-200"
  defp status_classes(nil), do: "bg-gray-100 text-gray-600 border-gray-200"
  defp status_classes(_), do: "bg-red-50 text-red-700 border-red-200"

  defp job(job, key), do: Map.get(job, key) || Map.get(job, to_string(key))

  ## ---- render ----

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :now, DateTime.utc_now())

    ~H"""
    <div class="space-y-6" id={@id}>
      <div class="exo-page-header">
        <div>
          <h2 class="exo-page-title">Scheduled Tasks</h2>
          <p class="exo-page-subtitle">The jobs your extensions declare with <code class="font-mono">[ExoCron]</code>, and what happened the last time each ran.</p>
        </div>
        <div class="exo-page-actions">
          <button type="button" phx-click="refresh" phx-target={@myself} class="exo-btn exo-btn-secondary"><.studio_icon icon="refresh" class="w-3.5 h-3.5" /> Refresh</button>
        </div>
      </div>

      <div :if={@error} class="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700" role="alert"><%= @error %></div>
      <div :if={@notice} class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700" role="status"><%= @notice %></div>

      <div :if={@jobs == []} class="rounded-xl border border-blue-200 bg-blue-50 px-5 py-4 text-sm text-blue-800">
        <p class="font-semibold">No scheduled tasks</p>
        <p>An extension declares one with <code class="font-mono">[ExoCron("0 0 * * *")]</code> on an action; it appears here once the extension is running.</p>
      </div>

      <div :if={@jobs != []} class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
            <tr>
              <th class="px-4 py-2.5 font-semibold">Job</th>
              <th class="px-4 py-2.5 font-semibold">Runs</th>
              <th class="px-4 py-2.5 font-semibold">Last run</th>
              <th class="px-4 py-2.5 font-semibold">Result</th>
              <th class="px-4 py-2.5 font-semibold text-right">Total runs</th>
              <th class="px-4 py-2.5 font-semibold text-right"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100">
            <%= for j <- @jobs do %>
              <tr id={"job-" <> to_string(job(j, :id))}>
                <td class="px-4 py-3">
                  <p class="font-mono font-semibold text-gray-900"><%= job(j, :name) %></p>
                  <p class="text-xs text-gray-500"><%= job(j, :service) %>.<%= job(j, :action) %><span :if={job(j, :description) not in [nil, ""]}> · <%= job(j, :description) %></span></p>
                </td>
                <td class="px-4 py-3 text-gray-700"><span><%= describe(to_string(job(j, :schedule))) %></span> <code class="ml-1 font-mono text-[11px] text-gray-400"><%= job(j, :schedule) %></code></td>
                <td class="px-4 py-3 text-gray-700"><%= ago(job(j, :last_run), @now) %></td>
                <td class="px-4 py-3">
                  <span class={"inline-flex rounded-full border px-2 py-0.5 text-[11px] font-semibold " <> status_classes(job(j, :last_status))}><%= job(j, :last_status) || "no result" %></span>
                  <span :if={job(j, :last_latency_ms)} class="ml-1 font-mono text-[11px] text-gray-500"><%= job(j, :last_latency_ms) %> ms</span>
                </td>
                <td class="px-4 py-3 text-right font-mono"><%= job(j, :run_count) || 0 %></td>
                <td class="px-4 py-3 text-right">
                  <button type="button" phx-click="ask" phx-value-id={job(j, :id)} phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Run now</button>
                </td>
              </tr>
              <tr :if={@confirm == to_string(job(j, :id))}>
                <td colspan="6" class="bg-amber-50 px-4 py-3">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <p class="text-sm text-amber-800">Run <span class="font-mono font-semibold"><%= job(j, :service) %>.<%= job(j, :action) %></span> now? It runs once, outside its schedule.</p>
                    <div class="flex gap-2">
                      <button type="button" phx-click="run" phx-target={@myself} class="exo-btn exo-btn-primary exo-btn-sm">Yes, run it</button>
                      <button type="button" phx-click="cancel" phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Cancel</button>
                    </div>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
