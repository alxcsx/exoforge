using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json.Nodes;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

public class NullableManifestTests
{
    [Fact]
    public void Nullable_Value_Types_Are_Listed_In_The_Manifest()
    {
        const string source = """
            using System.Collections.Generic;
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja", Resources = new[] { typeof(Item) })]
            public partial class Loja { [ExoAction] public List<Item> Listar() => new(); }
            [ExoResource("itens")]
            public class Item { public string Id { get; set; } = ""; public int? Preco { get; set; } public int Qtd { get; set; } }
            """;
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_nullable_{Guid.NewGuid():N}.json");

        try
        {
            typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path });

            JsonNode service = JsonNode.Parse(File.ReadAllText(path))!["services"]!.AsArray()[0]!;
            JsonNode action = service["actions"]!.AsArray()[0]!;

            Assert.Equal("integer", action["returns"]!["preco"]!.GetValue<string>());
            Assert.Equal(new[] { "preco" }, action["returns_nullable"]!.AsArray().Select(n => n!.GetValue<string>()));

            var columns = service["resources"]!.AsArray()[0]!["columns"]!.AsArray();
            Assert.True(columns.Single(c => c!["name"]!.GetValue<string>() == "preco")!["nullable"]!.GetValue<bool>());
            Assert.Null(columns.Single(c => c!["name"]!.GetValue<string>() == "qtd")!["nullable"]);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Parameter_Defaults_And_Nullability_Are_Listed_In_The_Manifest()
    {
        const string source = """
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja")]
            public partial class Loja { [ExoAction] public int Comprar(string id, int qtd = 1, int? desconto = null, string nota = "a\"b") => qtd; }
            """;
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_params_{Guid.NewGuid():N}.json");

        try
        {
            typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path });

            JsonNode action = JsonNode.Parse(File.ReadAllText(path))!["services"]!.AsArray()[0]!["actions"]!.AsArray()[0]!;

            Assert.Equal(new[] { "qtd", "desconto", "nota" }, action["params_optional"]!.AsArray().Select(n => n!.GetValue<string>()));
            Assert.Equal(new[] { "desconto" }, action["params_nullable"]!.AsArray().Select(n => n!.GetValue<string>()));
            Assert.Equal(1, action["params_defaults"]!["qtd"]!.GetValue<int>());
            Assert.Equal("a\"b", action["params_defaults"]!["nota"]!.GetValue<string>());
            Assert.Null(action["params_defaults"]!["desconto"]);
            Assert.Null(action["params_defaults"]!["id"]);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Lists_Are_Typed_By_Element_Not_Emitted_As_Map()
    {
        const string source = """
            using System.Collections.Generic;
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja", Resources = new[] { typeof(Inv) })]
            public partial class Loja { [ExoAction] public int Dar(List<string> itens, long[] ids) => 0; }
            [ExoResource("inventario")]
            public class Inv { public string Id { get; set; } = ""; public List<string> Itens { get; set; } = new(); public List<Inv> Filhos { get; set; } = new(); public byte[] Blob { get; set; } = new byte[0]; }
            """;
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_lists_{Guid.NewGuid():N}.json");

        try
        {
            typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path });

            JsonNode service = JsonNode.Parse(File.ReadAllText(path))!["services"]!.AsArray()[0]!;
            JsonNode parameters = service["actions"]!.AsArray()[0]!["params"]!;
            Assert.Equal("[:string]", parameters["itens"]!.GetValue<string>());
            Assert.Equal("[:integer]", parameters["ids"]!.GetValue<string>());

            string Column(string name) => service["resources"]!.AsArray()[0]!["columns"]!.AsArray()
                .Single(c => c!["name"]!.GetValue<string>() == name)!["type"]!.GetValue<string>();

            Assert.Equal("[:string]", Column("itens"));
            Assert.Equal("list", Column("filhos"));
            Assert.Equal("binary", Column("blob"));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
