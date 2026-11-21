defmodule Exoforge.Std.Dashboard.ResourceRefsTest do
  use ExUnit.Case, async: true

  alias Exoforge.Std.Dashboard.{ResourceForms, ResourceRefs}
  import Phoenix.LiveViewTest, only: [render_component: 2]

  # Two extensions: one owns items (table differs from the resource name), one owns offers that
  # point at them. Nothing here knows either name; it is all in the declared resources.
  @items %{
    resource: %{
      name: :itens,
      table: "shop_items",
      primary_key: :id,
      columns: [%{name: :id, type: :string}, %{name: :nome, type: :string}]
    }
  }
  @offers %{
    resource: %{
      name: :ofertas,
      primary_key: :id,
      columns: [
        %{name: :id, type: :string},
        %{name: :item_id, type: :string, foreign_key: true, references: "itens.id"},
        %{"name" => "by_table", "type" => "string", "references" => "shop_items.id"},
        %{name: :ghost, type: :string, references: "nowhere.id"}
      ]
    }
  }

  @item_rows [%{id: "sword", nome: "Sword"}, %{id: "shield", nome: "Shield"}]
  @offer_rows [
    %{id: "o1", item_id: "sword", by_table: "sword", ghost: "x"},
    %{id: "o2", item_id: "sword", by_table: "gone", ghost: ""},
    %{id: "o3", item_id: "shield", by_table: "", ghost: ""}
  ]

  # A store that answers like resource_store: rows and a total, an error for a resource the viewer
  # may not read, and a count of how often it was asked.
  defp opts(extra \\ %{}) do
    test = self()
    denied = Map.get(extra, :denied, [])
    item_rows = Map.get(extra, :item_rows, @item_rows)
    total = Map.get(extra, :items_total, length(item_rows))

    base = %{
      entries: fn -> [@items, @offers] end,
      get: fn name, id ->
        send(test, {:get, to_string(name), id})

        cond do
          to_string(name) in denied -> :error
          true -> {:ok, Enum.find(@item_rows, &(&1.id == id))}
        end
      end,
      list: fn name, params ->
        send(test, {:list, to_string(name), params})
        name = to_string(name)

        cond do
          name in denied -> :error
          name == "itens" -> {:ok, %{rows: item_rows, total: total}}
          true -> {:ok, %{rows: @offer_rows, total: length(@offer_rows)}}
        end
      end
    }

    Map.merge(base, Map.drop(extra, [:denied, :item_rows, :items_total]))
  end

  defp columns, do: ResourceForms.columns(@offers.resource)

  test "references parse from atom or string keys, and a bad one is ignored" do
    assert ResourceRefs.parse(%{references: "itens.id"}) == {"itens", "id"}
    assert ResourceRefs.parse(%{"references" => "a.b"}) == {"a", "b"}
    assert ResourceRefs.parse(%{references: "nodot"}) == nil
    assert ResourceRefs.parse(%{name: :x}) == nil
  end

  test "a resource resolves by its name or by its table" do
    assert ResourceRefs.resolve("itens", [@items, @offers]) == @items
    assert ResourceRefs.resolve("shop_items", [@items, @offers]) == @items
    assert ResourceRefs.resolve("nowhere", [@items, @offers]) == nil
  end

  test "a value links to its row, URI-encoded; a missing row stays text; unknown resource gets nothing" do
    rows = [%{item_id: "sword", by_table: "gone", ghost: "x"}, %{item_id: "a b/c", ghost: ""}]
    links = ResourceRefs.links(columns(), rows, opts())

    assert %{status: :found, path: "/resources/itens?focus=row:sword", label: "Sword"} =
             links[{"item_id", "sword"}]

    assert %{status: :missing, resource: :itens} = links[{"item_id", "a b/c"}]
    assert %{status: :missing} = links[{"by_table", "gone"}]
    refute Map.has_key?(links, {"ghost", "x"})
    assert ResourceRefs.path("itens", "a b/c") == "/resources/itens?focus=row:a+b%2Fc"
  end

  test "the form column keeps its reference" do
    assert Enum.find(columns(), &(&1.key == :item_id)).references == "itens.id"
    assert Enum.find(columns(), &(&1.key == :item_id)).foreign_key
  end

  test "a picker lists key plus label; large, unreadable or unknown falls back to text" do
    picks = ResourceRefs.options(columns(), opts())
    assert picks["item_id"] == [{"sword", "sword · Sword"}, {"shield", "shield · Shield"}]
    assert picks["ghost"] == :text
    refute Map.has_key?(picks, "id")

    big = opts(%{item_rows: Enum.map(1..201, &%{id: "#{&1}"}), items_total: 500})
    assert ResourceRefs.options(columns(), big)["item_id"] == :text

    broken = opts(%{list: fn _, _ -> raise "db down" end})
    assert ResourceRefs.options(columns(), broken)["item_id"] == :text
  end

  test "a row lists the rows of other resources that point at it" do
    [group] = ResourceRefs.referenced_by("itens", %{id: "sword", nome: "Sword"}, opts())

    assert group.resource == "ofertas"
    assert Enum.map(group.rows, & &1.id) == ["o1", "o2"]
    assert hd(group.rows).path == "/resources/ofertas?focus=row:o1"
    assert ResourceRefs.referenced_by("itens", %{id: "unused"}, opts()) == []
    assert ResourceRefs.referenced_by("ofertas", %{id: "o1"}, opts()) == []
  end

  test "data_table renders a foreign-key cell as a link, and a dangling one as text with a hint" do
    cols = [
      %{key: :id, label: "ID"},
      %{key: :item_id, label: "Item", references: "itens.id"}
    ]

    rows = [%{id: "o1", item_id: "sword"}, %{id: "o2", item_id: "gone"}]

    links =
      ResourceRefs.links(cols, rows, opts())

    html =
      render_component(&Exoforge.Std.Dashboard.Components.data_table/1,
        id: "t",
        rows: rows,
        columns: cols,
        fk_links: links
      )

    assert html =~ ~s(href="/resources/itens?focus=row:sword")
    refute html =~ "focus=row:gone"
    assert html =~ "no match"
  end

  test "a reference to a resource that does not exist leaves a plain cell and breaks nothing" do
    rows = [%{item_id: "sword", ghost: "x"}]
    links = ResourceRefs.links(columns(), rows, opts())

    refute Map.has_key?(links, {"ghost", "x"})
    assert Map.has_key?(links, {"item_id", "sword"})
    # An unrelated stale declaration does not break another resource's drawer either.
    assert [%{resource: "ofertas"}] = ResourceRefs.referenced_by("itens", %{id: "sword"}, opts())
  end

  test "a resource or row the viewer cannot read is unresolved everywhere" do
    denied = opts(%{denied: ["itens"]})
    rows = [%{item_id: "sword"}]

    assert ResourceRefs.links(columns(), rows, denied) == %{}
    assert ResourceRefs.options(columns(), denied)["item_id"] == :text
    # The viewer may read offers but not items: items' own drawer is not the question, offers
    # that point at a row of a denied resource are simply never looked up.
    assert ResourceRefs.referenced_by("itens", %{id: "sword"}, opts(%{denied: ["ofertas"]})) == []

    # The default reads go through the store with the viewer's scopes: nothing readable, no crash.
    assert ResourceRefs.links(columns(), rows, %{entries: fn -> [@items, @offers] end, scopes: []}) == %{}
  end

  test "the referenced resource is fetched once per render, not once per value" do
    rows = for i <- 1..25, do: %{item_id: if(rem(i, 2) == 0, do: "sword", else: "shield")}
    ResourceRefs.links(columns(), rows, opts())

    assert_received {:list, "itens", _}
    refute_received {:list, "itens", _}
    refute_received {:get, _, _}
  end

  test "past the bounded fetch a primary-key value is checked exactly, other columns say what was checked" do
    # 1000 rows fetched of 1500: "sword" is not among them.
    big = opts(%{item_rows: Enum.map(1..1000, &%{id: "i#{&1}"}), items_total: 1500})

    links = ResourceRefs.links(columns(), [%{item_id: "sword", by_table: "x"}], big)
    assert %{status: :found} = links[{"item_id", "sword"}]
    assert_received {:get, "itens", "sword"}

    # `shop_items.id` is also the key, so it is exact too; a non-key column that cannot be queried
    # is reported as unchecked rather than "no match".
    cols = [%{key: :code, references: "itens.nome"}]
    links = ResourceRefs.links(cols, [%{code: "Sword"}], big)
    assert %{status: :unchecked, limit: 1000} = links[{"code", "Sword"}]
  end

  test "a filterable referencing column is asked exactly; otherwise the scan says how much it checked" do
    filterable = %{
      resource: put_in(@offers.resource, [:columns], [
        %{name: :id},
        %{name: :item_id, references: "itens.id", filterable: true}
      ])
    }

    filter_opts =
      opts(%{
        entries: fn -> [@items, filterable] end,
        list: fn _name, params ->
          send(self(), {:q, params})
          {:ok, %{rows: [%{id: "o1", item_id: "sword"}], total: 45}}
        end
      })

    [group] = ResourceRefs.referenced_by("itens", %{id: "sword"}, filter_opts)
    assert group.more == 25 and group.checked == nil
    assert_received {:q, %{filter: %{"item_id" => "sword"}}}

    # Not filterable and too large to scan completely: bounded, and honest about it.
    big = Enum.map(1..1000, &%{id: "o#{&1}", item_id: if(&1 == 3, do: "sword", else: "x")})

    scan =
      opts(%{
        list: fn name, _ ->
          if to_string(name) == "itens",
            do: {:ok, %{rows: @item_rows, total: 2}},
            else: {:ok, %{rows: big, total: 5000}}
        end
      })

    [group] = ResourceRefs.referenced_by("itens", %{id: "sword"}, scan)
    assert Enum.map(group.rows, & &1.id) == ["o3"]
    assert group.checked == 1000 and group.more == 0
  end
end
