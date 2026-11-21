using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json.Nodes;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

public class TypedManifestTests
{
    private static JsonNode Service(string source)
    {
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_typed_{Guid.NewGuid():N}.json");

        try
        {
            typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path });

            return JsonNode.Parse(File.ReadAllText(path))!["services"]!.AsArray()[0]!;
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Nested_Lists_Dictionaries_Records_And_Enums_Are_Described()
    {
        var service = Service("""
            using System.Collections.Generic;
            using Exoforge.Plugin.SDK;
            namespace P;
            public enum Raridade { Comum, MuitoRaro }
            public class Dono { public string Nome { get; set; } = ""; }
            public class Item
            {
                public int Slot { get; set; }
                public string? Nome { get; set; }
                public Raridade Raridade { get; set; }
                public List<Item> Filhos { get; set; } = new();
            }
            public class Inv
            {
                public string Id { get; set; } = "";
                public List<Item> Itens { get; set; } = new();
                public Dictionary<string, int> Contagens { get; set; } = new();
                public Dono? Dono { get; set; }
                public int? Preco { get; set; }
            }
            [ExoService("loja")]
            public partial class Loja
            {
                [ExoAction] public Inv Get(List<string> tags, Dictionary<string, Dono> donos) => new();
                [ExoAction] public Dictionary<string, int> Totais() => new();
            }
            """);

        var get = service["actions"]!.AsArray().Single(a => a!["name"]!.GetValue<string>() == "get")!;

        // The existing keys are untouched.
        Assert.Equal("list", get["returns"]!["itens"]!.GetValue<string>());
        Assert.Equal("map", get["returns"]!["contagens"]!.GetValue<string>());

        var shapes = get["returns_shapes"]!;
        Assert.Equal("Item", shapes["itens"]!["items"]!["ref"]!.GetValue<string>());
        Assert.Equal("int", shapes["contagens"]!["values"]!["type"]!.GetValue<string>());
        Assert.True(shapes["dono"]!["nullable"]!.GetValue<bool>());
        Assert.Null(shapes["id"]);
        Assert.Equal("record", get["returns_shape"]!["type"]!.GetValue<string>());
        Assert.Equal("Dono", get["params_shapes"]!["donos"]!["values"]!["ref"]!.GetValue<string>());

        var totais = service["actions"]!.AsArray().Single(a => a!["name"]!.GetValue<string>() == "totais")!;
        Assert.Equal("int", totais["returns_shape"]!["values"]!["type"]!.GetValue<string>());

        var types = service["types"]!;
        Assert.Equal(new[] { "Dono", "Inv", "Item" }, types.AsObject().Select(p => p.Key).OrderBy(k => k, StringComparer.Ordinal));

        var item = types["Item"]!["fields"]!;
        Assert.True(item["nome"]!["nullable"]!.GetValue<bool>());
        Assert.Equal(new[] { "comum", "muito_raro" }, item["raridade"]!["choices"]!.AsArray().Select(n => n!.GetValue<string>()));
        // A type that holds itself ends at its own reference.
        Assert.Equal("Item", item["filhos"]!["items"]!["ref"]!.GetValue<string>());
        Assert.True(types["Inv"]!["fields"]!["preco"]!["nullable"]!.GetValue<bool>());
    }

    [Fact]
    public void A_Service_Of_Scalars_Writes_No_Types_Or_Shapes()
    {
        var service = Service("""
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja")]
            public partial class Loja { [ExoAction] public int Dar(string id, int qtd) => qtd; }
            """);

        Assert.Null(service["types"]);
        var action = service["actions"]!.AsArray()[0]!;
        Assert.Null(action["returns_shape"]);
        Assert.Null(action["params_shapes"]);
    }

    [Fact]
    public void Wire_Names_Ignored_Properties_And_Dictionary_Keys_Follow_System_Text_Json()
    {
        var service = Service("""
            using System.Collections.Generic;
            using System.Text.Json.Serialization;
            using Exoforge.Plugin.SDK;
            namespace P;
            public class Child
            {
                [JsonPropertyName("display_name_v2")] public string DisplayName { get; set; } = "";
                [JsonIgnore(Condition = JsonIgnoreCondition.Always)] public string Secret { get; set; } = "";
                [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public string? Kept { get; set; }
                [JsonIgnore] public string Hidden { get; set; } = "";
                public string WriteOnly { set { } }
                public int this[int i] => i;
            }
            public class Reply
            {
                public Child Child { get; set; } = new();
                [JsonPropertyName("by_id")] public Dictionary<int, Child> ById { get; set; } = new();
                [JsonIgnore(Condition = JsonIgnoreCondition.Always)] public string Secret { get; set; } = "";
            }
            [ExoEvent("changed", PayloadType = typeof(Reply))]
            [ExoService("loja")]
            public partial class Loja { [ExoAction] public Reply Get() => new(); }
            """);

        var reply = service["actions"]!.AsArray()[0]!["returns"]!.AsObject();
        Assert.Equal(new[] { "by_id", "child" }, reply.Select(p => p.Key).OrderBy(k => k, StringComparer.Ordinal));
        Assert.Equal(new[] { "by_id", "child" }, service["events"]!.AsArray()[0]!["payload"]!.AsObject().Select(p => p.Key).OrderBy(k => k, StringComparer.Ordinal));

        var fields = service["types"]!["Child"]!["fields"]!.AsObject();
        Assert.Equal(new[] { "display_name_v2", "kept" }, fields.Select(p => p.Key).OrderBy(k => k, StringComparer.Ordinal));

        // A non-string key is not a string-keyed map.
        Assert.Equal("json", service["types"]!["Reply"]!["fields"]!["by_id"]!["type"]!.GetValue<string>());
    }
}
