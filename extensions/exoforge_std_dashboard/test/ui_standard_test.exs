defmodule Exoforge.Std.Dashboard.UiStandardTest do
  @moduledoc """
  Freezes the Studio UI conventions from `docs/design/ui-standard.md`.

  The dark theme is a remap: templates are authored in light-theme Tailwind
  classes and `exoforge-studio.css` re-colours them. That only holds while every
  class a template uses is on the list — a missing entry is a light box with
  light text, which is how the theme broke before. This test diffs the two sets
  and fails on the drift instead of leaving it for someone to notice in a
  screenshot.

  It is a grep, not a parser: the banned patterns below are exactly the ones the
  standard forbids, so a new violation is a one-line failure with a file:line.
  """
  use ExUnit.Case, async: true

  @dashboard_lib Path.expand("../lib", __DIR__)
  @views_lib Path.expand("../../exoforge_std_dashboard_views/lib", __DIR__)
  @docs_lib Path.expand("../../exoforge_std_docs/lib", __DIR__)
  @css Path.expand("../priv/static/vendor/exoforge-studio.css", __DIR__)

  # Every extension that renders Studio chrome. The docs extension is the third surface and had
  # drifted furthest (87 rounded-2xl, 36 dark: variants) because this test did not look at it.
  @sources Enum.flat_map([@dashboard_lib, @views_lib, @docs_lib], fn dir ->
             Path.wildcard(Path.join(dir, "**/*.ex"))
           end)

  # Hues the standard retired. One hue, one name: primary / emerald / amber /
  # red / blue. Anything else renders as a second name for a colour we already
  # have, and picks up a different dark-mode tint.
  @alias_hues ~r/\b(?:bg|text|border|ring|from|to|via|divide|fill|stroke|shadow)-(?:purple|violet|indigo|sky|cyan|teal|rose|yellow|green|pink|fuchsia)-\d/

  # A second dark-mode mechanism. The remap is the only one.
  @dark_variant ~r/\bdark:(?:hover:)?[a-z]/

  # Radius belongs to the component kind, not to the mood. Four values.
  @banned_radius ~r/\brounded-(?:2xl|3xl|md|sm)\b/

  # text-xs (12px) is the floor for anything a user reads; below that only
  # uppercase micro-labels, and never below 10px.
  @banned_type ~r/\btext-\[(?:8|9|13)px\]/

  # Brand colour is an accent, not a background wash.
  @gradients ~r/\bbg-gradient-/

  # Three-weight typographic hierarchy: 400 / 500 / 600 (no black/extrabold).
  @banned_weights ~r/\bfont-(?:black|extrabold)\b/

  test "templates use one hue name per colour" do
    assert_violations(
      @alias_hues,
      "retired hue alias (use primary / emerald / amber / red / blue)"
    )
  end

  test "templates do not carry dark: variants" do
    assert_violations(
      @dark_variant,
      "dark: variant (the remap in exoforge-studio.css owns dark mode)"
    )
  end

  test "templates use the four-value radius scale" do
    assert_violations(
      @banned_radius,
      "banned radius (rounded | rounded-lg | rounded-xl | rounded-full)"
    )
  end

  test "templates respect the type floor" do
    assert_violations(@banned_type, "text below 10px (use text-[10px] or text-xs)")
  end

  test "templates do not use gradient backgrounds" do
    assert_violations(
      @gradients,
      "gradient background (hero highlights use .exo-hero / .exo-hero-accent from the CSS)"
    )
  end

  test "templates respect the three-weight typography scale" do
    assert_violations(
      @banned_weights,
      "heavy font weight (use font-normal, font-medium, or font-semibold)"
    )
  end

  # Emoji in Studio-owned chrome (nav, modals, buttons, stat tiles, headers) — an SVG from the
  # icon set instead. Emoji stay where the content is user- or extension-generated: the
  # presenter's extension identity icons, manifest-declared icons, and the fallbacks an
  # extension's own author would have picked.
  @emoji ~r/[\x{1F000}-\x{1FAFF}\x{2300}-\x{23FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}\x{200D}]/u
  # Keyboard/typographic glyphs that belong in chrome: ✓ ✕ ✎ ✦ ➔ ⌘ ⏎ ← → ↑ ↓ ▸ ▾ · —
  @text_glyphs ~r/[✓✕✎✦➔⌘⏎←→↑↓▸▾·—]/u

  test "studio chrome uses the icon set, emoji only on extension surfaces" do
    violations =
      for path <- @sources,
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          stripped = String.replace(line, @text_glyphs, ""),
          Regex.match?(@emoji, stripped),
          not allowed_emoji?(path, line),
          do: "#{Path.basename(path)}:#{number} emoji in studio chrome (use Components.icon / Icons.studio_icon)\n    #{String.trim(line)}"

    assert violations == [],
           "emoji in studio chrome\n\n  " <> Enum.join(Enum.uniq(violations), "\n  ")
  end

  # An emoji in an icon *data* field is identity — an extension's own manifest icon, a service's
  # declared glyph, an architecture node's symbol. An emoji in markup is chrome and belongs to the
  # icon set. That is the whole distinction; it needs no per-file exceptions.
  @icon_data ~r/(?:icon:|Icon\s*=)/

  defp allowed_emoji?(path, line) do
    # the presenter's whole job is extension identity icons
    Path.basename(path) == "extension_presenter.ex" or
      Regex.match?(@icon_data, line) or
      String.contains?(line, [
        "dashboard_view[",
        "|| \"🧩\"",
        "nodeIcon",
        "service, :icon",
        "raw_icon"
      ])
  end

  # The three UI extensions are compile-independent, so the icon map is data copied three times.
  # Copied data drifts; comparing the literals makes a divergence fail here instead of showing up
  # as a missing icon in one surface.
  test "the three copies of the icon set have not drifted" do
    sets =
      Enum.flat_map([@dashboard_lib, @views_lib, @docs_lib], fn dir ->
        dir
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.flat_map(fn file ->
          case Regex.run(~r/@icons %\{(.*?)\n  \}/s, File.read!(file)) do
            [_, body] -> [{Path.basename(file), String.replace(body, ~r/\s+/, " ")}]
            nil -> []
          end
        end)
      end)

    assert length(sets) == 3,
           "expected three icon sets, found #{inspect(Enum.map(sets, &elem(&1, 0)))}"

    [{first, reference} | rest] = sets

    for {name, body} <- rest do
      assert body == reference,
             "#{name} icon set differs from #{first} — the copies must stay identical"
    end
  end

  test "every tinted background a template uses is remapped for the dark theme" do
    remapped = remapped_classes()

    missing =
      class_tokens()
      |> Enum.filter(&tinted_background?/1)
      |> Enum.reject(&MapSet.member?(remapped, &1))
      |> Enum.uniq()
      |> Enum.sort()

    assert missing == [],
           """
           Tinted backgrounds with no dark-theme entry in exoforge-studio.css.
           Each one renders as a near-white box with light text on the dark theme:

             #{Enum.join(missing, "\n  ")}

           Add the exact class (alpha step included) to the remap in
           extensions/exoforge_std_dashboard/priv/static/vendor/exoforge-studio.css.
           """
  end

  test "code-copy buttons stay visible and ringed for keyboard focus" do
    path = Path.join(@docs_lib, "exoforge/std/docs/view.ex")

    violations =
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> String.contains?(line, "exoCopyCode") end)
      |> Enum.reject(fn {line, _} ->
        String.contains?(line, "focus-visible:opacity-100") and
          String.contains?(line, "focus-visible:ring-2")
      end)
      |> Enum.map(fn {line, number} -> "view.ex:#{number}\n    #{String.trim(line)}" end)

    assert violations == [],
           "code-copy buttons need focus-visible visibility and a ring\n\n  " <>
             Enum.join(violations, "\n  ")
  end

  test "scroll motion is gated behind reduced-motion preference" do
    ungated = ~r/window\.scrollTo\(\{top: 0, behavior: 'smooth'\}\)|scrollIntoView\(\{ behavior: ['"]smooth/

    violations =
      for path <- @sources,
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(ungated, line),
          do: "#{Path.basename(path)}:#{number}\n    #{String.trim(line)}"

    assert violations == [],
           "smooth scrolling must use the reduced-motion helper\n\n  " <>
             Enum.join(Enum.uniq(violations), "\n  ")
  end

  defp assert_violations(pattern, description) do
    violations =
      for path <- @sources,
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(pattern, line),
          do: "#{Path.basename(path)}:#{number} #{description}\n    #{String.trim(line)}"

    assert violations == [],
           "#{description}\n\n  " <> Enum.join(Enum.uniq(violations), "\n  ")
  end

  # bg-{hue}-{tint} or any bg-{hue}-{step}/{alpha} — the two shapes that depend
  # on the remap. Solid fills (bg-emerald-500, bg-red-600) are theme-neutral and
  # deliberately absent from it.
  defp tinted_background?(token) do
    case Regex.run(
           ~r/^(?:(?:[a-z]+):)*bg-(?:primary|emerald|amber|red|blue)-(\d+)(\/\d+)?$/,
           token
         ) do
      [_, step] -> step in ~w(50 100 200 300)
      [_, _step, _alpha] -> true
      nil -> false
    end
  end

  defp class_tokens do
    Enum.flat_map(@sources, fn path ->
      path
      |> File.read!()
      |> then(&Regex.scan(~r/class=(?:"([^"]*)"|\{"([^"]*)"\})/, &1))
      |> Enum.flat_map(fn [_ | captures] -> Enum.reject(captures, &(&1 == "")) end)
      |> Enum.flat_map(&String.split(&1, ~r/[\s"'#{}]+/))
      |> Enum.reject(&(&1 == ""))
    end)
  end

  defp remapped_classes do
    @css
    |> File.read!()
    |> then(&Regex.scan(~r/html:not\(\.light\)\s+(\.[^\s,{]+)/, &1))
    |> Enum.map(fn [_, selector] ->
      selector
      |> String.replace(~r/:(?:hover|focus|focus-visible|disabled)$/, "")
      |> String.replace("\\/", "/")
      |> String.replace("\\:", ":")
      |> String.trim_leading(".")
    end)
    |> MapSet.new()
  end

  test "every icon a template names exists in the icon set, so a missing one never shows its name as text" do
    root = Path.expand("../..", __DIR__)

    set =
      Regex.run(~r/@icons %\{(.*?)\n  \}/s, File.read!(Path.join(root, "exoforge_std_dashboard/lib/exoforge/std/dashboard/components.ex")))
      |> List.last()
      |> then(&Regex.scan(~r/^\s{4}(\w+):/m, &1))
      |> Enum.map(&List.last/1)
      |> MapSet.new()

    used =
      for dir <- ~w(exoforge_std_dashboard exoforge_std_dashboard_views exoforge_std_docs exoforge_std_file_bucket),
          file <- Path.wildcard(Path.join(root, dir <> "/lib/**/*.ex")),
          [_, name] <- Regex.scan(~r/<\.studio_icon icon="(\w+)"/, File.read!(file)),
          uniq: true,
          do: name

    assert MapSet.difference(MapSet.new(used), set) |> Enum.sort() == []
  end
end
