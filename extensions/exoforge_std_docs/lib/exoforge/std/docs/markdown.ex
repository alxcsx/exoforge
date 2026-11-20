defmodule Exoforge.Std.Docs.Markdown do
  @moduledoc """
  Lightweight, dependency-free Markdown renderer for Exoforge documentation.
  Supports headings, fenced code blocks with syntax highlighting, lists,
  tables, links, images, and GitHub-style callout alerts.
  """

  # Raw-HTML sibling of Icons.studio_icon/1 for the heredocs this renderer emits.
  defp icon(name, class \\ "w-3.5 h-3.5") do
    case Exoforge.Std.Docs.Icons.path(name) do
      nil ->
        ""

      path ->
        ~s(<svg class="#{class}" fill="none" viewBox="0 0 24 24" stroke="currentColor" ) <>
          ~s(stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) <>
          ~s(<path d="#{path}" /></svg>)
    end
  end

  def to_html(markdown) when is_binary(markdown) do
    {text, blocks} = extract_tab_blocks(markdown)
    lines = String.split(text, ~r/\r?\n/)
    {html_blocks, _state} = parse_lines(lines, [], :normal)

    html_blocks
    |> Enum.reverse()
    |> Enum.join("\n")
    |> put_blocks(blocks)
    |> Phoenix.HTML.raw()
  end

  def to_html(_), do: Phoenix.HTML.raw("")

  # ---- COMPONENTS: tabs ----
  #
  #     :::tabs
  #     :::tab Callback style
  #     (any Markdown: text, tables, code)
  #     :::tab Async style
  #     (...)
  #     :::end
  #
  # Way A and way B of doing one thing are tabs, not two long blocks one after the other. The block is lifted out
  # before parsing (each tab body is rendered by this same module) and put back where its token stands.

  defp extract_tab_blocks(markdown) do
    {lines, blocks, _current} =
      markdown
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({[], [], nil}, fn line, {out, blocks, current} ->
        trimmed = String.trim(line)

        cond do
          current == nil and trimmed == ":::tabs" ->
            {out, blocks, []}

          current != nil and trimmed == ":::end" ->
            token = "EXOBLOCK#{length(blocks)}END"
            {[token, "" | out], [{token, render_tabs(Enum.reverse(current))} | blocks], nil}

          current != nil ->
            {out, blocks, [line | current]}

          true ->
            {[line | out], blocks, nil}
        end
      end)

    {lines |> Enum.reverse() |> Enum.join("\n"), blocks}
  end

  defp put_blocks(html, blocks) do
    Enum.reduce(blocks, html, fn {token, rendered}, acc ->
      String.replace(acc, ~s(<p class="text-sm text-gray-700 leading-7 my-3">#{token}</p>), rendered)
    end)
  end

  defp render_tabs(lines) do
    tabs =
      lines
      |> Enum.chunk_while(
        nil,
        fn line, acc ->
          case Regex.run(~r/^\s*:::tab\s+(.+?)\s*$/, line) do
            [_, title] -> {:cont, acc, {title, []}}
            _ when acc == nil -> {:cont, nil}
            _ -> {:cont, {elem(acc, 0), [line | elem(acc, 1)]}}
          end
        end,
        fn acc -> {:cont, acc, nil} end
      )
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn {title, body} -> {title, body |> Enum.reverse() |> Enum.join("\n")} end)

    buttons =
      for {{title, _}, index} <- Enum.with_index(tabs) do
        active = index == 0

        ~s(<button type="button" role="tab" data-tab="#{index}" aria-selected="#{active}" onclick="#{tab_script()}" ) <>
          ~s(class="px-3 py-1.5 rounded-t-lg text-xs font-semibold transition-colors #{tab_classes(active)}">#{Plug.HTML.html_escape(title)}</button>)
      end

    panes =
      for {{title, body}, index} <- Enum.with_index(tabs) do
        hidden = if index == 0, do: "", else: " hidden"

        ~s(<div role="tabpanel" data-pane="#{index}" class="px-4 py-2#{hidden} print:block">) <>
          ~s(<p class="hidden print:block text-xs font-semibold text-gray-500 mt-2">#{Plug.HTML.html_escape(title)}</p>) <>
          (body |> to_html() |> Phoenix.HTML.safe_to_string()) <> "</div>"
      end

    ~s(<div data-exo-tabs class="my-4 rounded-xl border border-gray-200 bg-white overflow-hidden print:border-gray-300">) <>
      ~s(<div role="tablist" class="print:hidden flex flex-wrap gap-1 border-b border-gray-200 bg-gray-50 px-2 pt-2">#{Enum.join(buttons)}</div>) <>
      Enum.join(panes) <> "</div>"
  end

  defp tab_classes(true), do: "bg-white text-primary-700 border border-gray-200 border-b-white -mb-px"
  defp tab_classes(false), do: "text-gray-500 hover:text-gray-900 border border-transparent"

  # Switches the tab in the browser: no round trip, and nothing to wire up on the server.
  defp tab_script do
    "(function(b){var g=b.closest('[data-exo-tabs]');" <>
      "g.querySelectorAll('[role=tab]').forEach(function(t){var on=t===b;t.setAttribute('aria-selected',on);" <>
      "t.classList.toggle('bg-white',on);t.classList.toggle('text-primary-700',on);t.classList.toggle('border-gray-200',on);" <>
      "t.classList.toggle('-mb-px',on);t.classList.toggle('text-gray-500',!on);t.classList.toggle('border-transparent',!on)});" <>
      "g.querySelectorAll('[data-pane]').forEach(function(p){p.classList.toggle('hidden',p.getAttribute('data-pane')!==b.getAttribute('data-tab'))})})(this)"
  end

  # ---- COMPONENTS: diagrams ----
  #
  # An SVG that lives next to the chapters is inlined, so it takes the page's text size and, through the Studio's
  # `--exo-*` colour variables, both themes. The name is a word, never a path.
  defp render_diagram(alt, name) do
    path = Path.join([Exoforge.Std.Docs.docs_dir(), "diagrams", name <> ".svg"])

    case File.read(path) do
      {:ok, svg} ->
        svg = String.replace(svg, "<svg ", ~s(<svg role="img" aria-label="#{Plug.HTML.html_escape(alt)}" class="w-full h-auto mx-auto max-w-4xl" ), global: false)

        ~s(<figure class="my-6 rounded-xl border border-gray-200 bg-white p-4 overflow-x-auto print:border-gray-300 print:break-inside-avoid">) <>
          svg <> ~s(<figcaption class="mt-3 text-center text-xs text-gray-500">#{inline_format(alt)}</figcaption></figure>)

      _ ->
        ~s(<p class="text-xs text-red-600">Missing diagram: #{Plug.HTML.html_escape(name)}</p>)
    end
  end

  # ---- LINE PARSER STATE MACHINE ----

  defp parse_lines([], acc, :normal), do: {acc, :normal}

  defp parse_lines([], acc, {:code_block, lang, code_lines}) do
    # Unclosed code block - close it
    rendered = render_code_block(lang, Enum.reverse(code_lines))
    {[rendered | acc], :normal}
  end

  defp parse_lines([], acc, {:blockquote, lines}) do
    rendered = render_blockquote(Enum.reverse(lines))
    {[rendered | acc], :normal}
  end

  defp parse_lines([], acc, {:list, type, items}) do
    rendered = render_list(type, Enum.reverse(items))
    {[rendered | acc], :normal}
  end

  defp parse_lines([], acc, {:table, rows}) do
    rendered = render_table(Enum.reverse(rows))
    {[rendered | acc], :normal}
  end

  # Inside Fenced Code Block
  defp parse_lines([line | rest], acc, {:code_block, lang, code_lines}) do
    if String.starts_with?(String.trim(line), "```") do
      rendered = render_code_block(lang, Enum.reverse(code_lines))
      parse_lines(rest, [rendered | acc], :normal)
    else
      parse_lines(rest, acc, {:code_block, lang, [line | code_lines]})
    end
  end

  # Start of Fenced Code Block
  defp parse_lines([line | rest], acc, :normal) when binary_part(line, 0, 3) == "```" do
    lang = String.trim_leading(line, "`") |> String.trim()
    parse_lines(rest, acc, {:code_block, lang, []})
  end

  # Blockquote / Alert
  defp parse_lines([line | rest], acc, {:blockquote, lines}) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, ">") do
      content = String.replace_prefix(trimmed, ">", "") |> String.trim()
      parse_lines(rest, acc, {:blockquote, [content | lines]})
    else
      rendered = render_blockquote(Enum.reverse(lines))
      parse_lines([line | rest], [rendered | acc], :normal)
    end
  end

  defp parse_lines([line | rest], acc, :normal) do
    trimmed = String.trim(line)

    cond do
      # Fenced code block start (handle if line starts with whitespace)
      String.starts_with?(trimmed, "```") ->
        lang = String.trim_leading(trimmed, "`") |> String.trim()
        parse_lines(rest, acc, {:code_block, lang, []})

      # Headings
      String.starts_with?(trimmed, "#") ->
        parse_heading(trimmed, rest, acc)

      # Blockquotes & Alerts
      String.starts_with?(trimmed, ">") ->
        content = String.replace_prefix(trimmed, ">", "") |> String.trim()
        parse_lines(rest, acc, {:blockquote, [content]})

      # Unordered lists
      Regex.match?(~r/^[-*+]\s+/, trimmed) ->
        item = Regex.replace(~r/^[-*+]\s+/, trimmed, "")
        parse_list_lines(rest, [item], :ul, acc)

      # Ordered lists
      Regex.match?(~r/^\d+\.\s+/, trimmed) ->
        item = Regex.replace(~r/^\d+\.\s+/, trimmed, "")
        parse_list_lines(rest, [item], :ol, acc)

      # Tables
      String.starts_with?(trimmed, "|") and String.ends_with?(trimmed, "|") ->
        parse_table_lines(rest, [trimmed], acc)

      # A diagram: `![What it shows](diagram:name)` inlines priv/guide/diagrams/name.svg
      Regex.match?(~r/^!\[[^\]]*\]\(diagram:[\w-]+\)$/, trimmed) ->
        [_, alt, name] = Regex.run(~r/^!\[([^\]]*)\]\(diagram:([\w-]+)\)$/, trimmed)
        parse_lines(rest, [render_diagram(alt, name) | acc], :normal)

      # Collapsible sections: <details> / <summary>Title</summary> / </details> (progressive disclosure)
      String.starts_with?(trimmed, "<details") ->
        d = "<details class=\"my-4 rounded-xl border border-gray-200 bg-white px-4 py-2 print:border-gray-300\">"
        parse_lines(rest, [d | acc], :normal)

      String.starts_with?(trimmed, "<summary>") ->
        title = trimmed |> String.replace_prefix("<summary>", "") |> String.replace_suffix("</summary>", "")
        sm = "<summary class=\"cursor-pointer text-sm font-semibold text-gray-900 py-1\">#{inline_format(title)}</summary>"
        parse_lines(rest, [sm | acc], :normal)

      trimmed == "</details>" ->
        parse_lines(rest, ["</details>" | acc], :normal)

      # Horizontal rules
      trimmed in ["---", "***", "___"] ->
        hr = "<hr class=\"my-6 border-gray-200 print:border-gray-400\" />"
        parse_lines(rest, [hr | acc], :normal)

      # Empty line
      trimmed == "" ->
        parse_lines(rest, acc, :normal)

      # Regular paragraph
      true ->
        p = "<p class=\"text-sm text-gray-700 leading-7 my-3\">#{inline_format(trimmed)}</p>"
        parse_lines(rest, [p | acc], :normal)
    end
  end

  # ---- LIST PARSING ----

  defp parse_list_lines([line | rest], items, type, acc) do
    trimmed = String.trim(line)
    is_ul = Regex.match?(~r/^[-*+]\s+/, trimmed)
    is_ol = Regex.match?(~r/^\d+\.\s+/, trimmed)

    cond do
      type == :ul and is_ul ->
        item = Regex.replace(~r/^[-*+]\s+/, trimmed, "")
        parse_list_lines(rest, [item | items], :ul, acc)

      type == :ol and is_ol ->
        item = Regex.replace(~r/^\d+\.\s+/, trimmed, "")
        parse_list_lines(rest, [item | items], :ol, acc)

      trimmed == "" ->
        # List might continue or end
        case rest do
          [next | next_rest] ->
            next_trimmed = String.trim(next)

            if (type == :ul and Regex.match?(~r/^[-*+]\s+/, next_trimmed)) or
                 (type == :ol and Regex.match?(~r/^\d+\.\s+/, next_trimmed)) do
              parse_list_lines(next_rest, ["" | items], type, acc)
            else
              rendered = render_list(type, Enum.reverse(items))
              parse_lines([line | rest], [rendered | acc], :normal)
            end

          [] ->
            rendered = render_list(type, Enum.reverse(items))
            parse_lines([], [rendered | acc], :normal)
        end

      true ->
        rendered = render_list(type, Enum.reverse(items))
        parse_lines([line | rest], [rendered | acc], :normal)
    end
  end

  defp parse_list_lines([], items, type, acc) do
    rendered = render_list(type, Enum.reverse(items))
    {[rendered | acc], :normal}
  end

  # ---- TABLE PARSING ----

  defp parse_table_lines([line | rest], rows, acc) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "|") and String.ends_with?(trimmed, "|") do
      parse_table_lines(rest, [trimmed | rows], acc)
    else
      rendered = render_table(Enum.reverse(rows))
      parse_lines([line | rest], [rendered | acc], :normal)
    end
  end

  defp parse_table_lines([], rows, acc) do
    rendered = render_table(Enum.reverse(rows))
    {[rendered | acc], :normal}
  end

  # ---- BLOCK RENDERERS ----

  defp parse_heading(trimmed, rest, acc) do
    level = count_leading_hashes(trimmed, 0)
    text = String.trim_leading(trimmed, "#") |> String.trim()
    id = slugify(text)

    classes =
      case level do
        1 -> "text-3xl font-semibold text-gray-900 tracking-tight mt-2 mb-4"
        2 -> "text-xl font-semibold text-gray-900 tracking-tight mt-10 mb-3 pb-2 border-b border-gray-100 scroll-mt-4"
        3 -> "text-base font-semibold text-gray-900 tracking-tight mt-6 mb-2"
        4 -> "text-xs font-bold text-gray-700 uppercase tracking-wider mt-5 mb-1"
        _ -> "text-xs font-semibold text-gray-600 mt-2 mb-1"
      end

    tag = "h#{min(max(level, 1), 6)}"
    h = "<#{tag} id=\"#{id}\" class=\"#{classes}\">#{inline_format(text)}</#{tag}>"
    parse_lines(rest, [h | acc], :normal)
  end

  defp count_leading_hashes(<<?#, rest::binary>>, count), do: count_leading_hashes(rest, count + 1)
  defp count_leading_hashes(_, count), do: count

  # A snippet copied from inside a class keeps the class's indentation; show it flush left.
  defp dedent(lines) do
    indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn line -> byte_size(line) - byte_size(String.trim_leading(line)) end)
      |> Enum.min(fn -> 0 end)

    Enum.map(lines, fn line -> if String.trim(line) == "", do: "", else: binary_part(line, indent, byte_size(line) - indent) end)
  end

  defp render_code_block(lang, lines) do
    code = lines |> dedent() |> Enum.join("\n")
    lang_clean = String.downcase(to_string(lang || ""))

    highlighted =
      case lang_clean do
        l when l in ["c#", "cs", "csharp"] -> highlight_csharp(code)
        l when l in ["elixir", "ex", "exs"] -> highlight_elixir(code)
        l when l in ["json"] -> highlight_json(code)
        _ -> Plug.HTML.html_escape(code)
      end

    lang_badge =
      if lang_clean != "" do
        "<span class=\"absolute top-2.5 right-3 text-[10px] font-mono text-gray-400 font-bold uppercase select-none\">#{Plug.HTML.html_escape(lang_clean)}</span>"
      else
        ""
      end

    copy_btn = """
    <button type=\"button\" onclick=\"window.exoCopyCode && window.exoCopyCode(this)\" class=\"absolute top-2 right-14 opacity-0 group-hover:opacity-100 focus-visible:opacity-100 transition-opacity text-[10px] font-mono font-medium px-2 py-0.5 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700 flex items-center gap-1 cursor-pointer print:hidden shadow-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-400 focus-visible:ring-offset-2 focus-visible:ring-offset-gray-950\" title=\"Copy code\"><span class=\"copy-icon\">#{icon("clipboard")}</span><span class=\"copy-text\">Copy</span></button>
    """

    """
    <div class="relative group my-3 min-w-0 max-w-full">
      #{copy_btn}
      #{lang_badge}
      <pre class="bg-gray-950 text-gray-200 p-4 rounded-xl font-mono text-xs md:text-xs overflow-x-auto max-w-full border border-gray-800 leading-relaxed shadow-sm print:bg-gray-100 print:text-gray-900 print:border-gray-300"><code>#{highlighted}</code></pre>
    </div>
    """
  end

  defp render_blockquote(lines) do
    first = hd(lines)

    {alert_type, content_lines} =
      cond do
        String.starts_with?(first, "[!NOTE]") ->
          {:note, [String.replace_prefix(first, "[!NOTE]", "") | tl(lines)]}

        String.starts_with?(first, "[!TIP]") ->
          {:tip, [String.replace_prefix(first, "[!TIP]", "") | tl(lines)]}

        String.starts_with?(first, "[!IMPORTANT]") ->
          {:important, [String.replace_prefix(first, "[!IMPORTANT]", "") | tl(lines)]}

        String.starts_with?(first, "[!WARNING]") ->
          {:warning, [String.replace_prefix(first, "[!WARNING]", "") | tl(lines)]}

        String.starts_with?(first, "[!CAUTION]") ->
          {:caution, [String.replace_prefix(first, "[!CAUTION]", "") | tl(lines)]}

        true ->
          {:quote, lines}
      end

    body =
      content_lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&inline_format/1)
      |> Enum.join("<br/>")

    case alert_type do
      :note ->
        """
        <div class="p-4 my-3 rounded-xl bg-blue-50 border border-blue-200/80 text-blue-900 text-sm leading-6 space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-blue-800 text-[11px] uppercase tracking-wider">
            #{icon("book")} <span>Note</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :tip ->
        """
        <div class="p-4 my-3 rounded-xl bg-emerald-50 border border-emerald-200/80 text-emerald-900 text-sm leading-6 space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-emerald-800 text-[11px] uppercase tracking-wider">
            #{icon("target")} <span>Tip</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :important ->
        """
        <div class="p-4 my-3 rounded-xl bg-primary-50 border border-primary-200/80 text-primary-900 text-sm leading-6 space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-primary-800 text-[11px] uppercase tracking-wider">
            #{icon("target")} <span>Important</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :warning ->
        """
        <div class="p-4 my-3 rounded-xl bg-amber-50 border border-amber-200/80 text-amber-900 text-sm leading-6 space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-amber-800 text-[11px] uppercase tracking-wider">
            #{icon("alert")} <span>Warning</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :caution ->
        """
        <div class="p-4 my-3 rounded-xl exo-callout-danger text-sm leading-6 space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-[11px] uppercase tracking-wider">
            #{icon("alert")} <span>Caution</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :quote ->
        """
        <blockquote class="border-l-4 border-primary-500 bg-gray-50 pl-4 py-2 my-3 text-sm italic text-gray-700 rounded-r-xl">
          #{body}
        </blockquote>
        """
    end
  end

  defp render_list(:ul, items) do
    lis =
      items
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn it ->
        "<li class=\"leading-relaxed\">#{inline_format(it)}</li>"
      end)
      |> Enum.join("\n")

    """
    <ul class="list-disc list-outside space-y-1.5 text-sm leading-7 text-gray-700 my-3 pl-6">
      #{lis}
    </ul>
    """
  end

  defp render_list(:ol, items) do
    lis =
      items
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn it ->
        "<li class=\"leading-relaxed\">#{inline_format(it)}</li>"
      end)
      |> Enum.join("\n")

    """
    <ol class="list-decimal list-outside space-y-1.5 text-sm leading-7 text-gray-700 my-3 pl-6">
      #{lis}
    </ol>
    """
  end

  defp render_table(raw_rows) do
    # Remove delimiter rows like |---|---|
    parsed_rows =
      raw_rows
      |> Enum.map(fn r ->
        r
        |> String.trim_leading("|")
        |> String.trim_trailing("|")
        |> String.split("|")
        |> Enum.map(&String.trim/1)
      end)

    case parsed_rows do
      [] ->
        ""

      [header | data_rows] ->
        # Filter out |---|---| separator row if present
        filtered_data =
          Enum.reject(data_rows, fn cells ->
            Enum.all?(cells, &Regex.match?(~r/^:?-+:?$/, &1))
          end)

        th_html =
          header
          |> Enum.map(fn cell ->
            "<th class=\"py-2 px-3 font-semibold text-gray-700\">#{inline_format(cell)}</th>"
          end)
          |> Enum.join("")

        tr_html =
          filtered_data
          |> Enum.map(fn row ->
            tds =
              row
              |> Enum.map(fn cell ->
                "<td class=\"py-2 px-3 text-gray-600\">#{inline_format(cell)}</td>"
              end)
              |> Enum.join("")

            "<tr class=\"hover:bg-gray-50/50\">#{tds}</tr>"
          end)
          |> Enum.join("\n")

        table = """
        <div class="overflow-x-auto rounded-xl border border-gray-200">
          <table class="w-full text-left text-xs bg-white">
            <thead class="bg-gray-50 border-b border-gray-200 text-gray-600 uppercase text-[10px]">
              <tr>#{th_html}</tr>
            </thead>
            <tbody class="divide-y divide-gray-100 text-xs leading-5 text-gray-700">
              #{tr_html}
            </tbody>
          </table>
        </div>
        """

        # A wide or long table gets a button that shows it full width in a dialog.
        if length(header) > 2 or length(filtered_data) > 5 do
          ~s(<div data-exo-table class="mt-6 mb-3 relative"><button type="button" onclick="#{expand_script()}" aria-label="Show this table full width" ) <>
            ~s(class="print:hidden absolute right-2 -top-2.5 z-10 inline-flex items-center gap-1 rounded-full border border-gray-200 bg-white px-2 py-0.5 text-[10px] font-semibold text-gray-500 hover:text-primary-700 shadow-sm">) <>
            ~s(<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 9V4h5 M20 9V4h-5 M4 15v5h5 M20 15v5h-5" /></svg>Expand</button>) <>
            table <> "</div>"
        else
          ~s(<div class="my-3">) <> table <> "</div>"
        end
    end
  end

  # ---- INLINE FORMATTER ----

  # Code spans are lifted out first (they escape their own content), everything else is escaped, then
  # links, bold and italic are applied to the escaped text, and the code spans go back in. Without the
  # escape a heading such as `[ExoDependency<T>]` produced a real `<T>` element.
  # Opens a copy of the table in a native <dialog>, as wide as the window. Styled by `.exo-table-dialog` in the Studio's CSS.
  defp expand_script do
    "(function(b){var t=b.closest('[data-exo-table]').querySelector('table');var d=document.createElement('dialog');" <>
      "d.className='exo-table-dialog';d.innerHTML='<div class=\\'exo-table-dialog-bar\\'><button type=\\'button\\'>Close</button></div><div class=\\'exo-table-dialog-body\\'></div>';" <>
      "d.querySelector('.exo-table-dialog-body').appendChild(t.cloneNode(true));" <>
      "d.addEventListener('click',function(e){if(e.target===d||e.target.closest('button'))d.close()});" <>
      "d.addEventListener('close',function(){d.remove()});document.body.appendChild(d);d.showModal()})(this)"
  end

  defp inline_format(text) do
    {text, codes} = stash_code(text)

    text
    |> Plug.HTML.html_escape()
    |> IO.iodata_to_binary()
    |> render_images()
    |> render_links()
    |> render_bold()
    |> render_italic()
    |> restore_code(codes)
  end

  defp stash_code(text) do
    {replaced, codes} =
      Regex.split(~r/`([^`]+)`/, text, include_captures: true)
      |> Enum.map_reduce([], fn part, acc ->
        case Regex.run(~r/^`([^`]+)`$/, part) do
          [_, code] -> {"\u0000#{length(acc)}\u0000", [code | acc]}
          _ -> {part, acc}
        end
      end)

    {Enum.join(replaced), Enum.reverse(codes)}
  end

  defp restore_code(text, codes) do
    codes
    |> Enum.with_index()
    |> Enum.reduce(text, fn {code, index}, acc ->
      String.replace(acc, "\u0000#{index}\u0000", render_code_span(code))
    end)
  end

  defp render_code_span(code) do
    # a short value ("0.1.0", `null`) stays on one line even in a narrow table cell
    nowrap = if String.length(code) <= 24, do: "whitespace-nowrap ", else: ""
    "<code class=\"#{nowrap}font-mono text-primary-700 bg-primary-50 px-1.5 py-0.5 rounded text-[11px] border border-primary-200/60 font-semibold\">#{Plug.HTML.html_escape(code)}</code>"
  end

  defp render_images(text) do
    Regex.replace(~r/!\[([^\]]*)\]\(([^)]+)\)/, text, fn _match, alt, url ->
      "<img src=\"#{url}\" alt=\"#{alt}\" class=\"max-w-full rounded-xl shadow-sm border border-gray-200 my-3\" />"
    end)
  end

  defp render_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, text, fn _match, label, url ->
      {href, target} = link_target(url)

      "<a href=\"#{href}\"#{target} class=\"text-primary-600 hover:text-primary-800 underline font-medium\">#{label}</a>"
    end)
  end

  @patch " data-phx-link=\"patch\" data-phx-link-state=\"push\""

  defp catalog_link(kind, ref) do
    anchor =
      case String.split(ref, ".", parts: 2) do
        [service, name] -> "#{kind}-#{service}-#{name}"
        [name] -> "service-#{name}"
      end

    {"/guide?subpage=catalog##{anchor}", @patch}
  end

  # `guide:<page>#anchor` points at another page of the Developer Guide (a live patch, no reload); a bare
  # `#anchor` stays on the page; `http...` opens in a new tab. The url arrives already escaped.
  defp link_target("guide:" <> rest) do
    {page, anchor} =
      case String.split(rest, "#", parts: 2) do
        [page, anchor] -> {page, "#" <> anchor}
        [page] -> {page, ""}
      end

    {"/guide?subpage=#{URI.encode_www_form(page)}#{anchor}", @patch}
  end

  # `api:service.action`, `event:service.event` and `service:name` point at the live API catalog; the catalog opens
  # the folds around the target.
  defp link_target("api:" <> ref), do: catalog_link("action", ref)
  defp link_target("event:" <> ref), do: catalog_link("event", ref)
  defp link_target("service:" <> name), do: {"/guide?subpage=catalog#service-#{name}", @patch}

  defp link_target(url) do
    if String.starts_with?(url, "http"),
      do: {url, " target=\"_blank\" rel=\"noopener\""},
      else: {url, ""}
  end

  defp render_bold(text) do
    Regex.replace(~r/\*\*([^*]+)\*\*/, text, fn _match, inner ->
      "<strong class=\"font-semibold text-gray-900\">#{inner}</strong>"
    end)
  end

  defp render_italic(text) do
    Regex.replace(~r/(?<!\*)\*([^*]+)\*(?!\*)/, text, fn _match, inner ->
      "<em class=\"italic\">#{inner}</em>"
    end)
  end

  # ---- SYNTAX HIGHLIGHTERS ----

  @csharp_keywords ~w(public private protected internal class record struct interface enum static readonly void string int long float double bool var new return throw using namespace async await if else try catch finally null true false this base typeof is as get set event override virtual)
  @csharp_types ~w(Exoforge ExoServices ExoClient ExoSession ExoActionException ExoDatabaseException ExoDispatcher ExoCron ExoInput ExoRole ExoStandardInput Exo Task Action Func List IReadOnlyList Dictionary CancellationToken DateTime DateTimeOffset Guid Math JsonElement MonoBehaviour Debug GameObject)

  def highlight_csharp(code) when is_binary(code) do
    pattern =
      ~r{(//[^\n]*)|("(?:[^"\\]|\\.)*")|(\[[A-Za-z0-9_]+(?:\([^)]*\))?\])|(\b(?:#{Enum.join(@csharp_keywords, "|")})\b)|(\b(?:#{Enum.join(@csharp_types, "|")})\b)|(\b\d+(?:\.\d+)?f?\b)}

    parts = Regex.split(pattern, code, include_captures: true, trim: false)

    Enum.map(parts, fn part ->
      cond do
        String.starts_with?(part, "//") ->
          "<span class=\"text-gray-500 italic\">#{Plug.HTML.html_escape(part)}</span>"

        String.starts_with?(part, "\"") and String.ends_with?(part, "\"") ->
          "<span class=\"text-emerald-300\">#{Plug.HTML.html_escape(part)}</span>"

        String.starts_with?(part, "[") and String.ends_with?(part, "]") ->
          "<span class=\"text-amber-300 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        part in @csharp_keywords ->
          "<span class=\"text-primary-400 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        part in @csharp_types ->
          "<span class=\"text-blue-300 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        Regex.match?(~r/^\d+(?:\.\d+)?f?$/, part) ->
          "<span class=\"text-amber-300 font-mono\">#{Plug.HTML.html_escape(part)}</span>"

        true ->
          Plug.HTML.html_escape(part)
      end
    end)
    |> IO.iodata_to_binary()
  end

  @elixir_keywords ~w(def defmodule defp defservice defaction defresource action returns scope errors params do end case when fn if else with try rescue after import alias require use true false nil)

  def highlight_elixir(code) when is_binary(code) do
    pattern =
      ~r{(#[^\n]*)|("(?:[^"\\]|\\.)*")|(:[a-zA-Z0-9_]+)|(\b(?:#{Enum.join(@elixir_keywords, "|")})\b)|(\b[A-Z][a-zA-Z0-9_]*\b)|(\b\d+\b)}

    parts = Regex.split(pattern, code, include_captures: true, trim: false)

    Enum.map(parts, fn part ->
      cond do
        String.starts_with?(part, "#") ->
          "<span class=\"text-gray-500 italic\">#{Plug.HTML.html_escape(part)}</span>"

        String.starts_with?(part, "\"") and String.ends_with?(part, "\"") ->
          "<span class=\"text-emerald-300\">#{Plug.HTML.html_escape(part)}</span>"

        String.starts_with?(part, ":") ->
          "<span class=\"text-amber-300\">#{Plug.HTML.html_escape(part)}</span>"

        part in @elixir_keywords ->
          "<span class=\"text-primary-400 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        Regex.match?(~r/^[A-Z]/, part) ->
          "<span class=\"text-blue-300 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        Regex.match?(~r/^\d+$/, part) ->
          "<span class=\"text-amber-300 font-mono\">#{Plug.HTML.html_escape(part)}</span>"

        true ->
          Plug.HTML.html_escape(part)
      end
    end)
    |> IO.iodata_to_binary()
  end

  def highlight_json(code) when is_binary(code) do
    pattern = ~r{("(?:[^"\\]|\\.)*")\s*:|("(?:[^"\\]|\\.)*")|(\b(?:true|false|null)\b)|(-?\b\d+(?:\.\d+)?\b)}

    parts = Regex.split(pattern, code, include_captures: true, trim: false)

    Enum.map(parts, fn part ->
      trimmed = String.trim(part)

      cond do
        String.ends_with?(trimmed, ":") ->
          key = String.trim_trailing(trimmed, ":")
          "<span class=\"text-primary-300 font-semibold\">#{Plug.HTML.html_escape(key)}</span>:"

        String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") ->
          "<span class=\"text-emerald-300\">#{Plug.HTML.html_escape(part)}</span>"

        trimmed in ["true", "false", "null"] ->
          "<span class=\"text-amber-300 font-bold\">#{Plug.HTML.html_escape(part)}</span>"

        Regex.match?(~r/^-?\d+(?:\.\d+)?$/, trimmed) ->
          "<span class=\"text-blue-300 font-mono\">#{Plug.HTML.html_escape(part)}</span>"

        true ->
          Plug.HTML.html_escape(part)
      end
    end)
    |> IO.iodata_to_binary()
  end

  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
  end
end
