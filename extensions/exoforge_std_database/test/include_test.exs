defmodule Exoforge.Std.Database.IncludeTest do
  @moduledoc """
  `database.execute` with `include`: a foreign key column resolved across two extensions, with the
  referenced resource's own permission rule.
  """
  use ExUnit.Case, async: false

  alias Exoforge.ActionDispatcher
  alias Exoforge.Std.Database
  alias Exoforge.Std.Lldb.Manager

  defmodule Stub do
    use Exoforge.Extension
  end

  setup do
    Exoforge.ExtensionCase.start_kernel()
    unless Process.whereis(Manager), do: start_supervised!(Manager)
    start_supervised!(Exoforge.Std.Database.KindCache)
    Exoforge.ExtensionCase.register_database(Database)

    n = System.unique_integer([:positive])
    shop = :"inc_shop_#{n}"
    catalog = :"inc_catalog_#{n}"
    on_exit(fn -> Enum.each([shop, catalog], &Database.reset!/1) end)

    items = "itens_#{n}"
    secrets = "segredos_#{n}"
    offers = "ofertas_#{n}"

    col = fn name, extra -> Map.merge(%{name: name, storage: "text", nullable: true}, extra) end
    pk = %{primary_key: true, nullable: false}

    resources_catalog = [
      %{name: items, source: %{table: items}, primary_key: "id", allow_player_read: true, columns: [col.("id", pk), col.("name", %{})]},
      %{name: secrets, source: %{table: secrets}, primary_key: "id", columns: [col.("id", pk), col.("name", %{})]}
    ]

    resources_shop = [
      %{
        name: offers,
        source: %{table: offers},
        primary_key: "id",
        columns: [
          col.("id", pk),
          col.("item_id", %{foreign_key: true, references: "#{items}.id"}),
          col.("secret_id", %{foreign_key: true, references: "#{secrets}.id"}),
          col.("ghost_id", %{foreign_key: true, references: "nowhere_#{n}.id"}),
          col.("note", %{})
        ]
      }
    ]

    register(catalog, resources_catalog)
    register(shop, resources_shop)

    for {plugin, resources} <- [{catalog, resources_catalog}, {shop, resources_shop}] do
      assert {:ok, _} = ActionDispatcher.dispatch_internal(:lldb, :apply_schema, %{namespace: plugin, resources: resources})
    end

    sql = fn plugin, q, args -> {:ok, _} = Database.execute(plugin, q, args) end
    sql.(catalog, "INSERT INTO #{items} (id, name) VALUES ('sword', 'Sword'), ('shield', 'Shield')", [])
    sql.(catalog, "INSERT INTO #{secrets} (id, name) VALUES ('s1', 'Hidden')", [])

    sql.(
      shop,
      "INSERT INTO #{offers} (id, item_id, secret_id, ghost_id, note) VALUES " <>
        "('o1', 'sword', 's1', 'x', 'a'), ('o2', 'sword', 's1', 'x', 'b'), ('o3', 'shield', NULL, NULL, 'c'), " <>
        "('o4', NULL, NULL, NULL, 'd'), ('o5', 'gone', NULL, NULL, 'e')",
      []
    )

    {:ok, shop: shop, catalog: catalog, offers: offers, items: items, secrets: secrets}
  end

  defp register(id, resources) do
    Exoforge.ExtensionCase.register_extension(Stub,
      id: id,
      services: [%{name: "#{id}_svc", actions: [], events: [], resources: resources}]
    )
  end

  # database.execute is server-only: it is reached by an extension's own call, which runs inside the
  # request that started it. The scopes are those of that request (a player's, a studio's, or the server's).
  defp run(ctx, include, scopes, extra \\ %{}) do
    payload =
      Map.merge(
        %{plugin: ctx.shop, query: "SELECT * FROM #{ctx.offers} ORDER BY id", args: [], include: include},
        extra
      )

    previous = Exoforge.RequestContext.enter(%{origin: "caller", rid: "r_inc", depth: 0, capture: nil, internal: false, scopes: scopes})

    try do
      ActionDispatcher.dispatch_internal(:database, :execute, payload)
    after
      Exoforge.RequestContext.restore(previous)
    end
  end

  @tag :postgres
  test "a foreign key into another extension comes back in included, keyed by value", ctx do
    assert {:ok, %{rows: rows, included: %{"item_id" => items}} = res} = run(ctx, [%{"column" => "item_id"}], [])
    assert length(rows) == 5
    # a player may read it: the resource is allow_player_read
    assert %{"sword" => %{"id" => "sword", "name" => "Sword"}, "shield" => %{"name" => "Shield"}} = items
    # a dangling value (gone) and a null are simply absent
    assert Map.keys(items) |> Enum.sort() == ["shield", "sword"]
    refute Map.has_key?(res, :warnings)
  end

  @tag :postgres
  test "the same query without include answers as before", ctx do
    assert {:ok, res} = run(ctx, nil, [], %{include: nil})
    refute Map.has_key?(res, :included)
  end

  @tag :postgres
  test "a player gets nothing from a resource that is not player readable; server and studio do", ctx do
    assert {:ok, %{included: %{"secret_id" => none}}} = run(ctx, [%{"column" => "secret_id"}], ["player"])
    assert none == %{}

    for scopes <- [["studio"], ["service"], ["admin"], :internal] do
      assert {:ok, %{included: %{"secret_id" => %{"s1" => %{"name" => "Hidden"}}}}} =
               run(ctx, [%{"column" => "secret_id"}], scopes)
    end
  end

  @tag :postgres
  test "a column that is not a declared foreign key is invalid_include, and nothing runs", ctx do
    assert {:error, {:invalid_include, msg}} = run(ctx, [%{"column" => "note"}], [])
    assert msg =~ "note"
    assert {:error, {:invalid_include, _}} = run(ctx, [%{"column" => "nope"}], [])
    assert {:error, {:invalid_include, _}} = run(ctx, [%{}], [])
    assert {:error, {:invalid_include, _}} = run(ctx, "item_id", [])
  end

  @tag :postgres
  test "a reference to a resource no extension declares is a warning, not a crash", ctx do
    assert {:ok, %{rows: [_ | _], included: included, warnings: [warning]}} =
             run(ctx, [%{"column" => "ghost_id"}, %{"column" => "item_id"}], [])

    assert %{code: "missing_reference", column: "ghost_id"} = warning
    refute Map.has_key?(included, "ghost_id")
    assert Map.has_key?(included, "item_id")
  end

  @tag :postgres
  test "N rows with distinct values cost one query on the owner, not N", ctx do
    Exoforge.ActionTrace.enable()
    rid = "r_inc_count_#{System.unique_integer([:positive])}"
    previous = Exoforge.RequestContext.enter(%{origin: "caller", rid: rid, depth: 0, capture: :deep, internal: false, scopes: []})

    try do
      payload = %{plugin: ctx.shop, query: "SELECT * FROM #{ctx.offers}", args: [], include: [%{"column" => "item_id"}]}
      assert {:ok, %{rows: rows, included: %{"item_id" => items}}} = ActionDispatcher.dispatch_internal(:database, :execute, payload)
      assert length(rows) == 5
      assert map_size(items) == 2
    after
      Exoforge.RequestContext.restore(previous)
    end

    # five rows, three of them carrying a value, two distinct: the root query and one fetch from the owner
    execs = Enum.filter(Exoforge.ActionTrace.for_rid(rid), &(&1.key == "lldb.exec"))
    assert length(execs) == 2
  end
end
