using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Exoforge.Plugin.SDK;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Diagnostics;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

public class ResourceValidationTests
{
    private sealed class TestOptions : AnalyzerConfigOptions
    {
        private readonly Dictionary<string, string> _values;
        public TestOptions(Dictionary<string, string> values) => _values = values;
        public override bool TryGetValue(string key, [NotNullWhen(true)] out string? value) =>
            _values.TryGetValue(key, out value);
    }

    private sealed class TestOptionsProvider : AnalyzerConfigOptionsProvider
    {
        private static readonly AnalyzerConfigOptions Empty = new TestOptions(new());
        public TestOptionsProvider(Dictionary<string, string> global) => GlobalOptions = new TestOptions(global);
        public override AnalyzerConfigOptions GlobalOptions { get; }
        public override AnalyzerConfigOptions GetOptions(SyntaxTree tree) => Empty;
        public override AnalyzerConfigOptions GetOptions(AdditionalText textFile) => Empty;
    }

    private static (Compilation Output, ImmutableArray<Diagnostic> Diagnostics) RunGenerator(
        string source,
        string? manifestPath = null)
    {
        var syntaxTree = CSharpSyntaxTree.ParseText(source, path: "Resources.cs");
        var references = AppDomain.CurrentDomain.GetAssemblies()
            .Where(a => !a.IsDynamic && !string.IsNullOrEmpty(a.Location))
            .Select(a => MetadataReference.CreateFromFile(a.Location))
            .Cast<MetadataReference>()
            .ToList();

        var sdkLocation = typeof(ExoServiceAttribute).Assembly.Location;
        if (!references.Any(r => r.Display == sdkLocation))
        {
            references.Add(MetadataReference.CreateFromFile(sdkLocation));
        }

        var compilation = CSharpCompilation.Create(
            "TestPlugin",
            new[] { syntaxTree },
            references,
            new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary));

        var globals = new Dictionary<string, string>();
        if (manifestPath is not null)
        {
            globals["build_property.ExoforgeManifestPath"] = manifestPath;
        }

        var driver = CSharpGeneratorDriver.Create(
            generators: new[] { new ExoforgePluginGenerator().AsSourceGenerator() },
            optionsProvider: new TestOptionsProvider(globals));

        driver.RunGeneratorsAndUpdateCompilation(compilation, out var output, out var diagnostics);
        return (output, diagnostics);
    }

    [Fact]
    public void Duplicate_Column_Ignoring_Case_Reports_EXO005_Error()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace TestPlugin;

            [ExoService("test_svc", Resources = new[] { typeof(DupRecord) })]
            public partial class TestPlugin { }

            [ExoResource("dups")]
            public class DupRecord
            {
                public string Id { get; set; } = "";
                public string DisplayName { get; set; } = "";
                [ExoColumn("DISPLAY_NAME")]
                public string Alias { get; set; } = "";
            }
            """;

        var (_, diagnostics) = RunGenerator(source);
        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Equal(DiagnosticSeverity.Error, error.Severity);
        Assert.Contains("DisplayName", error.GetMessage());
        Assert.Contains("Alias", error.GetMessage());
    }

    [Fact]
    public void PrimaryKey_Naming_No_Column_Reports_EXO005_Error()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace TestPlugin;

            [ExoService("test_svc", Resources = new[] { typeof(BadPkRecord) })]
            public partial class TestPlugin { }

            [ExoResource("bad_pks", PrimaryKey = "MissingKey")]
            public class BadPkRecord
            {
                public string Id { get; set; } = "";
                public string Name { get; set; } = "";
            }
            """;

        var (_, diagnostics) = RunGenerator(source);
        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Equal(DiagnosticSeverity.Error, error.Severity);
        Assert.Contains("missing_key", error.GetMessage());
    }

    [Fact]
    public void Implicit_Id_PrimaryKey_Without_Id_Property_Reports_No_Diagnostic()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace TestPlugin;

            [ExoService("test_svc", Resources = new[] { typeof(ImplicitIdRecord) })]
            public partial class TestPlugin { }

            [ExoResource("implicit_ids", PrimaryKey = "id")]
            public class ImplicitIdRecord
            {
                public string Name { get; set; } = "";
            }
            """;

        var (_, diagnostics) = RunGenerator(source);
        Assert.DoesNotContain(diagnostics, d => d.Id == "EXO005");
    }

    [Fact]
    public void Invalid_Explicit_Column_Name_Reports_EXO005_Error()
    {
        const string source = """
            using Exoforge.Plugin.SDK;

            namespace TestPlugin;

            [ExoService("test_svc", Resources = new[] { typeof(BadColRecord) })]
            public partial class TestPlugin { }

            [ExoResource("bad_cols")]
            public class BadColRecord
            {
                public string Id { get; set; } = "";
                [ExoColumn("bad-name")]
                public string BadProp { get; set; } = "";
            }
            """;

        var (_, diagnostics) = RunGenerator(source);
        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Equal(DiagnosticSeverity.Error, error.Severity);
        Assert.Contains("BadProp", error.GetMessage());
    }

    [Fact]
    public void Explicit_Column_Name_Is_Lowercased_And_Acronym_ToSnakeCase_Applies()
    {
        var manifestPath = Path.Combine(Path.GetTempPath(), $"exoforge_test_{Guid.NewGuid():N}.json");
        try
        {
            const string source = """
                using Exoforge.Plugin.SDK;

                namespace TestPlugin;

                [ExoService("test_svc", Resources = new[] { typeof(AcronymRecord) })]
                public partial class TestPlugin
                {
                    [ExoAction]
                    public int SubmitScore(string playerID, int httpCode) => httpCode;
                }

                [ExoResource("acronyms", PrimaryKey = nameof(ID))]
                public class AcronymRecord
                {
                    public string ID { get; set; } = "";
                    public string PlayerID { get; set; } = "";
                    public int HTTPCode { get; set; }
                    [ExoColumn("Custom_Col")]
                    public string CustomProp { get; set; } = "";
                }
                """;

            var (_, diagnostics) = RunGenerator(source, manifestPath);
            Assert.Empty(diagnostics);

            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!;
            var svc = manifest["services"]!.AsArray()[0]!;

            var action = svc["actions"]!.AsArray().First(a => a!["name"]?.GetValue<string>() == "submit_score")!;
            var paramObj = action["params"]!.AsObject();
            Assert.True(paramObj.ContainsKey("player_id"));
            Assert.True(paramObj.ContainsKey("http_code"));

            var res = svc["resources"]!.AsArray()[0]!;
            Assert.Equal("id", res["primary_key"]?.GetValue<string>());
            var colNames = res["columns"]!.AsArray().Select(c => c!["name"]?.GetValue<string>()).ToList();
            Assert.Contains("id", colNames);
            Assert.Contains("player_id", colNames);
            Assert.Contains("http_code", colNames);
            Assert.Contains("custom_col", colNames);
        }
        finally
        {
            if (File.Exists(manifestPath)) File.Delete(manifestPath);
        }
    }

    [Fact]
    public void LojaItens_Compiles_With_No_Diagnostic_And_Emits_Lowercase_PrimaryKey()
    {
        var manifestPath = Path.Combine(Path.GetTempPath(), $"exoforge_loja_{Guid.NewGuid():N}.json");
        try
        {
            const string source = """
                using System.Collections.Generic;
                using Exoforge.Plugin.SDK;

                namespace Exoforge.Extensions;

                [ExoExtension("loja_itens", Version = "0.1.0", Resources = [typeof(Inventario), typeof(Item)])]
                public class LojaItensExtension
                {
                    [ExoAction(Scope = "player")]
                    public IReadOnlyList<Item> ListarItens() => ExoServices.Database.All<Item>();
                }

                [ExoResource("inventario", PrimaryKey = nameof(Id))]
                public class Inventario
                {
                    [ExoColumn(Label = "ID", PrimaryKey = true)] public string Id { get; set; } = "";
                    [ExoColumn(Label = "Ouro")] public int Ouro { get; set; }
                    [ExoColumn(Label = "Itens")] public List<string> Itens { get; set; } = new();
                }

                [ExoResource("itens", PrimaryKey = nameof(Id))]
                public class Item
                {
                    [ExoColumn(Label = "ID", PrimaryKey = true)] public string Id { get; set; } = "";
                    [ExoColumn(Label = "Nome")] public string Nome { get; set; } = "";
                    [ExoColumn(Label = "Tipo")] public string Tipo { get; set; } = "";
                    [ExoColumn(Label = "Preco")] public int Preco { get; set; }
                }
                """;

            var (output, diagnostics) = RunGenerator(source, manifestPath);
            Assert.Empty(diagnostics);
            var compileErrors = output.GetDiagnostics().Where(d => d.Severity == DiagnosticSeverity.Error).ToList();
            Assert.Empty(compileErrors);

            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!;
            var resources = manifest["services"]!.AsArray()[0]!["resources"]!.AsArray();
            Assert.Equal(2, resources.Count);
            foreach (var res in resources)
            {
                Assert.Equal("id", res!["primary_key"]?.GetValue<string>());
            }
        }
        finally
        {
            if (File.Exists(manifestPath)) File.Delete(manifestPath);
        }
    }

    [Fact]
    public void ReferencesType_With_Local_Resource_Infers_Target_Table_And_PrimaryKey()
    {
        var manifestPath = Path.Combine(Path.GetTempPath(), $"exoforge_reftype_{Guid.NewGuid():N}.json");
        try
        {
            const string source = """
                using Exoforge.Plugin.SDK;

                namespace TestPlugin;

                [ExoService("orders_svc", Resources = new[] { typeof(OrderRecord), typeof(CustomerRecord) })]
                public partial class TestPlugin { }

                [ExoResource("customers", PrimaryKey = "id")]
                public class CustomerRecord
                {
                    public string Id { get; set; } = "";
                    public string Name { get; set; } = "";
                }

                [ExoResource("orders")]
                public class OrderRecord
                {
                    public string Id { get; set; } = "";
                    [ExoColumn(ReferencesType = typeof(CustomerRecord))]
                    public string CustomerId { get; set; } = "";
                }
                """;

            var (output, diagnostics) = RunGenerator(source, manifestPath);
            Assert.Empty(diagnostics);

            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!;
            var svc = manifest["services"]!.AsArray()[0]!;
            var ordersRes = svc["resources"]!.AsArray().First(r => r!["name"]?.GetValue<string>() == "orders")!;
            var custCol = ordersRes["columns"]!.AsArray().First(c => c!["name"]?.GetValue<string>() == "customer_id")!;

            Assert.True(custCol["foreign_key"]?.GetValue<bool>());
            Assert.Equal("customers.id", custCol["references"]?.GetValue<string>());
        }
        finally
        {
            if (File.Exists(manifestPath)) File.Delete(manifestPath);
        }
    }

    [Fact]
    public void ReferencesType_With_Contract_Resource_Stub_Infers_Target_Table_And_PrimaryKey()
    {
        var manifestPath = Path.Combine(Path.GetTempPath(), $"exoforge_refstub_{Guid.NewGuid():N}.json");
        try
        {
            const string source = """
                using System;
                using Exoforge.Plugin.SDK;

                namespace TestPlugin;

                [AttributeUsage(AttributeTargets.Class)]
                internal sealed class ExoContractResourceAttribute : Attribute
                {
                    public ExoContractResourceAttribute(string name) => Name = name;
                    public string Name { get; }
                    public string? PrimaryKey { get; set; }
                }

                [ExoContractResource("catalog_items", PrimaryKey = "sku")]
                public class ItemStub
                {
                    public string Sku { get; set; } = "";
                }

                [ExoService("cart_svc", Resources = new[] { typeof(CartItemRecord) })]
                public partial class TestPlugin { }

                [ExoResource("cart_items")]
                public class CartItemRecord
                {
                    public string Id { get; set; } = "";
                    [ExoColumn(ReferencesType = typeof(ItemStub))]
                    public string ItemSku { get; set; } = "";
                }
                """;

            var (output, diagnostics) = RunGenerator(source, manifestPath);
            Assert.Empty(diagnostics);

            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!;
            var svc = manifest["services"]!.AsArray()[0]!;
            var cartRes = svc["resources"]!.AsArray().First(r => r!["name"]?.GetValue<string>() == "cart_items")!;
            var itemCol = cartRes["columns"]!.AsArray().First(c => c!["name"]?.GetValue<string>() == "item_sku")!;

            Assert.True(itemCol["foreign_key"]?.GetValue<bool>());
            Assert.Equal("catalog_items.sku", itemCol["references"]?.GetValue<string>());
        }
        finally
        {
            if (File.Exists(manifestPath)) File.Delete(manifestPath);
        }
    }

    [Fact]
    public void ReferencesType_With_Unknown_Type_Reports_EXO005_Error()
    {
        const string source = """
            using System;
            using Exoforge.Plugin.SDK;

            namespace TestPlugin;

            public class OrdinaryClass
            {
                public string Value { get; set; } = "";
            }

            [ExoService("test_svc", Resources = new[] { typeof(BadRefRecord) })]
            public partial class TestPlugin { }

            [ExoResource("bad_refs")]
            public class BadRefRecord
            {
                public string Id { get; set; } = "";
                [ExoColumn(ReferencesType = typeof(OrdinaryClass))]
                public string RefProp { get; set; } = "";
            }
            """;

        var (_, diagnostics) = RunGenerator(source);
        var error = Assert.Single(diagnostics, d => d.Id == "EXO005");
        Assert.Equal(DiagnosticSeverity.Error, error.Severity);
        Assert.Contains("OrdinaryClass", error.GetMessage());
        Assert.Contains("RefProp", error.GetMessage());
    }

    [Fact]
    public void ExplicitNavigation_IsNotAColumn_AndRequiresDeclaredForeignKey()
    {
        const string valid = """
            using Exoforge.Plugin.SDK;
            namespace TestPlugin;
            [ExoService("test_svc", Resources = new[] { typeof(Order) })] public partial class TestPlugin { }
            [ExoResource("items")] public class Item { public string Id { get; set; } = ""; }
            [ExoResource("orders")] public class Order
            {
                public string Id { get; set; } = "";
                [ExoColumn(ForeignKey = true, References = "items.id", ReferencesType = typeof(Item))] public string ItemId { get; set; } = "";
                [ExoNavigation(nameof(ItemId))] public virtual Item? Item { get; set; }
            }
            """;
        var path = Path.Combine(Path.GetTempPath(), $"exoforge_navigation_{Guid.NewGuid():N}.json");
        try
        {
            var (_, diagnostics) = RunGenerator(valid, path);
            Assert.DoesNotContain(diagnostics, d => d.Id == "EXO005");
            var columns = JsonNode.Parse(File.ReadAllText(path))!["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!["columns"]!.AsArray();
            Assert.DoesNotContain(columns, c => c!["name"]!.GetValue<string>() == "item");
        }
        finally { if (File.Exists(path)) File.Delete(path); }

        const string invalid = """
            using Exoforge.Plugin.SDK;
            namespace TestPlugin;
            [ExoService("test_svc", Resources = new[] { typeof(Order) })] public partial class TestPlugin { }
            [ExoResource("items")] public class Item { public string Id { get; set; } = ""; }
            [ExoResource("orders")] public class Order
            {
                public string Id { get; set; } = "";
                public string ItemId { get; set; } = "";
                [ExoNavigation(nameof(ItemId))] public virtual Item? Item { get; set; }
            }
            """;
        var (_, invalidDiagnostics) = RunGenerator(invalid);
        var error = Assert.Single(invalidDiagnostics, d => d.Id == "EXO005");
        Assert.Contains("ItemId", error.GetMessage());
        Assert.Contains("navigation", error.GetMessage());
    }
}
