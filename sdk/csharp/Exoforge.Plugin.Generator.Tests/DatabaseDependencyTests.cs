using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json.Nodes;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

public class DatabaseDependencyTests
{
    private static JsonNode RunManifest(string source)
    {
        string path = Path.Combine(Path.GetTempPath(), $"exoforge_dbdep_{Guid.NewGuid():N}.json");

        try
        {
            typeof(ResourceValidationTests)
                .GetMethod("RunGenerator", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, new object?[] { source, path });

            return JsonNode.Parse(File.ReadAllText(path))!;
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static string[] Dependencies(JsonNode manifest) =>
        manifest["dependencies"]!.AsArray().Select(n => n!.GetValue<string>()).ToArray();

    [Fact]
    public void Declaring_A_Resource_Adds_The_Database_Dependency()
    {
        const string source = """
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja", Resources = new[] { typeof(Item) })]
            public partial class Loja { [ExoAction] public Item Get(string id) => new(); }
            [ExoResource("itens")]
            public class Item { public string Id { get; set; } = ""; }
            """;

        Assert.Contains("database", Dependencies(RunManifest(source)));
    }

    [Fact]
    public void Referencing_Exo_Database_Adds_The_Database_Dependency()
    {
        const string source = """
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja")]
            public partial class Loja
            {
                [ExoAction]
                public string Get(string id) => Exo.Database.Get<string>("itens", id) ?? "";
            }
            """;

        Assert.Contains("database", Dependencies(RunManifest(source)));
    }

    [Fact]
    public void Injecting_IDatabase_Adds_The_Database_Dependency()
    {
        const string source = """
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja")]
            public partial class Loja
            {
                public IDatabase Database { get; set; } = null!;
                [ExoAction]
                public string Get(string id) => Database.Get<string>("itens", id) ?? "";
            }
            """;

        Assert.Contains("database", Dependencies(RunManifest(source)));
    }

    [Fact]
    public void No_Resource_Or_Database_Reference_Leaves_The_Dependency_Out()
    {
        const string source = """
            using Exoforge.Plugin.SDK;
            namespace P;
            [ExoService("loja")]
            public partial class Loja
            {
                [ExoAction]
                public int Ping(int value) => value;
            }
            """;

        Assert.DoesNotContain("database", Dependencies(RunManifest(source)));
    }
}
