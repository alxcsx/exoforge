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
      icon: "📖"
    }
  }

  @doc "Dashboard visualization specification."
  def dashboard_view, do: @manifest.dashboard_view

  ## ---- SERVICE ACTIONS ----

  @impl true
  defaction list_chapters do
    chapters = load_all_chapters_meta()
    {:ok, %{chapters: chapters, count: length(chapters)}}
  end

  @impl true
  defaction get_chapter(payload) do
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
  defaction export_docs(payload) do
    format = Map.get(payload, :format) || Map.get(payload, "format") || "markdown"
    chapters = load_all_chapters()
    catalog = build_api_catalog()

    consolidated_md =
      Enum.map(chapters, fn %{content: content} -> content end)
      |> Enum.join("\n\n---\n\n")

    catalog_md = format_catalog_as_markdown(catalog)
    full_markdown = consolidated_md <> "\n\n---\n\n" <> catalog_md

    case format do
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
          icon: svc["icon"] || svc[:icon] || ext["icon"] || "⚙️",
          actions: normalize_actions(svc["actions"] || svc[:actions] || [])
        }
      end)
    end)
    |> Enum.reject(&(&1.actions == []))
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
          icon: svc[:icon] || m.icon || "⚙️",
          actions: normalize_actions(svc[:actions] || [])
        }
      end)
    end)
    |> Enum.reject(&(&1.actions == []))
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_actions(actions) do
    Enum.map(actions, fn act ->
      params =
        case act[:params] || act["params"] do
          list when is_list(list) ->
            Enum.map(list, fn
              {k, type} when is_atom(k) ->
                %{name: to_string(k), type: to_string(type), optional: false, doc: nil}

              {k, opts} when is_list(opts) ->
                %{
                  name: to_string(k),
                  type: to_string(opts[:type] || :term),
                  optional: Keyword.get(opts, :optional, false),
                  doc: Keyword.get(opts, :doc)
                }

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

          _ ->
            []
        end

      %{
        name: to_string(act[:name] || act["name"]),
        mode: to_string(act[:mode] || act["mode"] || "sync"),
        scope: to_string(act[:scope] || act["scope"] || "guest"),
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
    Application.app_dir(:exoforge_std_docs, "priv/docs")
  rescue
    _ ->
      # Development fallback relative path
      cond do
        File.dir?("extensions/exoforge_std_docs/priv/docs") -> "extensions/exoforge_std_docs/priv/docs"
        File.dir?("priv/docs") -> "priv/docs"
        true -> "priv/docs"
      end
  end

  defp load_all_chapters_meta do
    load_all_chapters()
    |> Enum.map(fn c -> %{id: c.id, title: c.title, order: c.order, filename: c.filename} end)
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
        content = File.read!(path)
        title = extract_title(content, id)

        %{
          id: id,
          title: title,
          order: idx,
          filename: filename,
          content: content
        }
      end)
    else
      []
    end
  end

  defp find_chapter(id) when is_binary(id) do
    Enum.find(load_all_chapters(), fn c -> c.id == id or c.filename == id end)
  end

  defp find_chapter(_), do: nil

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
