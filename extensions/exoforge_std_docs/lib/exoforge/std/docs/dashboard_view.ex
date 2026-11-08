defmodule Exoforge.Std.Docs.DashboardView do
  @moduledoc """
  Phoenix LiveComponent providing the Producer & Designer Studio visualization
  for the Documentation & Developer Guide service (:docs).
  """
  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok, assign(socket, subpage: "flow")}
  end

  @impl true
  def update(assigns, socket) do
    subpage = assigns[:subpage] || assigns[:guide_subpage] || socket.assigns[:subpage] || "flow"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:subpage, subpage)}
  end

  @impl true
  def handle_event("set_guide_subpage", %{"subpage" => subpage}, socket) do
    path = if subpage == "flow", do: "/guide", else: "/guide?subpage=#{subpage}"

    {:noreply,
     socket
     |> assign(:subpage, subpage)
     |> push_patch(to: path)}
  end

  @impl true
  def handle_event("open_sdk_modal", _params, socket) do
    send(self(), :open_sdk_modal)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    action_catalog =
      if assigns[:action_catalog] && assigns[:action_catalog] != [] do
        assigns.action_catalog
      else
        Exoforge.Std.Docs.build_api_catalog()
      end

    extensions =
      if assigns[:extensions] && assigns[:extensions] != [] do
        assigns.extensions
      else
        Exoforge.ExtensionRegistry.all_manifests()
      end

    project_name = assigns[:project_name] || "Game"
    studio_name = assigns[:studio_name] || "Exoforge Studio"

    assigns =
      assigns
      |> assign(:action_catalog, action_catalog)
      |> assign(:extensions, extensions)
      |> assign(:project_name, project_name)
      |> assign(:studio_name, studio_name)

    ~H"""
    <div id="docs-extension-view" class="space-y-6">
      <Exoforge.Std.Docs.View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
        myself={@myself}
      />
    </div>
    """
  end
end
