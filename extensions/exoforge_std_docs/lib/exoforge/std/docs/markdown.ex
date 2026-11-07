defmodule Exoforge.Std.Docs.Markdown do
  @moduledoc """
  Lightweight, dependency-free Markdown renderer for Exoforge documentation.
  Supports headings, fenced code blocks with syntax highlighting, lists,
  tables, links, images, and GitHub-style callout alerts.
  """

  @doc "Renders a Markdown binary string into HTML (safe Phoenix.HTML.raw)."
  def to_html(markdown) when is_binary(markdown) do
    lines = String.split(markdown, ~r/\r?\n/)
    {html_blocks, _state} = parse_lines(lines, [], :normal)

    html_blocks
    |> Enum.reverse()
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end

  def to_html(_), do: Phoenix.HTML.raw("")

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

      # Horizontal rules
      trimmed in ["---", "***", "___"] ->
        hr = "<hr class=\"my-6 border-gray-200 print:border-gray-400\" />"
        parse_lines(rest, [hr | acc], :normal)

      # Empty line
      trimmed == "" ->
        parse_lines(rest, acc, :normal)

      # Regular paragraph
      true ->
        p = "<p class=\"text-xs text-gray-700 leading-relaxed my-2\">#{inline_format(trimmed)}</p>"
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
        1 -> "text-2xl font-black text-gray-900 tracking-tight mt-6 mb-3 pb-2 border-b border-gray-100"
        2 -> "text-lg font-bold text-gray-900 tracking-tight mt-5 mb-2"
        3 -> "text-sm font-bold text-gray-800 tracking-tight mt-4 mb-1.5"
        4 -> "text-xs font-bold text-gray-700 uppercase tracking-wider mt-3 mb-1"
        _ -> "text-xs font-semibold text-gray-600 mt-2 mb-1"
      end

    tag = "h#{min(max(level, 1), 6)}"
    h = "<#{tag} id=\"#{id}\" class=\"#{classes}\">#{inline_format(text)}</#{tag}>"
    parse_lines(rest, [h | acc], :normal)
  end

  defp count_leading_hashes(<<?#, rest::binary>>, count), do: count_leading_hashes(rest, count + 1)
  defp count_leading_hashes(_, count), do: count

  defp render_code_block(lang, lines) do
    code = Enum.join(lines, "\n")
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

    """
    <div class="relative group my-3">
      #{lang_badge}
      <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800 leading-relaxed shadow-sm print:bg-gray-100 print:text-gray-900 print:border-gray-300"><code>#{highlighted}</code></pre>
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
        <div class="p-4 my-3 rounded-2xl bg-blue-50 border border-blue-200/80 text-blue-900 text-xs space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-blue-800 text-[11px] uppercase tracking-wider">
            <span>ℹ️</span> <span>Note</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :tip ->
        """
        <div class="p-4 my-3 rounded-2xl bg-emerald-50 border border-emerald-200/80 text-emerald-900 text-xs space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-emerald-800 text-[11px] uppercase tracking-wider">
            <span>💡</span> <span>Tip</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :important ->
        """
        <div class="p-4 my-3 rounded-2xl bg-indigo-50 border border-indigo-200/80 text-indigo-900 text-xs space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-indigo-800 text-[11px] uppercase tracking-wider">
            <span>⭐</span> <span>Important</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :warning ->
        """
        <div class="p-4 my-3 rounded-2xl bg-amber-50 border border-amber-200/80 text-amber-900 text-xs space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-amber-800 text-[11px] uppercase tracking-wider">
            <span>⚠️</span> <span>Warning</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :caution ->
        """
        <div class="p-4 my-3 rounded-2xl bg-rose-50 border border-rose-200/80 text-rose-900 text-xs space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-rose-800 text-[11px] uppercase tracking-wider">
            <span>🚨</span> <span>Caution</span>
          </div>
          <div class="leading-relaxed">#{body}</div>
        </div>
        """

      :quote ->
        """
        <blockquote class="border-l-4 border-primary-500 bg-gray-50 pl-4 py-2 my-3 text-xs italic text-gray-700 rounded-r-xl">
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
    <ul class="list-disc list-inside space-y-1.5 text-xs text-gray-700 my-2 pl-1">
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
    <ol class="list-decimal list-inside space-y-1.5 text-xs text-gray-700 my-2 pl-1">
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

        """
        <div class="overflow-x-auto my-3 rounded-xl border border-gray-200">
          <table class="w-full text-left text-xs bg-white">
            <thead class="bg-gray-50 border-b border-gray-200 text-gray-600 uppercase text-[10px]">
              <tr>#{th_html}</tr>
            </thead>
            <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
              #{tr_html}
            </tbody>
          </table>
        </div>
        """
    end
  end

  # ---- INLINE FORMATTER ----

  defp inline_format(text) do
    text
    # 1. Images: ![alt](url)
    |> render_images()
    # 2. Links: [text](url)
    |> render_links()
    # 3. Inline code: `code`
    |> render_inline_code()
    # 4. Bold: **text**
    |> render_bold()
    # 5. Italic: *text*
    |> render_italic()
  end

  defp render_images(text) do
    Regex.replace(~r/!\[([^\]]*)\]\(([^)]+)\)/, text, fn _match, alt, url ->
      safe_alt = Plug.HTML.html_escape(alt)
      safe_url = Plug.HTML.html_escape(url)
      "<img src=\"#{safe_url}\" alt=\"#{safe_alt}\" class=\"max-w-full rounded-2xl shadow-sm border border-gray-200 my-3\" />"
    end)
  end

  defp render_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, text, fn _match, label, url ->
      safe_label = Plug.HTML.html_escape(label)
      safe_url = Plug.HTML.html_escape(url)

      target = if String.starts_with?(url, "http"), do: " target=\"_blank\" rel=\"noopener\"", else: ""

      "<a href=\"#{safe_url}\"#{target} class=\"text-primary-600 hover:text-primary-800 underline font-medium\">#{safe_label}</a>"
    end)
  end

  defp render_inline_code(text) do
    Regex.replace(~r/`([^`]+)`/, text, fn _match, code ->
      "<code class=\"font-mono text-primary-700 bg-primary-50 px-1.5 py-0.5 rounded text-[11px] border border-primary-200/60 font-semibold\">#{Plug.HTML.html_escape(code)}</code>"
    end)
  end

  defp render_bold(text) do
    Regex.replace(~r/\*\*([^*]+)\*\*/, text, fn _match, inner ->
      "<strong class=\"font-bold text-gray-900\">#{inner}</strong>"
    end)
  end

  defp render_italic(text) do
    Regex.replace(~r/(?<!\*)\*([^*]+)\*(?!\*)/, text, fn _match, inner ->
      "<em class=\"italic\">#{inner}</em>"
    end)
  end

  # ---- SYNTAX HIGHLIGHTERS ----

  @csharp_keywords ~w(public private protected internal class record struct interface enum static readonly void string int long float double bool var new return throw using namespace async await if else try catch finally null true false this base typeof is as get set event override virtual)
  @csharp_types ~w(Exoforge ExoServices ExoClient ExoSession ExoActionException ExoDispatcher ExoCron Task Action Func List DateTime Guid MonoBehaviour Debug GameObject)

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
          "<span class=\"text-yellow-300 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        part in @csharp_keywords ->
          "<span class=\"text-purple-400 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        part in @csharp_types ->
          "<span class=\"text-cyan-300 font-bold\">#{Plug.HTML.html_escape(part)}</span>"

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
          "<span class=\"text-yellow-300\">#{Plug.HTML.html_escape(part)}</span>"

        part in @elixir_keywords ->
          "<span class=\"text-purple-400 font-semibold\">#{Plug.HTML.html_escape(part)}</span>"

        Regex.match?(~r/^[A-Z]/, part) ->
          "<span class=\"text-cyan-300 font-bold\">#{Plug.HTML.html_escape(part)}</span>"

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
          "<span class=\"text-purple-300 font-semibold\">#{Plug.HTML.html_escape(key)}</span>:"

        String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") ->
          "<span class=\"text-emerald-300\">#{Plug.HTML.html_escape(part)}</span>"

        trimmed in ["true", "false", "null"] ->
          "<span class=\"text-amber-300 font-bold\">#{Plug.HTML.html_escape(part)}</span>"

        Regex.match?(~r/^-?\d+(?:\.\d+)?$/, trimmed) ->
          "<span class=\"text-cyan-300 font-mono\">#{Plug.HTML.html_escape(part)}</span>"

        true ->
          Plug.HTML.html_escape(part)
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
  end
end
