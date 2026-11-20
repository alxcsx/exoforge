defmodule Exoforge.Std.Docs do
  @moduledoc """
  Standard Documentation & Developer Guide extension for Exoforge.
  Provides the :docs service contract, dynamically generating API catalogs
  from the Extension Manager, serving Markdown documentation with code highlighting,
  and supporting print/PDF export.
  """
  use Exoforge.Extension, provides: [:docs]

  alias Exoforge.Std.Docs.Markdown
  alias Exoforge.ActionDispatcher
  alias Exoforge.ExtensionRegistry

  @manifest %{
    system: true,
    dependencies: [Exoforge.Std.Services.ExtensionManager],
    title: "Developer Guide",
    icon: "📖",
    category: "System",
    dashboard_view: %{
      id: :docs,
      title: "Developer Guide",
      icon: "📖",
      module: Exoforge.Std.Docs.DashboardView
    }
  }

  @doc "Dashboard visualization specification."
  def dashboard_view, do: @manifest.dashboard_view

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction list_chapters, scope: Exoforge.Auth.Roles.studio() do
    chapters = load_all_chapters_meta()
    {:ok, %{chapters: chapters, count: length(chapters)}}
  end

  @impl true
  defaction get_chapter(payload), scope: Exoforge.Auth.Roles.studio() do
    id = Map.get(payload, :id) || Map.get(payload, "id")

    case find_chapter(id) do
      nil ->
        {:error, :not_found}

      %{title: _title, content: content} = chap ->
        html = Markdown.to_html(content)
        {:ok, %{chapter: Map.merge(chap, %{html: Phoenix.HTML.safe_to_string(html)})}}
    end
  end

  @impl true
  defaction export_docs(payload), scope: Exoforge.Auth.Roles.studio() do
    format = Map.get(payload, :format) || Map.get(payload, "format") || "markdown"
    chapters = all_pages()
    catalog = build_api_catalog()

    consolidated_md =
      Enum.map(chapters, fn %{content: content} -> content end)
      |> Enum.join("\n\n---\n\n")

    catalog_md = format_catalog_as_markdown(catalog)
    full_markdown = consolidated_md <> "\n\n---\n\n" <> catalog_md

    case format do
      "pdf" ->
        pdf = Exoforge.Std.Docs.PdfManual.generate()
        {:ok, %{title: "Exoforge Complete Developer Guide", binary: pdf, format: "pdf"}}

      "html" ->
        html = Markdown.to_html(full_markdown) |> Phoenix.HTML.safe_to_string()
        {:ok, %{title: "Exoforge Complete Developer Guide", content: html, format: "html"}}

      _ ->
        {:ok, %{title: "Exoforge Complete Developer Guide", content: full_markdown, format: "markdown"}}
    end
  end

  ## ---- DYNAMIC API CATALOG EXTRACTION ----

  @doc """
  Queries ExtensionManager via ActionDispatcher (loose coupling) to extract all
  callable actions, parameters, scopes, and schemas across all running extensions.
  """
  def build_api_catalog do
    case ActionDispatcher.dispatch(:extension_manager, :export_extension_info, %{}) do
      {:ok, %{export: %{"extensions" => exts}}} ->
        extract_catalog_from_export(exts)

      _ ->
        # Fallback to local ExtensionRegistry if running standalone or before boot
        extract_catalog_from_registry()
    end
  end

  defp extract_catalog_from_export(exts) when is_list(exts) do
    exts
    |> Enum.flat_map(fn ext ->
      services = ext["services"] || []

      Enum.map(services, fn svc ->
        %{
          extension_id: ext["id"],
          extension_title: ext["title"] || ext["name"],
          name: svc["name"] || svc[:name],
          title: svc["title"] || svc[:title] || Macro.camelize(to_string(svc["name"] || svc[:name])),
          icon: svc["icon"] || svc[:icon] || ext["icon"] || "⚙",
          actions: normalize_actions(svc["actions"] || svc[:actions] || []),
          events: normalize_events(svc["events"] || svc[:events] || [])
        }
      end)
    end)
    |> Enum.reject(&(&1.actions == [] and &1.events == []))
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp extract_catalog_from_registry do
    ExtensionRegistry.all_manifests()
    |> Enum.flat_map(fn m ->
      services = ExtensionRegistry.manifest_services(m)

      Enum.map(services, fn svc ->
        %{
          extension_id: to_string(m.id),
          extension_title: m.title || to_string(m.name || m.id),
          name: to_string(svc.name),
          title: svc[:title] || Macro.camelize(to_string(svc.name)),
          icon: svc[:icon] || m.icon || "⚙",
          actions: normalize_actions(svc[:actions] || []),
          events: normalize_events(svc[:events] || [])
        }
      end)
    end)
    |> Enum.reject(&(&1.actions == [] and &1.events == []))
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_events(events) do
    Enum.map(events, fn evt ->
      payload =
        case evt[:payload] || evt["payload"] do
          list when is_list(list) ->
            Enum.map(list, fn
              {k, _type} -> to_string(k)
              %{} = p -> to_string(p["name"] || p[:name])
              other -> to_string(other)
            end)

          %{} = map ->
            Enum.map(Map.keys(map), &to_string/1)

          _ ->
            []
        end

      %{
        name: to_string(evt[:name] || evt["name"]),
        doc: evt[:doc] || evt["doc"],
        topic: evt[:topic] || evt["topic"],
        scope: to_string(evt[:scope] || evt["scope"] || ""),
        payload: payload
      }
    end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_actions(actions) do
    Enum.map(actions, fn act ->
      params =
        case act[:params] || act["params"] do
          list when is_list(list) ->
            Enum.map(list, fn
              {k, opts} when is_list(opts) ->
                %{
                  name: to_string(k),
                  type: to_string(opts[:type] || :term),
                  optional: Keyword.get(opts, :optional, false),
                  doc: Keyword.get(opts, :doc)
                }

              {k, type} when is_atom(k) ->
                type_str =
                  cond do
                    is_binary(type) -> type
                    is_atom(type) -> Atom.to_string(type)
                    true -> inspect(type)
                  end

                %{name: to_string(k), type: type_str, optional: false, doc: nil}

              p when is_map(p) ->
                %{
                  name: to_string(p["name"] || p[:name]),
                  type: to_string(p["type"] || p[:type] || "term"),
                  optional: p["optional"] || p[:optional] || false,
                  doc: p["doc"] || p[:doc]
                }

              other ->
                %{name: to_string(other), type: "term", optional: false, doc: nil}
            end)
            |> Enum.uniq_by(& &1.name)
            |> Enum.sort_by(fn p -> if p.optional, do: 1, else: 0 end)

          _ ->
            []
        end

      %{
        name: to_string(act[:name] || act["name"]),
        mode: to_string(act[:mode] || act["mode"] || "sync"),
        scope: to_string(act[:scope] || act["scope"] || "player"),
        doc: act[:doc] || act["doc"] || "No documentation provided.",
        params: params,
        returns: act[:returns] || act["returns"]
      }
    end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  ## ---- CHAPTER LOADER ----

  def docs_dir do
    priv_dir =
      try do
        :code.priv_dir(:exoforge_std_docs) |> to_string()
      rescue
        _ -> nil
      end

    app_dir =
      try do
        Application.app_dir(:exoforge_std_docs, "priv/guide")
      rescue
        _ -> nil
      end

    release_dirs =
      try do
        Path.wildcard(Path.join([:code.root_dir(), "lib", "exoforge_std_docs*", "priv", "guide"]))
      rescue
        _ -> []
      end

    candidates =
      [
        priv_dir && Path.join(priv_dir, "guide"),
        app_dir,
        "extensions/exoforge_std_docs/priv/guide",
        "priv/guide"
      ] ++ release_dirs

    Enum.find(candidates, fn path -> is_binary(path) and File.dir?(path) end) || "priv/guide"
  end

  defp load_all_chapters_meta do
    load_all_chapters()
    |> Enum.map(&Map.take(&1, [:id, :title, :nav, :order, :filename, :group, :icon, :summary]))
  end

  def load_all_chapters do
    dir = docs_dir()

    if File.dir?(dir) do
      Path.wildcard(Path.join(dir, "*.md"))
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Enum.map(fn {path, idx} ->
        filename = Path.basename(path)
        id = Path.rootname(filename)
        {meta, content} = split_front_matter(File.read!(path))
        title = extract_title(content, id)

        %{
          id: id,
          title: title,
          order: idx,
          filename: filename,
          nav: Map.get(meta, "nav", title),
          group: Map.get(meta, "group", "Guide"),
          icon: Map.get(meta, "icon", "book"),
          summary: Map.get(meta, "summary", ""),
          content: content
        }
      end)
    else
      []
    end
  end

  defp find_chapter(id) when is_binary(id) do
    Enum.find(load_all_chapters() ++ load_extension_pages(), fn c -> c.id == id or c.filename == id end)
  end

  defp find_chapter(_), do: nil

  ## ---- EXTENSION DOCS ----

  # The folder an extension keeps its own documentation in, next to its manifest. An Elixir extension ships files
  # through `priv/`, so `priv/docs` is the same folder for it.
  @extension_docs_dirs ["docs", "priv/docs"]
  @max_extension_pages 24
  @max_page_bytes 262_144

  @doc """
  The documentation every running extension ships, gathered from the extensions themselves: each `*.md` file
  directly inside the reserved `docs/` folder of an extension (Elixir: `priv/docs/`), in file-name order, as a
  page of the guide's *Extensions* group. Nothing registers them: deploy an extension with a `docs/` folder and its
  pages appear, remove the extension and they go. Front matter is optional (`nav`, `icon`, `summary`).
  """
  def load_extension_pages do
    Exoforge.ExtensionRegistry.all_manifests()
    |> Enum.uniq_by(&manifest_field(&1, :id))
    |> Enum.sort_by(&extension_title/1)
    |> Enum.flat_map(&extension_pages/1)
  rescue
    # the registry is not running (a tool rendering the guide offline): the guide's own chapters still work
    _ -> []
  end

  @doc "Every page the exports contain: the guide's chapters, then the extensions' documentation."
  def all_pages, do: load_all_chapters() ++ load_extension_pages()

  defp extension_pages(manifest) do
    id = to_string(manifest_field(manifest, :id) || "")
    root = manifest_field(manifest, :physical_path)

    with true <- id != "" and is_binary(root) and root != "",
         dir when is_binary(dir) <- Enum.find_value(@extension_docs_dirs, &existing_dir(root, &1)) do
      title = extension_title(manifest)

      dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.take(@max_extension_pages)
      |> Enum.flat_map(&extension_page(&1, id, title))
    else
      _ -> []
    end
  end

  defp existing_dir(root, sub) do
    dir = Path.join(root, sub)
    if File.dir?(dir), do: dir
  end

  defp extension_page(path, extension_id, extension_title) do
    with {:ok, %{size: size}} when size <= @max_page_bytes <- File.stat(path),
         {:ok, raw} <- File.read(path) do
      stem = path |> Path.basename() |> Path.rootname()
      {meta, content} = split_front_matter(raw)
      content = expand_directives(content, extension_id)
      title = extract_title(content, stem)

      [
        %{
          id: "ext-" <> slug(extension_id) <> "-" <> slug(stem),
          title: title,
          nav: Map.get(meta, "nav", if(stem == "overview", do: "Overview", else: title)),
          order: 0,
          filename: Path.basename(path),
          group: "Extensions",
          icon: Map.get(meta, "icon", "box"),
          summary: Map.get(meta, "summary", ""),
          extension: extension_id,
          extension_title: extension_title,
          content: content
        }
      ]
    else
      _ -> []
    end
  end

  # `{{actions}}`, `{{events}}` and `{{resources}}` on a line of their own in an extension's page become tables built from
  # what the extension declares now, linked to the API catalog. The prose is the author's; the signatures can never
  # drift from the code because they are not written down.
  defp expand_directives(content, extension_id) do
    if String.contains?(content, "{{") do
      services = catalog_services(extension_id)

      content
      |> String.replace("{{actions}}", actions_markdown(services))
      |> String.replace("{{events}}", events_markdown(services))
      |> String.replace("{{resources}}", resources_markdown(extension_id))
    else
      content
    end
  end

  defp catalog_services(extension_id) do
    extract_catalog_from_registry() |> Enum.filter(&(&1.extension_id == extension_id))
  end

  defp actions_markdown(services) do
    rows =
      for svc <- services, act <- svc.actions do
        takes =
          Enum.map_join(act.params, ", ", fn p -> "`#{p.name}#{if p.optional, do: "?"}`" end)

        "| [`#{act.name}`](api:#{svc.name}.#{act.name}) | `#{act.scope}` | #{if takes == "", do: "-", else: takes} | #{cell(act.doc)} |"
      end

    if rows == [],
      do: "It declares no actions.",
      else: Enum.join(["| Action | Scope | Takes | What it does |", "|---|---|---|---|" | rows], "\n") <> "\n\n`name?` marks an optional field. Select an action to see its types and a call example."
  end

  defp events_markdown(services) do
    rows =
      for svc <- services, evt <- svc.events do
        payload = Enum.map_join(evt.payload, ", ", &"`#{&1}`")
        "| [`#{evt.name}`](event:#{svc.name}.#{evt.name}) | #{if evt.topic, do: "`#{evt.topic}`", else: "-"} | #{if payload == "", do: "-", else: payload} | #{cell(evt.doc)} |"
      end

    if rows == [],
      do: "It declares no events.",
      else: Enum.join(["| Event | Topic | Payload | What it means |", "|---|---|---|---|" | rows], "\n")
  end

  defp resources_markdown(extension_id) do
    rows =
      for m <- ExtensionRegistry.all_manifests(),
          to_string(manifest_field(m, :id)) == extension_id,
          svc <- ExtensionRegistry.manifest_services(m),
          res <- List.wrap(svc[:resources] || svc["resources"]),
          is_map(res) do
        name = to_string(res[:name] || res["name"])
        "- `#{name}`"
      end

    if rows == [], do: "It stores nothing of its own.", else: Enum.join(Enum.uniq(rows), "\n")
  end

  # A table cell: the first sentence of the text, on one line, without the pipe that would split the cell.
  defp cell(nil), do: "-"
  defp cell(text), do: text |> to_string() |> String.split("\n") |> hd() |> String.replace("|", "/") |> then(&if(&1 == "", do: "-", else: &1))

  defp extension_title(manifest) do
    to_string(manifest_field(manifest, :title) || manifest_field(manifest, :name) || manifest_field(manifest, :id) || "")
  end

  defp manifest_field(manifest, key), do: Map.get(manifest, key) || Map.get(manifest, to_string(key))

  defp slug(text), do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

  # A chapter may start with a `---` block of `key: value` lines (group, icon, summary) that the guide's
  # navigation reads. The exports (PDF, markdown) get the chapter without it.
  defp split_front_matter("---\n" <> rest = whole) do
    case String.split(rest, "\n---\n", parts: 2) do
      [block, content] ->
        meta =
          for line <- String.split(block, "\n"),
              [key, value] <- [String.split(line, ":", parts: 2)],
              into: %{},
              do: {String.trim(key), String.trim(value)}

        {meta, content}

      _ ->
        {%{}, whole}
    end
  end

  defp split_front_matter(content), do: {%{}, content}

  defp extract_title(content, fallback) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, match] -> String.trim(match)
      _ -> Macro.camelize(fallback)
    end
  end

  defp format_catalog_as_markdown(catalog) do
    header = "# Dynamic Cluster API Reference\n\nLive service catalog generated across active cluster extensions.\n\n"

    sections =
      Enum.map(catalog, fn svc ->
        actions_md =
          Enum.map(svc.actions, fn act ->
            params_md =
              if act.params == [] do
                "_No parameters required._\n"
              else
                table_header = "| Parameter | Type | Required | Description |\n|---|---|---|---|\n"

                rows =
                  Enum.map(act.params, fn p ->
                    req = if p.optional, do: "Optional", else: "**Required**"
                    "| `#{p.name}` | `#{p.type}` | #{req} | #{p.doc || "—"} |"
                  end)
                  |> Enum.join("\n")

                table_header <> rows <> "\n"
              end

            """
            ### .#{act.name}() [#{act.mode}]

            #{act.doc}

            **Scope**: `#{act.scope}`

            #{params_md}
            """
          end)
          |> Enum.join("\n")

        """
        ## #{svc.icon} #{svc.title} (`#{svc.name}`)

        #{actions_md}
        """
      end)
      |> Enum.join("\n---\n\n")

    header <> sections
  end
end
