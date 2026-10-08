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

    public static string ScaffoldPlugin(string pluginsDirectory, string rawName, string? sdkProjectPath = null, string template = "standard")
    {
        string cleanName = NormalizeName(rawName);
        string className = ToPascalCase(cleanName);
        string targetDir = Path.Combine(pluginsDirectory, cleanName);
        string srcDir = Path.Combine(targetDir, "src");

        Directory.CreateDirectory(srcDir);

        sdkProjectPath ??= FindSdkProjectPath(srcDir);

        File.WriteAllText(Path.Combine(srcDir, $"{cleanName}.csproj"), GenerateCsproj(sdkProjectPath, srcDir));
        File.WriteAllText(Path.Combine(srcDir, $"{className}Plugin.cs"), GeneratePluginCode(cleanName, className, template));
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.slnx"), GenerateSolution(cleanName));
        File.WriteAllText(Path.Combine(targetDir, "README.md"), GenerateReadme(cleanName, className));

        // The staged native binary and the local build counter are build artifacts.
        File.WriteAllText(Path.Combine(targetDir, ".gitignore"), "/.exoforge/\n/.buildcount\n/manifest.exs\n");

        return targetDir;
    }

    /// <summary>The plugin id a raw name will become. Shared with the CLI so it can say so up front.</summary>
    public static string NormalizePluginName(string rawName) =>
        rawName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");

    /// <summary>The C# class name for a plugin id, e.g. <c>snake_leaderboard</c> → <c>SnakeLeaderboard</c>.</summary>
    public static string ClassNameFor(string pluginId) => ToPascalCase(NormalizePluginName(pluginId));

    private static string NormalizeName(string rawName) => NormalizePluginName(rawName);

    /// <summary>
    /// Environment variable pointing at Exoforge.Plugin.SDK, either the .csproj or its directory.
    /// Lets a workspace that lives outside the repo (or a CI checkout) scaffold without guessing.
    /// </summary>
    public const string SdkPathEnvVar = "EXOFORGE_PLUGIN_SDK";

    /// <summary>The published package a scaffolded plugin references when no local checkout is given.</summary>
    public const string SdkPackageId = "Exoforge.Plugin.SDK";

    /// <summary>Version of <see cref="SdkPackageId"/> a scaffolded plugin references.</summary>
    public const string SdkPackageVersion = "0.1.0";

    /// <summary>
    /// The SDK a scaffolded plugin compiles against, when it is not the published package.
    ///
    /// Resolved explicitly: an environment override, or nothing — in which case the project
    /// references the published `Exoforge.Plugin.SDK` package. The SDK does not search the
    /// filesystem, because a consumer installed from a tarball has no `sdk/csharp` to find, and
    /// guessing produces a project that cannot restore with no explanation of why.
    /// </summary>
    private static string? FindSdkProjectPath(string fromDir)
    {
        string? configured = Environment.GetEnvironmentVariable(SdkPathEnvVar);

        if (string.IsNullOrEmpty(configured))
        {
            return null;
        }

        string candidate = configured!.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase)
            ? configured
            : Path.Combine(configured, "Exoforge.Plugin.SDK.csproj");

        if (!File.Exists(candidate))
        {
            throw new InvalidOperationException(
                $"{SdkPathEnvVar} is set to '{configured}', but no Exoforge.Plugin.SDK.csproj was " +
                "found there. Point it at the .csproj or its directory, or unset it to reference " +
                "the published package.");
        }

        return Path.GetFullPath(candidate);
    }

    private static string GenerateCsproj(string? sdkProjectPath, string srcDir)
    {
        // Two ways to get the SDK, both explicit:
        //   - a ProjectReference, when a local checkout was pointed at with EXOFORGE_PLUGIN_SDK;
        //   - the published package, which is the path a consumer without a checkout takes.
        string reference = sdkProjectPath != null && File.Exists(sdkProjectPath)
            ? $"    <!-- Local Exoforge.Plugin.SDK checkout, via {SdkPathEnvVar}. -->\n" +
              $"    <ProjectReference Include=\"{ReferencePath(srcDir, sdkProjectPath)}\" />"
            : $"    <!-- Published package. Point {SdkPathEnvVar} at a local checkout to build against that instead. -->\n" +
              $"    <PackageReference Include=\"{SdkPackageId}\" Version=\"{SdkPackageVersion}\" />";

        string? generatorProject = GeneratorProjectPath(sdkProjectPath);

        string generator = generatorProject != null
            ? "    <!-- Writes manifest.exs and the entry point from the attributes. -->\n" +
              $"    <ProjectReference Include=\"{ReferencePath(srcDir, generatorProject)}\" OutputItemType=\"Analyzer\" ReferenceOutputAssembly=\"false\" />"
            : "    <!-- The published package ships the Exoforge generator as an analyzer. -->";

        return $@"
<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <OutputType>Exe</OutputType>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>

    <!-- Consumed by the Exoforge generator. ExoDeployer overrides the build stamp per build. -->
    <ExoforgePluginType>native</ExoforgePluginType>
    <ExoforgeManifestPath Condition=""'$(ExoforgeManifestPath)' == ''"">$(MSBuildProjectDirectory)/../manifest.exs</ExoforgeManifestPath>
  </PropertyGroup>

  <ItemGroup>
{reference}
{generator}
  </ItemGroup>

  <ItemGroup>
    <!-- The manifest is a build output the generator writes, so a missing one has to re-run the
         compile rather than being treated as up to date. -->
    <UpToDateCheckOutput Include=""$(ExoforgeManifestPath)"" />
    <FileWrites Include=""$(ExoforgeManifestPath)"" />

    <CompilerVisibleProperty Include=""ExoforgePluginType"" />
    <CompilerVisibleProperty Include=""ExoforgeBuildStamp"" />
    <CompilerVisibleProperty Include=""ExoforgeManifestPath"" />
    <CompilerVisibleProperty Include=""DesignTimeBuild"" />
  </ItemGroup>
</Project>
";
    }

    /// <summary>
    /// The generator project that ships beside the SDK. A local checkout builds against it directly;
    /// the published package carries it as an analyzer.
    /// </summary>
    private static string? GeneratorProjectPath(string? sdkProjectPath)
    {
        if (sdkProjectPath is null) return null;

        string? dir = Path.GetDirectoryName(sdkProjectPath);
        if (string.IsNullOrEmpty(dir)) return null;

        string candidate = Path.GetFullPath(Path.Combine(dir!, "..", "Exoforge.Plugin.Generator", "Exoforge.Plugin.Generator.csproj"));
        return File.Exists(candidate) ? candidate : null;
    }

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

    /// <summary>
    /// How to write the SDK's location into the generated csproj.
    ///
    /// Relative while the SDK lives inside the workspace — a committed plugin then builds on
    /// another machine. Absolute once it does not, because the alternative is a long `../../../..`
    /// climb out of the tree that means nothing to a reader.
    /// </summary>
    private static string ReferencePath(string srcDir, string sdkProjectPath)
    {
        string workspaceRoot = Path.GetFullPath(Path.Combine(srcDir, "..", "..", ".."));
        string full = Path.GetFullPath(sdkProjectPath);

        bool insideWorkspace = full.StartsWith(workspaceRoot + Path.DirectorySeparatorChar, StringComparison.Ordinal);

        return insideWorkspace ? Path.GetRelativePath(srcDir, full) : full;
    }

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
