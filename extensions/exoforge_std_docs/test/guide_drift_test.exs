defmodule Exoforge.Std.GuideDriftTest do
  @moduledoc """
  The Developer Guide is the main documentation, so it must not fall behind the code. These tests read the
  sources of truth in the repository (the SDK attributes, the CLI, the standard extensions) and fail when
  the guide no longer matches them. A failure here means: update the chapter, not the test.
  """
  use ExUnit.Case, async: true

  alias Exoforge.Std.Docs
  alias Exoforge.Std.Docs.{Markdown, Pages}

  @repo Path.expand("../../..", __DIR__)
  @attributes Path.join(@repo, "sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs")
  @cli Path.join(@repo, "sdk/csharp/Exoforge.CLI/Program.cs")

  defp chapter(id), do: Enum.find(Docs.load_all_chapters(), &(&1.id == id)).content

  # `class Name : Attribute` bodies of Attributes.cs: name => settable property names.
  defp attribute_properties do
    source = File.read!(@attributes)

    ~r/public (?:sealed )?class (Exo\w+)Attribute\b[^{]*\{(.*?)\n\}\n/s
    |> Regex.scan(source)
    |> Map.new(fn [_, name, body] ->
      props = ~r/public [\w<>\[\]?,\. ]+? (\w+) \{ get; set; \}/ |> Regex.scan(body) |> Enum.map(&List.last/1)
      {name, props}
    end)
  end

  @tag :repo
  test "every attribute of the SDK has a section in the attributes chapter" do
    skip_without_repo()
    doc = chapter("03_csharp_attributes") <> chapter("04_versions_and_migrations")

    # Attributes that are implementation detail or only meaningful inside another one's section.
    internal = ~w(ExoJson)

    for name <- Map.keys(attribute_properties()), name not in internal do
      assert doc =~ "[#{name}", "[#{name}] is in Attributes.cs but not in the guide"
    end
  end

  @tag :repo
  test "every settable property of the main attributes is in its table, and no table lists one that is gone" do
    skip_without_repo()
    doc = chapter("03_csharp_attributes")
    properties = attribute_properties()

    # attribute => the heading its property table sits under
    sections = %{"ExoAction" => "## [ExoAction]", "ExoResource" => "### [ExoResource] Parameters", "ExoColumn" => "### [ExoColumn] Parameters"}

    for {attr, heading} <- sections do
      [_, rest] = String.split(doc, heading, parts: 2)
      # the section runs to the next heading of the same or a higher level
      level = heading |> String.split(" ") |> hd() |> String.length()
      table = rest |> String.split(~r/\n\#{1,#{level}} /, parts: 2) |> hd()
      documented = ~r/^\|\s*`?(\w+)`?[^|]*\|/m |> Regex.scan(table) |> Enum.map(&(&1 |> List.last() |> String.downcase())) |> MapSet.new()
      actual = properties[attr] |> Enum.map(&String.downcase/1) |> MapSet.new()

      missing = MapSet.difference(actual, documented) |> Enum.sort()
      stale = MapSet.difference(documented, actual) |> MapSet.difference(MapSet.new(~w(property type name))) |> Enum.sort()

      assert missing == [], "#{attr}: properties missing from the guide: #{inspect(missing)}"
      assert stale == [], "#{attr}: the guide documents properties that no longer exist: #{inspect(stale)}"
    end
  end

  test "every standard extension on disk is described in the standard extensions chapter" do
    skip_without_repo()
    doc = chapter("05_standard_extensions")

    for dir <- Path.wildcard(Path.join(@repo, "extensions/exoforge_std_*")), File.dir?(dir) do
      name = Path.basename(dir)
      assert doc =~ name, "#{name} ships with the server but is not in the standard extensions chapter"
    end
  end

  test "every `exo <command>` the guide mentions exists in the CLI" do
    skip_without_repo()
    cli = File.read!(@cli)

    for %{id: id, content: content} <- Docs.load_all_chapters(),
        [_, verb] <- Regex.scan(~r/`exo ([a-z][a-z\-]+)/, content) do
      assert cli =~ ~s("#{verb}"), "#{id} mentions `exo #{verb}`, which the CLI does not have"
    end
  end

  test "every guide: link points at a page and a heading that exist" do
    pages = Pages.all()

    for %{id: id, kind: :chapter, content: content} <- pages,
        [_, target] <- Regex.scan(~r/\]\(guide:([^)]+)\)/, content) do
      {page_id, anchor} =
        case String.split(target, "#", parts: 2) do
          [page, anchor] -> {page, anchor}
          [page] -> {page, nil}
        end

      page = Enum.find(pages, &(&1.id == page_id))
      assert page, "#{id} links to guide:#{page_id}, which is not a page"

      if anchor && page.kind == :chapter do
        ids = Enum.map(Pages.toc(page.content), fn {_, _, heading} -> heading end)
        assert anchor in ids, "#{id} links to #{page_id}##{anchor}, but that page has no such heading (has #{inspect(ids)})"
      end
    end
  end

  test "no chapter is left without a group, an icon and a summary for the navigation" do
    for %{id: id, group: group, icon: icon, summary: summary} <- Docs.load_all_chapters() do
      assert group != "Guide", "#{id} has no `group:` in its front matter"
      assert Exoforge.Std.Docs.Icons.path(String.to_atom(icon)), "#{id} names an icon the Studio does not have: #{icon}"
      assert summary != "", "#{id} has no `summary:` in its front matter"
    end
  end

  test "headings of a page have unique ids so links and the table of contents are unambiguous" do
    for %{id: id, kind: :chapter, content: content} <- Pages.all() do
      ids = Enum.map(Pages.toc(content), fn {_, _, heading} -> heading end)
      assert ids == Enum.uniq(ids), "#{id} has two headings with the same id: #{inspect(ids -- Enum.uniq(ids))}"
    end

    assert Markdown.slugify("Two `code`") == "two-code"
  end

  # ---- the standard extensions' own pages ----

  @std_dirs Path.wildcard(Path.join(@repo, "extensions/exoforge_std_*"))

  defp overview(dir), do: Path.join(dir, "priv/docs/overview.md")

  test "every standard extension documents itself in its own docs folder" do
    skip_without_repo()

    for dir <- @std_dirs do
      path = overview(dir)
      assert File.exists?(path), "#{Path.basename(dir)} has no priv/docs/overview.md"

      text = File.read!(path)
      assert text =~ ~r/\A---\n(?:.*\n)*?summary: \S/, "#{Path.basename(dir)}: overview.md needs front matter with a summary"
      assert text =~ ~r/^# \S/m, "#{Path.basename(dir)}: overview.md needs a title"
    end
  end

  test "a standard extension's page builds its action and event tables from the code and names only settings the code reads" do
    skip_without_repo()

    sources =
      ["core/lib/**/*.ex", "extensions/*/lib/**/*.ex", "extensions/*/config/**/*.exs", "config/*.exs"]
      |> Enum.flat_map(&Path.wildcard(Path.join(@repo, &1)))
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    for dir <- @std_dirs, File.exists?(overview(dir)) do
      name = Path.basename(dir)
      text = File.read!(overview(dir))

      # the signatures are not typed into the page: a directive expands them from the contract at render time
      assert text =~ "{{actions}}" and text =~ "{{events}}", "#{name}: the page should use {{actions}} and {{events}} instead of a hand-written table"

      for [_, setting] <- Regex.scan(~r/`([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)`/, text) do
        assert sources =~ setting, "#{name}: the page mentions setting `#{setting}`, which the code never reads"
      end
    end
  end

  test "every error code the troubleshooting chapter explains exists in the code" do
    skip_without_repo()

    sources =
      ["core/lib/**/*.ex", "extensions/*/lib/**/*.ex", "sdk/csharp/**/*.cs"]
      |> Enum.flat_map(&Path.wildcard(Path.join(@repo, &1)))
      |> Enum.reject(&String.contains?(&1, ["/obj/", "/bin/"]))
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    for [_, codes] <- Regex.scan(~r/^\|\s*((?:`[a-z_]+`(?:,\s*)?)+)\s*\|/m, chapter("11_troubleshooting")),
        [_, code] <- Regex.scan(~r/`([a-z_]+)`/, codes) do
      assert sources =~ code, "11_troubleshooting explains `#{code}`, which no code mentions"
    end
  end

  defp skip_without_repo do
    unless File.exists?(@attributes), do: flunk("the repository sources were not found; run the drift tests from a checkout")
  end
end
