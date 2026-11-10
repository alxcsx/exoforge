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
  @css Path.expand("../priv/static/vendor/exoforge-studio.css", __DIR__)

  @sources Path.wildcard(Path.join(@dashboard_lib, "**/*.ex")) ++
             Path.wildcard(Path.join(@views_lib, "**/*.ex"))

  # Hues the standard retired. One hue, one name: primary / emerald / amber /
  # red / blue. Anything else renders as a second name for a colour we already
  # have, and picks up a different dark-mode tint.
  @alias_hues ~r/\b(?:bg|text|border|ring|from|to|via|divide|fill|stroke|shadow)-(?:purple|violet|indigo|sky|cyan|rose|yellow|green|pink|fuchsia)-\d/

  # A second dark-mode mechanism. The remap is the only one.
  @dark_variant ~r/\bdark:(?:hover:)?[a-z]/

  # Radius belongs to the component kind, not to the mood. Four values.
  @banned_radius ~r/\brounded-(?:2xl|3xl|md|sm)\b/

  # text-xs (12px) is the floor for anything a user reads; below that only
  # uppercase micro-labels, and never below 10px.
  @banned_type ~r/\btext-\[(?:8|9|13)px\]/

  # Brand colour is an accent, not a background wash.
  @gradients ~r/\bbg-gradient-/

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
    assert_violations(@gradients, "gradient background (use a flat surface and a border)")
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
end
