defmodule Exoforge.Std.DashboardViews.MeteringView do
  @moduledoc """
  The Studio screen for usage (service `:metering`): how much each extension is called, how often it fails and how
  long it takes, over a range the producer picks.

  The action behind it takes an epoch-seconds `since`; the screen turns "last 24 hours" into that, so nobody types a
  timestamp. Totals are tiles, extensions are rows, and a row opens into its actions.
  """
  use Phoenix.LiveComponent
  import Exoforge.Std.DashboardViews.Icons, only: [studio_icon: 1]
  alias Exoforge.ActionDispatcher

  @ranges [{"1h", "Last hour", 3_600}, {"24h", "Last 24 hours", 86_400}, {"7d", "Last 7 days", 604_800}, {"30d", "Last 30 days", 2_592_000}, {"all", "All time", nil}]

  @impl true
  def mount(socket), do: {:ok, assign(socket, range: "24h", usage: nil, open: MapSet.new(), error: nil, loaded: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns.loaded, do: socket, else: socket |> assign(:loaded, true) |> load())}
  end

  @impl true
  def handle_event("range", %{"range" => range}, socket) do
    if Enum.any?(@ranges, &(elem(&1, 0) == range)), do: {:noreply, socket |> assign(:range, range) |> load()}, else: {:noreply, socket}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  def handle_event("toggle", %{"id" => id}, socket) do
    open = socket.assigns.open
    {:noreply, assign(socket, :open, if(MapSet.member?(open, id), do: MapSet.delete(open, id), else: MapSet.put(open, id)))}
  end

  defp load(socket) do
    payload = case since(socket.assigns.range) do nil -> %{}; since -> %{since: since} end

    case ActionDispatcher.dispatch_internal(:metering, :usage, payload) do
      {:ok, usage} -> assign(socket, usage: usage, error: nil)
      {:error, reason} -> assign(socket, usage: nil, error: "Usage could not be read: #{inspect(reason)}")
    end
  end

  ## ---- pure helpers (tested directly) ----

  @doc "Epoch seconds a range starts at, or nil for all time."
  def since(range, now \\ System.os_time(:second)) do
    case Enum.find(@ranges, &(elem(&1, 0) == range)) do
      {_, _, seconds} when is_integer(seconds) -> now - seconds
      _ -> nil
    end
  end

  @doc "Bytes as a short human string."
  def bytes(n) when is_integer(n) and n >= 1_073_741_824, do: "#{Float.round(n / 1_073_741_824, 1)} GB"
  def bytes(n) when is_integer(n) and n >= 1_048_576, do: "#{Float.round(n / 1_048_576, 1)} MB"
  def bytes(n) when is_integer(n) and n >= 1024, do: "#{Float.round(n / 1024, 1)} KB"
  def bytes(n) when is_integer(n), do: "#{n} B"
  def bytes(_), do: "0 B"

  @doc "Average latency in milliseconds from total microseconds and a call count."
  def avg_ms(_wall_us, calls) when not is_integer(calls) or calls <= 0, do: "-"
  def avg_ms(wall_us, calls), do: "#{Float.round(wall_us / calls / 1000, 1)} ms"

  @doc "Errors as a percentage of calls."
  def error_rate(_errors, calls) when not is_integer(calls) or calls <= 0, do: "0%"
  def error_rate(errors, calls), do: "#{Float.round(errors * 100 / calls, 1)}%"

  defp sum(actions, key), do: actions |> Enum.map(&Map.get(&1, key, 0)) |> Enum.sum()
  defp calls_of(plugin), do: sum(plugin.actions, :invocations)

  defp share(plugin, usage) do
    total = max(usage.totals[:invocations] || 0, 1)
    min(100, round(calls_of(plugin) * 100 / total))
  end

  ## ---- render ----

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :ranges, @ranges)

    ~H"""
    <div class="space-y-6" id={@id}>
      <div class="exo-page-header">
        <div>
          <h2 class="exo-page-title">Usage</h2>
          <p class="exo-page-subtitle">How much each extension is called, how often it fails and how long it takes.</p>
        </div>
        <div class="exo-page-actions flex-wrap">
          <div class="inline-flex rounded-lg border border-gray-200 bg-white p-0.5" role="group" aria-label="Range">
            <button :for={{key, label, _} <- @ranges} type="button" phx-click="range" phx-value-range={key} phx-target={@myself} aria-pressed={to_string(@range == key)}
              class={["px-2.5 py-1 text-xs font-semibold rounded-lg transition-colors", if(@range == key, do: "bg-primary-600 text-white", else: "text-gray-600 hover:text-gray-900")]}><%= label %></button>
          </div>
          <button type="button" phx-click="refresh" phx-target={@myself} class="exo-btn exo-btn-secondary"><.studio_icon icon="refresh" class="w-3.5 h-3.5" /> Refresh</button>
        </div>
      </div>

      <div :if={@error} class="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700" role="alert"><%= @error %></div>

      <div :if={@usage && @usage.plugins == []} class="rounded-xl border border-blue-200 bg-blue-50 px-5 py-4 text-sm text-blue-800">
        <p class="font-semibold">No usage in this range yet</p>
        <p>Usage is written once a minute. Call an action from the game or the Studio and check again, or pick a longer range.</p>
      </div>

      <div :if={@usage && @usage.plugins != []} class="space-y-6">
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <.tile label="Calls" value={Integer.to_string(@usage.totals[:invocations] || 0)} />
          <.tile label="Error rate" value={error_rate(@usage.totals[:errors] || 0, @usage.totals[:invocations] || 0)} tone={if (@usage.totals[:errors] || 0) > 0, do: "warn"} />
          <.tile label="Average time" value={avg_ms(@usage.totals[:wall_us] || 0, @usage.totals[:invocations] || 0)} />
          <.tile label="Data in / out" value={bytes(@usage.totals[:bytes_in]) <> " / " <> bytes(@usage.totals[:bytes_out])} />
          <.tile label="Events" value={Integer.to_string(@usage.totals[:events] || 0)} />
        </div>

        <div class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
              <tr>
                <th class="px-4 py-2.5 font-semibold">Extension</th>
                <th class="px-4 py-2.5 font-semibold w-48">Share of calls</th>
                <th class="px-4 py-2.5 font-semibold text-right">Calls</th>
                <th class="px-4 py-2.5 font-semibold text-right">Errors</th>
                <th class="px-4 py-2.5 font-semibold text-right">Average</th>
                <th class="px-4 py-2.5 font-semibold text-right">Events</th>
                <th class="px-4 py-2.5 font-semibold text-right">Restarts</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100">
              <%= for p <- @usage.plugins do %>
                <tr class="cursor-pointer hover:bg-gray-50" phx-click="toggle" phx-value-id={p.plugin_id} phx-target={@myself} id={"usage-" <> p.plugin_id}>
                  <td class="px-4 py-3 font-mono font-semibold text-gray-900"><%= p.plugin_id %></td>
                  <td class="px-4 py-3"><div class="h-1.5 w-full rounded-full bg-gray-100"><div class="h-1.5 rounded-full bg-primary-500" style={"width: #{share(p, @usage)}%"}></div></div></td>
                  <td class="px-4 py-3 text-right font-mono"><%= calls_of(p) %></td>
                  <td class={["px-4 py-3 text-right font-mono", sum(p.actions, :errors) > 0 && "text-red-700"]}><%= sum(p.actions, :errors) %></td>
                  <td class="px-4 py-3 text-right font-mono"><%= avg_ms(sum(p.actions, :wall_us), calls_of(p)) %></td>
                  <td class="px-4 py-3 text-right font-mono"><%= p.plugin.events %></td>
                  <td class="px-4 py-3 text-right font-mono"><%= p.plugin.restarts %></td>
                </tr>
                <tr :if={MapSet.member?(@open, p.plugin_id)}>
                  <td colspan="7" class="bg-gray-50 px-4 py-3">
                    <table :if={p.actions != []} class="w-full text-left text-xs">
                      <thead class="text-[10px] uppercase tracking-wider text-gray-500">
                        <tr><th class="py-1 font-semibold">Action</th><th class="py-1 font-semibold text-right">Calls</th><th class="py-1 font-semibold text-right">Errors</th><th class="py-1 font-semibold text-right">Average</th><th class="py-1 font-semibold text-right">In</th><th class="py-1 font-semibold text-right">Out</th></tr>
                      </thead>
                      <tbody class="divide-y divide-gray-100">
                        <tr :for={a <- p.actions}>
                          <td class="py-1.5 font-mono text-gray-900"><%= a.action %></td>
                          <td class="py-1.5 text-right font-mono"><%= a.invocations %></td>
                          <td class={["py-1.5 text-right font-mono", a.errors > 0 && "text-red-700"]}><%= a.errors %></td>
                          <td class="py-1.5 text-right font-mono"><%= avg_ms(a.wall_us, a.invocations) %></td>
                          <td class="py-1.5 text-right font-mono"><%= bytes(a.bytes_in) %></td>
                          <td class="py-1.5 text-right font-mono"><%= bytes(a.bytes_out) %></td>
                        </tr>
                      </tbody>
                    </table>
                    <p :if={p.actions == []} class="text-xs text-gray-500">No action was called in this range.</p>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:tone, :string, default: nil)

  defp tile(assigns) do
    ~H"""
    <div class="rounded-xl border border-gray-200 bg-white p-4">
      <p class="text-[11px] font-semibold uppercase tracking-wider text-gray-400"><%= @label %></p>
      <p class={["mt-1 text-lg font-semibold font-mono", if(@tone == "warn", do: "text-amber-700", else: "text-gray-900")]}><%= @value %></p>
    </div>
    """
  end
end
