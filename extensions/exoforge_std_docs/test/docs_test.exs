defmodule Exoforge.Std.DocsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component

  alias Exoforge.Std.Docs
  alias Exoforge.Std.Docs.Markdown
  alias Exoforge.Std.Docs.View
  alias Exoforge.Std.Docs.Pages

  describe "Markdown Renderer" do
    test "renders headings, bold, italic, code, and links" do
      md = """
      # Main Title
      ## Subtitle

      This is **bold**, *italic*, and `inline_code`.
      Check out [Exoforge](https://exoforge.dev).
      """

      html = Markdown.to_html(md) |> Phoenix.HTML.safe_to_string()

      assert html =~ "<h1"
      assert html =~ "Main Title</h1>"
      assert html =~ "<h2"
      assert html =~ "<strong class=\"font-semibold text-gray-900\">bold</strong>"
      assert html =~ "<em class=\"italic\">italic</em>"
      assert html =~ "font-mono"
      assert html =~ "inline_code</code>"
      assert html =~ "<a href=\"https://exoforge.dev\""
      assert html =~ "target=\"_blank\""
    end

    test "renders images" do
      md = "![Diagram](/docs/images/arch.png)"
      html = Markdown.to_html(md) |> Phoenix.HTML.safe_to_string()

      assert html =~ "<img src=\"/docs/images/arch.png\" alt=\"Diagram\""
    end

    test "renders callout alerts" do
      md = """
      > [!NOTE]
      > This is a helpful note.

      > [!WARNING]
      > Beware of something breaking.
      """

      html = Markdown.to_html(md) |> Phoenix.HTML.safe_to_string()

      assert html =~ "Note"
      assert html =~ "This is a helpful note."
      assert html =~ "Warning"
      assert html =~ "Beware of something breaking."
    end

    test "renders tables" do
      md = """
      | Name | Type | Description |
      |---|---|---|
      | score | integer | The total score |
      """

      html = Markdown.to_html(md) |> Phoenix.HTML.safe_to_string()

      assert html =~ "<table"
      assert html =~ ">Name</th>"
      assert html =~ ">score</td>"
      assert html =~ ">integer</td>"
      assert html =~ ">The total score</td>"
    end

    test "renders syntax-highlighted C# code blocks" do
      md = """
      ```csharp
      public class Player : MonoBehaviour
      {
          [ExoAction]
          public int Score => 100;
      }
      ```
      """

      html = Markdown.to_html(md) |> Phoenix.HTML.safe_to_string()

      assert html =~ "<pre"
      assert html =~ "text-primary-400 font-semibold\">public</span>"
      assert html =~ "text-amber-300 font-semibold\">[ExoAction]</span>"
    end
  end

  describe "Docs Extension Actions" do
    test "list_chapters returns all markdown chapters" do
      {:ok, %{chapters: chapters, count: count}} = Docs.list_chapters()
      assert count >= 4
      assert Enum.any?(chapters, &(&1.id == "01_quickstart"))
      assert Enum.any?(chapters, &(&1.id == "03_csharp_attributes"))
      assert Enum.any?(chapters, &(&1.id == "08_architecture"))
      assert Enum.any?(chapters, &(&1.id == "07_patterns"))
      assert Enum.any?(chapters, &(&1.id == "04_versions_and_migrations"))
      assert Enum.any?(chapters, &(&1.id == "02_recipes"))
      assert Enum.any?(chapters, &(&1.id == "05_standard_extensions"))
      assert Enum.any?(chapters, &(&1.id == "06_arcade_walkthrough"))
    end

    test "no chapter documents an attribute property that no longer exists" do
      attributes = Path.expand("../../../sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs", __DIR__)

      if File.exists?(attributes) do
        source = File.read!(attributes)
        {:ok, %{chapters: chapters}} = Docs.list_chapters()

        for %{id: id} <- chapters do
          {:ok, %{chapter: %{html: html}}} = Docs.get_chapter(%{id: id})
          refute html =~ "ActionTransport", "#{id} still documents ActionTransport"
        end

        refute source =~ "enum ActionTransport"
      end
    end

    test "get_chapter returns chapter content and rendered html" do
      {:ok, %{chapter: chapter}} = Docs.get_chapter(%{id: "07_patterns"})
      assert chapter.title =~ "What You Can Build with Exoforge"
      assert chapter.content =~ "How Exoforge differs"
      assert chapter.html =~ "<table"
      # front matter belongs to the navigation, not to the chapter text
      refute chapter.content =~ "group:"
    end

    test "markdown escapes text, keeps code spans intact and renders guide links and collapsible sections" do
      html =
        "## [ExoDependency<T>] & friends\n\nUse `List<int>` with [the guide](guide:04_versions_and_migrations#two-kinds-of-version) or [docs](https://example.com?a=1&b=2).\n\n<details>\n<summary>More **detail**</summary>\n\nHidden.\n\n</details>\n"
        |> Markdown.to_html()
        |> Phoenix.HTML.safe_to_string()

      assert html =~ "[ExoDependency&lt;T&gt;] &amp; friends"
      refute html =~ "<T>"
      assert html =~ "List&lt;int&gt;"
      assert html =~ ~s(href="/guide?subpage=04_versions_and_migrations#two-kinds-of-version")
      assert html =~ ~s(data-phx-link="patch")
      assert html =~ ~s(href="https://example.com?a=1&amp;b=2")
      assert html =~ "<details"
      assert html =~ "More <strong"
    end

    test "get_chapter returns error for missing chapter" do
      assert {:error, :not_found} = Docs.get_chapter(%{id: "non_existent"})
    end

    test "export_docs produces unified markdown and html" do
      {:ok, %{title: title, content: md, format: "markdown"}} =
        Docs.export_docs(%{format: "markdown"})

      assert title =~ "Exoforge Complete Developer Guide"
      assert md =~ "Developer Quickstart"
      assert md =~ "C# Attributes Reference"
      assert md =~ "Dynamic Cluster API Reference"

      {:ok, %{content: html, format: "html"}} = Docs.export_docs(%{format: "html"})
      assert html =~ "<h1"

      {:ok, %{title: pdf_title, binary: pdf_bytes, format: "pdf"}} =
        Docs.export_docs(%{format: "pdf"})

      assert pdf_title =~ "Exoforge Complete Developer Guide"
      assert is_binary(pdf_bytes)
      assert String.starts_with?(pdf_bytes, "%PDF-1.4")
    end
  end

  describe "Extension documentation" do
    setup do
      Exoforge.ExtensionCase.start_kernel()
      root = Path.join(System.tmp_dir!(), "exo_ext_docs_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "docs"))
      File.mkdir_p!(Path.join(root, "priv/docs"))
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    defmodule Stub do
      use Exoforge.Extension
    end

    test "pages in an extension's docs folder join the guide, in file order, with optional front matter", %{root: root} do
      File.write!(Path.join(root, "docs/overview.md"), "# Wallet\n\nCoins shared by every game.\n")
      File.write!(Path.join(root, "docs/b_refunds.md"), "---\nnav: Refunds\nsummary: How refunds work\n---\n# Refunds & chargebacks\n\nText.\n")
      File.write!(Path.join(root, "docs/notes.txt"), "not markdown")

      Exoforge.ExtensionCase.register_extension(Stub, id: :wallet_ext, title: "Wallet", physical_path: root)

      pages = Docs.load_extension_pages()
      assert ["ext-wallet-ext-b-refunds", "ext-wallet-ext-overview"] = Enum.map(pages, & &1.id)
      assert [%{nav: "Refunds", summary: "How refunds work", extension_title: "Wallet", group: "Extensions"}, %{nav: "Overview"}] = pages

      # they are guide pages: navigable, rendered, and in the export
      assert Enum.any?(Pages.all(), &(&1.id == "ext-wallet-ext-overview"))
      html = render_guide("ext-wallet-ext-overview")
      assert html =~ "Coins shared by every game."
      assert html =~ "Extensions"
      {:ok, %{content: md}} = Docs.export_docs(%{format: "markdown"})
      assert md =~ "Refunds &amp; chargebacks" or md =~ "Refunds & chargebacks"
      assert {:ok, %{chapter: %{title: "Wallet"}}} = Docs.get_chapter(%{id: "ext-wallet-ext-overview"})
    end

    test "the extensions sit in a fold that is closed unless one of their pages is being read, and the index can be hidden", %{root: root} do
      File.write!(Path.join(root, "docs/overview.md"), "# Wallet\n\nCoins.\n")
      Exoforge.ExtensionCase.register_extension(Stub, id: :wallet_ext, title: "Wallet", physical_path: root)

      elsewhere = render_guide("01_quickstart")
      assert elsewhere =~ ~s(id="guide-ext-group")
      assert elsewhere =~ ~r/<div id="guide-ext-group" class="hidden"/
      assert elsewhere =~ ~s(data-page="01_quickstart")

      reading = render_guide("ext-wallet-ext-overview")
      refute reading =~ ~r/<div id="guide-ext-group" class="hidden"/
      refute reading =~ ~r/<div id="guide-ext-wallet-ext" class="hidden"/
      assert reading =~ ~s(data-page="ext-wallet-ext-overview")

      # one button hides and shows the index and the contents list
      assert reading =~ "Expand"
      refute reading =~ "Hide index"
      assert reading =~ ~s(id="guide-index")
      assert reading =~ ~s(id="guide-toc")
    end

    defmodule Contract do
      import Exoforge.Contracts.Service

      defservice wallet_svc do
        @doc "Credits coins to a player."
        action :credit do
          scope(:service)
          params(player_id: :string, amount: :integer, reason: [type: :string, optional: true])
          returns(balance: :integer)
        end

        @doc "Fired when a balance changes."
        event :balance_changed do
          payload(player_id: :string, balance: :integer)
          scope(:server)
        end
      end
    end

    test "{{actions}} and {{events}} are built from the contract and link to the API reference", %{root: root} do
      File.write!(Path.join(root, "docs/overview.md"), "# Wallet\n\n## Actions\n\n{{actions}}\n\n## Events\n\n{{events}}\n")

      Exoforge.ExtensionCase.register_extension(Stub,
        id: :wallet_ext,
        title: "Wallet",
        physical_path: root,
        services: [Contract.WalletSvc.__service_metadata__()]
      )

      [page] = Docs.load_extension_pages()
      assert page.content =~ "| [`credit`](api:wallet_svc.credit) | `service` | `player_id`, `amount`, `reason?` | Credits coins to a player. |"
      assert page.content =~ "| [`balance_changed`](event:wallet_svc.balance_changed) |"
      refute page.content =~ "{{"

      html = render_guide(page.id)
      assert html =~ ~s(href="/guide?subpage=catalog#action-wallet_svc-credit")
      assert html =~ ~s(href="/guide?subpage=catalog#event-wallet_svc-balance_changed")

      # the catalog is where those links land: anchors for the service, the action and the event, and a way back
      catalog = render_guide("catalog")
      assert catalog =~ ~s(id="service-wallet_svc")
      assert catalog =~ ~s(id="action-wallet_svc-credit")
      assert catalog =~ ~s(id="event-wallet_svc-balance_changed")
      assert catalog =~ "Read its documentation"
    end

    test "{{about}} is the extension module's own @moduledoc, so the explanation lives in the code", %{root: root} do
      File.write!(Path.join(root, "docs/overview.md"), "# Cron\n\n{{about}}\n")
      Exoforge.ExtensionCase.register_extension(Exoforge.Std.Docs, id: :docs_ext, title: "Docs", physical_path: root)

      [page] = Docs.load_extension_pages()
      assert page.content =~ "Developer Guide"
      refute page.content =~ "{{about}}"
    end

    test "an Elixir extension's priv/docs is the same folder, and an extension without docs adds nothing", %{root: root} do
      File.rm_rf!(Path.join(root, "docs"))
      File.write!(Path.join(root, "priv/docs/overview.md"), "# Elixir extension\n\nBody.\n")
      Exoforge.ExtensionCase.register_extension(Stub, id: :elixir_ext, physical_path: root)
      Exoforge.ExtensionCase.register_extension(Stub, id: :no_docs_ext, physical_path: Path.join(root, "missing"))

      assert ["ext-elixir-ext-overview"] = Enum.map(Docs.load_extension_pages(), & &1.id)
    end
  end

  describe "Docs Phoenix Component View" do
    defp render_guide(subpage) do
      assigns = %{action_catalog: [], extensions: [], project_name: "TestGame", studio_name: "TestStudio", subpage: subpage}

      Phoenix.LiveViewTest.rendered_to_string(~H"""
      <View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
      />
      """)
    end

    test "opens on the quickstart with the sidebar, the export link and the print styles" do
      html = render_guide("flow")

      assert html =~ "Developer Quickstart"
      assert html =~ "Developer Guide pages"
      groups = ["Get started", "Build", "Learn by example", "Understand", "Live reference"]
      for group <- groups, do: assert(html =~ group)
      assert html =~ "Export to PDF"
      assert html =~ "/api/docs/manual.pdf"
      assert html =~ "@media print"
    end

    test "every chapter renders as a page with its heading ids and neighbours" do
      for %{id: id, title: title} <- Pages.all(), id not in ["architecture", "catalog"] do
        html = render_guide(id)
        assert html =~ "guide-#{id}", "#{id} did not render as a chapter page"
        escaped = title |> Plug.HTML.html_escape() |> IO.iodata_to_binary()
        assert html =~ escaped, "#{id} lost its title"
        assert html =~ ~s(<h2 id="), "#{id} has no section headings"
      end

      # a page with a following page links to it, and the first page has no previous one
      assert render_guide("02_recipes") =~ "Previous</span>"
      refute render_guide("01_quickstart") =~ "Previous</span>"
    end

    test "the guide's old page ids still open the right page" do
      assert render_guide("how_to") =~ "Sign in a player"
      assert render_guide("attributes") =~ "[ExoAction]"
      assert render_guide("use_cases") =~ "Auction House"
    end

    test "renders the attributes reference with every core attribute and the lifecycle hook" do
      html = render_guide("03_csharp_attributes")

      for attr <- ~w([ExoExtension] [ExoAction] [ExoCron] [ExoEvent] [ExoResource] [ExoFileReference] [ExoInputType]), do: assert(html =~ attr)
      assert html =~ "OnExtensionStart"
    end

    test "renders the architecture map and the live catalog as pages of the guide" do
      arch = render_guide("architecture")
      assert arch =~ "architecture-graph"
      assert arch =~ "@media print"
      refute arch =~ "html:not(.light) :not(pre) > code"
      refute arch =~ "html:not(.light) .prose strong"

      catalog = render_guide("catalog")
      assert catalog =~ "Live Services &amp; Action Catalog"
    end

    test "on-page links use the guide scheme and the table of contents follows the headings" do
      html = render_guide("04_versions_and_migrations")
      assert html =~ "On this page"
      assert html =~ ~s(data-phx-link="patch")

      toc = Pages.toc("# T\n## One\n```\n## not a heading\n```\n### Two `code`\n")
      assert [{2, "One", "one"}, {3, "Two code", "two-code"}] = toc
    end

    test "deduplicates duplicate services and actions in action_catalog" do
      duplicated_catalog = [
        %{
          name: "inventory",
          title: "Inventory Service",
          icon: "🎒",
          actions: [
            %{name: "add_item", mode: "sync", doc: "Add item", params: []},
            %{name: "add_item", mode: "sync", doc: "Add item duplicate", params: []}
          ]
        },
        %{
          name: "inventory",
          title: "Duplicate Inventory Service",
          icon: "🎒",
          actions: [
            %{name: "add_item", mode: "sync", doc: "Add item duplicate", params: []}
          ]
        }
      ]

      assigns = %{
        action_catalog: duplicated_catalog,
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "catalog"
      }

      html =
        Phoenix.LiveViewTest.rendered_to_string(~H"""
        <View.view
          action_catalog={@action_catalog}
          extensions={@extensions}
          project_name={@project_name}
          studio_name={@studio_name}
          subpage={@subpage}
        />
        """)

      assert html =~ "<section id=\"catalog\""
      assert html =~ "1 Services Loaded"
      # Count occurrences of .add_item() in action summaries
      matches = Regex.scan(~r/\.add_item\(\)/, html)
      assert length(matches) == 1
    end

    test "formats action signature with required and optional params, and collapses folds by default" do
      catalog = [
        %{
          name: "auth",
          title: "Auth Service",
          icon: "🔐",
          actions: [
            %{
              name: "authenticate",
              mode: "sync",
              doc: "Auth token",
              params: [%{name: "token", type: "string", optional: false}]
            },
            %{
              name: "verify_scope",
              mode: "sync",
              doc: "Verify scope",
              params: [
                %{name: "user_id", type: "string", optional: true},
                %{name: "player_id", type: "string", optional: true},
                %{name: "required_scope", type: "string", optional: false}
              ]
            },
            %{
              name: "ping_event",
              mode: "cast",
              doc: "Cast ping",
              params: []
            },
            %{
              name: "fetch_stats",
              mode: "async",
              doc: "Async stats",
              params: []
            }
          ]
        }
      ]

      assigns = %{
        action_catalog: catalog,
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "catalog"
      }

      html =
        Phoenix.LiveViewTest.rendered_to_string(~H"""
        <View.view
          action_catalog={@action_catalog}
          extensions={@extensions}
          project_name={@project_name}
          studio_name={@studio_name}
          subpage={@subpage}
        />
        """)

      # Action title signatures: parameter names only, required first, ? for optionals
      assert html =~ ".authenticate(token)"
      assert html =~ ".verify_scope(required_scope, user_id?, player_id?)"

      # Only async and cast modes show badges in live catalog; sync is omitted
      refute html =~ "Understanding Action Modes"
      refute html =~ ">sync<"
      assert html =~ ">cast<"
      assert html =~ ">async<"

      # Folds collapsed by default (no 'open' attribute on details)
      refute html =~
               "<details class=\"group bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 print:border-gray-300 print:shadow-none print:break-inside-avoid\" open>"

      refute html =~
               "<details class=\"group/act bg-white rounded-xl border border-gray-200/80 p-4 space-y-3 shadow-2xs transition-all print:border-gray-300 print:break-inside-avoid\" open>"
    end

    test "renders ArchitectureGraph with UML diagram, maximize modal, and sequential workflow cascade" do
      assigns = %{}

      html =
        Phoenix.LiveViewTest.rendered_to_string(~H"""
        <Exoforge.Std.Docs.ArchitectureGraph.visualizer />
        """)

      # Core Philosophy & Rule of Thumb
      assert html =~ "CORE PHILOSOPHY"
      assert html =~ "Immutable Kernel Core + Pluggable Extensions"
      assert html =~ "Rule of Thumb"

      # UML Packages & Components
      assert html =~ "package Ingress"
      assert html =~ "package Kernel"
      assert html =~ "package Extensions"
      assert html =~ "package Storage"
      assert html =~ "&laquo;component&raquo;"

      # Maximize Button & Modal Popup
      assert html =~ "Maximize Diagram"
      assert html =~ "id=\"arch-graph-modal\""
      assert html =~ "Exoforge UML Architecture Diagram"

      # Node Inspector
      assert html =~ "id=\"arch-node-inspector\""
      assert html =~ "ActionDispatcher"

      # Sequential Workflow Cascade with collapsible cards
      assert html =~ "id=\"cascade-action-workflow\""
      assert html =~ "Client Action Request"
      assert html =~ "Scope Authorization &amp; Provider Resolution"
      assert html =~ "Native C# Extension Execution"
      assert html =~ "0.07 ms verified SLA"
    end
  end

  test "the manual PDF keeps its text on the page and in ASCII" do
    pdf = Exoforge.Std.Docs.PdfManual.generate()

    assert String.starts_with?(pdf, "%PDF-1.4")

    text_streams =
      Regex.scan(~r/>>\nstream\n(.*?)\nendstream/s, pdf, capture: :all_but_first)
      |> Enum.map(fn [body] -> :zlib.uncompress(body) end)

    assert text_streams != []

    # A code block taller than a page used to be drawn off the bottom of it; the footer sits at
    # y=30, so nothing else may fall below the bottom margin.
    rows =
      for stream <- text_streams,
          [_, _, y] <- Regex.scan(~r/([\d.]+) ([\d.-]+) Td/, stream),
          do: y |> Float.parse() |> elem(0)

    assert Enum.min(rows) >= 30.0

    # The standard fonts are WinAnsi: a UTF-8 bullet would reach the reader as mojibake.
    assert Enum.all?(text_streams, &(not String.match?(&1, ~r/[^\x00-\x7F]/)))
  end
end
