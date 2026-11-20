defmodule Exoforge.Std.Docs.Pages do
  @moduledoc """
  The Developer Guide's table of contents: which pages exist, how they group, and what comes before and
  after each one.

  A page is either a chapter (a Markdown file under `priv/guide`, whose front matter names its group and
  icon), a page an extension ships in its own `docs/` folder (group *Extensions*, gathered from the running
  extensions), or one of two live pages the guide renders itself: the architecture map and the API catalog.
  Adding a page means adding the file; nothing here lists pages by name.
  """

  alias Exoforge.Std.Docs

  # The order the sidebar shows its groups in. A chapter whose group is not listed goes last.
  @groups ["Get started", "Build", "Operate", "Learn by example", "Understand", "Live reference", "Extensions"]

  @live_pages [
    %{id: "architecture", title: "Architecture map", nav: "Architecture map", group: "Understand", icon: "graph", summary: "How the extensions on this server fit together.", kind: :architecture},
    %{id: "catalog", title: "API catalog", nav: "API catalog", group: "Live reference", icon: "book", summary: "Every service and action registered on this server, right now.", kind: :catalog}
  ]

  # Links and bookmarks from before the guide was one source of truth.
  @legacy %{
    "flow" => "01_quickstart",
    "how_to" => "02_recipes",
    "attributes" => "03_csharp_attributes",
    "use_cases" => "07_patterns"
  }

  @doc "All pages in reading order: chapters by file name within their group, then the live pages."
  def all do
    chapters = Enum.map(Docs.all_pages(), &Map.put(&1, :kind, :chapter))

    (chapters ++ @live_pages)
    |> Enum.with_index()
    |> Enum.sort_by(fn {page, index} -> {group_rank(page.group), index} end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "Pages grouped for the sidebar, in group order."
  def grouped(pages \\ all()) do
    pages
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group_rank(group) end)
  end

  @doc "The page an id names, accepting the guide's old ids; the first page when the id is unknown."
  def fetch(id, pages \\ all()) do
    id = Map.get(@legacy, to_string(id), to_string(id))
    Enum.find(pages, &(&1.id == id)) || hd(pages)
  end

  @doc "`{previous, next}` of a page, each a page or nil."
  def neighbours(page, pages \\ all()) do
    index = Enum.find_index(pages, &(&1.id == page.id)) || 0
    {if(index > 0, do: Enum.at(pages, index - 1)), Enum.at(pages, index + 1)}
  end

  @doc """
  The headings of a chapter's Markdown for its "On this page" list: `{level, text, id}` for every `##` and
  `###` outside code fences. Ids are the ones the renderer puts on the headings.
  """
  def toc(content) when is_binary(content) do
    content
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({false, []}, fn line, {in_code, acc} ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "```") -> {not in_code, acc}
        in_code -> {in_code, acc}
        match = Regex.run(~r/^(\#{2,3})\s+(.+)$/, trimmed) -> {in_code, [heading(match) | acc]}
        true -> {in_code, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp heading([_, hashes, text]) do
    {String.length(hashes), plain(text), Exoforge.Std.Docs.Markdown.slugify(text)}
  end

  # Inline markup is not wanted in a navigation label.
  defp plain(text), do: text |> String.replace(~r/[`*_]/, "") |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")

  defp group_rank(group), do: Enum.find_index(@groups, &(&1 == group)) || length(@groups)
end
