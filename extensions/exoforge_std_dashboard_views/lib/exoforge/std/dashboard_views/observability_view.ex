defmodule Exoforge.Std.DashboardViews.ObservabilityView do
  @moduledoc """
  The Studio screen for debugging a running game (service `:observability`): which actions need attention, the
  failures grouped by what broke, the recent events, one request's timeline, and the deep captures.

  It replaces eleven raw action cards. The common path is one click: a request id shown anywhere on the screen opens
  that request's timeline (its calls, events, log lines and failure on one clock). Everything it shows comes from the
  `observability` actions, so it only reads and never decides.
  """
  use Phoenix.LiveComponent
  import Exoforge.Std.DashboardViews.Icons, only: [studio_icon: 1]
  alias Exoforge.ActionDispatcher

  @tabs [{"health", "Health"}, {"failures", "Failures"}, {"events", "Events"}, {"request", "Request"}, {"captures", "Captures"}]
  @page 25

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       tab: "health",
       health: %{rows: [], attention: []},
       groups: [],
       events: %{events: [], total: 0},
       offset: 0,
       filters: %{"status" => "", "event" => "", "rid" => "", "player" => ""},
       timeline: nil,
       lookup: %{"rid" => "", "player" => ""},
       captures: [],
       capture_form: %{"kind" => "player", "value" => "", "seconds" => "300"},
       error: nil,
       notice: nil,
       loaded: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns.loaded, do: socket, else: socket |> assign(:loaded, true) |> load_tab())}
  end

  ## ---- events ----

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) do
    if Enum.any?(@tabs, &(elem(&1, 0) == tab)),
      do: {:noreply, socket |> assign(tab: tab, error: nil, notice: nil) |> load_tab()},
      else: {:noreply, socket}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load_tab(socket)}

  def handle_event("open_rid", %{"rid" => rid}, socket) do
    {:noreply, socket |> assign(tab: "request", lookup: %{"rid" => rid, "player" => ""}) |> load_timeline()}
  end

  def handle_event("lookup", params, socket) do
    lookup = %{"rid" => String.trim(Map.get(params, "rid", "")), "player" => String.trim(Map.get(params, "player", ""))}
    {:noreply, socket |> assign(:lookup, lookup) |> load_timeline()}
  end

  def handle_event("filter", params, socket) do
    filters = Map.new(socket.assigns.filters, fn {key, _} -> {key, String.trim(Map.get(params, key, ""))} end)
    {:noreply, socket |> assign(filters: filters, offset: 0) |> load_events()}
  end

  def handle_event("page", %{"dir" => dir}, socket) do
    offset = if dir == "next", do: socket.assigns.offset + @page, else: max(socket.assigns.offset - @page, 0)
    {:noreply, socket |> assign(:offset, offset) |> load_events()}
  end

  def handle_event("start_capture", params, socket) do
    kind = Map.get(params, "kind", "player")
    value = String.trim(Map.get(params, "value", ""))
    seconds = parse_seconds(Map.get(params, "seconds"))
    form = %{"kind" => kind, "value" => value, "seconds" => to_string(seconds)}

    socket =
      case ActionDispatcher.dispatch_internal(:observability, :capture, %{kind: kind, value: value, seconds: seconds}) do
        {:ok, _} -> assign(socket, notice: capture_started(kind, value, seconds), error: nil)
        {:error, reason} -> assign(socket, error: "The capture could not start: #{inspect(reason)}.", notice: nil)
      end

    {:noreply, socket |> assign(:capture_form, form) |> load_captures()}
  end

  def handle_event("stop_capture", %{"kind" => kind, "value" => value}, socket) do
    _ = ActionDispatcher.dispatch_internal(:observability, :stop_capture, %{kind: kind, value: value})
    {:noreply, socket |> assign(notice: "Capture stopped.", error: nil) |> load_captures()}
  end

  ## ---- data ----

  defp load_tab(%{assigns: %{tab: "health"}} = socket), do: load_health(socket)
  defp load_tab(%{assigns: %{tab: "failures"}} = socket), do: load_groups(socket)
  defp load_tab(%{assigns: %{tab: "events"}} = socket), do: load_events(socket)
  defp load_tab(%{assigns: %{tab: "request"}} = socket), do: if(socket.assigns.timeline, do: load_timeline(socket), else: socket)
  defp load_tab(%{assigns: %{tab: "captures"}} = socket), do: load_captures(socket)

  defp ask(action, payload, default) do
    case ActionDispatcher.dispatch_internal(:observability, action, payload) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason, default}
    end
  end

  defp load_health(socket) do
    case ask(:health, %{limit: 50}, %{rows: [], attention: []}) do
      {:ok, %{rows: rows, attention: attention}} -> assign(socket, health: %{rows: rows, attention: attention}, error: nil)
      {:error, reason, default} -> assign(socket, health: default, error: "Health could not be read: #{inspect(reason)}.")
    end
  end

  defp load_groups(socket) do
    case ask(:error_groups, %{limit: 50}, %{groups: []}) do
      {:ok, %{groups: groups}} -> assign(socket, groups: groups, error: nil)
      {:error, reason, _} -> assign(socket, groups: [], error: "Failures could not be read: #{inspect(reason)}.")
    end
  end

  defp load_events(socket) do
    payload =
      socket.assigns.filters
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.merge(%{limit: @page, offset: socket.assigns.offset})

    case ask(:events, payload, %{events: [], total: 0}) do
      {:ok, %{events: events, total: total}} -> assign(socket, events: %{events: events, total: total}, error: nil)
      {:error, reason, default} -> assign(socket, events: default, error: "Events could not be read: #{inspect(reason)}.")
    end
  end

  defp load_timeline(socket) do
    %{"rid" => rid, "player" => player} = socket.assigns.lookup

    payload =
      cond do
        rid != "" -> %{rid: rid}
        player != "" -> %{player: player, limit: 200}
        true -> nil
      end

    cond do
      is_nil(payload) -> assign(socket, timeline: nil)
      true ->
        case ask(:timeline, payload, %{nodes: []}) do
          {:ok, %{nodes: nodes}} -> assign(socket, timeline: %{for: if(rid != "", do: rid, else: player), nodes: Enum.sort_by(nodes, &(&1[:at] || 0))}, error: nil)
          {:error, reason, _} -> assign(socket, timeline: nil, error: "The timeline could not be read: #{inspect(reason)}.")
        end
    end
  end

  defp load_captures(socket) do
    case ask(:captures, %{}, %{captures: []}) do
      {:ok, %{captures: captures}} -> assign(socket, :captures, captures)
      {:error, _, _} -> assign(socket, :captures, [])
    end
  end

  ## ---- pure helpers (tested directly) ----

  @doc "How long ago an epoch-milliseconds time was."
  def ago_ms(nil, _now), do: "-"

  def ago_ms(at, now) when is_integer(at) do
    seconds = max(div(now - at, 1000), 0)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3_600 -> "#{div(seconds, 60)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)} h ago"
      true -> "#{div(seconds, 86_400)} d ago"
    end
  end

  def ago_ms(_, _), do: "-"

  @doc "An error rate (0..1) as a percentage."
  def rate(value) when is_number(value), do: "#{Float.round(value * 100, 1)}%"
  def rate(_), do: "0%"

  @doc "A latency in milliseconds."
  def ms(value) when is_number(value), do: "#{Float.round(value * 1.0, 1)} ms"
  def ms(_), do: "-"

  @doc "The clock time of an epoch-milliseconds instant, with milliseconds."
  def clock(at) when is_integer(at) do
    case DateTime.from_unix(at, :millisecond) do
      {:ok, dt} -> Calendar.strftime(dt, "%H:%M:%S.") <> String.pad_leading(Integer.to_string(rem(at, 1000)), 3, "0")
      _ -> "-"
    end
  end

  def clock(_), do: "-"

  @doc "Capture seconds from a form value, kept within what a capture allows (1 s to 1 h)."
  def parse_seconds(value) do
    case Integer.parse(to_string(value || "")) do
      {n, _} -> n |> max(1) |> min(3_600)
      :error -> 300
    end
  end

  defp capture_started("global", _value, seconds), do: "Capturing the whole cluster for #{seconds} s."
  defp capture_started(kind, value, seconds), do: "Capturing #{kind} #{value} for #{seconds} s."

  defp node_classes("log"), do: "bg-gray-100 text-gray-700 border-gray-200"
  defp node_classes("event"), do: "bg-blue-50 text-blue-700 border-blue-200"
  defp node_classes(kind) when kind in ["failure", "error"], do: "bg-red-50 text-red-700 border-red-200"
  defp node_classes(_), do: "bg-primary-50 text-primary-700 border-primary-200"

  defp level_classes("error"), do: "text-red-700"
  defp level_classes("warning"), do: "text-amber-700"
  defp level_classes(_), do: "text-gray-900"

  defp status_classes("ok"), do: "bg-emerald-50 text-emerald-700 border-emerald-200"
  defp status_classes(_), do: "bg-red-50 text-red-700 border-red-200"

  defp node_text(%{message: message}) when is_binary(message), do: message

  defp node_text(%{payload: %{} = payload}) do
    [payload[:status] && "status #{payload[:status]}", payload[:duration_ms] && "#{payload[:duration_ms]} ms"]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  defp node_text(_), do: ""

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  ## ---- render ----

  @impl true
  def render(assigns) do
    assigns = assign(assigns, tabs: @tabs, now: System.system_time(:millisecond), page: @page)

    ~H"""
    <div class="space-y-6" id={@id}>
      <div class="exo-page-header">
        <div>
          <h2 class="exo-page-title">Observability</h2>
          <p class="exo-page-subtitle">What is failing, which request did it, and what that request did.</p>
        </div>
        <div class="exo-page-actions">
          <button type="button" phx-click="refresh" phx-target={@myself} class="exo-btn exo-btn-secondary"><.studio_icon icon="refresh" class="w-3.5 h-3.5" /> Refresh</button>
        </div>
      </div>

      <div class="exo-tabs" role="tablist">
        <button :for={{key, label} <- @tabs} type="button" role="tab" aria-selected={to_string(@tab == key)} phx-click="tab" phx-value-tab={key} phx-target={@myself} class={["exo-tab", @tab == key && "exo-tab-active"]}><%= label %></button>
      </div>

      <div :if={@error} class="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700" role="alert"><%= @error %></div>
      <div :if={@notice} class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700" role="status"><%= @notice %></div>

      <%!-- HEALTH --%>
      <div :if={@tab == "health"} class="space-y-6">
        <div class="rounded-xl border border-gray-200 bg-white">
          <div class="border-b border-gray-200 px-4 py-3"><h3 class="text-sm font-semibold text-gray-900">Needs attention</h3></div>
          <p :if={@health.attention == []} class="px-4 py-4 text-sm text-emerald-700">Nothing needs attention: no action is failing or slow right now.</p>
          <ul :if={@health.attention != []} class="divide-y divide-gray-100">
            <li :for={item <- @health.attention} class="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
              <div>
                <p class="font-mono text-sm font-semibold text-gray-900"><%= field(item, :label) %></p>
                <p class="text-xs text-gray-500"><%= field(item, :detail) %></p>
              </div>
              <button :if={field(item, :rid)} type="button" phx-click="open_rid" phx-value-rid={field(item, :rid)} phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Open request</button>
            </li>
          </ul>
        </div>

        <div class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
              <tr>
                <th class="px-4 py-2.5 font-semibold">Action</th>
                <th class="px-4 py-2.5 font-semibold text-right">Calls (30 min)</th>
                <th class="px-4 py-2.5 font-semibold text-right">Error rate</th>
                <th class="px-4 py-2.5 font-semibold text-right">Median</th>
                <th class="px-4 py-2.5 font-semibold text-right">Slowest 5%</th>
                <th class="px-4 py-2.5 font-semibold text-right">Calls ever</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100">
              <tr :for={row <- @health.rows}>
                <td class="px-4 py-2.5 font-mono text-gray-900"><%= field(row, :service) %>.<%= field(row, :action) %></td>
                <td class="px-4 py-2.5 text-right font-mono"><%= field(row, :calls_30m) %></td>
                <td class={["px-4 py-2.5 text-right font-mono", (field(row, :error_rate) || 0) > 0 && "text-red-700"]}><%= rate(field(row, :error_rate)) %></td>
                <td class="px-4 py-2.5 text-right font-mono"><%= ms(field(row, :p50_ms)) %></td>
                <td class="px-4 py-2.5 text-right font-mono"><%= ms(field(row, :p95_ms)) %></td>
                <td class="px-4 py-2.5 text-right font-mono"><%= field(row, :invocations) %></td>
              </tr>
              <tr :if={@health.rows == []}><td colspan="6" class="px-4 py-6 text-center text-sm text-gray-500">No calls recorded yet. Latencies appear as soon as actions run.</td></tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- FAILURES --%>
      <div :if={@tab == "failures"} class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
            <tr>
              <th class="px-4 py-2.5 font-semibold">Action</th>
              <th class="px-4 py-2.5 font-semibold">What broke</th>
              <th class="px-4 py-2.5 font-semibold text-right">Times</th>
              <th class="px-4 py-2.5 font-semibold">Callers</th>
              <th class="px-4 py-2.5 font-semibold">Last seen</th>
              <th class="px-4 py-2.5 font-semibold text-right"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100">
            <tr :for={g <- @groups}>
              <td class="px-4 py-3 font-mono font-semibold text-gray-900"><%= field(g, :service) %>.<%= field(g, :action) %></td>
              <td class="px-4 py-3 font-mono text-xs text-red-700"><%= field(g, :reason) %></td>
              <td class="px-4 py-3 text-right font-mono"><%= field(g, :count) %></td>
              <td class="px-4 py-3 text-xs text-gray-600"><%= Enum.join(List.wrap(field(g, :callers)), ", ") %></td>
              <td class="px-4 py-3 text-gray-700"><%= ago_ms(field(g, :last_seen), @now) %></td>
              <td class="px-4 py-3 text-right"><button :if={field(g, :rid)} type="button" phx-click="open_rid" phx-value-rid={field(g, :rid)} phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Open a sample</button></td>
            </tr>
            <tr :if={@groups == []}><td colspan="6" class="px-4 py-8 text-center text-sm text-gray-500">No failures recorded. Failures are grouped here by action and cause once an action returns an error.</td></tr>
          </tbody>
        </table>
      </div>

      <%!-- EVENTS --%>
      <div :if={@tab == "events"} class="space-y-4">
        <form phx-submit="filter" phx-target={@myself} class="grid gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-5">
          <div>
            <label class="block text-xs font-semibold text-gray-600" for="ev-status">Status</label>
            <select id="ev-status" name="status" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-2 py-2 text-sm text-gray-900">
              <option value="" selected={@filters["status"] == ""}>Any</option>
              <option value="ok" selected={@filters["status"] == "ok"}>ok</option>
              <option value="error" selected={@filters["status"] == "error"}>error</option>
            </select>
          </div>
          <div><label class="block text-xs font-semibold text-gray-600" for="ev-event">Event</label><input id="ev-event" name="event" value={@filters["event"]} placeholder="action:auth.login" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-xs text-gray-900" /></div>
          <div><label class="block text-xs font-semibold text-gray-600" for="ev-rid">Request id</label><input id="ev-rid" name="rid" value={@filters["rid"]} placeholder="r_..." class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-xs text-gray-900" /></div>
          <div><label class="block text-xs font-semibold text-gray-600" for="ev-player">Player</label><input id="ev-player" name="player" value={@filters["player"]} placeholder="player id" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-xs text-gray-900" /></div>
          <div class="flex items-end"><button type="submit" class="exo-btn exo-btn-primary w-full">Filter</button></div>
        </form>

        <div class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
              <tr><th class="px-4 py-2.5 font-semibold">Time</th><th class="px-4 py-2.5 font-semibold">Status</th><th class="px-4 py-2.5 font-semibold">Event</th><th class="px-4 py-2.5 font-semibold">From</th><th class="px-4 py-2.5 font-semibold text-right">Request</th></tr>
            </thead>
            <tbody class="divide-y divide-gray-100">
              <tr :for={e <- @events.events}>
                <td class="px-4 py-2.5 font-mono text-xs text-gray-600"><%= field(e, :day) %> <%= field(e, :time) %></td>
                <td class="px-4 py-2.5"><span class={"inline-flex rounded-full border px-2 py-0.5 text-[11px] font-semibold " <> status_classes(to_string(field(e, :status)))}><%= field(e, :status) %></span></td>
                <td class="px-4 py-2.5 font-mono text-xs text-gray-900"><%= field(e, :event) %></td>
                <td class="px-4 py-2.5 text-xs text-gray-600"><%= field(e, :origin) %></td>
                <td class="px-4 py-2.5 text-right"><button :if={field(e, :rid)} type="button" phx-click="open_rid" phx-value-rid={field(e, :rid)} phx-target={@myself} class="font-mono text-[11px] text-primary-700 underline"><%= field(e, :rid) %></button></td>
              </tr>
              <tr :if={@events.events == []}><td colspan="5" class="px-4 py-8 text-center text-sm text-gray-500">No events match.</td></tr>
            </tbody>
          </table>
        </div>
        <div class="flex items-center justify-between text-xs text-gray-500">
          <span><%= @events.total %> events<span :if={@events.total > 0}>, showing <%= @offset + 1 %> to <%= min(@offset + @page, @events.total) %></span></span>
          <span class="flex gap-2">
            <button type="button" phx-click="page" phx-value-dir="prev" phx-target={@myself} disabled={@offset == 0} class="exo-btn exo-btn-secondary exo-btn-sm">Newer</button>
            <button type="button" phx-click="page" phx-value-dir="next" phx-target={@myself} disabled={@offset + @page >= @events.total} class="exo-btn exo-btn-secondary exo-btn-sm">Older</button>
          </span>
        </div>
      </div>

      <%!-- REQUEST --%>
      <div :if={@tab == "request"} class="space-y-4">
        <form phx-submit="lookup" phx-target={@myself} class="grid gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-[1fr_1fr_auto]">
          <div><label class="block text-xs font-semibold text-gray-600" for="lk-rid">Request id</label><input id="lk-rid" name="rid" value={@lookup["rid"]} placeholder="r_..." class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-sm text-gray-900" /></div>
          <div><label class="block text-xs font-semibold text-gray-600" for="lk-player">or a player's recent activity</label><input id="lk-player" name="player" value={@lookup["player"]} placeholder="player id" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-sm text-gray-900" /></div>
          <div class="flex items-end"><button type="submit" class="exo-btn exo-btn-primary">Show</button></div>
        </form>

        <p :if={@timeline == nil} class="rounded-xl border border-blue-200 bg-blue-50 px-5 py-4 text-sm text-blue-800">
          Paste the request id from an error (every failed call carries one), or click a request id anywhere on this screen.
        </p>

        <div :if={@timeline} class="rounded-xl border border-gray-200 bg-white">
          <div class="border-b border-gray-200 px-4 py-3"><h3 class="text-sm font-semibold text-gray-900">Timeline of <span class="font-mono"><%= @timeline.for %></span></h3></div>
          <p :if={@timeline.nodes == []} class="px-4 py-6 text-sm text-gray-500">Nothing was recorded for it. The history is kept for a limited time; a request id from today should be here.</p>
          <ol class="divide-y divide-gray-100">
            <li :for={n <- @timeline.nodes} class="flex gap-3 px-4 py-2.5">
              <span class="w-24 shrink-0 font-mono text-[11px] text-gray-500"><%= clock(n[:at]) %></span>
              <span class={"h-fit shrink-0 rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase " <> node_classes(to_string(n[:kind]))}><%= n[:kind] %></span>
              <div class="min-w-0">
                <p class={["font-mono text-xs break-words", level_classes(to_string(n[:label]))]}><%= n[:label] %></p>
                <p :if={node_text(n) != ""} class="text-xs text-gray-600 break-words"><%= node_text(n) %></p>
              </div>
            </li>
          </ol>
        </div>
      </div>

      <%!-- CAPTURES --%>
      <div :if={@tab == "captures"} class="space-y-4">
        <form phx-submit="start_capture" phx-target={@myself} class="grid gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-[10rem_1fr_8rem_auto]">
          <div>
            <label class="block text-xs font-semibold text-gray-600" for="cp-kind">Capture</label>
            <select id="cp-kind" name="kind" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-2 py-2 text-sm text-gray-900">
              <option value="player" selected={@capture_form["kind"] == "player"}>one player</option>
              <option value="action" selected={@capture_form["kind"] == "action"}>one action</option>
              <option value="global" selected={@capture_form["kind"] == "global"}>everything</option>
            </select>
          </div>
          <div><label class="block text-xs font-semibold text-gray-600" for="cp-value">Player id or service.action</label><input id="cp-value" name="value" value={@capture_form["value"]} placeholder="p_123 or wallet.credit" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-sm text-gray-900" /></div>
          <div><label class="block text-xs font-semibold text-gray-600" for="cp-seconds">Seconds</label><input id="cp-seconds" name="seconds" value={@capture_form["seconds"]} class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-sm text-gray-900" /></div>
          <div class="flex items-end"><button type="submit" class="exo-btn exo-btn-primary">Start</button></div>
        </form>
        <p class="text-xs text-gray-500">A capture keeps the full request of each matching call in memory (never saved) so it can be inspected and replayed. It stops by itself.</p>

        <div class="rounded-xl border border-gray-200 bg-white">
          <p :if={@captures == []} class="px-4 py-6 text-sm text-gray-500">No capture is running.</p>
          <ul :if={@captures != []} class="divide-y divide-gray-100">
            <li :for={c <- @captures} class="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
              <div>
                <p class="text-sm font-semibold text-gray-900"><%= field(c, :kind) %> <span class="font-mono"><%= field(c, :value) %></span></p>
                <p class="text-xs text-gray-500"><%= field(c, :remaining_s) %> s left</p>
              </div>
              <button type="button" phx-click="stop_capture" phx-value-kind={field(c, :kind)} phx-value-value={field(c, :value)} phx-target={@myself} class="exo-btn exo-btn-danger exo-btn-sm">Stop</button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
