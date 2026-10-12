defmodule Exoforge.Std.Dashboard.Microfrontend do
  @moduledoc """
  Unified Microfrontend renderer component for Exoforge Studio.
  Renders Custom Elements (Web Components), sandboxed iframes, or native LiveComponents.
  Also renders arbitrary custom hook slots so plugin control panels and drawers
  can provide their own extension points for other plugins.
  """
  use Phoenix.Component

  attr :spec, :map, required: true
  attr :target_id, :string, default: nil
  attr :context, :map, default: %{}
  attr :class, :string, default: ""

  @doc "Renders a microfrontend widget, tab, or custom element."
  def render_widget(assigns) do
    spec = assigns.spec
    type = to_string(spec[:type] || spec["type"] || "auto")
    element = spec[:element] || spec["element"]
    entry = spec[:entry] || spec["entry"]
    plugin_id = spec[:plugin_id] || spec["plugin_id"]

    entry_url = if entry, do: "/api/plugins/#{plugin_id}/assets/#{entry}?v=#{System.system_time(:second)}"

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(:element, element)
      |> assign(:entry, entry)
      |> assign(:entry_url, entry_url)
      |> assign(:plugin_id, plugin_id)

    ~H"""
    <div class={@class}>
      <%= cond do %>
        <% @element != nil -> %>
          <%= if @entry_url do %>
            <script type="module" src={@entry_url}></script>
          <% end %>
          <div
            id={"mfe_#{to_string(@spec[:id] || @element)}"}
            phx-hook="MicrofrontendLoader"
            data-entry={@entry_url}
            data-element={@element}
            phx-update="ignore"
          >
            <%= Phoenix.HTML.raw(render_custom_element_tag(@element, @plugin_id, @target_id, @context)) %>
          </div>

        <% @type == "iframe" and @entry != nil -> %>
          <iframe
            src={"/api/plugins/#{@plugin_id}/assets/#{@entry}"}
            class="w-full h-full min-h-[400px] border-0 rounded-xl"
            sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
          >
          </iframe>

        <% is_atom(@spec[:component]) and Code.ensure_loaded?(@spec[:component]) -> %>
          <.live_component module={@spec[:component]} id={to_string(@spec[:id])} {@context} />

        <% is_atom(@spec[:module]) and Code.ensure_loaded?(@spec[:module]) -> %>
          <.live_component module={@spec[:module]} id={to_string(@spec[:id])} {@context} />

        <% true -> %>
          <div class="p-4 bg-gray-50 rounded-xl border border-gray-100 text-xs text-gray-600">
            <p><%= Map.get(@spec, :description) || Map.get(@spec, "description") || "Microfrontend component for #{to_string(@plugin_id)}" %></p>
          </div>
      <% end %>
    </div>
    """
  end

  attr :point, :any, required: true
  attr :target_id, :string, default: nil
  attr :context, :map, default: %{}
  attr :class, :string, default: ""

  @doc """
  Renders all microfrontends registered for a specific hooking point.
  Any plugin control panel or drawer can call `<.hook_slot point={:my_custom_slot} ... />`
  allowing other plugins to contribute cards, tabs, or panels into it.
  """
  def hook_slot(assigns) do
    hooks = Exoforge.UIHookRegistry.list_hooks(assigns.point)
    assigns = assign(assigns, :hooks, hooks)

    ~H"""
    <%= if @hooks != [] do %>
      <div class={@class}>
        <%= for hook <- @hooks do %>
          <.render_widget spec={hook} target_id={@target_id} context={@context} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp render_custom_element_tag(element, plugin_id, target_id, context) do
    json_ctx = Jason.encode!(context) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    "<#{element} plugin-id=\"#{plugin_id}\" target-id=\"#{target_id || ""}\" context=\"#{json_ctx}\"></#{element}>"
  end
end
