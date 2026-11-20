using System;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json.Nodes;
using Microsoft.CodeAnalysis;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

/// <summary>Resource versions and the migrations between them, as the manifest tells the server (T6).</summary>
public class MigrationManifestTests
{
    private static (JsonNode Manifest, ImmutableArray<Diagnostic> Diagnostics) Run(string source)
    {
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_migration_{Guid.NewGuid():N}.json");

        try
        {
            var result = ((Compilation, ImmutableArray<Diagnostic>))typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path })!;

            JsonNode manifest = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))! : new JsonObject();
            return (manifest, result.Item2);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    private const string Preamble = """
        using Exoforge.Plugin.SDK;
        namespace P;
        [ExoService("svc", Resources = new[] { typeof(Item) })]
        public partial class Svc { }
        """;

    [Fact]
    public void A_Resource_Has_Version_One_Unless_It_Says_Otherwise()
    {
        var (plain, _) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }
            """);

        var (second, _) = Run(Preamble + """

            [ExoResource("items", Version = 2)]
            public class Item { public string Id { get; set; } = ""; }
            """);

        JsonNode Resource(JsonNode m) => m["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!;

        Assert.Equal(1, Resource(plain)["version"]!.GetValue<int>());
        Assert.Equal(2, Resource(second)["version"]!.GetValue<int>());
    }

    [Fact]
    public void A_Migration_Class_Lists_Its_Operations_In_Order_With_Where_It_Is_Declared()
    {
        var (manifest, diagnostics) = Run(Preamble + """

            [ExoResource("items", Version = 2)]
            public class Item { public string Id { get; set; } = ""; public decimal Price { get; set; } public string Name { get; set; } = ""; }

            [ExoMigration(typeof(Item), From = 1, To = 2)]
            [ExoRename("nm", "Name")]
            [ExoConvert("Price", ExoType.Decimal)]
            [ExoFill("rarity", "common")]
            [ExoFill("tier", 3)]
            [ExoFill("flag", true)]
            [ExoDrop("legacyFlag")]
            [ExoSetNotNull("owner", Fill = "nobody")]
            public static class ItemsV2 { }
            """);

        Assert.DoesNotContain(diagnostics, d => d.Id == "EXO005");

        var migration = Assert.Single(manifest["migrations"]!.AsArray())!;
        Assert.Equal("items", migration["resource"]!.GetValue<string>());
        Assert.Equal(1, migration["from"]!.GetValue<int>());
        Assert.Equal(2, migration["to"]!.GetValue<int>());
        Assert.Matches(@"^Resources\.cs:\d+$", migration["decl"]!.GetValue<string>());

        var ops = migration["ops"]!.AsArray();
        Assert.Equal(new[] { "rename", "convert", "fill", "fill", "fill", "drop", "set_not_null" }, ops.Select(o => o!["op"]!.GetValue<string>()));

        // names are written as the manifest names columns: snake_case
        Assert.Equal("nm", ops[0]!["from"]!.GetValue<string>());
        Assert.Equal("name", ops[0]!["to"]!.GetValue<string>());
        Assert.Equal("price", ops[1]!["column"]!.GetValue<string>());
        Assert.Equal("decimal", ops[1]!["to"]!.GetValue<string>());
        Assert.Equal("common", ops[2]!["value"]!.GetValue<string>());
        Assert.Equal(3, ops[3]!["value"]!.GetValue<int>());
        Assert.True(ops[4]!["value"]!.GetValue<bool>());
        Assert.Equal("legacy_flag", ops[5]!["column"]!.GetValue<string>());
        Assert.Equal("owner", ops[6]!["column"]!.GetValue<string>());
        Assert.Equal("nobody", ops[6]!["value"]!.GetValue<string>());
    }

    [Fact]
    public void Migrations_Come_Out_Ordered_By_Resource_And_Version_Whatever_Order_They_Are_Written_In()
    {
        var (manifest, _) = Run(Preamble + """

            [ExoResource("items", Version = 3)]
            public class Item { public string Id { get; set; } = ""; }

            [ExoMigration(typeof(Item), From = 2, To = 3)]
            [ExoDrop("b")]
            public static class ItemsV3 { }

            [ExoMigration(typeof(Item), From = 1, To = 2)]
            [ExoDrop("a")]
            public static class ItemsV2 { }
            """);

        Assert.Equal(new[] { 1, 2 }, manifest["migrations"]!.AsArray().Select(m => m!["from"]!.GetValue<int>()));
    }

    [Fact]
    public void A_Migration_Must_Step_One_Version()
    {
        var (_, diagnostics) = Run(Preamble + """

            [ExoResource("items", Version = 3)]
            public class Item { public string Id { get; set; } = ""; }

            [ExoMigration(typeof(Item), From = 1, To = 3)]
            [ExoDrop("a")]
            public static class Skip { }
            """);

        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Contains("To = From + 1", error.GetMessage());
    }

    [Fact]
    public void Two_Migrations_From_The_Same_Version_Are_An_Error()
    {
        var (_, diagnostics) = Run(Preamble + """

            [ExoResource("items", Version = 2)]
            public class Item { public string Id { get; set; } = ""; }

            [ExoMigration(typeof(Item), From = 1, To = 2)]
            [ExoDrop("a")]
            public static class One { }

            [ExoMigration(typeof(Item), From = 1, To = 2)]
            [ExoDrop("b")]
            public static class Two { }
            """);

        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Contains("two migrations from version 1", error.GetMessage());
    }

    [Fact]
    public void A_Migration_For_A_Type_That_Is_Not_A_Resource_Is_An_Error()
    {
        var (_, diagnostics) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }

            public class NotAResource { }

            [ExoMigration(typeof(NotAResource), From = 1, To = 2)]
            [ExoDrop("a")]
            public static class Lost { }
            """);

        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Contains("[ExoResource]", error.GetMessage());
    }

    [Fact]
    public void An_Extension_Without_Migrations_Lists_None()
    {
        var (manifest, _) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }
            """);

        Assert.Empty(manifest["migrations"]!.AsArray());
    }
}
