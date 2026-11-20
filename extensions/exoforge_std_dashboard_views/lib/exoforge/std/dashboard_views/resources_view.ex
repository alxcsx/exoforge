defmodule Exoforge.Std.DashboardViews.ResourcesView do
  @moduledoc """
  The Studio screen for data (service `:resource_store`): every resource the running extensions declare, whose it is,
  how many rows it holds, and a way into the row browser.

  The row browser (`/resources/:name`) always existed, but nothing led to it and this tab was the store's raw actions.
  The store is an admin API; what a producer needs is to find the data and look at it, so this is a list that opens it.
  """
  use Phoenix.LiveComponent
  import Exoforge.Std.DashboardViews.Icons, only: [studio_icon: 1]
  alias Exoforge.ExtensionRegistry

  @impl true
  def mount(socket), do: {:ok, assign(socket, resources: [], search: "", loaded: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns.loaded, do: socket, else: socket |> assign(:loaded, true) |> load())}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket), do: {:noreply, assign(socket, :search, String.trim(search))}
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket), do: assign(socket, :resources, list_resources())

  @doc "Every declared resource as a flat row: name, owner, column names and row count (nil when it cannot be counted)."
  def list_resources do
    ExtensionRegistry.all_resources()
    |> Enum.map(fn entry ->
      res = entry.resource
      name = to_string(field(res, :name))
      columns = field(res, :columns) || []

      %{
        name: name,
        extension: to_string(entry.extension_id),
        service: to_string(entry.service),
        columns: columns |> Enum.map(&to_string(field(&1, :name))) |> Enum.reject(&(&1 == "")),
        rows: count_rows(name)
      }
    end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(&{&1.extension, &1.name})
  end

  defp count_rows(name) do
    case ExtensionRegistry.page_resource_rows(name, limit: 1, offset: 0) do
      %{total: total} when is_integer(total) -> total
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_, _), do: nil

  @doc "The resources whose name, owner or a column matches the search; an empty search keeps all."
  def filter(resources, ""), do: resources

  def filter(resources, search) do
    q = String.downcase(search)

    Enum.filter(resources, fn r ->
      Enum.any?([r.name, r.extension, r.service | r.columns], &String.contains?(String.downcase(&1), q))
    end)
  end

  @doc "Row count as a person reads it."
  def rows_text(nil), do: "-"
  def rows_text(1), do: "1 row"
  def rows_text(n), do: "#{n} rows"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, filter(assigns.resources, assigns.search))

    ~H"""
    <div class="space-y-6" id={@id}>
      <div class="exo-page-header">
        <div>
          <h2 class="exo-page-title">Data</h2>
          <p class="exo-page-subtitle">The tables your extensions keep. Open one to look at its rows, search them and export.</p>
        </div>
        <div class="exo-page-actions flex-wrap">
          <form phx-change="search" phx-target={@myself} class="w-64">
            <input type="search" name="search" value={@search} placeholder="Find a table or column" phx-debounce="200" class="exo-input w-full" aria-label="Find a table or column" />
          </form>
          <button type="button" phx-click="refresh" phx-target={@myself} class="exo-btn exo-btn-secondary"><.studio_icon icon="refresh" class="w-3.5 h-3.5" /> Refresh</button>
        </div>
      </div>

      <div :if={@resources == []} class="rounded-xl border border-blue-200 bg-blue-50 px-5 py-4 text-sm text-blue-800">
        <p class="font-semibold">No extension declares a table yet</p>
        <p>Declare one with <code class="font-mono">[ExoResource]</code> on a record, then deploy. It appears here as soon as the extension runs.</p>
      </div>

      <div :if={@resources != [] and @shown == []} class="rounded-xl border border-gray-200 bg-white px-5 py-4 text-sm text-gray-600">Nothing matches "<%= @search %>".</div>

      <div :if={@shown != []} class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
            <tr>
              <th class="px-4 py-2.5 font-semibold">Table</th>
              <th class="px-4 py-2.5 font-semibold">Owned by</th>
              <th class="px-4 py-2.5 font-semibold">Columns</th>
              <th class="px-4 py-2.5 font-semibold text-right">Rows</th>
              <th class="px-4 py-2.5"><span class="sr-only">Open</span></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100">
            <tr :for={r <- @shown} id={"resource-" <> r.name} class="hover:bg-gray-50">
              <td class="px-4 py-3 font-mono font-semibold text-gray-900"><%= r.name %></td>
              <td class="px-4 py-3 font-mono text-xs text-gray-600"><%= r.extension %></td>
              <td class="px-4 py-3 text-xs text-gray-600"><%= r.columns |> Enum.take(6) |> Enum.join(", ") %><span :if={length(r.columns) > 6}> and <%= length(r.columns) - 6 %> more</span></td>
              <td class="px-4 py-3 text-right font-mono"><%= rows_text(r.rows) %></td>
              <td class="px-4 py-3 text-right">
                <.link navigate={"/resources/" <> r.name} class="exo-btn exo-btn-secondary exo-btn-sm">Browse rows</.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
