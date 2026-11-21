using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

public class TypedStubsTests
{
    // inventario.get_inventory: a record with a list of records, a string-keyed dictionary, a nested record,
    // a nullable one and an enum - the shapes the plugin generator writes into the manifest.
    private const string Export = """
        {
          "export": { "extensions": [ { "id": "inventario", "services": [ {
            "name": "inventario",
            "actions": [
              { "name": "get_inventory", "scope": "player", "params": { "owner": "string", "tags": "list" },
                "params_shapes": { "tags": { "type": "list", "items": { "type": "string" } } },
                "returns": { "id": "string", "ouro": "integer", "itens": "list", "contagens": "map", "dono": "map", "extra": "map" },
                "returns_list": false, "returns_type": "global::P.InventarioDetalhado",
                "returns_shape": { "type": "record", "ref": "InventarioDetalhado" },
                "returns_shapes": {
                  "itens": { "type": "list", "items": { "type": "record", "ref": "InventarioItemDetalhado" } },
                  "contagens": { "type": "map", "values": { "type": "int" } },
                  "dono": { "type": "record", "ref": "Dono", "nullable": true } } },
              { "name": "totals", "scope": "player", "params": {}, "returns": "map", "returns_list": false,
                "returns_shape": { "type": "map", "values": { "type": "integer" } } },
              { "name": "old_style", "scope": "player", "params": {}, "returns": "map", "returns_list": false }
            ],
            "events": [],
            "types": {
              "InventarioDetalhado": { "fields": { "id": { "type": "string" }, "ouro": { "type": "integer" },
                "itens": { "type": "list", "items": { "type": "record", "ref": "InventarioItemDetalhado" } },
                "contagens": { "type": "map", "values": { "type": "int" } },
                "dono": { "type": "record", "ref": "Dono", "nullable": true } } },
              "InventarioItemDetalhado": { "fields": { "slot": { "type": "int" }, "nome": { "type": "string", "nullable": true },
                "raridade": { "type": "string", "choices": ["comum", "raro"] },
                "filhos": { "type": "list", "items": { "type": "record", "ref": "InventarioItemDetalhado" } } } },
              "Dono": { "fields": { "nome": { "type": "string" } } }
            }
          } ] } ] }
        }
        """;

    [Fact]
    public void Plugin_Stubs_Type_Nested_Values()
    {
        string code = ExoCodeGenerator.GeneratePluginStubs(Export, "Exoforge.Test.Generated");

        Assert.Contains("public class InventarioDetalhado", code);
        Assert.Contains("public List<InventarioItemDetalhado> Itens { get; set; }", code);
        Assert.Contains("public Dictionary<string, int> Contagens { get; set; }", code);
        Assert.Contains("public Dono? Dono { get; set; }", code);
        Assert.Contains("public string? Nome { get; set; }", code);
        Assert.Contains("public string Raridade { get; set; }", code);
        // A record that holds itself ends at the reference, not at a bare json.
        Assert.Contains("public List<InventarioItemDetalhado> Filhos { get; set; }", code);
        Assert.Contains("public List<string> Tags { get; set; }", code);
        Assert.Contains("Task<InventarioDetalhado?> GetInventoryAsync(", code);
        Assert.Contains("Task<Dictionary<string, long>?> TotalsAsync(", code);
        // Without shapes the old output is unchanged.
        Assert.Contains("Task<JsonElement> OldStyleAsync(", code);
        Assert.Equal(1, Count(code, "public class InventarioDetalhado"));
    }

    [Fact]
    public void Unity_Client_Uses_The_Same_Names()
    {
        string code = ExoCodeGenerator.GenerateFromExportJson(Export, "Game.Client");

        Assert.Contains("public class InventarioDetalhado", code);
        Assert.Contains("public List<InventarioItemDetalhado> Itens { get; set; }", code);
        Assert.Contains("public class InventarioItemDetalhado", code);
        Assert.Contains("Task<InventarioDetalhado> GetInventoryAsync(", code);
        Assert.Contains("Task<Dictionary<string, long>> TotalsAsync(", code);
        Assert.DoesNotContain("JsonElement Itens", code);
    }

    [Fact]
    public void A_Manifest_Without_Shapes_Still_Generates_As_Before()
    {
        const string old = """
            { "export": { "extensions": [ { "id": "x", "services": [ { "name": "x",
              "actions": [ { "name": "go", "scope": "player", "params": {}, "returns": { "id": "string", "itens": "list" }, "returns_list": false, "returns_type": "global::P.Big" } ], "events": [] } ] } ] } }
            """;

        string code = ExoCodeGenerator.GeneratePluginStubs(old);

        Assert.Contains("public class Big", code);
        Assert.Contains("public JsonElement Itens { get; set; }", code);
    }

    [Fact]
    public void Same_Named_Records_Are_Shared_Across_Services_Only_When_Everything_Under_Them_Matches()
    {
        const string two = """
            { "export": { "extensions": [ { "id": "x", "services": [
              { "name": "a", "events": [], "actions": [ { "name": "get", "scope": "player", "params": {}, "returns": "map", "returns_shape": { "type": "record", "ref": "Outer" } } ],
                "types": { "Outer": { "fields": { "child": { "type": "record", "ref": "Child" } } }, "Child": { "fields": { "x": { "type": "int" } } } } },
              { "name": "b", "events": [], "actions": [ { "name": "get", "scope": "player", "params": {}, "returns": "map", "returns_shape": { "type": "record", "ref": "Outer" } } ],
                "types": { "Outer": { "fields": { "child": { "type": "record", "ref": "Child" } } }, "Child": { "fields": { "y": { "type": "string" } } } } }
            ] } ] } }
            """;

        string code = ExoCodeGenerator.GeneratePluginStubs(two);

        Assert.Contains("public class Outer", code);
        Assert.Contains("public class BOuter", code);
        Assert.Contains("public class Child", code);
        Assert.Contains("public class BChild", code);
        Assert.Contains("public BChild Child { get; set; }", code);
    }

    [Fact]
    public void A_Nullable_Rich_Return_Keeps_Its_Question_Mark()
    {
        const string nullable = """
            { "export": { "extensions": [ { "id": "x", "services": [ { "name": "x", "events": [],
              "actions": [ { "name": "get", "scope": "player", "params": {}, "returns": "map", "returns_shape": { "type": "record", "ref": "Inv", "nullable": true } } ],
              "types": { "Inv": { "fields": { "id": { "type": "string" } } } } } ] } ] } }
            """;

        string unity = ExoCodeGenerator.GenerateFromExportJson(nullable);
        Assert.Contains("Task<Inv?> GetAsync(", unity);
        Assert.Contains("Action<Inv?> onComplete", unity);

        string plugin = ExoCodeGenerator.GeneratePluginStubs(nullable);
        Assert.Contains("Task<Inv?> GetAsync(", plugin);
        Assert.DoesNotContain("Inv??", plugin);
    }

    private static int Count(string text, string needle)
    {
        int count = 0;
        for (int i = text.IndexOf(needle); i >= 0; i = text.IndexOf(needle, i + needle.Length)) count++;
        return count;
    }
}
