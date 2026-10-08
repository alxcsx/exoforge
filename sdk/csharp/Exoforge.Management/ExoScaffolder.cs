using System;
using System.IO;

namespace Exoforge.Management;

/// <summary>
/// Generates a plugin project skeleton:
/// <code>
/// plugins/&lt;name&gt;/
///   &lt;name&gt;.slnx          solution for the plugin
///   .gitignore           ignores the build outputs (the staged binary, the manifest)
///   src/&lt;name&gt;.csproj
///   src/&lt;Name&gt;Plugin.cs  the actions
///   src/Generated/       typed service stubs and the JSON context, from `exo plugin stubs`
/// </code>
/// The built binary is staged under <c>.exoforge/</c> and <c>manifest.exs</c> is written at the plugin
/// root; both are build outputs.
/// </summary>
public static class ExoScaffolder
{
    /// <summary>Templates a caller may ask for. Keep in step with <see cref="GeneratePluginCode"/>.</summary>
    public static readonly string[] Templates = { "standard", "inventory" };

    public static string ScaffoldPlugin(string pluginsDirectory, string rawName, string template = "standard")
    {
        string cleanName = NormalizeName(rawName);
        string className = ToPascalCase(cleanName);
        string targetDir = Path.Combine(pluginsDirectory, cleanName);
        string srcDir = Path.Combine(targetDir, "src");

        Directory.CreateDirectory(srcDir);

        File.WriteAllText(Path.Combine(srcDir, $"{cleanName}.csproj"), GenerateCsproj());
        File.WriteAllText(Path.Combine(srcDir, $"{className}Plugin.cs"), GeneratePluginCode(cleanName, className, template));
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.slnx"), GenerateSolution(cleanName));
        File.WriteAllText(Path.Combine(targetDir, "README.md"), GenerateReadme(cleanName, className));

        // The staged native binary and the local build counter are build artifacts.
        File.WriteAllText(Path.Combine(targetDir, ".gitignore"), "/.exoforge/\n/.buildcount\n/manifest.exs\n/manifest.json\n");

        RegisterLocalFeed(pluginsDirectory);

        return targetDir;
    }

    /// <summary>The plugin id a raw name will become. Shared with the CLI so it can say so up front.</summary>
    public static string NormalizePluginName(string rawName) =>
        rawName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");

    /// <summary>The C# class name for a plugin id, e.g. <c>snake_leaderboard</c> → <c>SnakeLeaderboard</c>.</summary>
    public static string ClassNameFor(string pluginId) => ToPascalCase(NormalizePluginName(pluginId));

    private static string NormalizeName(string rawName) => NormalizePluginName(rawName);

    /// <summary>
    /// Environment variable naming a directory of packed Exoforge packages, for a plugin built
    /// outside a checkout. A published feed needs nothing: nuget.org is already a source.
    /// </summary>
    public const string FeedEnvVar = "EXOFORGE_FEED";

    /// <summary>
    /// Points the workspace at a local feed, once, when one is configured.
    ///
    /// The project a plugin gets still names only the package. Where that package comes from is a
    /// property of the workspace, not of the plugin, which is why the reference in the project file
    /// reads the same whether the feed is a directory on this machine or a real one.
    /// </summary>
    private static void RegisterLocalFeed(string pluginsDirectory)
    {
        string? feed = Environment.GetEnvironmentVariable(FeedEnvVar);

        if (string.IsNullOrEmpty(feed) || !Directory.Exists(feed)) return;

        string? workspace = Path.GetDirectoryName(Path.GetFullPath(pluginsDirectory));
        if (workspace is null) return;

        string config =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<configuration>\n" +
            "  <!-- Written by `exo plugin new` from " + FeedEnvVar + ". Local packages, so a plugin -->\n" +
            "  <!-- builds without one being published anywhere. -->\n" +
            "  <packageSources>\n" +
            "    <add key=\"exoforge\" value=\"" + feed + "\" />\n" +
            "  </packageSources>\n" +
            "</configuration>\n";

        File.WriteAllText(Path.Combine(workspace, "nuget.config"), config);
    }

    /// <summary>The published package a scaffolded plugin references, and gets everything from.</summary>
    public const string SdkPackageId = "Exoforge.Plugin.SDK";

    /// <summary>Version of <see cref="SdkPackageId"/> a scaffolded plugin references.</summary>
    public const string SdkPackageVersion = "0.1.0";

    private static string GenerateCsproj() => $@"
<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <OutputType>Exe</OutputType>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>

    <!--
      An Exoforge plugin. The package below brings the SDK, the generator and the manifest plumbing
      together, which is why nothing else is here: no path into a checkout, and nothing to adjust
      for where the plugin happens to be built.
    -->
    <ExoforgePlugin>true</ExoforgePlugin>

    <!-- A native plugin is a process. Building it through the CLI overrides the build stamp. -->
    <ExoforgePluginType>native</ExoforgePluginType>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include=""{SdkPackageId}"" Version=""{SdkPackageVersion}"" />
  </ItemGroup>
</Project>
";

    private static string GenerateReadme(string cleanName, string className) => $"""
    # {cleanName}

    An Exoforge plugin. Actions are declared with attributes and discovered at build time.

    ## Layout

    | Path | What it is |
    | :--- | :--- |
    | `src/{className}Plugin.cs` | the plugin: `[ExoAction]` methods are what callers invoke |
    | `src/Generated/` | typed service stubs and the JSON context (`exo plugin stubs {cleanName}`) |
    | `manifest.exs` | generated from the attributes; do not edit |
    | `{cleanName}` | the staged native binary; generated |

    ## Working on it

    ```bash
    exo plugin build {cleanName}     # compile
    exo plugin push  {cleanName}     # build, deploy, verify
    exo plugin dev   {cleanName}     # redeploy on every save
    exo plugin logs  {cleanName}     # what the plugin just did
    ```

    In Unity: **Tools ▸ Exoforge ▸ Exoforge Studio**, then the Plugins tab.
    """;

    private static string GenerateSolution(string cleanName) => $"""
<Solution>
  <Project Path="src/{cleanName}.csproj" />
</Solution>
""";

    private static string GeneratePluginCode(string serviceName, string className, string template)
    {
        string kind = template.ToLowerInvariant();

        if (kind.Contains("inventory")) return InventoryTemplate(serviceName, className);

        if (kind is not ("standard" or ""))
        {
            throw new ArgumentException(
                $"Unknown template '{template}'. Available templates: standard, inventory.", nameof(template));
        }

        return StandardTemplate(serviceName, className);
    }

    private static string StandardTemplate(string serviceName, string className) => $$"""
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

// Native Exoforge plugin: attributes declare the contract, the host injects capabilities,
// and `exo plugin build` produces the NativeAOT binary.
[ExoService("{{serviceName}}", Version = "0.1.0", Resources = new[] { typeof({{className}}Item) },
    Category = "Game", Title = "{{className}}", Icon = "🧩")]
public class {{className}}Plugin
{
    [Inject("database")]
    public IDatabase? Database { get; set; }

    [Inject]
    public ILogger? Logger { get; set; }

    [ExoAction]
    public int Ping()
    {
        Logger?.Info("[{{serviceName}}] ping");
        return 42;
    }

    [ExoAction]
    public int Echo(int value) => value;
}

// Row stored in the plugin's isolated database.
[ExoResource("{{serviceName}}_items", PrimaryKey = "id", DrawerTabs = new[] { "overview", "attributes" })]
public record {{className}}Item
{
    [ExoColumn(Label = "Id", Sortable = true, Filterable = true)]
    public string Id { get; init; } = "";

    [ExoColumn(Label = "Owner", Sortable = true, Filterable = true)]
    public string OwnerId { get; init; } = "";

    [ExoColumn(Label = "Quantity", Sortable = true)]
    public int Quantity { get; init; }

    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "active";
}
""";

    private static string InventoryTemplate(string serviceName, string className) => $$"""
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

// Native Exoforge plugin: attributes declare the contract, the host injects capabilities,
// and `exo plugin build` produces the NativeAOT binary.
[ExoService("{{serviceName}}", Version = "0.1.0", Resources = new[] { typeof({{className}}Item) },
    Category = "Game", Title = "{{className}}", Icon = "🧩")]
public class {{className}}Plugin
{
    [Inject("database")]
    public IDatabase? Database { get; set; }

    [Inject]
    public IEventDispatcher? Events { get; set; }

    [ExoAction]
    public List<{{className}}Item> GetInventory(string playerId) =>
        new(Database!.All<{{className}}Item>("{{serviceName}}_items"));

    [ExoAction]
    [ExoEvent("item_granted", Topic = "{{serviceName}}:events", PayloadType = typeof(ItemGrantedEvent))]
    public async Task<int> GrantItem(string playerId, string itemId, int quantity = 1)
    {
        await Events!.EmitAsync(
            "item_granted",
            new ItemGrantedEvent { PlayerId = playerId, ItemId = itemId, Quantity = quantity },
            "{{serviceName}}:events");

        return quantity;
    }
}

public record ItemGrantedEvent
{
    public string PlayerId { get; init; } = "";
    public string ItemId { get; init; } = "";
    public int Quantity { get; init; }
}

[ExoResource("{{serviceName}}_items", PrimaryKey = "id", DrawerTabs = new[] { "overview", "attributes" })]
public record {{className}}Item
{
    [ExoColumn(Label = "Id", Sortable = true, Filterable = true)]
    public string Id { get; init; } = "";

    [ExoColumn(Label = "Owner", Sortable = true, Filterable = true)]
    public string OwnerId { get; init; } = "";

    [ExoColumn(Label = "Quantity", Sortable = true)]
    public int Quantity { get; init; }

    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "active";
}
""";

    private static string ToPascalCase(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;

        string[] parts = text.Split(new[] { '_', '-' }, StringSplitOptions.RemoveEmptyEntries);
        for (int i = 0; i < parts.Length; i++)
        {
            if (parts[i].Length > 0)
            {
                parts[i] = char.ToUpperInvariant(parts[i][0]) + parts[i].Substring(1);
            }
        }

        return string.Join("", parts);
    }
}
