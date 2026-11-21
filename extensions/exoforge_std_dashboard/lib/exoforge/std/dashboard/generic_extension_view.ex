defmodule Exoforge.Std.Dashboard.GenericExtensionView do
  @moduledoc """
  Universal auto-generated Visual Control GUI component for Exoforge extensions.
  Transforms any extension's contract metadata (actions, parameters, resources, events)
  into rich, interactive visual controls without requiring custom UI code.
  """
  use Phoenix.LiveComponent
  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Dashboard.ActionForms
  alias Exoforge.Std.Dashboard.ResourceForms
  alias Exoforge.Std.Dashboard.ResourceRefs
  alias Exoforge.EventDispatcher
  alias Exoforge.ExtensionRegistry
  alias Exoforge.DrawerRegistry
  import Exoforge.Std.Dashboard.Components
  import Exoforge.Std.Dashboard.InputTypes, only: [widget: 1]

  # 25 rows a page. Searching and paging both belong to the store, so they compose: the page is a
  # page of the matches, not a page that happened to match.
  @resource_per_page 25

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       subtab: nil,
       action_forms: %{},
       action_results: %{},
       confirming: nil,
       selected_resource_name: nil,
       resource_rows: [],
       filtered_resource_rows: [],
       resource_total: 0,
       resource_page: 1,
       resource_pages: 1,
       resource_search: "",
       drawer_open: false,
       inspected_row: nil,
       inspected_drawer_tab: "overview",
       drawer_tabs: [],
       resource_form: nil,
       fk_links: %{},
       fk_options: %{},
       drawer_fk: %{},
       referenced_by: [],
       export_modal_open: false,
       export_format: "CSV",
       export_content: "",
       export_filename: "export.csv",
       file_picker_open: false,
       file_picker_field: nil,
       file_picker_target: nil,
       file_picker_bucket: "default",
       file_picker_buckets: [],
       file_picker_files: [],
       file_picker_filtered_files: [],
       file_picker_search: ""
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    ext = socket.assigns.extension

    # Pick initial subtab based on what's available
    subtab =
      cond do
        socket.assigns.subtab in ["actions", "resources", "events", "contract"] ->
          socket.assigns.subtab

        (ext[:resources] || []) != [] ->
          "resources"

        (ext[:actions] || []) != [] ->
          "actions"

        (ext[:events] || []) != [] ->
          "events"

        true ->
          "contract"
      end

    # Initialize resource if available
    resources = ext[:resources] || []
    first_res = List.first(resources)

    selected_res_name =
      socket.assigns.selected_resource_name ||
        if first_res, do: to_string(first_res[:name] || first_res["name"]), else: nil

    socket =
      socket
      |> assign(:subtab, subtab)
      |> assign(:selected_resource_name, selected_res_name)
      |> load_resource_data()
      |> sync_focus()

    {:ok, socket}
  end

  # The row drawer is a URL (`?focus=row:<id>`), not component state, so the browser back button
  # closes it and a deep link opens it.
  defp sync_focus(socket) do
    case socket.assigns[:focus] do
      %{kind: "row", id: id} -> open_row(socket, id)
      _ -> assign(socket, drawer_open: false, inspected_row: nil)
    end
  end

  defp open_row(socket, id) do
    current = socket.assigns[:inspected_row]

    current_id =
      current && (current[:id] || current["id"] || current[:player_id] || current["player_id"])

    if current && to_string(current_id) == to_string(id) do
      socket
    else
      row =
        Enum.find(socket.assigns.resource_rows, fn r ->
          to_string(r[:id] || r["id"] || r[:player_id] || r["player_id"]) == to_string(id)
        end)

      res_name = socket.assigns.selected_resource_name
      tabs = if res_name, do: DrawerRegistry.list_tabs(res_name), else: []

      assign(socket,
        drawer_open: true,
        inspected_row: row,
        drawer_tabs: tabs,
        inspected_drawer_tab: "overview",
        drawer_fk: if(row, do: ResourceRefs.links(current_resource_columns(socket), [row], ref_opts(socket)), else: %{}),
        referenced_by: if(row && res_name, do: ResourceRefs.referenced_by(res_name, row, ref_opts(socket)), else: [])
      )
    end
  end

  # ---- EVENT HANDLERS ----

  @impl true
  def handle_event("close_focus", _params, socket) do
    tab = (socket.assigns[:extension] && socket.assigns.extension.id) || "overview"
    path = if tab in ["overview", :overview], do: "/", else: "/tab/#{tab}"

    {:noreply,
     socket
     |> assign(drawer_open: false, inspected_row: nil)
     |> push_patch(to: path)}
  end

  @impl true
  def handle_event("switch_subtab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :subtab, tab)}
  end

  @impl true
  def handle_event("select_resource", %{"name" => name}, socket) do
    socket =
      socket
      |> assign(:selected_resource_name, name)
      |> load_resource_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "change_param",
        %{"action" => act_name, "param" => param_name, "value" => val},
        socket
      ) do
    current_forms = socket.assigns.action_forms
    act_form = Map.get(current_forms, act_name, %{})
    updated_act_form = Map.put(act_form, param_name, val)
    updated_forms = Map.put(current_forms, act_name, updated_act_form)

    {:noreply, assign(socket, :action_forms, updated_forms)}
  end

  @impl true
  def handle_event("change_action_card_form", %{"action_name" => act_name} = params, socket) do
    current_forms = socket.assigns.action_forms
    act_form = Map.get(current_forms, act_name, %{})

    updated_act_form =
      Enum.reduce(params, act_form, fn
        {"param_" <> p_name, val}, acc -> Map.put(acc, p_name, val)
        _, acc -> acc
      end)

    updated_forms = Map.put(current_forms, act_name, updated_act_form)
    {:noreply, assign(socket, :action_forms, updated_forms)}
  end

  @impl true
  def handle_event("cancel_confirm", _params, socket), do: {:noreply, assign(socket, :confirming, nil)}

  # A destructive action asks first: the first press arms it, the second runs it. Anything else the person does to
  # the form (or another card) disarms it, so a stale confirmation is never left waiting.
  def handle_event("run_action", %{"action" => act_name, "service" => svc_name}, socket) do
    if ActionForms.action_kind(act_name) == :destructive and socket.assigns.confirming != act_name do
      {:noreply, assign(socket, :confirming, act_name)}
    else
      run_action(assign(socket, :confirming, nil), act_name, svc_name)
    end
  end

  @impl true
  def handle_event("search_resource", params, socket) do
    query = Map.get(params, "query") || Map.get(params, "value") || ""

    socket =
      socket
      |> assign(:resource_search, query)
      |> assign(:resource_page, 1)
      |> load_resource_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("resource_page", %{"page" => page}, socket) do
    target =
      if page == "next",
        do: socket.assigns.resource_page + 1,
        else: socket.assigns.resource_page - 1

    {:noreply, load_resource_data(assign(socket, :resource_page, max(target, 1)))}
  end

  @impl true
  def handle_event("select_drawer_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, inspected_drawer_tab: tab)}
  end

  # A new row and an edited one are the same form: the schema decides the fields, and the primary key
  # is the only thing that differs — it is what identifies the row, so it is fixed once it exists.
  @impl true
  def handle_event("new_resource", _params, socket) do
    columns = current_resource_columns(socket)

    {:noreply,
     assign(socket,
       resource_form: %{mode: :new, values: ResourceForms.defaults(columns), errors: %{}},
       fk_options: ResourceRefs.options(columns, ref_opts(socket))
     )}
  end

  @impl true
  def handle_event("edit_resource", _params, socket) do
    columns = current_resource_columns(socket)
    values = ResourceForms.values_for(socket.assigns.inspected_row, columns)

    {:noreply,
     assign(socket,
       resource_form: %{mode: :edit, values: values, errors: %{}},
       fk_options: ResourceRefs.options(columns, ref_opts(socket))
     )}
  end

  @impl true
  def handle_event("resource_form_change", %{"values" => values}, socket) do
    {:noreply, assign(socket, resource_form: %{socket.assigns.resource_form | values: values})}
  end

  @impl true
  def handle_event("close_resource_form", _params, socket) do
    {:noreply, assign(socket, resource_form: nil)}
  end

  # ---- FILE REFERENCE PICKER HANDLERS ----

  @impl true
  def handle_event("open_file_picker", params, socket) do
    field = params["field"]
    target = params["target"] || "singleton"
    raw_bucket = params["bucket"]

    buckets =
      case ActionDispatcher.dispatch_internal(:file_bucket, :list_buckets, %{}) do
        {:ok, %{buckets: entries}} when is_list(entries) -> Enum.map(entries, &bucket_name/1)
        _ -> ["default"]
      end

    bucket =
      if raw_bucket in ["", nil] do
        List.first(buckets) || "default"
      else
        raw_bucket
      end

    files =
      case ActionDispatcher.dispatch_internal(:file_bucket, :list_files, %{
             "bucket" => bucket,
             "limit" => 200
           }) do
        {:ok, %{files: f}} when is_list(f) -> f
        _ -> []
      end

    {:noreply,
     assign(socket,
       file_picker_open: true,
       file_picker_field: field,
       file_picker_target: target,
       file_picker_bucket: bucket,
       file_picker_buckets: buckets,
       file_picker_files: files,
       file_picker_filtered_files: files,
       file_picker_search: ""
     )}
  end

  @impl true
  def handle_event("file_picker_change_bucket", %{"bucket" => bucket}, socket) do
    files =
      case ActionDispatcher.dispatch_internal(:file_bucket, :list_files, %{
             "bucket" => bucket,
             "limit" => 200
           }) do
        {:ok, %{files: f}} when is_list(f) -> f
        _ -> []
      end

    q = String.downcase(String.trim(socket.assigns.file_picker_search || ""))

    filtered =
      if q == "" do
        files
      else
        Enum.filter(files, fn f ->
          String.contains?(String.downcase(to_string(f["filename"] || "")), q) or
            String.contains?(String.downcase(to_string(f["id"] || "")), q)
        end)
      end

    {:noreply,
     assign(socket,
       file_picker_bucket: bucket,
       file_picker_files: files,
       file_picker_filtered_files: filtered
     )}
  end

  @impl true
  def handle_event("file_picker_search", params, socket) do
    query = Map.get(params, "query") || Map.get(params, "value") || ""
    q = String.downcase(String.trim(query))
    files = socket.assigns.file_picker_files

    filtered =
      if q == "" do
        files
      else
        Enum.filter(files, fn f ->
          String.contains?(String.downcase(to_string(f["filename"] || "")), q) or
            String.contains?(String.downcase(to_string(f["id"] || "")), q)
        end)
      end

    {:noreply, assign(socket, file_picker_search: query, file_picker_filtered_files: filtered)}
  end

  @impl true
  def handle_event("file_picker_select", %{"id" => id}, socket) do
    field = to_string(socket.assigns.file_picker_field)
    target = socket.assigns.file_picker_target

    socket =
      case target do
        "singleton" ->
          form = socket.assigns[:singleton_form] || %{values: %{}, errors: %{}, saved: false}
          new_values = Map.put(form.values, field, id)
          assign(socket, singleton_form: %{form | values: new_values, saved: false})

        _ ->
          if form = socket.assigns.resource_form do
            new_values = Map.put(form.values, field, id)
            assign(socket, resource_form: %{form | values: new_values})
          else
            socket
          end
      end

    {:noreply, assign(socket, file_picker_open: false, file_picker_field: nil)}
  end

  @impl true
  def handle_event("clear_file_ref", params, socket) do
    field = to_string(params["field"])
    target = params["target"] || "singleton"

    socket =
      case target do
        "singleton" ->
          form = socket.assigns[:singleton_form] || %{values: %{}, errors: %{}, saved: false}
          new_values = Map.put(form.values, field, "")
          assign(socket, singleton_form: %{form | values: new_values, saved: false})

        _ ->
          if form = socket.assigns.resource_form do
            new_values = Map.put(form.values, field, "")
            assign(socket, resource_form: %{form | values: new_values})
          else
            socket
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_file_picker", _params, socket) do
    {:noreply, assign(socket, file_picker_open: false, file_picker_field: nil)}
  end

  @impl true
  def handle_event(
        "file_picker_uploaded",
        %{"filename" => filename, "base64" => base64, "content_type" => content_type},
        socket
      ) do
    bucket = socket.assigns.file_picker_bucket || "default"

    payload = %{
      "bucket" => bucket,
      "filename" => filename,
      "content" => base64,
      "content_type" => content_type
    }

    case ActionDispatcher.dispatch_internal(:file_bucket, :upload_file, payload) do
      {:ok, %{file: file}} ->
        field = to_string(socket.assigns.file_picker_field)
        target = socket.assigns.file_picker_target
        id = file["id"]

        socket =
          case target do
            "singleton" ->
              form = socket.assigns[:singleton_form] || %{values: %{}, errors: %{}, saved: false}
              new_values = Map.put(form.values, field, id)
              assign(socket, singleton_form: %{form | values: new_values, saved: false})

            _ ->
              if form = socket.assigns.resource_form do
                new_values = Map.put(form.values, field, id)
                assign(socket, resource_form: %{form | values: new_values})
              else
                socket
              end
          end

        {:noreply, assign(socket, file_picker_open: false, file_picker_field: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("singleton_form_change", %{"values" => values}, socket) do
    form = socket.assigns[:singleton_form] || %{values: %{}, errors: %{}, saved: false}
    {:noreply, assign(socket, singleton_form: %{form | values: values, saved: false})}
  end

  @impl true
  def handle_event("submit_singleton_form", %{"values" => values}, socket) do
    columns = current_resource_columns(socket)
    form = socket.assigns[:singleton_form] || %{values: %{}, errors: %{}, saved: false}
    name = socket.assigns.selected_resource_name

    case ResourceForms.errors(values, columns) do
      errors when errors != %{} ->
        {:noreply, assign(socket, singleton_form: %{form | values: values, errors: errors, saved: false})}

      _ ->
        attributes = ResourceForms.attributes(values, columns)

        case ActionDispatcher.dispatch_internal(:resource_store, :upsert, %{
               resource: name,
               attributes: attributes
             }) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:singleton_saved, true)
             |> load_resource_data()}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               singleton_form: %{
                 form
                 | values: values,
                   errors: %{"_form" => inspect(reason)},
                   saved: false
               }
             )}
        end
    end
  end

  @impl true
  def handle_event("submit_resource_form", %{"values" => values}, socket) do
    columns = current_resource_columns(socket)
    form = socket.assigns.resource_form
    name = socket.assigns.selected_resource_name

    case ResourceForms.errors(values, columns) do
      errors when errors != %{} ->
        {:noreply, assign(socket, resource_form: %{form | values: values, errors: errors})}

      _ ->
        attributes = ResourceForms.attributes(values, columns)
        key = Enum.find(columns, & &1.primary_key)

        result =
          case form.mode do
            :new ->
              ActionDispatcher.dispatch_internal(:resource_store, :create, %{
                resource: name,
                attributes: attributes
              })

            :edit ->
              ActionDispatcher.dispatch_internal(:resource_store, :update, %{
                resource: name,
                id: Map.get(values, to_string(key.key)),
                attributes: attributes
              })
          end

        case result do
          {:ok, _} ->
            {:noreply, socket |> assign(resource_form: nil) |> load_resource_data()}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               resource_form: %{form | values: values, errors: %{"_form" => inspect(reason)}}
             )}
        end
    end
  end

  @impl true
  def handle_event("delete_resource", _params, socket) do
    _ =
      ActionDispatcher.dispatch_internal(:resource_store, :clear, %{
        resource: socket.assigns.selected_resource_name
      })

    {:noreply, load_resource_data(socket)}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    res_name = socket.assigns.selected_resource_name || "data"
    # Exports cover the resource, not just the page on screen.
    rows = ExtensionRegistry.fetch_resource_rows(res_name)
    cols = current_resource_columns(socket)

    header = Enum.map_join(cols, ",", &"\"#{&1[:label] || &1[:key]}\"")

    body_lines =
      Enum.map(rows, fn row ->
        Enum.map_join(cols, ",", fn col ->
          key = col[:key] || col["key"]
          val = Map.get(row, key) || Map.get(row, to_string(key)) || ""
          escaped = String.replace(to_string(val), "\"", "\"\"")
          "\"#{escaped}\""
        end)
      end)

    csv_data = Enum.join([header | body_lines], "\n")

    {:noreply,
     assign(socket,
       export_modal_open: true,
       export_format: "CSV",
       export_content: csv_data,
       export_filename: "#{res_name}_export.csv"
     )}
  end

  @impl true
  def handle_event("export_json", _params, socket) do
    res_name = socket.assigns.selected_resource_name || "data"
    json_data = Jason.encode!(ExtensionRegistry.fetch_resource_rows(res_name), pretty: true)

    {:noreply,
     assign(socket,
       export_modal_open: true,
       export_format: "JSON",
       export_content: json_data,
       export_filename: "#{res_name}_export.json"
     )}
  end

  @impl true
  def handle_event("close_export_modal", _params, socket) do
    {:noreply, assign(socket, export_modal_open: false)}
  end

  @impl true
  def handle_event("simulate_event", %{"event" => event_name}, socket) do
    ext_id = socket.assigns.extension.id
    topic = "ext:#{ext_id}"

    payload = %{
      simulated: true,
      event: event_name,
      extension: ext_id,
      timestamp: System.system_time(:millisecond)
    }

    EventDispatcher.broadcast(topic, payload)
    {:noreply, socket}
  end

  ## ---- PRIVATE HELPERS ----

  # `list_buckets` reports each bucket with its visibility; the picker only needs the name.
  defp run_action(socket, act_name, svc_name) do
    ext = socket.assigns.extension
    action_def = Enum.find(ext[:actions] || [], &(&1[:name] == act_name))

    act_form = Map.get(socket.assigns.action_forms, act_name, %{})

    # The session's verified scopes (M33 Fix 27): the caller's RBAC comes from the login, not
    # from a form field that could claim `admin` or `server`.
    scopes = socket.assigns[:current_scopes] || []

    # Cast parameters
    payload =
      if action_def do
        Enum.reduce(action_def[:params] || [], %{}, fn p, acc ->
          val_str =
            Map.get(act_form, p[:name] || p["name"], default_value_for(p[:type] || p["type"], p[:optional] || p["optional"] || false))

          casted = cast_value(val_str, p[:type] || p["type"])
          Map.put(acc, Exoforge.Atoms.existing(p[:name] || p["name"]), casted)
        end)
      else
        %{}
      end

    start_time = System.monotonic_time(:microsecond)

    result =
      try do
        ActionDispatcher.dispatch(svc_name, act_name, payload, caller_scopes: scopes)
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, inspect(reason)}
      end

    duration_us = System.monotonic_time(:microsecond) - start_time
    latency_ms = Float.round(duration_us / 1000, 2)

    result_info = %{
      result: result,
      latency_ms: latency_ms,
      time: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    }

    updated_results = Map.put(socket.assigns.action_results, act_name, result_info)

    # Reload resource if action potentially changed resource data
    socket =
      socket
      |> assign(:action_results, updated_results)
      |> load_resource_data()

    {:noreply, socket}
  end

  defp bucket_name(%{"bucket" => name}), do: name
  defp bucket_name(%{bucket: name}), do: name
  defp bucket_name(name), do: to_string(name)

  defp load_resource_data(socket) do
    case socket.assigns.selected_resource_name do
      nil ->
        assign(socket, resource_rows: [], filtered_resource_rows: [], singleton_form: nil)

      name ->
        page = Map.get(socket.assigns, :resource_page, 1)
        %{rows: rows, total: total} = resource_page(name, page, socket.assigns.resource_search)
        columns = current_resource_columns(socket)

        socket =
          if singleton_resource?(socket) do
            row = List.first(rows)

            values =
              if row && map_size(row) > 0 do
                defaults = ResourceForms.defaults(columns)
                row_vals = ResourceForms.values_for(row, columns)

                Enum.reduce(defaults, row_vals, fn {k, def_v}, acc ->
                  case Map.get(acc, k) do
                    nil -> Map.put(acc, k, def_v)
                    "" -> if def_v != "", do: Map.put(acc, k, def_v), else: acc
                    _ -> acc
                  end
                end)
              else
                ResourceForms.defaults(columns)
              end

            saved_indicator = socket.assigns[:singleton_saved] || false
            assign(socket,
              singleton_form: %{values: values, errors: %{}, saved: saved_indicator},
              fk_options: ResourceRefs.options(columns, ref_opts(socket))
            )
          else
            assign(socket, singleton_form: nil)
          end

        pages = max(ceil(total / @resource_per_page), 1)

        socket
        |> assign(:resource_rows, rows)
        |> assign(:resource_total, total)
        |> assign(:resource_page, min(page, pages))
        |> assign(:resource_pages, pages)
        |> assign(:fk_links, ResourceRefs.links(columns, rows, ref_opts(socket)))
        |> apply_resource_search()
    end
  end

  # Reads of referenced resources run as the viewer, so a resource they may not read is not shown.
  defp ref_opts(socket), do: %{scopes: socket.assigns[:current_scopes] || []}

  defp resource_page(name, page, search) do
    ExtensionRegistry.page_resource_rows(name,
      limit: @resource_per_page,
      offset: (max(page, 1) - 1) * @resource_per_page,
      search: search
    )
  rescue
    _ -> %{rows: [], total: 0}
  end

  defp apply_resource_search(socket) do
    q = String.downcase(String.trim(socket.assigns.resource_search))
    rows = socket.assigns.resource_rows

    filtered =
      if q == "" do
        rows
      else
        Enum.filter(rows, fn row ->
          Enum.any?(Map.values(row), fn val ->
            String.contains?(String.downcase(to_string(val)), q)
          end)
        end)
      end

    assign(socket, :filtered_resource_rows, filtered)
  end

  defp current_resource_columns(%Phoenix.LiveView.Socket{assigns: assigns}) do
    current_resource_columns(assigns)
  end

  defp current_resource_columns(assigns) when is_map(assigns) do
    case ResourceForms.columns(current_resource(assigns)) do
      [] -> [%{key: :id, label: "ID"}, %{key: :data, label: "Data"}]
      columns -> columns
    end
  end

  # The resource the Data tab is showing, as the manifest declares it.
  defp current_resource(assigns) when is_map(assigns) do
    res_name = assigns[:selected_resource_name]
    ext = assigns[:extension] || %{}

    (ext[:resources] || [])
    |> Enum.find(fn r -> to_string(r[:name] || r["name"]) == to_string(res_name) end)
  end

  defp singleton_resource?(%Phoenix.LiveView.Socket{assigns: assigns}) do
    singleton_resource?(assigns)
  end

  defp singleton_resource?(assigns) when is_map(assigns) do
    res = current_resource(assigns)

    res != nil and
      (res[:singleton] == true or res["singleton"] == true or
         to_string(res[:kind] || res["kind"]) == "singleton")
  end

  # A column role (e.g. "user_id") turns a plain string into a deep link. The target is
  # contributed by whichever plugin owns the role, through a `:resource_column` UI hook, so the
  # dashboard never hardcodes a plugin's tab.
  defp column_link(nil), do: nil

  defp column_link(role) do
    role = to_string(role)

    Exoforge.UIHookRegistry.list_hooks(:resource_column)
    |> Enum.find(fn hook ->
      to_string(hook[:role] || hook[:id]) == role and is_binary(hook[:target]) and
        is_binary(hook[:focus])
    end)
  end

  defp focus_path(link, value) do
    "/tab/#{link[:target]}?focus=#{link[:focus]}:#{URI.encode_www_form(to_string(value))}"
  end

  defp default_value_for(type, optional) do
    case {type, optional} do
      {:integer, true} -> ""
      {:integer, _} -> "1"
      {:float, true} -> ""
      {:float, _} -> "1.0"
      {:boolean, _} -> "true"
      {:map, _} -> "{}"
      {:list, _} -> "[]"
      _ -> ""
    end
  end

  defp cast_value(val_str, type) when is_binary(val_str) do
    case type do
      :integer ->
        case Integer.parse(String.trim(val_str)) do
          {int, _} -> int
          _ -> 0
        end

      :float ->
        case Float.parse(String.trim(val_str)) do
          {flt, _} -> flt
          _ -> 0.0
        end

      :boolean ->
        String.trim(String.downcase(val_str)) in ["true", "1", "yes"]

      :map ->
        case Jason.decode(val_str) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      :list ->
        case Jason.decode(val_str) do
          {:ok, list} when is_list(list) ->
            list

          _ ->
            String.split(val_str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        end

      _ ->
        val_str
    end
  end

  defp cast_value(val, _), do: val

  defp column_input(assigns) do
    key = to_string(assigns.column.key)
    custom_spec = Exoforge.Std.Dashboard.InputTypes.resolve(assigns.column)
    is_file_ref = to_string(assigns.column[:role] || assigns.column["role"]) == "file_reference"
    bucket = assigns.column[:bucket] || assigns.column["bucket"] || "default"

    assigns =
      assigns
      |> assign(:key, key)
      |> assign(:custom_spec, custom_spec)
      |> assign(:is_file_ref, is_file_ref)
      |> assign(:bucket, bucket)
      |> assign(:fk_choices, fk_choices(assigns))

    ~H"""
    <div>
      <label class="exo-label">
        <%= @column.label %><%= if @column.primary_key, do: " · key" %>
      </label>

      <%= if @is_file_ref do %>
        <input type="hidden" name={"values[#{@key}]"} value={@value} />
        <div class="p-3 bg-gray-50 border border-gray-200 rounded-lg space-y-2">
          <%= if @value != "" and @value != nil do %>
            <div class="flex items-center justify-between gap-3 bg-white p-2 rounded-lg border border-gray-200/80">
              <div class="flex items-center gap-2.5 min-w-0">
                <img
                  src={"/api/files/#{@bucket}/#{@value}"}
                  class="w-9 h-9 object-contain rounded-lg border border-gray-200/80 bg-gray-50 shrink-0"
                  alt="Preview"
                  onerror="this.style.display='none'"
                />
                <div class="truncate">
                  <span class="font-mono text-xs font-medium text-primary-700 bg-primary-50 px-2 py-0.5 rounded border border-primary-200"><%= @value %></span>
                  <div class="text-[10px] text-gray-400 mt-0.5">Bucket: <%= @bucket %></div>
                </div>
              </div>
              <div class="flex items-center gap-1 shrink-0">
                <a
                  href={"/api/files/#{@bucket}/#{@value}"}
                  target="_blank"
                  class="exo-btn exo-btn-sm exo-btn-ghost"
                >
                  Open
                </a>
                <button
                  type="button"
                  phx-click="open_file_picker"
                  phx-value-field={@key}
                  phx-value-target={@target}
                  phx-value-bucket={@bucket}
                  phx-target={@myself}
                  class="exo-btn exo-btn-sm exo-btn-secondary"
                >
                  Change
                </button>
                <button
                  type="button"
                  phx-click="clear_file_ref"
                  phx-value-field={@key}
                  phx-value-target={@target}
                  phx-target={@myself}
                  class="exo-btn exo-btn-sm exo-btn-danger"
                  title="Clear"
                >
                  <.icon name="close" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          <% else %>
            <div class="flex items-center justify-between gap-3">
              <span class="text-xs text-gray-400 italic">No file selected</span>
              <button
                type="button"
                phx-click="open_file_picker"
                phx-value-field={@key}
                phx-value-target={@target}
                phx-value-bucket={@bucket}
                phx-target={@myself}
                class="exo-btn exo-btn-sm exo-btn-secondary"
              >
                <.icon name="folder" class="w-3.5 h-3.5" />
                <span>Select from Bucket</span>
              </button>
            </div>
          <% end %>
        </div>
      <% else %>
        <%= if is_map(@custom_spec) do %>
          <.widget spec={@custom_spec} name={"values[#{@key}]"} value={@value} readonly={@locked} />
        <% else %>
          <%= if is_list(@fk_choices) and not @locked do %>
            <select
              name={"values[#{@key}]"}
              class="exo-select font-mono"
              data-fk-picker
            >
              <option value="" selected={to_string(@value) == ""}>-</option>
              <%= for {val, text} <- @fk_choices do %>
                <option value={val} selected={to_string(@value) == val}><%= text %></option>
              <% end %>
            </select>
          <% else %>
          <%= if @column.choices != [] do %>
            <select
              name={"values[#{@key}]"}
              class="exo-select font-mono"
            >
              <%= for choice <- @column.choices do %>
                <option value={choice} selected={to_string(@value) == to_string(choice)}>
                  <%= choice %>
                </option>
              <% end %>
            </select>
          <% else %>
            <%= case @column.type do %>
              <% :boolean -> %>
                <input type="hidden" name={"values[#{@key}]"} value="false" />
                <input
                  type="checkbox"
                  name={"values[#{@key}]"}
                  value="true"
                  checked={@value in ["true", true]}
                  class="w-4 h-4 text-primary-600 rounded border-gray-300 focus:ring-primary-500"
                />
              <% :integer -> %>
                <input
                  type="number"
                  step="1"
                  name={"values[#{@key}]"}
                  value={@value}
                  readonly={@locked}
                  class={"exo-input font-mono #{if @locked, do: "opacity-70"}"}
                />
              <% :float -> %>
                <input
                  type="number"
                  step="any"
                  name={"values[#{@key}]"}
                  value={@value}
                  readonly={@locked}
                  class={"exo-input font-mono #{if @locked, do: "opacity-70"}"}
                />
              <% _ -> %>
                <input
                  type="text"
                  name={"values[#{@key}]"}
                  value={@value}
                  readonly={@locked}
                  class={"exo-input font-mono #{if @locked, do: "opacity-70"}"}
                />
            <% end %>
          <% end %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # The picker a foreign-key column gets, or nil for a plain input (no `references`, a list too
  # long to pick from, or one that could not be read). A stored value that no longer has a row is
  # kept as an option so that opening the form does not silently rewrite it.
  defp fk_choices(assigns) do
    case Map.get(assigns[:fk_options] || %{}, to_string(assigns.column.key)) do
      list when is_list(list) ->
        value = to_string(assigns[:value] || "")

        if value == "" or Enum.any?(list, fn {v, _} -> v == value end),
          do: list,
          else: list ++ [{value, "#{value} (no such row)"}]

      _ ->
        nil
    end
  end

  ## ---- TEMPLATE RENDERING ----

  @impl true
  def render(assigns) do
    ext = assigns.extension
    icon = (is_map(ext[:dashboard_view]) && ext[:dashboard_view][:icon]) || "🧩"
    actions = ext[:actions] || []
    resources = ext[:resources] || []
    events = ext[:events] || []
    columns = current_resource_columns(assigns)

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:actions, actions)
      |> assign(:action_groups, ActionForms.group_actions(actions))
      |> assign(:resources, resources)
      |> assign(:events, events)
      |> assign(:columns, columns)

    ~H"""
    <div class="space-y-5" id={@id}>
      <!-- Extension Header (Flat on Canvas) -->
      <div class="exo-page-header">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2.5">
            <span class="text-base shrink-0"><%= @icon %></span>
            <h1 class="exo-page-title truncate"><%= Exoforge.Std.Dashboard.ExtensionPresenter.display_name(@extension) %></h1>
            <span class="exo-badge bg-primary-50 text-primary-700 border-primary-200 font-mono">
              v<%= to_string(@extension.version) %>
            </span>
            <span class="exo-badge bg-emerald-50 text-emerald-700 border-emerald-200">
              <%= @extension.type %>
            </span>
          </div>
          <p class="exo-page-subtitle">
            Provides: <code class="font-mono text-primary-700 font-medium"><%= Enum.join(@extension.provides, ", ") %></code>
            <%= if @extension.dependencies != [] do %>
              <span class="mx-1.5 text-gray-300">•</span>
              Depends on: <code class="font-mono text-gray-600"><%= Enum.join(@extension.dependencies, ", ") %></code>
            <% end %>
          </p>
        </div>
      </div>

      <!-- Underline Subtab Switcher -->
      <div class="exo-tabs" role="tablist">
        <%= if @resources != [] do %>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@subtab == "resources")}
            phx-click="switch_subtab"
            phx-value-tab="resources"
            phx-target={@myself}
            class={"exo-tab #{if @subtab == "resources", do: "exo-tab-active"}"}
          >
            <.icon name="box" class="w-3.5 h-3.5" />
            <span>Data</span>
            <span class="exo-tab-count"><%= length(@resources) %></span>
          </button>
        <% end %>

        <%= if @actions != [] do %>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@subtab == "actions")}
            phx-click="switch_subtab"
            phx-value-tab="actions"
            phx-target={@myself}
            class={"exo-tab #{if @subtab == "actions", do: "exo-tab-active"}"}
          >
            <.icon name="bolt" class="w-3.5 h-3.5" />
            <span>Actions</span>
            <span class="exo-tab-count"><%= length(@actions) %></span>
          </button>
        <% end %>

        <%= if @events != [] do %>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@subtab == "events")}
            phx-click="switch_subtab"
            phx-value-tab="events"
            phx-target={@myself}
            class={"exo-tab #{if @subtab == "events", do: "exo-tab-active"}"}
          >
            <.icon name="radio" class="w-3.5 h-3.5" />
            <span>Telemetry</span>
            <span class="exo-tab-count"><%= length(@events) %></span>
          </button>
        <% end %>

        <button
          type="button"
          role="tab"
          aria-selected={to_string(@subtab == "contract")}
          phx-click="switch_subtab"
          phx-value-tab="contract"
          phx-target={@myself}
          class={"exo-tab #{if @subtab == "contract", do: "exo-tab-active"}"}
        >
          <.icon name="shield" class="w-3.5 h-3.5" />
          <span>Contract</span>
        </button>
      </div>

      <!-- SUBTAB 1: ACTIONS & VISUAL CONTROLS -->
      <%= if @subtab == "actions" do %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-semibold text-gray-900">Actions</h3>
              <p class="text-xs text-gray-500 mt-0.5">Run an action by hand with the fields it takes, and see its answer.</p>
            </div>
          </div>

          <%= for {kind, title, group_actions} <- @action_groups do %>
          <div class="space-y-3" id={"actions-" <> to_string(kind)}>
            <h4 :if={length(@action_groups) > 1} class={["text-[11px] font-semibold uppercase tracking-wider", if(kind == :destructive, do: "text-red-700", else: "text-gray-500")]}><%= title %></h4>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <%= for act <- group_actions do %>
              <% act_form = Map.get(@action_forms, act[:name], %{}) %>
              <% result_info = Map.get(@action_results, act[:name]) %>
              <% armed = @confirming == to_string(act[:name]) %>

              <div class={["exo-card p-5 space-y-3.5 transition-colors", if(kind == :destructive, do: "border-red-200 hover:border-red-300", else: "hover:border-primary-300")]}>
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <h4 class="font-semibold text-gray-900 text-sm tracking-tight"><%= Phoenix.Naming.humanize(to_string(act[:name])) %></h4>
                    <span class="text-[11px] font-mono text-gray-400"><%= act[:name] %></span>
                  </div>
                  <%!-- Every action is sync unless it says otherwise, so only the exceptions get a label. --%>
                  <span :if={to_string(act[:mode]) != "sync"} class="inline-flex items-center px-2 py-0.5 rounded-lg text-[10px] font-medium uppercase tracking-wider bg-gray-100 text-gray-700 shrink-0">
                    <%= act[:mode] %>
                  </span>
                </div>

                <p class="text-xs text-gray-500 leading-relaxed">
                  <%= act[:doc] %>
                </p>

                <form phx-change="change_action_card_form" phx-submit="run_action" phx-target={@myself} class="space-y-3">
                  <input type="hidden" name="action_name" value={act[:name]} />
                  <input type="hidden" name="service" value={act[:service]} />
                  <input type="hidden" name="action" value={act[:name]} />

                  <!-- Parameter Inputs -->
                  <%= if (act[:params] || []) != [] do %>
                    <div class="space-y-2.5 pt-1">
                      <%= for p <- act[:params] do %>
                        <% p_name = p[:name] || p["name"] %>
                        <% p_type = p[:type] || p["type"] %>
                        <% val = Map.get(act_form, p_name, default_value_for(p_type, p[:optional] || p["optional"] || false)) %>

                        <div>
                          <div class="flex items-center justify-between mb-1">
                            <label class="text-xs font-medium text-gray-700 font-mono"><%= p_name %></label>
                            <span class="text-[10px] text-primary-600 font-mono"><%= p_type %></span>
                          </div>

                          <% custom_spec = Exoforge.Std.Dashboard.InputTypes.resolve(p) %>

                          <%= if is_map(custom_spec) do %>
                            <.widget spec={custom_spec} name={"param_#{p_name}"} value={val} />
                          <% else %>
                            <%= case p_type do %>
                            <% :boolean -> %>
                              <select
                                name={"param_#{p_name}"}
                                class="exo-select font-mono"
                              >
                                <option value="true" selected={val in ["true", true]}>true</option>
                                <option value="false" selected={val in ["false", false]}>false</option>
                              </select>

                            <% :map -> %>
                              <textarea
                                name={"param_#{p_name}"}
                                rows="2"
                                class="exo-textarea font-mono"
                              ><%= val %></textarea>

                            <% _ -> %>
                              <input
                                type={if p_type in [:integer, :float], do: "number", else: "text"}
                                step={if p_type == :float, do: "0.1", else: "1"}
                                name={"param_#{p_name}"}
                                value={val}
                                class="exo-input font-mono"
                              />
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- Technical Context & Scope Gating (tucked inside fold) -->
                  <details class="exo-fold">
                    <summary>
                      <span>Access</span>
                      <span class="exo-chevron">▸</span>
                    </summary>
                    <div class="exo-fold-body space-y-2">
                      <div class="text-[11px] text-gray-400">
                        Service: <code class="text-primary-700 font-medium"><%= act[:service] %></code>
                      </div>
                      <div>
                        <label class="exo-label">Caller Scopes</label>
                        <div class="exo-input font-mono text-gray-500">
                          <%= Enum.join(@current_scopes || [], ", ") %>
                        </div>
                      </div>
                    </div>
                  </details>

                  <!-- Run Button -->
                  <div class="pt-1 flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <button
                        type="submit"
                        class={["exo-btn", if(kind == :destructive, do: "exo-btn-danger", else: "exo-btn-primary")]}
                      >
                        <.icon name={:bolt} class="w-3.5 h-3.5" />
                        <span><%= cond do %><% armed -> %>Yes, run it<% kind == :destructive -> %>Run…<% true -> %>Run Action<% end %></span>
                      </button>
                      <button :if={armed} type="button" phx-click="cancel_confirm" phx-target={@myself} class="exo-btn exo-btn-secondary">Cancel</button>
                    </div>

                    <%= if result_info do %>
                      <span class="inline-flex items-center gap-1 text-[11px] font-mono text-emerald-700 bg-emerald-50 px-2 py-1 rounded-lg border border-emerald-200 font-medium tabular-nums">
                        <%= result_info.latency_ms %> ms
                      </span>
                    <% end %>
                  </div>
                </form>

                <!-- Action Result Box -->
                <%= if result_info do %>
                  <div class="mt-3 pt-3 border-t border-gray-200/80 space-y-1.5">
                    <div class="flex items-center justify-between text-[11px]">
                      <span class="font-medium text-gray-600 tabular-nums">Response (<%= result_info.time %>)</span>
                      <span class={"font-medium px-1.5 py-0.5 rounded text-[10px] #{case result_info.result do
                        {:ok, _} -> "bg-emerald-100 text-emerald-800"
                        _ -> "bg-red-100 text-red-800"
                      end}"}>
                        <%= case result_info.result do
                          {:ok, _} -> "SUCCESS (200)"
                          _ -> "ERROR"
                        end %>
                      </span>
                    </div>
                    <pre class="exo-terminal text-[11px] font-mono bg-gray-900 text-emerald-400 p-3 rounded-lg overflow-x-auto max-h-40"><%= case result_info.result do
                      {:ok, payload} -> Jason.encode!(payload, pretty: true)
                      {:error, reason} -> inspect(reason)
                      other -> inspect(other)
                    end %></pre>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
          </div>
          <% end %>
        </div>
      <% end %>

      <!-- SUBTAB 2: DATA & RESOURCES -->
      <%= if @subtab == "resources" do %>
        <div class="space-y-4">
          <!-- Resource Switcher & Toolbar -->
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-3">
            <div class="exo-tabs flex-1">
              <%= for res <- @resources do %>
                <% res_name = to_string(res[:name] || res["name"]) %>
                <% active? = to_string(@selected_resource_name) == res_name %>
                <button
                  type="button"
                  phx-click="select_resource"
                  phx-value-name={res_name}
                  phx-target={@myself}
                  class={"exo-tab #{if active?, do: "exo-tab-active"}"}
                >
                  <%= Phoenix.Naming.humanize(res_name) %>
                </button>
              <% end %>
            </div>

            <%= if not singleton_resource?(assigns) do %>
              <div class="flex items-center gap-2 shrink-0">
                <form id="resource-search-form" phx-change="search_resource" phx-submit="search_resource" phx-target={@myself}>
                  <input
                    type="search"
                    placeholder="Search rows..."
                    value={@resource_search}
                    phx-debounce="200"
                    name="query"
                    class="exo-input w-48"
                  />
                </form>

                <%= if @resource_pages > 1 do %>
                  <div class="flex items-center gap-1.5 text-[11px] text-gray-500 tabular-nums">
                    <span><%= @resource_page %>/<%= @resource_pages %> of <%= @resource_total %></span>
                    <button
                      type="button"
                      phx-click="resource_page"
                      phx-value-page="prev"
                      phx-target={@myself}
                      disabled={@resource_page <= 1}
                      class="exo-btn exo-btn-sm exo-btn-secondary"
                    >‹</button>
                    <button
                      type="button"
                      phx-click="resource_page"
                      phx-value-page="next"
                      phx-target={@myself}
                      disabled={@resource_page >= @resource_pages}
                      class="exo-btn exo-btn-sm exo-btn-secondary"
                    >›</button>
                  </div>
                <% end %>

                <button
                  type="button"
                  phx-click="new_resource"
                  phx-target={@myself}
                  class="exo-btn exo-btn-primary"
                >
                  <span>＋ New</span>
                </button>

                <details class="exo-menu relative">
                  <summary title="More actions">
                    ⋯
                  </summary>
                  <div class="exo-menu-panel">
                    <button
                      type="button"
                      phx-click="export_csv"
                      phx-target={@myself}
                      class="exo-menu-item"
                    >
                      <.icon name="download" class="w-3 h-3" /> <span>Export CSV</span>
                    </button>
                    <button
                      type="button"
                      phx-click="export_json"
                      phx-target={@myself}
                      class="exo-menu-item"
                    >
                      <.icon name="download" class="w-3 h-3" /> <span>Export JSON</span>
                    </button>
                    <button
                      type="button"
                      phx-click="delete_resource"
                      phx-target={@myself}
                      data-confirm={"Delete all data for resource '#{@selected_resource_name}'? This cannot be undone."}
                      class="exo-menu-item exo-menu-danger"
                    >
                      <.icon name={:trash} class="w-3 h-3" /> <span>Clear Resource</span>
                    </button>
                  </div>
                </details>
              </div>
            <% else %>
              <div class="flex items-center gap-2">
                <span class="exo-badge bg-primary-50 text-primary-700 border-primary-200">
                  Singleton Config
                </span>
              </div>
            <% end %>
          </div>

          <%= if singleton_resource?(assigns) do %>
            <!-- Singleton Resource Direct Configuration Card -->
            <div class="exo-card p-6 space-y-6">
              <div class="flex items-center justify-between border-b border-gray-100 pb-4">
                <div>
                  <h3 class="text-base font-semibold text-gray-900 flex items-center gap-2">
                    <span><%= Phoenix.Naming.humanize(to_string(@selected_resource_name)) %></span>
                    <span class="text-xs font-mono font-normal text-primary-600 bg-primary-50 px-2 py-0.5 rounded-lg">singleton</span>
                  </h3>
                  <p class="text-xs text-gray-500 mt-1">
                    This resource contains a single instance configuration. Updating values persists directly into server storage.
                  </p>
                </div>
                <%= if @singleton_form && @singleton_form.saved do %>
                  <span class="inline-flex items-center gap-1 px-3 py-1 text-xs font-semibold rounded-xl bg-emerald-50 text-emerald-700 border border-emerald-200 animate-pulse">
                    ✓ Saved successfully
                  </span>
                <% end %>
              </div>

              <%= if @singleton_form do %>
                <form
                  phx-submit="submit_singleton_form"
                  phx-change="singleton_form_change"
                  phx-target={@myself}
                  class="space-y-4 max-w-2xl"
                >
                  <%= for column <- current_resource_columns(assigns) do %>
                    <% key = to_string(column.key) %>
                    <% value = Map.get(@singleton_form.values, key, "") %>
                    <% locked = column.primary_key %>

                    <.column_input column={column} value={value} locked={locked} target="singleton" myself={@myself} fk_options={@fk_options} />

                    <%= if error = @singleton_form.errors[key] do %>
                      <p class="text-[11px] text-red-600 mt-1 font-semibold"><%= error %></p>
                    <% end %>
                  <% end %>

                  <%= if error = @singleton_form.errors["_form"] do %>
                    <p class="text-xs text-red-600 bg-red-50 border border-red-200 rounded-xl p-3 font-mono">
                      <%= error %>
                    </p>
                  <% end %>

                  <div class="pt-3">
                    <button
                      type="submit"
                      class="px-5 py-2 text-xs font-semibold text-white bg-primary-600 hover:bg-primary-700 rounded-xl transition-colors shadow-sm flex items-center gap-1.5"
                    >
                      <.icon name={:save} class="w-3.5 h-3.5" /> <span>Save Settings</span>
                    </button>
                  </div>
                </form>
              <% end %>
            </div>
          <% else %>
            <!-- Declarative Resource Table -->
            <div class="bg-white rounded-xl border border-gray-200/80 shadow-sm overflow-hidden">
              <%= if @filtered_resource_rows == [] do %>
                <div class="p-12 text-center space-y-2">
                  <.icon name="box" class="w-8 h-8 mx-auto" />
                  <h3 class="text-sm font-semibold text-gray-900">No records found</h3>
                  <p class="text-xs text-gray-500 max-w-sm mx-auto">
                    No rows currently stored in resource <code class="font-mono text-primary-700 font-semibold"><%= @selected_resource_name %></code>.
                  </p>
                </div>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="w-full text-left border-collapse text-xs">
                    <thead>
                      <tr class="bg-gray-50/75 border-b border-gray-200 text-[10px] font-semibold text-gray-500 uppercase tracking-wider">
                        <%= for col <- @columns do %>
                          <th class="py-3 px-4"><%= col[:label] %></th>
                        <% end %>
                        <th class="py-3 px-4 text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100">
                      <%= for row <- @filtered_resource_rows do %>
                        <% row_id = Map.get(row, :id) || Map.get(row, "id") || Map.get(row, :player_id) || Map.get(row, "player_id") || "item" %>
                        <tr class="hover:bg-primary-50/30 transition-colors group">
                          <%= for col <- @columns do %>
                            <% val = Map.get(row, col[:key]) || Map.get(row, to_string(col[:key])) || "" %>
                            <td class="py-3 px-4">
                              <%= cond do %>
                                <% to_string(col[:role]) == "file_reference" -> %>
                                  <%= if val not in ["", nil] do %>
                                    <a
                                      href={"/api/files/#{col[:bucket] || "default"}/#{val}"}
                                      target="_blank"
                                      class="inline-flex items-center gap-1.5 font-mono text-xs font-semibold text-primary-700 bg-primary-50 hover:bg-primary-100 hover:text-primary-900 px-2 py-0.5 rounded-lg border border-primary-200 transition-colors"
                                      title={"View file " <> to_string(val)}
                                    >
                                      <.icon name="paperclip" class="w-3 h-3" />
                                      <span><%= to_string(val) %></span>
                                      <span class="text-[10px]">↗</span>
                                    </a>
                                  <% else %>
                                    <span class="text-xs text-gray-400 italic">none</span>
                                  <% end %>

                                <% fk = Map.get(@fk_links, {to_string(col[:key]), to_string(val)}) -> %>
                                  <ResourceRefs.fk_value link={fk} value={val} />

                                <% link = column_link(col[:role]) -> %>
                                  <.link
                                    patch={focus_path(link, val)}
                                    class="inline-flex items-center gap-1 font-mono font-semibold text-primary-700 hover:text-primary-900 hover:underline"
                                    title={"Open " <> to_string(col[:label])}
                                  >
                                    <span><%= to_string(val) %></span>
                                    <span class="text-[10px]"><%= link[:icon] || "↗" %></span>
                                  </.link>

                                <% col[:badge] -> %>
                                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
                                    <%= val %>
                                  </span>

                                <% true -> %>
                                  <span class="font-mono font-medium text-gray-800"><%= to_string(val) %></span>
                              <% end %>
                            </td>
                          <% end %>
                          <td class="py-3 px-4 text-right">
                            <button
                              type="button"
                              phx-click="open_focus"
                              phx-value-kind="row"
                              phx-value-id={to_string(row_id)}
                              class="px-2.5 py-1 text-xs font-semibold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-lg transition-colors"
                            >
                              Inspect
                            </button>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- SUBTAB 3: LIVE TELEMETRY & EVENTS -->
      <%= if @subtab == "events" do %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-semibold text-gray-900">Declared Event Contracts</h3>
              <p class="text-xs text-gray-400 mt-0.5">Server broadcasts emitted by this extension via EventDispatcher</p>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for ev <- @events do %>
              <% ev_name = to_string(ev[:name] || ev["name"]) %>
              <div class="exo-card p-5 space-y-3">
                <div class="flex items-center justify-between">
                  <span class="font-mono font-semibold text-primary-700 text-sm"><%= ev_name %></span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-lg text-[10px] font-semibold uppercase bg-gray-100 text-gray-700">
                    <%= ev[:scope] || "server" %>
                  </span>
                </div>
                <p class="text-xs text-gray-500"><%= ev[:doc] || "No description provided." %></p>

                <div class="pt-2 flex items-center justify-between border-t border-gray-100">
                  <span class="text-[11px] text-gray-400 font-mono">Topic: <%= ev[:topic] || ":global" %></span>
                  <button
                    type="button"
                    phx-click="simulate_event"
                    phx-value-event={ev_name}
                    phx-target={@myself}
                    class="px-3 py-1 text-xs font-semibold text-primary-700 bg-primary-50 hover:bg-primary-100 border border-primary-200 rounded-lg transition-colors"
                  >
                    Simulate Broadcast
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- SUBTAB 4: CONTRACT SPECIFICATION -->
      <%= if @subtab == "contract" do %>
        <div class="exo-card p-6 space-y-4">
          <h3 class="text-sm font-semibold text-gray-900">Contract & Architecture Specification</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
            <div class="p-4 bg-gray-50 rounded-xl border border-gray-100 space-y-2">
              <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">Extension Identity</span>
              <p><strong>ID:</strong> <code class="font-mono text-primary-700"><%= @extension.id %></code></p>
              <p><strong>Entry Point:</strong> <code class="font-mono text-gray-700"><%= inspect(@extension[:entry_point] || @extension.id) %></code></p>
              <p><strong>Runtime Engine:</strong> <%= @extension.type %></p>
            </div>
            <div class="p-4 bg-gray-50 rounded-xl border border-gray-100 space-y-2">
              <span class="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">Contract Topology</span>
              <p><strong>Provided Services:</strong> <%= Enum.join(@extension.provides, ", ") %></p>
              <p><strong>Dependencies:</strong> <%= if @extension.dependencies == [], do: "None (Kernel Root)", else: Enum.join(@extension.dependencies, ", ") %></p>
              <p><strong>Visual GUI Status:</strong> Synthesized by Exoforge Engine</p>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Entity/Row Inspector Popup -->
      <%= if @drawer_open and @inspected_row do %>
        <.inspect_popup
          open={true}
          icon="box"
          title={to_string(Map.get(@inspected_row, :id) || Map.get(@inspected_row, "id") || "Record")}
          subtitle={"Resource: #{@selected_resource_name}"}
          tabs={@drawer_tabs}
          active_tab={@inspected_drawer_tab}
          on_close="close_focus"
          on_select_tab="select_drawer_tab"
          target={@myself}
          width="max-w-2xl"
        >
          <%= if @inspected_drawer_tab == "attributes" do %>
            <!--
              The row exactly as the store returned it. Keys as stored, values as stored, and
              including anything the schema does not describe - which is what you want when a column
              is not what the schema says it should be.
            -->
            <div class="space-y-3">
              <p class="text-xs text-gray-500">
                As stored. Unlabelled, and including anything the schema does not describe.
              </p>

              <div class="space-y-2">
                <%= for {k, v} <- @inspected_row do %>
                  <div class="p-2.5 bg-gray-50 rounded-xl border border-gray-100 flex flex-col text-xs font-mono">
                    <span class="text-gray-400 text-[10px] uppercase font-semibold"><%= k %></span>
                    <span class="text-gray-900 break-all"><%= inspect(v) %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <!--
              The schema's view: the columns the plugin declared, in the order it declared them, with
              their labels and types. A column the row has no value for says so rather than being
              omitted - an absent field and an empty one are different questions.
            -->
            <div class="space-y-3">
              <%= for column <- current_resource_columns(assigns) do %>
                <% key = to_string(column.key) %>
                <% value = Map.get(@inspected_row, key) || Map.get(@inspected_row, column.key) %>

                <div class="p-2.5 bg-gray-50 rounded-xl border border-gray-100 flex items-start justify-between gap-3">
                  <div class="flex flex-col min-w-0">
                    <span class="text-[10px] text-gray-400 uppercase font-semibold">
                      <%= column.label %><%= if column.primary_key, do: " · key" %>
                    </span>
                    <span class="text-xs text-gray-900 break-all font-mono">
                      <%= if is_nil(value) or value == "" do %>
                        <span class="text-gray-300 italic">no value</span>
                      <% else %>
                        <ResourceRefs.fk_value
                          link={Map.get(@drawer_fk, {key, to_string(value)})}
                          value={value}
                        />
                      <% end %>
                    </span>
                  </div>

                  <%= if column.badge and value not in [nil, ""] do %>
                    <span class="px-2 py-0.5 text-[10px] font-semibold rounded-full bg-primary-100 text-primary-800 shrink-0">
                      <%= value %>
                    </span>
                  <% else %>
                    <span class="text-[10px] font-mono text-gray-400 shrink-0"><%= column.type %></span>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <div class="mt-4">
            <ResourceRefs.referenced_by_list groups={@referenced_by} />
          </div>

          <div class="pt-4 border-t border-gray-200/80 flex items-center gap-2">
            <button
              type="button"
              phx-click="edit_resource"
              phx-target={@myself}
              class="exo-btn exo-btn-primary"
            >
              Edit
            </button>

            <button
              type="button"
              phx-click="close_focus"
              class="exo-btn exo-btn-secondary flex-1"
            >
              Close Inspector
            </button>
          </div>
        </.inspect_popup>
      <% end %>

      <!--
        The row form. Every field comes from the plugin's declared schema, so a record that gains a
        column gains an input and nothing here has to know what the column means.
      -->
      <%= if @resource_form do %>
        <div
          data-exo-modal
          data-close-event="close_resource_form"
          class="exo-modal-backdrop z-[70]"
          role="dialog"
          aria-modal="true"
        >
          <div class="fixed inset-0" phx-click="close_resource_form" phx-target={@myself}></div>
          <div class="exo-modal-panel max-w-lg z-10">
            <div class="exo-modal-header">
              <div class="min-w-0">
                <h3 class="exo-modal-title truncate">
                  <%= if @resource_form.mode == :new, do: "New", else: "Edit" %>
                  <%= Phoenix.Naming.humanize(to_string(@selected_resource_name)) %>
                </h3>
                <p class="exo-modal-subtitle truncate">
                  Fields come from the schema this plugin declares.
                </p>
              </div>

              <button
                type="button"
                phx-click="close_resource_form"
                phx-target={@myself}
                class="exo-btn exo-btn-icon shrink-0"
                title="Close (Esc)"
              >
                <.icon name="close" class="w-4 h-4" />
              </button>
            </div>

            <form
              phx-submit="submit_resource_form"
              phx-change="resource_form_change"
              phx-target={@myself}
              class="flex flex-col min-h-0 flex-1"
            >
              <div class="exo-modal-body custom-scrollbar space-y-3">
                <%= for column <- current_resource_columns(assigns) do %>
                  <% key = to_string(column.key) %>
                  <% value = Map.get(@resource_form.values, key, "") %>
                  <% locked = column.primary_key and @resource_form.mode == :edit %>

                  <.column_input column={column} value={value} locked={locked} target="resource_form" myself={@myself} fk_options={@fk_options} />

                  <%= if error = @resource_form.errors[key] do %>
                    <p class="text-[11px] text-red-600 mt-1 font-medium"><%= error %></p>
                  <% end %>
                <% end %>

                <%= if error = @resource_form.errors["_form"] do %>
                  <p class="text-xs text-red-600 bg-red-50 border border-red-200 rounded-lg p-3 font-mono">
                    <%= error %>
                  </p>
                <% end %>
              </div>

              <div class="exo-modal-footer">
                <button
                  type="button"
                  phx-click="close_resource_form"
                  phx-target={@myself}
                  class="exo-btn exo-btn-secondary"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="exo-btn exo-btn-primary"
                >
                  Save
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <%= if @export_modal_open do %>
        <div
          data-exo-modal
          data-close-event="close_export_modal"
          class="exo-modal-backdrop z-[70]"
          role="dialog"
          aria-modal="true"
        >
          <div class="fixed inset-0" phx-click="close_export_modal" phx-target={@myself}></div>
          <div class="exo-modal-panel max-w-xl z-10">
            <div class="exo-modal-header">
              <h3 class="exo-modal-title truncate">Export <%= @export_format %> Data (<%= @export_filename %>)</h3>
              <button
                type="button"
                phx-click="close_export_modal"
                phx-target={@myself}
                class="exo-btn exo-btn-icon shrink-0"
                title="Close (Esc)"
              >
                <.icon name="close" class="w-4 h-4" />
              </button>
            </div>

            <div class="exo-modal-body custom-scrollbar">
              <textarea
                readonly
                rows="8"
                class="exo-textarea font-mono"
              ><%= @export_content %></textarea>
            </div>

            <div class="exo-modal-footer">
              <button
                type="button"
                phx-click="close_export_modal"
                phx-target={@myself}
                class="exo-btn exo-btn-secondary"
              >
                Close
              </button>
              <button
                type="button"
                phx-click={Phoenix.LiveView.JS.dispatch("exoforge:clip", detail: %{text: @export_content})}
                class="exo-btn exo-btn-primary"
              >
                Copy to Clipboard
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- File Bucket Picker Modal -->
      <%= if @file_picker_open do %>
        <div
          data-exo-modal
          data-close-event="close_file_picker"
          class="exo-modal-backdrop z-[70]"
          role="dialog"
          aria-modal="true"
        >
          <div class="fixed inset-0" phx-click="close_file_picker" phx-target={@myself}></div>
          <div class="exo-modal-panel max-w-2xl z-10">
            <div class="exo-modal-header">
              <div class="flex items-center gap-2.5 min-w-0">
                <.icon name="folder" class="w-4 h-4 text-primary-600 shrink-0" />
                <div class="min-w-0">
                  <h3 class="exo-modal-title truncate">Select File from Bucket</h3>
                  <p class="exo-modal-subtitle truncate">Selecting for field <code class="font-mono text-primary-700 font-medium"><%= @file_picker_field %></code></p>
                </div>
              </div>
              <button
                type="button"
                phx-click="close_file_picker"
                phx-target={@myself}
                class="exo-btn exo-btn-icon shrink-0"
                title="Close (Esc)"
              >
                <.icon name="close" class="w-4 h-4" />
              </button>
            </div>

            <div class="exo-modal-body custom-scrollbar space-y-4">
              <!-- Bucket tabs & Search -->
              <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div class="exo-tabs flex-1">
                  <%= for b <- @file_picker_buckets do %>
                    <button
                      type="button"
                      phx-click="file_picker_change_bucket"
                      phx-value-bucket={b}
                      phx-target={@myself}
                      class={"exo-tab #{if @file_picker_bucket == b, do: "exo-tab-active"}"}
                    >
                      <%= b %>
                    </button>
                  <% end %>
                </div>

                <form id="file-picker-search-form" phx-change="file_picker_search" phx-submit="file_picker_search" phx-target={@myself} class="relative w-full sm:w-56">
                  <input
                    type="search"
                    name="query"
                    placeholder="Search files..."
                    value={@file_picker_search}
                    phx-debounce="150"
                    class="exo-input pl-7"
                  />
                  <span class="absolute left-2.5 top-2 text-gray-400"><.icon name="search" class="w-3 h-3" /></span>
                </form>
              </div>

              <!-- File Grid / List -->
              <div class="max-h-80 overflow-y-auto p-1 grid grid-cols-2 sm:grid-cols-3 gap-3">
                <%= if @file_picker_filtered_files == [] do %>
                  <div class="col-span-full py-12 text-center text-xs text-gray-400">
                    No files found in bucket <strong class="text-gray-700"><%= @file_picker_bucket %></strong>.
                  </div>
                <% else %>
                  <%= for file <- @file_picker_filtered_files do %>
                    <% is_img = String.starts_with?(to_string(file["content_type"] || ""), "image/") or Path.extname(file["filename"] || "") in [".png", ".jpg", ".jpeg", ".webp", ".svg"] %>
                    <div
                      phx-click="file_picker_select"
                      phx-value-id={file["id"]}
                      phx-target={@myself}
                      class="p-2.5 rounded-xl border border-gray-200 hover:border-primary-400 hover:bg-primary-50/30 cursor-pointer transition-colors flex flex-col justify-between group bg-white shadow-2xs"
                    >
                      <div class="h-20 bg-gray-50 rounded-lg mb-2 flex items-center justify-center overflow-hidden border border-gray-100">
                        <%= if is_img do %>
                          <img src={file["url"]} class="max-h-full max-w-full object-contain" alt="" />
                        <% else %>
                          <.icon name="file" class="w-6 h-6 text-gray-300" />
                        <% end %>
                      </div>
                      <div>
                        <p class="text-xs font-medium text-gray-800 truncate" title={file["filename"]}><%= file["filename"] %></p>
                        <div class="flex items-center justify-between text-[10px] text-gray-400 mt-1 tabular-nums">
                          <code class="font-mono truncate"><%= file["id"] %></code>
                          <span><%= if file["size_bytes"], do: "#{Float.round(file["size_bytes"] / 1024, 1)} KB", else: "" %></span>
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="file_picker_select"
                        phx-value-id={file["id"]}
                        phx-target={@myself}
                        class="mt-2 w-full exo-btn exo-btn-sm exo-btn-secondary group-hover:bg-primary-600 group-hover:text-white group-hover:border-primary-600"
                      >
                        Select
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <div class="exo-modal-footer justify-between">
              <!-- Quick upload inside picker -->
              <form id="picker_quick_upload_form" phx-submit="file_picker_uploaded" phx-target={@myself} class="m-0 p-0 inline">
                <input type="hidden" id="picker_upload_filename" name="filename" value="" />
                <input type="hidden" id="picker_upload_content_type" name="content_type" value="" />
                <input type="hidden" id="picker_upload_base64" name="base64" value="" />
                <label class="exo-btn exo-btn-secondary cursor-pointer">
                  <span class="inline-flex items-center gap-1.5"><.icon name="upload" class="w-3.5 h-3.5" /> Upload &amp; Select</span>
                  <input
                    type="file"
                    class="hidden"
                    id="picker_quick_upload"
                    onchange="
                      const file = this.files[0];
                      if (!file) return;
                      const reader = new FileReader();
                      reader.onload = function(e) {
                        const base64 = e.target.result.split(',')[1];
                        document.getElementById('picker_upload_filename').value = file.name;
                        document.getElementById('picker_upload_content_type').value = file.type || 'application/octet-stream';
                        document.getElementById('picker_upload_base64').value = base64;
                        document.getElementById('picker_quick_upload_submit').click();
                      };
                      reader.readAsDataURL(file);
                    "
                  />
                </label>
                <button type="submit" id="picker_quick_upload_submit" class="hidden"></button>
              </form>

              <button
                type="button"
                phx-click="close_file_picker"
                phx-target={@myself}
                class="exo-btn exo-btn-secondary"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
