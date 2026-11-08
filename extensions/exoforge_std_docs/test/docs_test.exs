defmodule Exoforge.Std.DocsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component

  alias Exoforge.Std.Docs
  alias Exoforge.Std.Docs.Markdown
  alias Exoforge.Std.Docs.View

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
      assert html =~ "<strong class=\"font-bold text-gray-900\">bold</strong>"
      assert html =~ "<em class=\"italic\">italic</em>"
      assert html =~ "<code class=\"font-mono"
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
      assert html =~ "text-purple-400 font-semibold\">public</span>"
      assert html =~ "text-yellow-300 font-semibold\">[ExoAction]</span>"
    end
  end

  describe "Docs Extension Actions" do
    test "list_chapters returns all markdown chapters" do
      {:ok, %{chapters: chapters, count: count}} = Docs.list_chapters()
      assert count >= 4
      assert Enum.any?(chapters, &(&1.id == "01_quickstart"))
      assert Enum.any?(chapters, &(&1.id == "02_csharp_attributes"))
      assert Enum.any?(chapters, &(&1.id == "03_architecture"))
      assert Enum.any?(chapters, &(&1.id == "04_use_cases_and_patterns"))
    end

    test "get_chapter returns chapter content and rendered html" do
      {:ok, %{chapter: chapter}} = Docs.get_chapter(%{id: "04_use_cases_and_patterns"})
      assert chapter.title =~ "What You Can Build with Exoforge"
      assert chapter.content =~ "Paradigm Shift"
      assert chapter.html =~ "<table"
    end

    test "get_chapter returns error for missing chapter" do
      assert {:error, :not_found} = Docs.get_chapter(%{id: "non_existent"})
    end

    test "export_docs produces unified markdown and html" do
      {:ok, %{title: title, content: md, format: "markdown"}} = Docs.export_docs(%{format: "markdown"})
      assert title =~ "Exoforge Complete Developer Guide"
      assert md =~ "Developer Quickstart"
      assert md =~ "C# Attributes Reference"
      assert md =~ "Dynamic Cluster API Reference"

      {:ok, %{content: html, format: "html"}} = Docs.export_docs(%{format: "html"})
      assert html =~ "<h1"
    end
  end

  describe "Docs Phoenix Component View" do
    test "renders quickstart flow by default" do
      assigns = %{
        action_catalog: [],
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "flow"
      }

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
      <View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
      />
      """)

      assert html =~ "Creating Your First Online Multiplayer Feature"
      assert html =~ "Export to PDF"
      assert html =~ "@media print"
    end

    test "renders attributes subpage" do
      assigns = %{
        action_catalog: [],
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "attributes"
      }

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
      <View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
      />
      """)

      assert html =~ "[ExoExtension]"
      assert html =~ "[ExoAction]"
      assert html =~ "[ExoCron]"
      assert html =~ "[ExoEvent]"
      assert html =~ "[ExoResource]"
    end

    test "renders use_cases subpage with blueprints and comparison matrix" do
      assigns = %{
        action_catalog: [],
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "use_cases"
      }

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
      <View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
      />
      """)

      assert html =~ "What You Can Build with Exoforge"
      assert html =~ "The Paradigm Shift: Exoforge vs. Legacy BaaS"
      assert html =~ "Auction House &amp; P2P"
      assert html =~ "In-Memory Matchmaker"
      assert html =~ "World Boss LiveOps"
      assert html =~ "Guilds &amp; Clans"
      assert html =~ "Automated Season Rollovers"
      assert html =~ "Web Store Checkout, Stripe Webhooks &amp; Instant Delivery"
      assert html =~ "Exoforge Architecture Tips &amp; Golden Rules"
      assert html =~ "Stateless Extensions, Resilient State in DB"
    end

    test "renders architecture subpage with high-contrast badge styles" do
      assigns = %{
        action_catalog: [],
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "architecture"
      }

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
      <View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
      />
      """)

      assert html =~ "Architecture"
      assert html =~ "html:not(.light) :not(pre) > code"
      assert html =~ "pre code"
    end

    test "subpage flow does not duplicate the action catalog" do
      assigns = %{
        action_catalog: [
          %{name: "test_svc", title: "Test Svc", icon: "🎮", actions: [%{name: "run", mode: "sync", doc: "runs", params: []}]}
        ],
        extensions: [],
        project_name: "TestGame",
        studio_name: "TestStudio",
        subpage: "flow"
      }

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
      <View.view
        action_catalog={@action_catalog}
        extensions={@extensions}
        project_name={@project_name}
        studio_name={@studio_name}
        subpage={@subpage}
      />
      """)

      refute html =~ "<section id=\"catalog\""
      assert html =~ "Live Action Catalog"
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

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
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

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
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

      # Folds collapsed by default (no 'open' attribute on details)
      refute html =~ "<details class=\"group bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 print:border-gray-300 print:shadow-none print:break-inside-avoid\" open>"
      refute html =~ "<details class=\"group/act bg-white rounded-xl border border-gray-200/80 p-4 space-y-3 shadow-2xs transition-all print:border-gray-300 print:break-inside-avoid\" open>"
    end

    test "renders ArchitectureGraph with UML diagram, maximize modal, and sequential workflow cascade" do
      assigns = %{}

      html = Phoenix.LiveViewTest.rendered_to_string(~H"""
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
end
