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

    private static JsonNode RunManifest(string source)
    {
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_schema_{Guid.NewGuid():N}.json");
        try
        {
            typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path });
            return JsonNode.Parse(File.ReadAllText(path))!;
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void Columns_Carry_Postgres_Storage_Type_Nullability_And_Enum_Choices()
    {
        const string source = """
            #nullable enable
            using System;
            using System.Collections.Generic;
            using Exoforge.Plugin.SDK;
            namespace P;
            public enum RankTier { Rookie, ProLevel }
            public record NestedMeta(string Tag);
            [ExoService("svc", Resources = new[] { typeof(AllTypes) })]
            public partial class Svc { }
            [ExoResource("all_types")]
            public class AllTypes
            {
                public string Id { get; set; } = "";
                public string? OptionalText { get; set; }
                public int IntCol { get; set; }
                public int? NullableInt { get; set; }
                public long LongCol { get; set; }
                public short ShortCol { get; set; }
                public bool BoolCol { get; set; }
                public double DoubleCol { get; set; }
                public float FloatCol { get; set; }
                public decimal DecimalCol { get; set; }
                public Guid GuidCol { get; set; }
                public DateTime DateTimeCol { get; set; }
                public DateTimeOffset DateTimeOffsetCol { get; set; }
                public byte[] BytesCol { get; set; } = Array.Empty<byte>();
                public RankTier TierCol { get; set; }
                public RankTier? NullableTier { get; set; }
                public List<string> ListCol { get; set; } = new();
                public int[] ArrayCol { get; set; } = Array.Empty<int>();
                public Dictionary<string, int> DictCol { get; set; } = new();
                public NestedMeta NestedCol { get; set; } = new("x");
            }
            """;

        var columns = RunManifest(source)["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!["columns"]!.AsArray();
        JsonNode Col(string name) => columns.Single(c => c!["name"]!.GetValue<string>() == name)!;
        string Storage(string name) => Col(name)["storage"]!.GetValue<string>();

        Assert.Equal("text", Storage("id"));
        Assert.Null(Col("id")["nullable"]);
        Assert.Equal("text", Storage("optional_text"));
        Assert.True(Col("optional_text")["nullable"]!.GetValue<bool>());
        Assert.Equal("integer", Storage("int_col"));
        Assert.Equal("integer", Storage("nullable_int"));
        Assert.True(Col("nullable_int")["nullable"]!.GetValue<bool>());
        Assert.Equal("bigint", Storage("long_col"));
        Assert.Equal("smallint", Storage("short_col"));
        Assert.Equal("boolean", Storage("bool_col"));
        Assert.Equal("double precision", Storage("double_col"));
        Assert.Equal("real", Storage("float_col"));
        Assert.Equal("numeric", Storage("decimal_col"));
        Assert.Equal("uuid", Storage("guid_col"));
        Assert.Equal("timestamptz", Storage("date_time_col"));
        Assert.Equal("timestamptz", Storage("date_time_offset_col"));
        Assert.Equal("bytea", Storage("bytes_col"));
        Assert.Equal("text", Storage("tier_col"));
        Assert.Equal(new[] { "rookie", "pro_level" }, Col("tier_col")["choices"]!.AsArray().Select(c => c!.GetValue<string>()));
        Assert.Equal("text", Storage("nullable_tier"));
        Assert.True(Col("nullable_tier")["nullable"]!.GetValue<bool>());
        Assert.Equal(new[] { "rookie", "pro_level" }, Col("nullable_tier")["choices"]!.AsArray().Select(c => c!.GetValue<string>()));
        Assert.Equal("jsonb", Storage("list_col"));
        Assert.Equal("jsonb", Storage("array_col"));
        Assert.Equal("jsonb", Storage("dict_col"));
        Assert.Equal("jsonb", Storage("nested_col"));
    }

    [Fact]
    public void Columns_Carry_PrimaryKey_Unique_And_Indexed_Flags()
    {
        const string source = """
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("svc", Resources = new[] { typeof(Account) })]
            public partial class Svc { }
            [ExoResource("accounts", PrimaryKey = "account_id")]
            public class Account
            {
                public string AccountId { get; set; } = "";
                [ExoColumn(Unique = true, Indexed = true)]
                public string Email { get; set; } = "";
                [ExoColumn(Indexed = true)]
                public string Handle { get; set; } = "";
                public int Score { get; set; }
            }
            """;

        var columns = RunManifest(source)["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!["columns"]!.AsArray();
        JsonNode Col(string name) => columns.Single(c => c!["name"]!.GetValue<string>() == name)!;

        Assert.True(Col("account_id")["primary_key"]!.GetValue<bool>());
        Assert.False(Col("account_id")["unique"]!.GetValue<bool>());
        Assert.False(Col("account_id")["indexed"]!.GetValue<bool>());

        Assert.False(Col("email")["primary_key"]!.GetValue<bool>());
        Assert.True(Col("email")["unique"]!.GetValue<bool>());
        Assert.True(Col("email")["indexed"]!.GetValue<bool>());

        Assert.False(Col("handle")["unique"]!.GetValue<bool>());
        Assert.True(Col("handle")["indexed"]!.GetValue<bool>());

        Assert.False(Col("score")["primary_key"]!.GetValue<bool>());
        Assert.False(Col("score")["unique"]!.GetValue<bool>());
        Assert.False(Col("score")["indexed"]!.GetValue<bool>());
    }

    [Fact]
    public void Resource_SchemaHash_Is_Stable_Ignores_Labels_And_Changes_With_Storage()
    {
        static string Source(string type, string label) => $$"""
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("svc", Resources = new[] { typeof(Item) })]
            public partial class Svc { }
            [ExoResource("items")]
            public class Item
            {
                public string Id { get; set; } = "";
                [ExoColumn(Label = "{{label}}", Sortable = true)]
                public {{type}} Amount { get; set; }
            }
            """;

        string Hash(string src) =>
            RunManifest(src)["services"]!.AsArray()[0]!["resources"]!.AsArray()[0]!["schema_hash"]!.GetValue<string>();

        string h1 = Hash(Source("int", "Amount"));
        string h2 = Hash(Source("int", "Amount"));
        string hLabelChanged = Hash(Source("int", "Total Amount"));
        string hStorageChanged = Hash(Source("long", "Amount"));

        Assert.Equal(64, h1.Length);
        Assert.Equal(h1, h2);
        Assert.Equal(h1, hLabelChanged);
        Assert.NotEqual(h1, hStorageChanged);
    }
}
