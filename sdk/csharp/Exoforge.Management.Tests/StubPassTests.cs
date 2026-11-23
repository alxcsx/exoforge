using System.Text.RegularExpressions;
using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

/// <summary>The explicit stub pass: dependency discovery without a manifest, output under obj/exoforge, and what a fresh clone sees.</summary>
public class StubPassTests : IDisposable
{
    private readonly string _root;
    private readonly string _extensions;

    public StubPassTests()
    {
        _root = Path.Combine(Path.GetTempPath(), $"exo_stub_{Guid.NewGuid():N}");
        _extensions = Path.Combine(_root, "extensions");
        Directory.CreateDirectory(_extensions);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch { }
    }

    private const string ItemsManifest = """
        { "id": "items", "version": "1.0.0", "type": "native", "provides": ["items"], "dependencies": [],
          "services": [ { "name": "items",
            "actions": [ { "name": "get_item", "scope": "player", "params": { "id": "string" }, "returns": { "id": "string", "nome": "string" }, "returns_list": false } ],
            "events": [] } ] }
        """;

    private ExoWorkspace Workspace(params string[] excluded)
    {
        var config = new ExoProjectConfig { ExtensionsDir = "extensions", ExcludedExtensions = excluded.Length == 0 ? null : excluded.ToList() };
        // A port nothing listens on: the pass must work from the manifests alone, never from a developer's running server.
        config.Environments["local"].WsUrl = "ws://127.0.0.1:1/ws";
        return new ExoWorkspace(_root, config);
    }

    private string Extension(string name, string source = "", bool project = true)
    {
        string dir = Path.Combine(_extensions, name);
        Directory.CreateDirectory(Path.Combine(dir, "src"));
        if (project) File.WriteAllText(Path.Combine(dir, "src", name + ".csproj"), "<Project Sdk=\"Microsoft.NET.Sdk\" />");
        File.WriteAllText(Path.Combine(dir, "src", "Main.cs"), source);
        return dir;
    }

    private const string ShopSource = "class Shop { async Task Buy() => await ExoServices.Items.GetItemAsync(\"x\"); }";

    [Fact]
    public void Discovery_Reads_Sources_And_Pins_Without_A_Manifest()
    {
        Extension("loja_itens", "var a = ExoServices.Items; var b = ExoServices.PlayerData; ExoServices.Database.X(); [ExoDependency(\"wallet\")] class A {}");
        Extension("items");
        Extension("wallet");

        var found = ExoDependencyDiscovery.Discover(Path.Combine(_extensions, "loja_itens"), "loja_itens",
            ExoDependencyDiscovery.SiblingServices(_extensions));

        Assert.Equal(new[] { "wallet", "items" }, found.Services);
        Assert.Equal(new[] { "PlayerData" }, found.Unmatched);
    }

    [Fact]
    public void Discovery_Maps_Pascal_To_Snake_And_Ignores_Generated_Files_And_Itself()
    {
        string dir = Extension("loja_itens", "ExoServices.LojaItens.X();");
        Directory.CreateDirectory(Path.Combine(dir, "obj", "exoforge"));
        File.WriteAllText(Path.Combine(dir, "obj", "exoforge", "PluginServices.g.cs"), "ExoServices.Items.Y();");
        File.WriteAllText(Path.Combine(dir, "src", "A.g.cs"), "ExoServices.Items.Y();");
        Extension("items");

        var found = ExoDependencyDiscovery.Discover(dir, "loja_itens", new[] { "items", "loja_itens" });

        Assert.Empty(found.Services);
    }

    [Fact]
    public void Exclusions_And_Order_Use_The_Same_Discovery()
    {
        Extension("items");
        Extension("shop", ShopSource);

        var ws = Workspace("items");
        Assert.Contains("shop needs items, which is excluded", ws.ValidateIncluded());

        var order = ExoDeployOrder.Plan(ExoDeployOrder.ReadNodes(_extensions, new[] { "shop", "items" })
            .Select(n => new DeployNode(n.Name, n.Provides.Append(n.Name).ToList(), n.Dependencies))).Order;
        Assert.Equal(new[] { "items", "shop" }, order);
    }

    [Fact]
    public async Task Fresh_Clone_Pass_Needs_The_Provider_Built_Then_Writes_Only_Under_Obj()
    {
        Extension("items");
        string shop = Extension("shop", ShopSource);
        var deployer = new ExoDeployer(Workspace());

        // Nothing built, no obj, no cache, no server: a message that says what to do, and nothing written.
        var first = await deployer.GenerateStubsAsync(new[] { "shop" });
        Assert.False(first.Ok);
        Assert.Contains("items", first.FailureMessage);
        Assert.False(Directory.Exists(Path.Combine(shop, "obj")));

        // The provider has been built (its manifest exists): the stubs appear under obj/exoforge, never in src.
        File.WriteAllText(Path.Combine(_extensions, "items", "manifest.json"), ItemsManifest);
        var second = await deployer.GenerateStubsAsync(new[] { "shop" });
        Assert.True(second.Ok, second.FailureMessage);
        string stubs = Path.Combine(shop, "obj", "exoforge", "PluginServices.g.cs");
        Assert.True(File.Exists(stubs));
        Assert.Contains("GetItemAsync", File.ReadAllText(stubs));
        Assert.False(Directory.Exists(Path.Combine(shop, "src", "Generated")));
    }

    [Fact]
    public async Task The_Pass_Covers_Included_Extensions_Providers_First()
    {
        Extension("items");
        string shop = Extension("shop", ShopSource);
        string other = Extension("other", ShopSource);
        File.WriteAllText(Path.Combine(_extensions, "items", "manifest.json"), ItemsManifest);

        var result = await new ExoDeployer(Workspace("other")).GenerateIncludedStubsAsync();

        Assert.True(result.Ok, result.FailureMessage);
        Assert.Equal(new[] { "items", "shop" }, result.Items.Select(i => i.Name));
        Assert.True(File.Exists(Path.Combine(shop, "obj", "exoforge", "PluginServices.g.cs")));
        Assert.False(Directory.Exists(Path.Combine(other, "obj")));
    }

    [Fact]
    public async Task An_Extension_That_Commits_Its_Own_Stubs_Keeps_Them()
    {
        Extension("items");
        string shop = Extension("shop", ShopSource);
        Directory.CreateDirectory(Path.Combine(shop, "src", "Generated"));
        File.WriteAllText(Path.Combine(shop, "src", "Generated", "PluginServices.g.cs"), "// committed");

        var result = await new ExoDeployer(Workspace()).GenerateStubsAsync(new[] { "shop" });

        Assert.True(result.Ok);
        Assert.Equal(StubOutcome.CommittedStubs, result.Items[0].Outcome);
        Assert.False(Directory.Exists(Path.Combine(shop, "obj", "exoforge")));
    }

    [Fact]
    public void Using_A_Services_Model_Type_Is_A_Dependency_Without_A_Call()
    {
        Extension("items");
        File.WriteAllText(Path.Combine(_extensions, "items", "manifest.json"), ItemsManifest);
        Extension("shop", "using Exoforge.Plugins.Generated;\nclass Shop { ItemsGetItemRequest R; }");
        Extension("local", "using Exoforge.Plugins.Generated;\nclass ItemsGetItemRequest { }\nclass L { ItemsGetItemRequest R; }");
        Extension("nousing", "class N { ItemsGetItemRequest R; }");

        var nodes = ExoDeployOrder.ReadNodes(_extensions, new[] { "shop", "local", "nousing" });

        Assert.Contains("items", nodes.First(n => n.Name == "shop").Dependencies);
        Assert.DoesNotContain("items", nodes.First(n => n.Name == "local").Dependencies);
        Assert.DoesNotContain("items", nodes.First(n => n.Name == "nousing").Dependencies);
    }

    [Fact]
    public void A_Build_Stops_With_The_Reason_Before_Any_Compile_When_A_Contract_Is_Missing()
    {
        Extension("items");
        Extension("shop", ShopSource);

        // items has no manifest, so it is built first; here it has no project to build, which stops 'shop' with the chain named.
        var ex = Assert.ThrowsAny<ExoStubPassException>(() => new ExoDeployer(Workspace()).BuildExtension("shop"));
        Assert.Contains("items", ex.Message);
    }

    [Fact]
    public void Client_Bindings_Are_Reported_Missing_Or_Stale_Never_Thrown()
    {
        Extension("items");
        File.WriteAllText(Path.Combine(_extensions, "items", "manifest.json"), ItemsManifest);
        var ws = Workspace();
        string client = Path.Combine(_root, "Assets", "Exoforge", "Generated", "ExoforgeServices.g.cs");

        Assert.Equal(ClientBindingsState.Missing, ExoClientBindings.Check(ws, client));
        Assert.NotNull(ExoClientBindings.Message(ClientBindingsState.Missing, "x"));

        Directory.CreateDirectory(Path.GetDirectoryName(client)!);
        File.WriteAllText(client, "// client");
        File.SetLastWriteTimeUtc(client, DateTime.UtcNow.AddHours(-1));
        Assert.Equal(ClientBindingsState.Stale, ExoClientBindings.Check(ws, client));

        File.SetLastWriteTimeUtc(client, DateTime.UtcNow.AddHours(1));
        Assert.Equal(ClientBindingsState.Current, ExoClientBindings.Check(ws, client));
        Assert.Null(ExoClientBindings.Message(ClientBindingsState.Current, "x"));
    }

    [Fact]
    public void Extensions_Inside_Assets_Are_Reported_But_A_Sibling_Folder_Is_Not()
    {
        string project = Path.Combine(_root, "game");
        Directory.CreateDirectory(Path.Combine(project, "Assets"));
        Directory.CreateDirectory(Path.Combine(project, "ProjectSettings"));

        var beside = new ExoWorkspace(Path.Combine(project, "Exoforge"), new ExoProjectConfig());
        Assert.Null(ExoClientBindings.ExtensionsInsideUnityCompile(beside));

        var inside = new ExoWorkspace(Path.Combine(project, "Exoforge"), new ExoProjectConfig { ExtensionsDir = "../Assets/Backend" });
        Assert.Contains("Assets/", ExoClientBindings.ExtensionsInsideUnityCompile(inside));
    }

    // ---- static checks over the sources: nothing Unity compiles reaches the stubs, nothing runs on load ----

    private static string Repo()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir != null && !Directory.Exists(Path.Combine(dir, "sdk", "unity", "Exoforge.SDK"))) dir = Path.GetDirectoryName(dir);
        return dir ?? throw new DirectoryNotFoundException("repository root");
    }

    private static IEnumerable<string> UnitySources() =>
        new[] { "Editor", "Runtime" }
            .Select(d => Path.Combine(Repo(), "sdk", "unity", "Exoforge.SDK", d))
            .SelectMany(d => Directory.EnumerateFiles(d, "*.cs", SearchOption.AllDirectories))
            .Where(f => !f.Replace('\\', '/').Contains("/Plugins/"));

    [Fact]
    public void Unity_Assemblies_Never_Reference_Extension_Stubs_Or_Projects()
    {
        foreach (string file in UnitySources())
        {
            string text = File.ReadAllText(file);
            Assert.DoesNotContain("obj/exoforge", text.Replace('\\', '/'));
            Assert.DoesNotContain("PluginServices.g", text);
        }

        foreach (string asmdef in Directory.EnumerateFiles(Path.Combine(Repo(), "sdk", "unity", "Exoforge.SDK"), "*.asmdef", SearchOption.AllDirectories))
        {
            string text = File.ReadAllText(asmdef);
            Assert.DoesNotContain("extensions", text);
            Assert.DoesNotContain("obj", text);
        }
    }

    [Fact]
    public void Nothing_That_Runs_On_Load_Generates_Stubs_Or_Builds()
    {
        string[] forbidden =
        {
            "GenerateStubsAsync", "GenerateAllExtensionStubsAsync", "GenerateIncludedStubsAsync", "GenerateExtensionStubsAsync",
            "EnsureStubs", "BuildExtension", "SyncContractsAsync", "SyncAndGenerateClientAsync", "Process.Start",
        };

        int hooks = 0;
        foreach (string file in UnitySources())
        {
            string text = File.ReadAllText(file);
            foreach (Match m in Regex.Matches(text, @"\[(InitializeOnLoadMethod|DidReloadScripts|InitializeOnLoad)\]|class\s+\w+\s*:\s*AssetPostprocessor"))
            {
                hooks++;
                string body = BodyAfter(text, m.Index);
                foreach (string name in forbidden) Assert.DoesNotContain(name, body);
            }
        }

        Assert.True(hooks > 0, "the scan found no load hooks at all, so it checks nothing");
    }

    /// <summary>The text from <paramref name="start"/> through the next balanced { } block that follows the attribute or class header.</summary>
    private static string BodyAfter(string text, int start)
    {
        int open = text.IndexOf('{', start);
        // [InitializeOnLoad] on a class: the class body is where the static constructor lives.
        if (open < 0) return "";
        int depth = 0;
        for (int i = open; i < text.Length; i++)
        {
            if (text[i] == '{') depth++;
            else if (text[i] == '}' && --depth == 0) return text.Substring(start, i - start + 1);
        }

        return text.Substring(start);
    }

    [Fact]
    public void The_Packaged_Targets_Only_Add_A_Static_Compile_Include_And_A_Hint()
    {
        string targets = File.ReadAllText(Path.Combine(Repo(), "sdk", "csharp", "Exoforge.Plugin.SDK", "build", "Exoforge.Plugin.SDK.targets"));
        string withoutComments = Regex.Replace(targets, "<!--.*?-->", "", RegexOptions.Singleline);

        Assert.Contains("obj/exoforge", targets);
        Assert.Contains("<Compile Include=\"$(ExoforgeStubsDir)/**/*.cs\"", withoutComments);
        Assert.DoesNotContain("<Exec", withoutComments);
        Assert.DoesNotContain("dotnet run", withoutComments);
        Assert.Contains("EXOFORGE003", withoutComments);

        string repoTargets = Regex.Replace(File.ReadAllText(Path.Combine(Repo(), "Directory.Build.targets")), "<!--.*?-->", "", RegexOptions.Singleline);
        Assert.DoesNotContain("<Exec", repoTargets);
    }
}
