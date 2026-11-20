using System;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json.Nodes;
using Microsoft.CodeAnalysis;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

/// <summary>The migrations an extension declares on the way to a version, as the manifest tells the server.</summary>
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
    public void A_Resource_Carries_No_Version_Of_Its_Own()
    {
        var (manifest, _) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }
            """);

        var resource = manifest["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!;
        Assert.Null(resource["version"]);
    }

    [Fact]
    public void A_Resource_The_Studio_Owns_Says_So_And_The_Default_Says_Nothing()
    {
        var (manifest, _) = Run(Preamble + """

            [ExoResource("items", SchemaVersioningMode = SchemaVersioningMode.Manual)]
            public class Item { public string Id { get; set; } = ""; }
            """);

        var (auto, _) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }
            """);

        JsonNode Resource(JsonNode m) => m["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!;

        Assert.Equal("manual", Resource(manifest)["schema_versioning_mode"]!.GetValue<string>());
        Assert.Null(Resource(auto)["schema_versioning_mode"]);
    }

    [Fact]
    public void A_Migration_Class_Lists_Its_Operations_In_Order_With_Where_It_Is_Declared()
    {
        var (manifest, diagnostics) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; public decimal Price { get; set; } public string Name { get; set; } = ""; }

            [ExoMigration(typeof(Item), To = "1.2.0")]
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
        Assert.Equal("1.2.0", migration["to"]!.GetValue<string>());
        Assert.Null(migration["from"]);
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
    public void Migrations_Come_Out_Ordered_By_Resource_And_Version_Number_Whatever_Order_They_Are_Written_In()
    {
        var (manifest, _) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }

            [ExoMigration(typeof(Item), To = "1.10.0")]
            [ExoDrop("b")]
            public static class ItemsV110 { }

            [ExoMigration(typeof(Item), To = "1.2.0")]
            [ExoDrop("a")]
            public static class ItemsV12 { }
            """);

        // 1.2.0 before 1.10.0: by number, not by text
        Assert.Equal(new[] { "1.2.0", "1.10.0" }, manifest["migrations"]!.AsArray().Select(m => m!["to"]!.GetValue<string>()));
    }

    [Fact]
    public void A_Migration_Needs_An_Extension_Version_To_Lead_To()
    {
        var (_, diagnostics) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }

            [ExoMigration(typeof(Item), To = "two")]
            [ExoDrop("a")]
            public static class Bad { }
            """);

        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Contains("MAJOR.MINOR.PATCH", error.GetMessage());
    }

    [Fact]
    public void Two_Migrations_To_The_Same_Version_Are_An_Error()
    {
        var (_, diagnostics) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }

            [ExoMigration(typeof(Item), To = "1.2.0")]
            [ExoDrop("a")]
            public static class One { }

            [ExoMigration(typeof(Item), To = "1.2.0")]
            [ExoDrop("b")]
            public static class Two { }
            """);

        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Contains("two migrations to version 1.2.0", error.GetMessage());
    }

    [Theory]
    [InlineData("2.1.0")]
    [InlineData("0.1.0")]
    [InlineData("10.20.30")]
    [InlineData("1.4.0-beta.1")]
    [InlineData("nonsense")]
    [InlineData("1.1000.0")]
    public void The_Generator_And_The_SDK_Encode_Versions_The_Same_Way(string version)
    {
        // Both are reached by name: the emitter is internal to the generator assembly, and naming the
        // generator's types here would make the build read this project as depending on a service.
        var emitter = typeof(ResourceValidationTests).Assembly.GetReferencedAssemblies()
            .Where(a => a.Name == "Exoforge.Plugin.Generator").Select(Assembly.Load).Single()
            .GetTypes().Single(t => t.Name == "ManifestEmitter");
        long generator = (long)emitter.GetMethod("EncodeVersion", BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Static)!.Invoke(null, new object?[] { version })!;
        long sdk = (long)Assembly.Load("Exoforge.Plugin.SDK").GetType("Exoforge.Plugin.SDK.ExoVersion")!.GetMethod("Encode")!.Invoke(null, new object?[] { version })!;

        Assert.Equal(sdk, generator);
    }

    [Fact]
    public void A_Migration_For_A_Type_That_Is_Not_A_Resource_Is_An_Error()
    {
        var (_, diagnostics) = Run(Preamble + """

            [ExoResource("items")]
            public class Item { public string Id { get; set; } = ""; }

            public class NotAResource { }

            [ExoMigration(typeof(NotAResource), To = "1.2.0")]
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

    [Fact]
    public void Revisions_Of_An_Action_Show_As_One_Action_The_Newest()
    {
        var (manifest, diagnostics) = Run("""
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("svc")]
            public partial class Svc
            {
                [ExoAction("score")] public int ScoreV1(int a) => a;
                [ExoAction("score", FromVersion = "2.0.0")] public string ScoreV2(int a, int b) => "";
            }
            """);

        Assert.DoesNotContain(diagnostics, d => d.Severity == DiagnosticSeverity.Error);
        var actions = manifest["services"]!.AsArray()[0]!["actions"]!.AsArray();
        var score = Assert.Single(actions.Where(a => a!["name"]!.GetValue<string>() == "score"))!;
        Assert.Equal(2, score["arity"]!.GetValue<int>());
    }
}
