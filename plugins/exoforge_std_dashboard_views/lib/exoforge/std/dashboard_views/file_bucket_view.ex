defmodule Exoforge.Std.DashboardViews.FileBucketView do
  @moduledoc """
  Phoenix LiveComponent providing the Producer & Designer Studio visualization
  for the File Bucket asset and binary storage service (:file_bucket).
  """
  use Phoenix.LiveComponent

  alias Exoforge.ActionDispatcher

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       buckets: ["default"],
       selected_bucket: "all",
       files: [],
       filtered_files: [],
       search_query: "",
       type_filter: "all",
       selected_file: nil,
       view_mode: "tree",
       expanded_buckets: %{"default" => true},
       show_upload_modal: false,
       show_modify_modal: false,
       show_delete_modal: false,
       show_new_bucket_modal: false,
       upload_target_bucket: "default",
       upload_form: %{
         "bucket" => "default",
         "filename" => "",
         "content" => "",
         "content_type" => "",
         "preview_data_url" => ""
       },
       modify_form: %{
         "id" => "",
         "bucket" => "",
         "filename" => "",
         "content" => "",
         "content_type" => "",
         "preview_data_url" => ""
       },
       delete_file_target: nil,
       new_bucket_name: "",
       action_notification: nil,
       loaded: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.loaded do
        socket
      else
        socket
        |> assign(:loaded, true)
        |> load_data()
      end

    {:ok, socket}
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("select_bucket", %{"bucket" => bucket}, socket) do
    expanded = Map.put(socket.assigns.expanded_buckets, bucket, true)

    socket =
      socket
      |> assign(selected_bucket: bucket, expanded_buckets: expanded)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("toggle_bucket_expand", %{"bucket" => bucket}, socket) do
    curr = Map.get(socket.assigns.expanded_buckets, bucket, true)
    new_expanded = Map.put(socket.assigns.expanded_buckets, bucket, !curr)
    {:noreply, assign(socket, expanded_buckets: new_expanded)}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(search_query: query)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(type_filter: type)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) when mode in ["tree", "grid"] do
    {:noreply, assign(socket, view_mode: mode)}
  end

  def handle_event("select_file", %{"id" => id}, socket) do
    file = Enum.find(socket.assigns.files, &(to_string(&1["id"]) == to_string(id)))
    {:noreply, assign(socket, selected_file: file)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_event("open_upload_modal", params, socket) do
    target_bucket =
      params["bucket"] ||
        (if socket.assigns.selected_bucket != "all", do: socket.assigns.selected_bucket, else: "default")

    {:noreply,
     assign(socket,
       show_upload_modal: true,
       upload_target_bucket: target_bucket,
       upload_form: %{
         "bucket" => target_bucket,
         "filename" => "",
         "content" => "",
         "content_type" => "",
         "preview_data_url" => ""
       }
     )}
  end

  def handle_event("file_picked_for_upload", params, socket) do
    filename = params["filename"] || "file"
    base64 = params["base64"] || ""
    content_type = params["content_type"] || ""
    preview = if String.starts_with?(content_type, "image/"), do: "data:#{content_type};base64,#{base64}", else: ""

    updated_form =
      socket.assigns.upload_form
      |> Map.put("filename", filename)
      |> Map.put("content", base64)
      |> Map.put("content_type", content_type)
      |> Map.put("preview_data_url", preview)

    {:noreply, assign(socket, upload_form: updated_form)}
  end

  def handle_event("update_upload_form", %{"upload" => params}, socket) do
    updated = Map.merge(socket.assigns.upload_form, params)
    {:noreply, assign(socket, upload_form: updated)}
  end

  def handle_event("submit_upload", params, socket) do
    submitted = params["upload"] || %{}
    form = socket.assigns.upload_form
    bucket = submitted["bucket"] || form["bucket"] || "default"
    raw_filename = submitted["filename"] || form["filename"] || ""
    filename = String.trim(to_string(raw_filename))
    content = submitted["content"] || form["content"] || ""
    content_type = submitted["content_type"] || form["content_type"] || nil

    cond do
      content == "" ->
        {:noreply, notify(socket, :error, "Please select a file to upload first.")}

      filename == "" ->
        {:noreply, notify(socket, :error, "Please enter a filename for the upload.")}

      true ->
        payload = %{
          "bucket" => bucket,
          "filename" => filename,
          "content" => content,
          "content_type" => content_type
        }

        case ActionDispatcher.dispatch(:file_bucket, :upload_file, payload) do
          {:ok, %{file: file}} ->
            socket =
              socket
              |> assign(show_upload_modal: false, selected_file: file)
              |> load_data()
              |> notify(:info, "Uploaded '#{filename}' to bucket '#{bucket}' (ID: #{file["id"]})")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, notify(socket, :error, "Upload failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("open_modify_modal", _params, socket) do
    case socket.assigns.selected_file do
      nil ->
        {:noreply, socket}

      file ->
        preview =
          if String.starts_with?(to_string(file["content_type"] || ""), "image/"),
            do: file["url"],
            else: ""

        {:noreply,
         assign(socket,
           show_modify_modal: true,
           modify_form: %{
             "id" => file["id"],
             "bucket" => file["bucket"],
             "filename" => file["filename"],
             "content" => "",
             "content_type" => file["content_type"] || "",
             "preview_data_url" => preview
           }
         )}
    end
  end

  def handle_event("file_picked_for_modify", params, socket) do
    filename = params["filename"] || socket.assigns.modify_form["filename"]
    base64 = params["base64"] || ""
    content_type = params["content_type"] || socket.assigns.modify_form["content_type"]
    preview = if String.starts_with?(content_type, "image/"), do: "data:#{content_type};base64,#{base64}", else: ""

    updated_form =
      socket.assigns.modify_form
      |> Map.put("filename", filename)
      |> Map.put("content", base64)
      |> Map.put("content_type", content_type)
      |> Map.put("preview_data_url", preview)

    {:noreply, assign(socket, modify_form: updated_form)}
  end

  def handle_event("update_modify_form", %{"modify" => params}, socket) do
    updated = Map.merge(socket.assigns.modify_form, params)
    {:noreply, assign(socket, modify_form: updated)}
  end

  def handle_event("submit_modify", params, socket) do
    submitted = params["modify"] || %{}
    form = socket.assigns.modify_form
    id = form["id"]
    bucket = form["bucket"]
    raw_filename = submitted["filename"] || form["filename"] || ""
    filename = String.trim(to_string(raw_filename))
    content = submitted["content"] || form["content"]
    content_type = submitted["content_type"] || form["content_type"]

    payload =
      %{
        "id" => id,
        "bucket" => bucket,
        "filename" => filename
      }
      |> then(fn p -> if content != "" and content != nil, do: Map.put(p, "content", content), else: p end)
      |> then(fn p -> if content_type != "" and content_type != nil, do: Map.put(p, "content_type", content_type), else: p end)

    case ActionDispatcher.dispatch(:file_bucket, :update_file, payload) do
      {:ok, %{file: updated_file}} ->
        socket =
          socket
          |> assign(show_modify_modal: false, selected_file: updated_file)
          |> load_data()
          |> notify(:info, "Updated file '#{updated_file["filename"]}' (ID: #{id})")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, notify(socket, :error, "Modify failed: #{inspect(reason)}")}
    end
  end

  def handle_event("open_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: true, delete_file_target: socket.assigns.selected_file)}
  end

  def handle_event("confirm_delete", _params, socket) do
    case socket.assigns.delete_file_target do
      nil ->
        {:noreply, assign(socket, show_delete_modal: false)}

      file ->
        payload = %{"id" => file["id"], "bucket" => file["bucket"]}

        case ActionDispatcher.dispatch(:file_bucket, :delete_file, payload) do
          {:ok, _} ->
            socket =
              socket
              |> assign(show_delete_modal: false, delete_file_target: nil, selected_file: nil)
              |> load_data()
              |> notify(:info, "Deleted '#{file["filename"]}'")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, notify(socket, :error, "Delete failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("open_new_bucket_modal", _params, socket) do
    {:noreply, assign(socket, show_new_bucket_modal: true, new_bucket_name: "")}
  end

  def handle_event("update_new_bucket_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, new_bucket_name: name)}
  end

  def handle_event("submit_new_bucket", _params, socket) do
    name =
      socket.assigns.new_bucket_name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]/, "_")

    if name == "" do
      {:noreply, notify(socket, :error, "Bucket name cannot be empty.")}
    else
      base = Application.get_env(:exoforge_std_file_bucket, :storage_dir, "priv/data/file_bucket")
      dir = Path.join(base, name)
      _ = File.mkdir_p(dir)

      new_buckets = Enum.uniq([name | socket.assigns.buckets]) |> Enum.sort()

      socket =
        socket
        |> assign(
          buckets: new_buckets,
          selected_bucket: name,
          show_new_bucket_modal: false,
          new_bucket_name: ""
        )
        |> apply_filters()
        |> notify(:info, "Bucket '#{name}' created and selected.")

      {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_upload_modal: false,
       show_modify_modal: false,
       show_delete_modal: false,
       show_new_bucket_modal: false
     )}
  end

  def handle_event("dismiss_notification", _params, socket) do
    {:noreply, assign(socket, action_notification: nil)}
  end

  # ---- PRIVATE HELPERS ----

  defp load_data(socket) do
    buckets =
      case ActionDispatcher.dispatch(:file_bucket, :list_buckets, %{}) do
        {:ok, %{buckets: b}} when is_list(b) -> b
        _ -> ["default"]
      end

    files =
      case ActionDispatcher.dispatch(:file_bucket, :list_files, %{"bucket" => "all", "limit" => 500}) do
        {:ok, %{files: f}} when is_list(f) -> f
        _ -> []
      end

    expanded =
      Map.merge(
        Map.new(buckets, fn b -> {b, true} end),
        socket.assigns.expanded_buckets
      )

    selected_file =
      if socket.assigns.selected_file do
        Enum.find(files, &(to_string(&1["id"]) == to_string(socket.assigns.selected_file["id"]))) ||
          List.first(files)
      else
        List.first(files)
      end

    socket
    |> assign(
      buckets: buckets,
      files: files,
      expanded_buckets: expanded,
      selected_file: selected_file
    )
    |> apply_filters()
  end

  defp apply_filters(socket) do
    files = socket.assigns.files
    selected_bucket = socket.assigns.selected_bucket
    type_filter = socket.assigns.type_filter
    search = String.downcase(String.trim(socket.assigns.search_query))

    filtered =
      files
      |> Enum.filter(fn f ->
        (selected_bucket == "all" or to_string(f["bucket"]) == selected_bucket) and
          match_type?(f, type_filter) and
          match_search?(f, search)
      end)

    assign(socket, filtered_files: filtered)
  end

  defp match_type?(_file, "all"), do: true
  defp match_type?(file, "image") do
    ct = to_string(file["content_type"] || "")
    ext = Path.extname(file["filename"] || "") |> String.downcase()
    String.starts_with?(ct, "image/") or ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]
  end
  defp match_type?(file, "audio") do
    ct = to_string(file["content_type"] || "")
    ext = Path.extname(file["filename"] || "") |> String.downcase()
    String.starts_with?(ct, "audio/") or String.starts_with?(ct, "video/") or ext in [".mp3", ".wav", ".ogg", ".mp4", ".webm"]
  end
  defp match_type?(file, "document") do
    ct = to_string(file["content_type"] || "")
    ext = Path.extname(file["filename"] || "") |> String.downcase()
    String.starts_with?(ct, "text/") or ct == "application/json" or ext in [".txt", ".json", ".csv", ".pdf", ".xml"]
  end
  defp match_type?(file, "other") do
    not match_type?(file, "image") and not match_type?(file, "audio") and not match_type?(file, "document")
  end

  defp match_search?(_file, ""), do: true
  defp match_search?(file, search) do
    String.contains?(String.downcase(to_string(file["filename"] || "")), search) or
      String.contains?(String.downcase(to_string(file["id"] || "")), search) or
      String.contains?(String.downcase(to_string(file["bucket"] || "")), search)
  end

  defp notify(socket, type, message) do
    assign(socket, action_notification: %{type: type, message: message})
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
    end
  end
  defp format_bytes(_), do: "0 B"

  defp file_icon(file) do
    ct = to_string(file["content_type"] || "")
    ext = Path.extname(file["filename"] || "") |> String.downcase()

    cond do
      String.starts_with?(ct, "image/") or ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"] -> "🖼️"
      String.starts_with?(ct, "audio/") or ext in [".mp3", ".wav", ".ogg"] -> "🎵"
      String.starts_with?(ct, "video/") or ext in [".mp4", ".webm"] -> "🎬"
      ct == "application/json" or ext == ".json" -> "⚙️"
      ext in [".txt", ".csv", ".pdf"] -> "📄"
      ext in [".zip", ".gz", ".tar"] -> "📦"
      true -> "📎"
    end
  end

  defp image_file?(file) do
    ct = to_string(file["content_type"] || "")
    ext = Path.extname(file["filename"] || "") |> String.downcase()
    String.starts_with?(ct, "image/") or ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]
  end

  # ---- RENDER ----

  @impl true
  def render(assigns) do
    total_bytes = Enum.reduce(assigns.files, 0, fn f, acc -> acc + (f["size_bytes"] || 0) end)
    assigns = assign(assigns, :total_storage_bytes, total_bytes)

    ~H"""
    <div class="space-y-6">
      <!-- Notification Banner -->
      <%= if @action_notification do %>
        <div class={"p-4 rounded-2xl flex items-center justify-between border shadow-sm transition-all #{if @action_notification.type == :error, do: "bg-red-50 text-red-700 border-red-200", else: "bg-emerald-50 text-emerald-800 border-emerald-200"}"}>
          <div class="flex items-center gap-3">
            <span class="text-base"><%= if @action_notification.type == :error, do: "⚠️", else: "✅" %></span>
            <span class="text-xs font-semibold"><%= @action_notification.message %></span>
          </div>
          <button phx-click="dismiss_notification" phx-target={@myself} class="text-xs font-bold opacity-60 hover:opacity-100">✕</button>
        </div>
      <% end %>

      <!-- Top Summary & Metrics Card -->
      <div class="bg-white rounded-2xl border border-gray-100 p-6 shadow-sm">
        <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div class="flex items-center gap-3">
              <span class="text-2xl">🗂️</span>
              <h2 class="text-lg font-bold text-gray-900">File Bucket Storage</h2>
              <span class="text-xs px-2.5 py-0.5 font-bold rounded-full bg-violet-50 text-violet-700 border border-violet-100">Cluster Engine</span>
            </div>
            <p class="text-xs text-gray-400 mt-1">Pluggable binary asset storage for Unity, web clients, game media, and configurations</p>
          </div>

          <!-- Top Actions -->
          <div class="flex items-center gap-2">
            <button
              phx-click="open_new_bucket_modal"
              phx-target={@myself}
              class="px-3.5 py-2 text-xs font-semibold text-gray-700 bg-white hover:bg-gray-50 border border-gray-200 rounded-xl transition-colors shadow-sm flex items-center gap-1.5"
            >
              <span>📁</span>
              <span>New Bucket</span>
            </button>
            <button
              phx-click="open_upload_modal"
              phx-target={@myself}
              class="px-4 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl transition-colors shadow-sm flex items-center gap-1.5"
            >
              <span>⬆️</span>
              <span>Upload File</span>
            </button>
            <button
              phx-click="refresh"
              phx-target={@myself}
              class="p-2 text-gray-500 hover:text-gray-700 bg-white hover:bg-gray-50 border border-gray-200 rounded-xl transition-colors shadow-sm"
              title="Refresh"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
            </button>
          </div>
        </div>

        <!-- Metric Pills -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mt-6 pt-5 border-t border-gray-100">
          <div class="bg-gray-50/70 p-3 rounded-xl border border-gray-100">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Total Buckets</span>
            <p class="text-base font-bold text-gray-900 mt-0.5"><%= length(@buckets) %></p>
          </div>
          <div class="bg-gray-50/70 p-3 rounded-xl border border-gray-100">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Total Files</span>
            <p class="text-base font-bold text-gray-900 mt-0.5"><%= length(@files) %></p>
          </div>
          <div class="bg-gray-50/70 p-3 rounded-xl border border-gray-100">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Total Storage</span>
            <p class="text-base font-bold text-gray-900 mt-0.5"><%= format_bytes(@total_storage_bytes) %></p>
          </div>
          <div class="bg-gray-50/70 p-3 rounded-xl border border-gray-100">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Selected Scope</span>
            <p class="text-base font-bold text-violet-600 mt-0.5 truncate"><%= if @selected_bucket == "all", do: "All Buckets", else: @selected_bucket %></p>
          </div>
        </div>
      </div>

      <!-- Controls & Filter Toolbar -->
      <div class="flex flex-col md:flex-row items-center justify-between gap-3">
        <!-- Bucket filter pills -->
        <div class="flex items-center gap-1.5 overflow-x-auto w-full md:w-auto pb-1 md:pb-0">
          <button
            phx-click="select_bucket"
            phx-value-bucket="all"
            phx-target={@myself}
            class={"px-3 py-1.5 text-xs font-semibold rounded-xl border transition-colors shrink-0 #{if @selected_bucket == "all", do: "bg-violet-600 text-white border-violet-600 shadow-sm", else: "bg-white text-gray-600 border-gray-200 hover:bg-gray-50"}"}
          >
            All Buckets
          </button>
          <%= for b <- @buckets do %>
            <button
              phx-click="select_bucket"
              phx-value-bucket={b}
              phx-target={@myself}
              class={"px-3 py-1.5 text-xs font-semibold rounded-xl border transition-colors shrink-0 flex items-center gap-1.5 #{if @selected_bucket == b, do: "bg-violet-600 text-white border-violet-600 shadow-sm", else: "bg-white text-gray-600 border-gray-200 hover:bg-gray-50"}"}
            >
              <span>📁</span>
              <span><%= b %></span>
            </button>
          <% end %>
        </div>

        <div class="flex items-center gap-2 w-full md:w-auto justify-end">
          <!-- Search box -->
          <div class="relative flex-1 md:w-64">
            <input
              type="text"
              placeholder="Search filename or ID..."
              value={@search_query}
              phx-keyup="search"
              phx-target={@myself}
              class="w-full pl-8 pr-3 py-1.5 text-xs bg-white border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 shadow-sm"
            />
            <span class="absolute left-2.5 top-2 text-xs text-gray-400">🔍</span>
          </div>

          <!-- Type filter dropdown -->
          <select
            phx-change="filter_type"
            name="type"
            phx-target={@myself}
            class="text-xs bg-white border border-gray-200 rounded-xl px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-violet-500 shadow-sm"
          >
            <option value="all" selected={@type_filter == "all"}>All Types</option>
            <option value="image" selected={@type_filter == "image"}>Images</option>
            <option value="document" selected={@type_filter == "document"}>Documents</option>
            <option value="audio" selected={@type_filter == "audio"}>Audio & Media</option>
            <option value="other" selected={@type_filter == "other"}>Other</option>
          </select>

          <!-- View Mode Toggle -->
          <div class="flex items-center bg-gray-100 p-0.5 rounded-xl border border-gray-200 shrink-0">
            <button
              phx-click="set_view_mode"
              phx-value-mode="tree"
              phx-target={@myself}
              class={"px-2 py-1 text-xs font-bold rounded-lg transition-all #{if @view_mode == "tree", do: "bg-white text-gray-800 shadow-sm", else: "text-gray-500 hover:text-gray-800"}"}
              title="Tree view"
            >
              📁 Tree
            </button>
            <button
              phx-click="set_view_mode"
              phx-value-mode="grid"
              phx-target={@myself}
              class={"px-2 py-1 text-xs font-bold rounded-lg transition-all #{if @view_mode == "grid", do: "bg-white text-gray-800 shadow-sm", else: "text-gray-500 hover:text-gray-800"}"}
              title="Grid view"
            >
              ▦ Grid
            </button>
          </div>
        </div>
      </div>

      <!-- Main Explorer (Split View) -->
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        <!-- Left Panel: File Tree / File List (7 cols) -->
        <div class="lg:col-span-7 bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden flex flex-col min-h-[500px]">
          <div class="p-3.5 border-b border-gray-100 bg-gray-50/50 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold text-gray-700 uppercase tracking-wider">
                Files (<%= length(@filtered_files) %>)
              </span>
              <%= if @selected_bucket != "all" do %>
                <span class="text-[10px] font-mono text-violet-700 bg-violet-50 px-2 py-0.5 rounded-full border border-violet-100">
                  /<%= @selected_bucket %>
                </span>
              <% end %>
            </div>
          </div>

          <div class="p-2 flex-1 overflow-y-auto max-h-[620px]">
            <%= if @filtered_files == [] do %>
              <div class="py-16 text-center">
                <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 flex items-center justify-center mx-auto mb-3 text-xl">
                  🗂️
                </div>
                <p class="text-sm font-semibold text-gray-700">No Files Found</p>
                <p class="text-xs text-gray-400 mt-1">Upload binary files, game assets, or textures to this bucket.</p>
                <button
                  phx-click="open_upload_modal"
                  phx-target={@myself}
                  class="mt-4 px-4 py-2 text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 rounded-xl transition-colors inline-flex items-center gap-1.5"
                >
                  <span>⬆️</span> Upload File
                </button>
              </div>
            <% else %>
              <%= if @view_mode == "tree" do %>
                <!-- Tree Mode: Buckets as folders -->
                <% grouped_files = Enum.group_by(@filtered_files, &(&1["bucket"] || "default")) %>
                <div class="space-y-2">
                  <%= for {bucket_name, bucket_files} <- grouped_files do %>
                    <% is_expanded = Map.get(@expanded_buckets, bucket_name, true) %>
                    <div class="border border-gray-100 rounded-xl overflow-hidden">
                      <!-- Bucket Folder Header -->
                      <div
                        phx-click="toggle_bucket_expand"
                        phx-value-bucket={bucket_name}
                        phx-target={@myself}
                        class="p-2.5 bg-gray-50/70 hover:bg-gray-100/70 flex items-center justify-between cursor-pointer transition-colors select-none"
                      >
                        <div class="flex items-center gap-2">
                          <span class="text-xs text-gray-400 transition-transform"><%= if is_expanded, do: "▼", else: "▶" %></span>
                          <span class="text-sm">📁</span>
                          <span class="text-xs font-bold text-gray-800"><%= bucket_name %></span>
                          <span class="text-[10px] text-gray-400 font-semibold">(<%= length(bucket_files) %>)</span>
                        </div>
                        <button
                          phx-click="open_upload_modal"
                          phx-value-bucket={bucket_name}
                          phx-target={@myself}
                          class="text-[10px] font-bold text-violet-600 hover:text-violet-800 bg-white px-2 py-0.5 rounded-lg border border-gray-200 shadow-2xs"
                          onclick="event.stopPropagation();"
                        >
                          + Upload
                        </button>
                      </div>

                      <!-- Bucket Files List -->
                      <%= if is_expanded do %>
                        <div class="divide-y divide-gray-50 bg-white pl-4">
                          <%= for file <- bucket_files do %>
                            <% is_selected = @selected_file && to_string(@selected_file["id"]) == to_string(file["id"]) %>
                            <div
                              phx-click="select_file"
                              phx-value-id={file["id"]}
                              phx-target={@myself}
                              class={"p-2.5 hover:bg-violet-50/40 cursor-pointer flex items-center justify-between gap-3 transition-colors #{if is_selected, do: "bg-violet-50/70 border-l-2 border-violet-600 font-medium"}"}
                            >
                              <div class="flex items-center gap-2.5 min-w-0">
                                <span class="text-base shrink-0"><%= file_icon(file) %></span>
                                <div class="truncate">
                                  <div class="text-xs text-gray-900 truncate font-semibold">
                                    <%= file["filename"] %>
                                  </div>
                                  <div class="flex items-center gap-2 mt-0.5">
                                    <span class="text-[10px] font-mono text-gray-400"><%= file["id"] %></span>
                                    <span class="text-[10px] text-gray-400">• <%= format_bytes(file["size_bytes"]) %></span>
                                  </div>
                                </div>
                              </div>
                              <span class="text-[10px] font-mono text-gray-400 shrink-0"><%= file["content_type"] %></span>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <!-- Grid Mode -->
                <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 p-1">
                  <%= for file <- @filtered_files do %>
                    <% is_selected = @selected_file && to_string(@selected_file["id"]) == to_string(file["id"]) %>
                    <div
                      phx-click="select_file"
                      phx-value-id={file["id"]}
                      phx-target={@myself}
                      class={"p-3 rounded-xl border cursor-pointer hover:border-violet-300 transition-all flex flex-col justify-between #{if is_selected, do: "border-violet-500 bg-violet-50/50 shadow-sm", else: "border-gray-200 bg-white hover:bg-gray-50/50"}"}
                    >
                      <div class="flex items-center justify-center h-24 bg-gray-50 rounded-lg mb-2 overflow-hidden border border-gray-100">
                        <%= if image_file?(file) do %>
                          <img src={file["url"]} class="max-h-full max-w-full object-contain" alt={file["filename"]} />
                        <% else %>
                          <span class="text-3xl"><%= file_icon(file) %></span>
                        <% end %>
                      </div>
                      <div>
                        <p class="text-xs font-bold text-gray-800 truncate" title={file["filename"]}><%= file["filename"] %></p>
                        <div class="flex items-center justify-between mt-1 text-[10px] text-gray-400">
                          <span class="truncate font-mono"><%= file["id"] %></span>
                          <span><%= format_bytes(file["size_bytes"]) %></span>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <!-- Right Panel: File Preview & Inspector (5 cols) -->
        <div class="lg:col-span-5 bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden flex flex-col min-h-[500px]">
          <div class="p-3.5 border-b border-gray-100 bg-gray-50/50 flex items-center justify-between">
            <span class="text-xs font-bold text-gray-700 uppercase tracking-wider">File Details & Live Preview</span>
            <%= if @selected_file do %>
              <div class="flex items-center gap-1">
                <button
                  phx-click="open_modify_modal"
                  phx-target={@myself}
                  class="text-xs font-semibold text-gray-700 bg-white hover:bg-gray-50 px-2.5 py-1 rounded-lg border border-gray-200 transition-colors shadow-2xs"
                  title="Modify file"
                >
                  ✏️ Edit
                </button>
                <button
                  phx-click="open_delete_modal"
                  phx-target={@myself}
                  class="text-xs font-semibold text-red-600 bg-white hover:bg-red-50 px-2.5 py-1 rounded-lg border border-red-200 transition-colors shadow-2xs"
                  title="Delete file"
                >
                  🗑️
                </button>
              </div>
            <% end %>
          </div>

          <div class="p-5 flex-1 flex flex-col justify-between">
            <%= if @selected_file do %>
              <div class="space-y-5">
                <!-- File Preview Box -->
                <div class="rounded-xl border border-gray-200 bg-gray-50/80 p-4 flex flex-col items-center justify-center min-h-[200px] overflow-hidden relative">
                  <%= if image_file?(@selected_file) do %>
                    <div class="max-h-56 max-w-full flex items-center justify-center">
                      <img
                        src={@selected_file["url"]}
                        alt={@selected_file["filename"]}
                        class="max-h-52 max-w-full rounded-lg shadow-sm object-contain"
                      />
                    </div>
                  <% else %>
                    <%= if String.starts_with?(to_string(@selected_file["content_type"] || ""), "audio/") do %>
                      <div class="w-full space-y-3 text-center">
                        <span class="text-4xl">🎵</span>
                        <audio controls src={@selected_file["url"]} class="w-full mt-2"></audio>
                      </div>
                    <% else %>
                      <div class="text-center py-6">
                        <span class="text-5xl"><%= file_icon(@selected_file) %></span>
                        <p class="text-xs font-bold text-gray-700 mt-2"><%= @selected_file["filename"] %></p>
                        <p class="text-[10px] text-gray-400 font-mono mt-0.5"><%= @selected_file["content_type"] %></p>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <!-- Properties Details -->
                <div class="space-y-3">
                  <div>
                    <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Filename</span>
                    <p class="text-sm font-bold text-gray-900 break-all"><%= @selected_file["filename"] %></p>
                  </div>

                  <!-- File ID with Quick Copy -->
                  <div>
                    <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">File Reference ID</span>
                    <div class="flex items-center gap-2 mt-1">
                      <code class="px-2.5 py-1 text-xs font-mono font-bold bg-violet-50 text-violet-700 rounded-lg border border-violet-100 select-all">
                        <%= @selected_file["id"] %>
                      </code>
                      <button
                        onclick={"navigator.clipboard.writeText('#{@selected_file["id"]}');"}
                        class="text-xs px-2 py-1 bg-white hover:bg-gray-50 border border-gray-200 rounded-lg font-semibold text-gray-600 transition-colors shadow-2xs"
                        title="Copy ID"
                      >
                        📋 Copy
                      </button>
                    </div>
                    <p class="text-[10px] text-gray-400 mt-1">Use this ID on any resource column tagged as <span class="font-mono text-gray-600">file_reference</span></p>
                  </div>

                  <div class="grid grid-cols-2 gap-3 pt-2 border-t border-gray-100">
                    <div>
                      <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Bucket</span>
                      <p class="text-xs font-semibold text-gray-800"><%= @selected_file["bucket"] %></p>
                    </div>
                    <div>
                      <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Size</span>
                      <p class="text-xs font-semibold text-gray-800"><%= format_bytes(@selected_file["size_bytes"]) %></p>
                    </div>
                    <div>
                      <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Content Type</span>
                      <p class="text-xs font-mono text-gray-700 truncate" title={@selected_file["content_type"]}><%= @selected_file["content_type"] %></p>
                    </div>
                    <div>
                      <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">SHA-256</span>
                      <p class="text-xs font-mono text-gray-500 truncate" title={@selected_file["sha256"]}><%= String.slice(to_string(@selected_file["sha256"] || ""), 0, 12) %>...</p>
                    </div>
                  </div>

                  <!-- API URL -->
                  <div class="pt-2 border-t border-gray-100">
                    <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Public HTTP URL</span>
                    <div class="flex items-center gap-2 mt-1">
                      <input
                        type="text"
                        readonly
                        value={@selected_file["url"]}
                        class="w-full text-xs font-mono bg-gray-50 border border-gray-200 rounded-lg px-2.5 py-1 text-gray-600 select-all"
                      />
                      <a
                        href={@selected_file["url"]}
                        target="_blank"
                        class="px-2.5 py-1 text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 rounded-lg border border-violet-100 shrink-0"
                      >
                        ↗ Open
                      </a>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Bottom Actions -->
              <div class="pt-5 border-t border-gray-100 flex items-center gap-2">
                <a
                  href={@selected_file["url"]}
                  download={@selected_file["filename"]}
                  class="flex-1 py-2 text-center text-xs font-bold text-gray-800 bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-xl transition-colors shadow-2xs"
                >
                  ⬇️ Download
                </a>
                <button
                  phx-click="open_modify_modal"
                  phx-target={@myself}
                  class="flex-1 py-2 text-center text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 border border-violet-100 rounded-xl transition-colors shadow-2xs"
                >
                  ✏️ Modify
                </button>
              </div>
            <% else %>
              <div class="py-24 text-center my-auto">
                <div class="w-12 h-12 rounded-2xl bg-gray-100 text-gray-400 flex items-center justify-center mx-auto mb-3 text-xl">
                  🔍
                </div>
                <p class="text-sm font-semibold text-gray-700">No File Selected</p>
                <p class="text-xs text-gray-400 mt-1">Click any file from the explorer on the left to inspect, preview, and copy its ID.</p>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- ================= MODALS ================= -->

      <!-- 1. Upload File Modal -->
      <%= if @show_upload_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 space-y-4">
            <div class="flex items-center justify-between border-b border-gray-100 pb-3">
              <div class="flex items-center gap-2">
                <span class="text-xl">⬆️</span>
                <h3 class="text-sm font-bold text-gray-900">Upload File to Bucket</h3>
              </div>
              <button phx-click="close_modal" phx-target={@myself} class="text-gray-400 hover:text-gray-600 text-sm font-bold">✕</button>
            </div>

            <form phx-submit="submit_upload" phx-target={@myself} class="space-y-4">
              <input type="hidden" id="bucket_upload_content_input" name="upload[content]" value="" />
              <input type="hidden" id="bucket_upload_content_type_input" name="upload[content_type]" value="" />

              <!-- Bucket Target Selection -->
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Target Bucket</label>
                <select
                  name="upload[bucket]"
                  class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-2 font-semibold text-gray-800 focus:outline-none focus:ring-2 focus:ring-violet-500"
                >
                  <%= for b <- @buckets do %>
                    <option value={b} selected={b == @upload_form["bucket"]}><%= b %></option>
                  <% end %>
                </select>
              </div>

              <!-- File Picker via Client-Side FileReader -->
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Select File to Upload</label>
                <div class="border-2 border-dashed border-gray-300 rounded-xl p-5 text-center hover:border-violet-400 transition-colors bg-gray-50/50">
                  <input
                    type="file"
                    id="bucket_upload_file_picker"
                    onchange="
                      const file = this.files[0];
                      if (!file) return;
                      const fnInput = document.getElementById('bucket_upload_filename_input');
                      if (fnInput) fnInput.value = file.name;
                      const reader = new FileReader();
                      reader.onload = function(e) {
                        const parts = e.target.result.split(',');
                        const base64 = parts[1];
                        const contentInput = document.getElementById('bucket_upload_content_input');
                        const ctInput = document.getElementById('bucket_upload_content_type_input');
                        if (contentInput) contentInput.value = base64;
                        if (ctInput) ctInput.value = file.type || 'application/octet-stream';

                        const previewBox = document.getElementById('bucket_upload_preview_box');
                        const previewImg = document.getElementById('bucket_upload_preview_img');
                        const previewName = document.getElementById('bucket_upload_preview_name');
                        const previewType = document.getElementById('bucket_upload_preview_type');
                        if (previewBox && previewImg) {
                          if (file.type && file.type.startsWith('image/')) {
                            previewImg.src = e.target.result;
                            if (previewName) previewName.textContent = file.name;
                            if (previewType) previewType.textContent = file.type;
                            previewBox.style.display = 'flex';
                          } else {
                            previewBox.style.display = 'none';
                          }
                        }
                      };
                      reader.readAsDataURL(file);
                    "
                    class="block w-full text-xs text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-xl file:border-0 file:text-xs file:font-bold file:bg-violet-50 file:text-violet-700 hover:file:bg-violet-100 cursor-pointer"
                  />
                  <p class="text-[11px] text-gray-400 mt-2">Selecting a file will automatically populate the filename below.</p>
                </div>
              </div>

              <!-- Filename Input -->
              <div>
                <div class="flex items-center justify-between mb-1">
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider">Filename</label>
                  <span class="text-[10px] text-gray-400">Auto-filled on select • edit to rename before saving</span>
                </div>
                <input
                  type="text"
                  id="bucket_upload_filename_input"
                  name="upload[filename]"
                  value={@upload_form["filename"]}
                  placeholder="Select a file above or enter custom filename..."
                  class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-2 font-mono focus:outline-none focus:ring-2 focus:ring-violet-500"
                />
                <p class="text-[11px] text-gray-400 mt-1">This is the saved file name in the bucket. Edit it if you wish to save with a new name.</p>
              </div>

              <!-- Preview container -->
              <div id="bucket_upload_preview_box" style="display: none;" class="p-3 bg-gray-50 rounded-xl border border-gray-100 items-center gap-3">
                <img id="bucket_upload_preview_img" class="w-12 h-12 object-contain rounded-lg border border-gray-200 bg-white" />
                <div class="truncate text-xs">
                  <p id="bucket_upload_preview_name" class="font-bold text-gray-800 truncate"></p>
                  <p id="bucket_upload_preview_type" class="text-gray-400 font-mono text-[10px]"></p>
                </div>
              </div>

              <div class="flex items-center justify-end gap-2 pt-3 border-t border-gray-100">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl transition-colors shadow-sm"
                >
                  Upload File
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- 2. Modify File Modal -->
      <%= if @show_modify_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-gray-200 space-y-4">
            <div class="flex items-center justify-between border-b border-gray-100 pb-3">
              <div class="flex items-center gap-2">
                <span class="text-xl">✏️</span>
                <h3 class="text-sm font-bold text-gray-900">Modify File (<%= @modify_form["id"] %>)</h3>
              </div>
              <button phx-click="close_modal" phx-target={@myself} class="text-gray-400 hover:text-gray-600 text-sm font-bold">✕</button>
            </div>

            <form phx-submit="submit_modify" phx-target={@myself} class="space-y-4">
              <input type="hidden" id="bucket_modify_content_input" name="modify[content]" value="" />
              <input type="hidden" id="bucket_modify_content_type_input" name="modify[content_type]" value="" />

              <!-- Bucket (Readonly) -->
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Bucket</label>
                <input
                  type="text"
                  readonly
                  value={@modify_form["bucket"]}
                  class="w-full text-xs bg-gray-100 text-gray-500 border border-gray-200 rounded-xl px-3 py-2 font-mono"
                />
              </div>

              <!-- Filename Input -->
              <div>
                <div class="flex items-center justify-between mb-1">
                  <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider">Filename</label>
                  <span class="text-[10px] text-gray-400">Edit to rename file</span>
                </div>
                <input
                  type="text"
                  id="bucket_modify_filename_input"
                  name="modify[filename]"
                  value={@modify_form["filename"]}
                  class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-2 font-mono focus:outline-none focus:ring-2 focus:ring-violet-500"
                />
              </div>

              <!-- Optional Content Replacement -->
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Replace Binary Content (Optional)</label>
                <input
                  type="file"
                  id="bucket_modify_file_picker"
                  onchange="
                    const file = this.files[0];
                    if (!file) return;
                    const reader = new FileReader();
                    reader.onload = function(e) {
                      const parts = e.target.result.split(',');
                      const base64 = parts[1];
                      const contentInput = document.getElementById('bucket_modify_content_input');
                      const ctInput = document.getElementById('bucket_modify_content_type_input');
                      if (contentInput) contentInput.value = base64;
                      if (ctInput) ctInput.value = file.type || 'application/octet-stream';

                      const previewBox = document.getElementById('bucket_modify_preview_box');
                      const previewImg = document.getElementById('bucket_modify_preview_img');
                      const previewName = document.getElementById('bucket_modify_preview_name');
                      const previewType = document.getElementById('bucket_modify_preview_type');
                      if (previewBox && previewImg) {
                        if (file.type && file.type.startsWith('image/')) {
                          previewImg.src = e.target.result;
                          if (previewName) previewName.textContent = file.name;
                          if (previewType) previewType.textContent = file.type;
                          previewBox.style.display = 'flex';
                        }
                      }
                    };
                    reader.readAsDataURL(file);
                  "
                  class="block w-full text-xs text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-xl file:border-0 file:text-xs file:font-bold file:bg-gray-100 file:text-gray-700 hover:file:bg-gray-200 cursor-pointer"
                />
                <p class="text-[10px] text-gray-400 mt-1">Replacing content preserves the exact same File ID (<%= @modify_form["id"] %>)</p>
              </div>

              <!-- Live Preview if replaced or current image -->
              <div id="bucket_modify_preview_box" style={if @modify_form["preview_data_url"] != "", do: "display: flex;", else: "display: none;"} class="p-3 bg-gray-50 rounded-xl border border-gray-100 items-center gap-3">
                <img id="bucket_modify_preview_img" src={@modify_form["preview_data_url"]} class="w-12 h-12 object-contain rounded-lg border border-gray-200 bg-white" />
                <div class="truncate text-xs">
                  <p id="bucket_modify_preview_name" class="font-bold text-gray-800 truncate"><%= @modify_form["filename"] %></p>
                  <p id="bucket_modify_preview_type" class="text-gray-400 font-mono text-[10px]"><%= @modify_form["content_type"] %></p>
                </div>
              </div>

              <div class="flex items-center justify-end gap-2 pt-3 border-t border-gray-100">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl transition-colors shadow-sm"
                >
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- 3. Delete Confirmation Modal -->
      <%= if @show_delete_modal and @delete_file_target do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-gray-200 space-y-4">
            <div class="flex items-center gap-3 text-red-600">
              <span class="text-2xl">⚠️</span>
              <h3 class="text-sm font-bold text-gray-900">Delete Stored File</h3>
            </div>
            <p class="text-xs text-gray-600">
              Are you sure you want to permanently delete <strong class="text-gray-900"><%= @delete_file_target["filename"] %></strong> (ID: <code class="font-mono text-violet-700 bg-violet-50 px-1 rounded"><%= @delete_file_target["id"] %></code>) from bucket <strong class="text-gray-900"><%= @delete_file_target["bucket"] %></strong>?
            </p>
            <p class="text-[11px] text-gray-400">Any game client or resource referencing this File ID will fail to load the asset.</p>
            <div class="flex items-center justify-end gap-2 pt-3 border-t border-gray-100">
              <button
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="px-4 py-2 text-xs font-semibold text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                phx-click="confirm_delete"
                phx-target={@myself}
                class="px-4 py-2 text-xs font-bold text-white bg-red-600 hover:bg-red-700 rounded-xl transition-colors shadow-sm"
              >
                Yes, Delete File
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- 4. New Bucket Modal -->
      <%= if @show_new_bucket_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
          <div class="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-gray-200 space-y-4">
            <div class="flex items-center justify-between border-b border-gray-100 pb-3">
              <div class="flex items-center gap-2">
                <span class="text-xl">📁</span>
                <h3 class="text-sm font-bold text-gray-900">Create New Bucket</h3>
              </div>
              <button phx-click="close_modal" phx-target={@myself} class="text-gray-400 hover:text-gray-600 text-sm font-bold">✕</button>
            </div>

            <form phx-submit="submit_new_bucket" phx-target={@myself} class="space-y-4">
              <div>
                <label class="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">Bucket Name</label>
                <input
                  type="text"
                  name="name"
                  placeholder="e.g. game_textures"
                  value={@new_bucket_name}
                  phx-change="update_new_bucket_name"
                  phx-target={@myself}
                  class="w-full text-xs bg-gray-50 border border-gray-200 rounded-xl px-3 py-2 font-mono focus:outline-none focus:ring-2 focus:ring-violet-500"
                />
                <p class="text-[10px] text-gray-400 mt-1">Lowercase letters, numbers, and underscores only.</p>
              </div>

              <div class="flex items-center justify-end gap-2 pt-3 border-t border-gray-100">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="px-4 py-2 text-xs font-semibold text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 text-xs font-bold text-white bg-violet-600 hover:bg-violet-700 rounded-xl transition-colors shadow-sm"
                >
                  Create Bucket
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
