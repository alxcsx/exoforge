defmodule Exoforge.Std.Dashboard.ResourceLive do
  @moduledoc """
  Declarative generic resource LiveView for Exoforge extensions.
  Automatically reads column schemas and drawer metadata from __service_metadata__()
  and renders dynamic data tables and inspectors.
  """
  use Phoenix.LiveView
  import Exoforge.Std.Dashboard.Components
  alias Exoforge.PluginRegistry
  alias Exoforge.DrawerRegistry

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    resource_info =
      case PluginRegistry.fetch_resource(name) do
        {:ok, res} -> res
        _ -> %{resource: %{name: name, primary_key: :id, columns: []}}
      end

    res = resource_info[:resource] || resource_info["resource"] || %{}
    cols = res[:columns] || res["columns"] || []

    drawer_tabs = DrawerRegistry.list_tabs(name)

    table_columns =
      if Enum.empty?(cols) do
        [%{key: :id, label: "ID", type: :code}, %{key: :data, label: "Data"}]
      else
        Enum.map(cols, fn c ->
          %{
            key: c[:name] || c["name"],
            label: Phoenix.Naming.humanize(to_string(c[:name] || c["name"])),
            type: if((c[:name] || c["name"]) in [:id, :player_id], do: :code, else: :text)
          }
        end)
      end

    rows = fetch_resource_rows(name)

    {:ok,
     assign(socket,
       resource_name: name,
       resource: res,
       columns: table_columns,
       rows: rows,
       drawer_open: false,
       inspected_row: nil,
       drawer_tabs: drawer_tabs,
       inspected_tab: "overview"
     )}
  end

  @impl true
  def handle_event("inspect_row", %{"id" => id}, socket) do
    row = Enum.find(socket.assigns.rows, fn r -> (r[:id] || r["id"] || r["player_id"]) == id end)
    {:noreply, assign(socket, drawer_open: true, inspected_row: row, inspected_tab: "overview")}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, drawer_open: false, inspected_row: nil)}
  end

  def handle_event("select_drawer_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, inspected_tab: tab)}
  end

  defp fetch_resource_rows(resource_name) do
    Exoforge.PluginRegistry.fetch_resource_rows(resource_name)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto p-6 space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-black text-gray-900 tracking-tight flex items-center gap-2">
            <span>Declarative Resource:</span>
            <code class="text-primary-600 bg-primary-50 px-2 py-0.5 rounded-lg text-sm"><%= @resource_name %></code>
          </h2>
          <p class="text-xs text-gray-500 mt-1">
            Primary Key: <code><%= @resource[:primary_key] || "id" %></code> • Supervised by BEAM Kernel
          </p>
        </div>
        <a href="/" class="text-xs font-bold text-gray-600 hover:text-gray-900 bg-white border px-3 py-1.5 rounded-xl shadow-xs">
          &larr; Back to Studio
        </a>
      </div>

      <.data_table
        id="declarative_resource_table"
        rows={@rows}
        columns={@columns}
        row_click_event="inspect_row"
        empty_text={"No records found for #{@resource_name}."}
      />

      <.side_drawer
        open={@drawer_open}
        title={"Inspect #{@resource_name} Entity"}
        subtitle={"Properties and metadata"}
        tabs={@drawer_tabs}
        active_tab={@inspected_tab}
        on_close="close_drawer"
        on_select_tab="select_drawer_tab"
      >
        <%= if @inspected_row do %>
          <div class="space-y-4 text-xs">
            <pre class="p-4 bg-gray-50 border rounded-xl overflow-x-auto font-mono text-gray-700"><%= Jason.encode!(@inspected_row) %></pre>
          </div>
        <% end %>
      </.side_drawer>
    </div>
    """
  end
end
