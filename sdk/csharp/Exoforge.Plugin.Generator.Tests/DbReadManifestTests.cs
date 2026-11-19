using System;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json.Nodes;
using Microsoft.CodeAnalysis;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

public class DbReadManifestTests
{
    private static (JsonNode Manifest, Compilation Output, ImmutableArray<Diagnostic> Diagnostics) RunManifest(string source)
    {
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_dbread_{Guid.NewGuid():N}.json");

        try
        {
            var result = ((Compilation Output, ImmutableArray<Diagnostic> Diagnostics))typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path })!;

            return (JsonNode.Parse(File.ReadAllText(path))!, result.Output, result.Diagnostics);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    private static string[] DbRead(JsonNode manifest) =>
        manifest["db_read"]!.AsArray().Select(n => n!.GetValue<string>()).ToArray();

    private static string[] Dependencies(JsonNode manifest) =>
        manifest["dependencies"]!.AsArray().Select(n => n!.GetValue<string>()).ToArray();

    private static void AssertClean(Compilation output, ImmutableArray<Diagnostic> diagnostics)
    {
        Assert.Empty(diagnostics);
        var compileErrors = output.GetDiagnostics().Where(d => d.Severity == DiagnosticSeverity.Error).ToList();
        Assert.Empty(compileErrors);
    }

    [Fact]
    public void DbRead_Generic_Marker_Emits_DbRead_And_Dependency()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoExtension("items")]
            public abstract class ItemsMarker { }

            [ExoExtension("inventory")]
            [DbRead<ItemsMarker>]
            public partial class InventoryExtension
            {
                [ExoAction]
                public int Ping() => 1;
            }
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        Assert.Equal(new[] { "items" }, DbRead(manifest));
        Assert.Contains("items", Dependencies(manifest));
    }

    [Fact]
    public void DbRead_Interface_Marker_And_String_Id_Emit_DbRead_And_Dependency()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoExtension("catalog")]
            public interface ICatalogMarker { }

            [ExoExtension("inventory")]
            [DbRead<ICatalogMarker>]
            [DbRead("economy")]
            public partial class InventoryExtension
            {
                [ExoAction]
                public int Ping() => 1;
            }
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        Assert.Equal(new[] { "catalog", "economy" }, DbRead(manifest));
        Assert.Contains("catalog", Dependencies(manifest));
        Assert.Contains("economy", Dependencies(manifest));
    }

    [Fact]
    public void ForeignKey_On_Property_Infers_Reference_DbRead_Dependency_And_Excludes_Foreign_Resource()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoExtension("items")]
            public abstract class ItemsMarker
            {
                [ExoResource("items")]
                public class Record
                {
                    public string Id { get; set; } = "";
                }
            }

            [ExoExtension("inventory", Resources = new[] { typeof(PlayerItem) })]
            public partial class InventoryExtension
            {
                [ExoAction]
                public int Ping() => 1;
            }

            [ExoResource("player_items")]
            public class PlayerItem
            {
                public string Id { get; set; } = "";
                [ExoForeignKey<ItemsMarker.Record>("id")]
                public string ItemId { get; set; } = "";
            }
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        var resources = manifest["services"]!.AsArray()[0]!["resources"]!.AsArray();
        var ownResource = Assert.Single(resources);
        Assert.Equal("player_items", ownResource!["name"]?.GetValue<string>());

        var itemCol = ownResource["columns"]!.AsArray()
            .Single(c => c!["name"]?.GetValue<string>() == "item_id")!;
        Assert.True(itemCol["foreign_key"]?.GetValue<bool>());
        Assert.Equal("items.id", itemCol["references"]?.GetValue<string>());

        Assert.Equal(new[] { "items" }, DbRead(manifest));
        Assert.Contains("items", Dependencies(manifest));
    }

    [Fact]
    public void ForeignKey_On_Positional_Record_Parameter_Infers_Reference_And_DbRead()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoExtension("catalog")]
            public abstract class CatalogMarker
            {
                [ExoResource("catalog_items")]
                public class Item
                {
                    public string Sku { get; set; } = "";
                }
            }

            [ExoExtension("inventory", Resources = new[] { typeof(Slot) })]
            public partial class InventoryExtension
            {
                [ExoAction]
                public int Ping() => 1;
            }

            [ExoResource("slots")]
            public record Slot(string Id, [ExoForeignKey<CatalogMarker.Item>("sku")] string ItemSku);
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        var resources = manifest["services"]!.AsArray()[0]!["resources"]!.AsArray();
        var slotRes = Assert.Single(resources);
        Assert.Equal("slots", slotRes!["name"]?.GetValue<string>());

        var skuCol = slotRes["columns"]!.AsArray()
            .Single(c => c!["name"]?.GetValue<string>() == "item_sku")!;
        Assert.True(skuCol["foreign_key"]?.GetValue<bool>());
        Assert.Equal("catalog_items.sku", skuCol["references"]?.GetValue<string>());

        Assert.Contains("catalog", DbRead(manifest));
        Assert.Contains("catalog", Dependencies(manifest));
    }

    [Fact]
    public void Multiple_Sources_Deduplicate_And_Sort_DbRead_And_Dependencies()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoExtension("items")]
            public abstract class ItemsMarker
            {
                [ExoResource("items")]
                public class Record
                {
                    public string Id { get; set; } = "";
                }
            }

            [ExoExtension("catalog")]
            public abstract class CatalogMarker { }

            [ExoExtension("inventory", Resources = new[] { typeof(PlayerItem) })]
            [DbRead<ItemsMarker>]
            [DbRead<CatalogMarker>]
            public partial class InventoryExtension
            {
                [ExoAction]
                public int Ping() => 1;
            }

            [ExoResource("player_items")]
            public class PlayerItem
            {
                public string Id { get; set; } = "";
                [ExoForeignKey<ItemsMarker.Record>("id")]
                public string ItemId { get; set; } = "";
            }
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        Assert.Equal(new[] { "catalog", "items" }, DbRead(manifest));

        var deps = Dependencies(manifest);
        Assert.Equal(1, deps.Count(d => d == "catalog"));
        Assert.Equal(1, deps.Count(d => d == "items"));
    }

    [Fact]
    public void Local_And_SelfEnclosed_ForeignKey_Does_Not_Add_DbRead_Or_SelfDependency()
    {
        const string source = """
            using System.Linq;
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoResource("local_records")]
            public class LocalRecord
            {
                public string Id { get; set; } = "";
            }

            [ExoExtension("shop", Resources = new[] { typeof(Order), typeof(LocalRecord), typeof(OwnNestedRecord) })]
            public partial class ShopExtension
            {
                [ExoResource("own_nested_records")]
                public class OwnNestedRecord
                {
                    public string Id { get; set; } = "";
                }

                [ExoAction]
                public int Ping() => 1;
            }

            [ExoResource("orders")]
            public class Order
            {
                public string Id { get; set; } = "";
                [ExoForeignKey<LocalRecord>("id")]
                public string LocalId { get; set; } = "";
                [ExoForeignKey<ShopExtension.OwnNestedRecord>("id")]
                public string NestedId { get; set; } = "";
            }
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        var resources = manifest["services"]!.AsArray()[0]!["resources"]!.AsArray();
        var orderRes = resources.Single(r => r!["name"]?.GetValue<string>() == "orders")!;
        var cols = orderRes["columns"]!.AsArray();

        var localCol = cols.Single(c => c!["name"]?.GetValue<string>() == "local_id")!;
        Assert.True(localCol["foreign_key"]?.GetValue<bool>());
        Assert.Equal("local_records.id", localCol["references"]?.GetValue<string>());

        var nestedCol = cols.Single(c => c!["name"]?.GetValue<string>() == "nested_id")!;
        Assert.True(nestedCol["foreign_key"]?.GetValue<bool>());
        Assert.Equal("own_nested_records.id", nestedCol["references"]?.GetValue<string>());

        Assert.Empty(DbRead(manifest));
        Assert.DoesNotContain("shop", Dependencies(manifest));
    }

    [Fact]
    public void Extension_Without_DbRead_Or_Foreign_Keys_Emits_Empty_DbRead_Array()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace P;

            [ExoExtension("plain")]
            public partial class PlainExtension
            {
                [ExoAction]
                public int Ping() => 1;
            }
            """;

        var (manifest, output, diagnostics) = RunManifest(source);
        AssertClean(output, diagnostics);

        Assert.NotNull(manifest["db_read"]);
        Assert.Empty(DbRead(manifest));
    }
}
