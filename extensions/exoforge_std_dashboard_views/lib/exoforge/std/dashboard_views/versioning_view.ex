defmodule Exoforge.Std.DashboardViews.VersioningView do
  @moduledoc """
  The Studio screen for game versions (service `:versioning`): which release is live, which are still served,
  which are blocked, and the extension version each one locks.

  The screen exists because the job is consequential (blocking a version tells every player on it to update)
  and the generic action panel made the producer type version strings and raw JSON. Here a version is a row
  with a status, its locks are `extension@version` chips, and Promote and Block ask for a confirmation that
  names what will happen. Every change still goes through the `versioning` actions, so their rules (at most
  three served, only a dev version can change locks) are the only rules.
  """
  use Phoenix.LiveComponent
  import Exoforge.Std.DashboardViews.Icons, only: [studio_icon: 1]
  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       versions: [],
       extensions: %{},
       max_active: 3,
       confirm: nil,
       editing: nil,
       locks_text: "",
       register_form: %{"version" => "", "locks" => ""},
       error: nil,
       notice: nil,
       loaded: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns.loaded, do: socket, else: socket |> assign(:loaded, true) |> load())}
  end

  ## ---- events ----

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, socket |> clear_messages() |> load()}

  def handle_event("ask", %{"op" => op, "version" => version}, socket) when op in ["promote", "block"] do
    {:noreply, assign(socket, confirm: {op, version}, error: nil, notice: nil)}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, confirm: nil, editing: nil)}

  def handle_event("confirm", _params, %{assigns: %{confirm: {op, version}}} = socket) do
    action = String.to_existing_atom(op)

    socket =
      case ActionDispatcher.dispatch_internal(:versioning, action, %{version: version}) do
        {:ok, result} -> assign(socket, notice: done_message(op, version, result), error: nil)
        {:error, reason} -> assign(socket, error: error_text(reason), notice: nil)
      end

    {:noreply, socket |> assign(:confirm, nil) |> load()}
  end

  def handle_event("confirm", _params, socket), do: {:noreply, socket}

  def handle_event("edit_locks", %{"version" => version}, socket) do
    locks = socket.assigns.versions |> Enum.find(&(&1.version == version)) |> then(&((&1 && &1.locks) || %{}))
    {:noreply, assign(socket, editing: version, locks_text: locks_to_text(locks), error: nil, notice: nil)}
  end

  def handle_event("save_locks", %{"version" => version, "locks" => text}, socket) do
    socket =
      with {:ok, locks} <- parse_locks(text),
           {:ok, _} <- ActionDispatcher.dispatch_internal(:versioning, :set_locks, %{version: version, locks: locks}) do
        assign(socket, editing: nil, notice: "Locks of #{version} saved.", error: nil)
      else
        {:error, reason} -> assign(socket, error: error_text(reason), locks_text: text)
      end

    {:noreply, load(socket)}
  end

  def handle_event("register", %{"version" => version, "locks" => text}, socket) do
    version = String.trim(version)

    socket =
      with {:ok, locks} <- parse_locks(text),
           {:ok, _} <- ActionDispatcher.dispatch_internal(:versioning, :register, %{version: version, locks: locks}) do
        assign(socket, register_form: %{"version" => "", "locks" => ""}, notice: "Game version #{version} registered as dev.", error: nil)
      else
        {:error, reason} -> assign(socket, error: error_text(reason), register_form: %{"version" => version, "locks" => text})
      end

    {:noreply, load(socket)}
  end

  ## ---- data ----

  defp load(socket) do
    versions =
      case ActionDispatcher.dispatch_internal(:versioning, :list, %{}) do
        {:ok, %{versions: list}} when is_list(list) -> Enum.map(list, &normalize/1)
        _ -> []
      end

    assign(socket, versions: versions, extensions: running_extensions(), max_active: max_active())
  end

  defp normalize(row) do
    %{
      version: to_string(field(row, :version)),
      status: to_string(field(row, :status)),
      locks: field(row, :locks) |> then(&if(is_map(&1), do: &1, else: %{})),
      created_at: field(row, :created_at)
    }
  end

  defp field(row, key), do: Map.get(row, key) || Map.get(row, to_string(key))

  # The game's own extensions with the version each runs now: what a producer picks locks from. The standard
  # extensions ship with the server and are not what a game version is built against.
  defp running_extensions do
    Exoforge.ExtensionRegistry.all_manifests()
    |> Enum.reject(&(Map.get(&1, :system, false) or String.starts_with?(to_string(&1.id), "exoforge_std_")))
    |> Map.new(fn m -> {to_string(m.id), to_string(m.version)} end)
  rescue
    _ -> %{}
  end

  defp max_active do
    Application.get_env(:exoforge_std_versioning, :max_active_versions, 3)
  end

  defp clear_messages(socket), do: assign(socket, error: nil, notice: nil, confirm: nil)

  ## ---- pure helpers (tested directly) ----

  @doc "Parses `extension@1.2.0` or `extension=1.2.0` entries, one per line or comma separated, into a locks map."
  def parse_locks(text) when is_binary(text) do
    text
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
      case Regex.run(~r/^([\w.\-]+)\s*[@=:\s]\s*([\w.\-+]+)$/, entry) do
        [_, extension, version] -> {:cont, {:ok, Map.put(acc, extension, version)}}
        _ -> {:halt, {:error, {:bad_lock, entry}}}
      end
    end)
  end

  def parse_locks(_), do: {:ok, %{}}

  @doc "The locks as the lines `parse_locks/1` reads back."
  def locks_to_text(locks) when is_map(locks) do
    locks |> Enum.sort() |> Enum.map_join("\n", fn {extension, version} -> "#{extension}@#{version}" end)
  end

  @doc "A producer-facing sentence for an error the `versioning` actions or the form can answer."
  def error_text(:already_exists), do: "That game version is already registered."
  def error_text(:invalid_version), do: "Write the game version, for example 1.4.0."
  def error_text(:not_found), do: "That game version does not exist."
  def error_text(:invalid_transition), do: "Only a dev version can be made live."
  def error_text(:locks_immutable), do: "Only a dev version can change its locks: players already use this one."
  def error_text(:invalid_locks), do: "The locks could not be read."
  def error_text(:too_many_active), do: "Too many versions are in use. Block an outdated one first."
  def error_text({:bad_lock, entry}), do: "\"#{entry}\" is not a lock. Write one extension per line, like achievements@1.2.0."
  def error_text(other), do: "The action failed: #{inspect(other)}."

  defp done_message("promote", version, %{blocked: [_ | _] = blocked}),
    do: "#{version} is live. Blocked as a result: #{Enum.join(blocked, ", ")}."

  defp done_message("promote", version, _), do: "#{version} is live."
  defp done_message("block", version, _), do: "#{version} is blocked: its players are told to update."

  defp status_classes("live"), do: "bg-emerald-50 text-emerald-700 border-emerald-200"
  defp status_classes("dev"), do: "bg-blue-50 text-blue-700 border-blue-200"
  defp status_classes("outdated"), do: "bg-amber-50 text-amber-700 border-amber-200"
  defp status_classes("blocked"), do: "bg-red-50 text-red-700 border-red-200"
  defp status_classes(_), do: "bg-gray-100 text-gray-700 border-gray-200"

  defp confirm_text({"promote", version}), do: "Make #{version} the live version? The current live version becomes outdated."
  defp confirm_text({"block", version}), do: "Block #{version}? Players on it are told to update and cannot sign in until they do."

  ## ---- render ----

  @impl true
  def render(assigns) do
    served = Enum.count(assigns.versions, &(&1.status != "blocked"))
    live = Enum.find(assigns.versions, &(&1.status == "live"))

    assigns =
      assigns
      |> assign(:served, served)
      |> assign(:blocked, Enum.count(assigns.versions, &(&1.status == "blocked")))
      |> assign(:live, live)

    ~H"""
    <div class="space-y-6" id={@id}>
      <div class="exo-page-header">
        <div>
          <h2 class="exo-page-title">Game Versions</h2>
          <p class="exo-page-subtitle">
            Which releases of your game the server still serves, and which extension version each one was built against.
          </p>
        </div>
        <div class="exo-page-actions">
          <button type="button" phx-click="refresh" phx-target={@myself} class="exo-btn exo-btn-secondary">
            <.studio_icon icon="refresh" class="w-3.5 h-3.5" /> Refresh
          </button>
        </div>
      </div>

      <div :if={@error} class="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700" role="alert"><%= @error %></div>
      <div :if={@notice} class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700" role="status"><%= @notice %></div>

      <div :if={@versions == []} class="rounded-xl border border-blue-200 bg-blue-50 px-5 py-4 text-sm text-blue-800 space-y-1">
        <p class="font-semibold">Versioning is off</p>
        <p>
          No game version is registered, so every client is served. Register the version your game reports
          (Unity sends <code class="font-mono">Application.version</code>) to start controlling who may connect.
        </p>
      </div>

      <div :if={@versions != []} class="grid gap-3 sm:grid-cols-3">
        <div class="rounded-xl border border-gray-200 bg-white p-4">
          <p class="text-[11px] font-semibold uppercase tracking-wider text-gray-400">Live</p>
          <p class="mt-1 text-lg font-semibold text-gray-900 font-mono"><%= if @live, do: @live.version, else: "none" %></p>
        </div>
        <div class="rounded-xl border border-gray-200 bg-white p-4">
          <p class="text-[11px] font-semibold uppercase tracking-wider text-gray-400">Served</p>
          <p class="mt-1 text-lg font-semibold text-gray-900 font-mono"><%= @served %> of <%= @max_active %></p>
        </div>
        <div class="rounded-xl border border-gray-200 bg-white p-4">
          <p class="text-[11px] font-semibold uppercase tracking-wider text-gray-400">Blocked</p>
          <p class="mt-1 text-lg font-semibold text-gray-900 font-mono"><%= @blocked %></p>
        </div>
      </div>

      <div :if={@versions != []} class="rounded-xl border border-gray-200 bg-white overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-gray-200 bg-gray-50 text-[11px] uppercase tracking-wider text-gray-500">
            <tr>
              <th class="px-4 py-2.5 font-semibold">Version</th>
              <th class="px-4 py-2.5 font-semibold">Status</th>
              <th class="px-4 py-2.5 font-semibold">Locks the extensions at</th>
              <th class="px-4 py-2.5 font-semibold text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100">
            <%= for v <- @versions do %>
              <tr id={"version-" <> v.version}>
                <td class="px-4 py-3 font-mono font-semibold text-gray-900"><%= v.version %></td>
                <td class="px-4 py-3">
                  <span class={"inline-flex rounded-full border px-2 py-0.5 text-[11px] font-semibold uppercase " <> status_classes(v.status)}><%= v.status %></span>
                </td>
                <td class="px-4 py-3">
                  <div class="flex flex-wrap gap-1">
                    <span :for={{extension, version} <- Enum.sort(v.locks)} class="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[11px] text-gray-700"><%= extension %>@<%= version %></span>
                    <span :if={v.locks == %{}} class="text-xs text-gray-400">no locks</span>
                  </div>
                </td>
                <td class="px-4 py-3">
                  <div class="flex flex-wrap justify-end gap-1.5">
                    <button :if={v.status == "dev"} type="button" phx-click="ask" phx-value-op="promote" phx-value-version={v.version} phx-target={@myself} class="exo-btn exo-btn-primary exo-btn-sm">Make live</button>
                    <button :if={v.status == "dev"} type="button" phx-click="edit_locks" phx-value-version={v.version} phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Edit locks</button>
                    <button :if={v.status != "blocked"} type="button" phx-click="ask" phx-value-op="block" phx-value-version={v.version} phx-target={@myself} class="exo-btn exo-btn-danger exo-btn-sm">Block</button>
                  </div>
                </td>
              </tr>
              <tr :if={@confirm && elem(@confirm, 1) == v.version}>
                <td colspan="4" class="bg-amber-50 px-4 py-3">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <p class="text-sm text-amber-800"><%= confirm_text(@confirm) %></p>
                    <div class="flex gap-2">
                      <button type="button" phx-click="confirm" phx-target={@myself} class={if elem(@confirm, 0) == "block", do: "exo-btn exo-btn-danger-solid exo-btn-sm", else: "exo-btn exo-btn-primary exo-btn-sm"}>
                        Yes, <%= if elem(@confirm, 0) == "block", do: "block it", else: "make it live" %>
                      </button>
                      <button type="button" phx-click="cancel" phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Cancel</button>
                    </div>
                  </div>
                </td>
              </tr>
              <tr :if={@editing == v.version}>
                <td colspan="4" class="bg-gray-50 px-4 py-3">
                  <form phx-submit="save_locks" phx-target={@myself} class="space-y-2">
                    <input type="hidden" name="version" value={v.version} />
                    <label class="block text-xs font-semibold text-gray-600" for={"locks-" <> v.version}>Locks of <%= v.version %>, one extension per line</label>
                    <textarea id={"locks-" <> v.version} name="locks" rows="4" class="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-xs text-gray-900"><%= @locks_text %></textarea>
                    <div class="flex gap-2">
                      <button type="submit" class="exo-btn exo-btn-primary exo-btn-sm">Save locks</button>
                      <button type="button" phx-click="cancel" phx-target={@myself} class="exo-btn exo-btn-secondary exo-btn-sm">Cancel</button>
                    </div>
                  </form>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <form phx-submit="register" phx-target={@myself} class="rounded-xl border border-gray-200 bg-white p-5 space-y-3">
        <h3 class="text-sm font-semibold text-gray-900">Register a game version</h3>
        <p class="text-xs text-gray-500">A new version starts as <span class="font-semibold">dev</span>. Make it live when its players are ready; the one that was live becomes outdated.</p>
        <div class="grid gap-3 sm:grid-cols-[14rem_1fr]">
          <div>
            <label class="block text-xs font-semibold text-gray-600" for="register-version">Version</label>
            <input id="register-version" name="version" value={@register_form["version"]} placeholder="1.4.0" class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-sm text-gray-900" />
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600" for="register-locks">Locks, one extension per line</label>
            <textarea id="register-locks" name="locks" rows="3" placeholder={locks_placeholder(@extensions)} class="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 font-mono text-xs text-gray-900"><%= @register_form["locks"] %></textarea>
          </div>
        </div>
        <p :if={@extensions != %{}} class="text-[11px] text-gray-500">
          Running now:
          <button :for={{extension, version} <- Enum.sort(@extensions)} type="button" class="mr-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700" onclick={"var t=document.getElementById('register-locks');t.value=(t.value?t.value.replace(/\\n?$/,'\\n'):'')+'#{extension}@#{version}';t.focus()"}><%= extension %>@<%= version %></button>
        </p>
        <button type="submit" class="exo-btn exo-btn-primary exo-btn-sm"><.studio_icon icon="plus" class="w-3.5 h-3.5" /> Register</button>
      </form>
    </div>
    """
  end

  defp locks_placeholder(extensions) do
    case Enum.sort(extensions) do
      [{extension, version} | _] -> "#{extension}@#{version}"
      [] -> "achievements@1.2.0"
    end
  end
end
