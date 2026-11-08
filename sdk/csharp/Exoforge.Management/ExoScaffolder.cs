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
/// The built binary is staged under <c>.exoforge/</c> and <c>manifest.json</c> is written at the plugin
/// root; both are build outputs.
/// </summary>
public static class ExoScaffolder
{
    /// <summary>Templates a caller may ask for. Keep in step with <see cref="GeneratePluginCode"/>.</summary>
    public static readonly string[] Templates = { "standard", "basic", "persistent", "config", "events" };

    public static string ScaffoldExtension(string extensionsDirectory, string rawName, string template = "standard", string? feed = null) =>
        Scaffold(extensionsDirectory, rawName, isExtension: true, template: template, feed: feed);

    public static string ScaffoldPlugin(string pluginsDirectory, string rawName, string template = "standard", string? feed = null) =>
        Scaffold(pluginsDirectory, rawName, isExtension: false, template: template, feed: feed);

    private static string Scaffold(string targetDirectory, string rawName, bool isExtension, string template = "standard", string? feed = null)
    {
        string cleanName = NormalizeName(rawName);
        string className = ToPascalCase(cleanName);
        string targetDir = Path.Combine(targetDirectory, cleanName);
        string srcDir = Path.Combine(targetDir, "src");

        Directory.CreateDirectory(srcDir);

        string suffix = isExtension ? "Extension" : "Plugin";
        File.WriteAllText(Path.Combine(srcDir, $"{cleanName}.csproj"), GenerateCsproj());
        File.WriteAllText(Path.Combine(srcDir, $"{className}{suffix}.cs"), GenerateCode(cleanName, className, isExtension, template));
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.sln"), GenerateSln(cleanName));
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.slnx"), GenerateSolution(cleanName));

        // The staged native binary and the local build counter are build artifacts.
        File.WriteAllText(Path.Combine(targetDir, ".gitignore"), "/.exoforge/\n/.buildcount\n/manifest.json\n");

        // Ensure nuget feed in workspace root as well as directly inside the extension folder for Rider
        RegisterLocalFeed(targetDirectory, feed);
        EnsureLocalFeed(targetDir, feed);

        // Pre-restore packages so Rider has project assets, autocomplete, and Roslyn analyzers ready
        RestoreExtension(srcDir, cleanName);

        return targetDir;
    }

    /// <summary>The extension id a raw name will become. Shared with the CLI so it can say so up front.</summary>
    public static string NormalizeExtensionName(string rawName) => NormalizePluginName(rawName);

    /// <summary>The plugin id a raw name will become. Shared with the CLI so it can say so up front.</summary>
    public static string NormalizePluginName(string rawName) =>
        rawName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");

    /// <summary>The C# class name for a plugin id, e.g. <c>snake_leaderboard</c> → <c>SnakeLeaderboard</c>.</summary>
    public static string ClassNameFor(string pluginId) => ToPascalCase(NormalizePluginName(pluginId));

    private static string NormalizeName(string rawName) => NormalizePluginName(rawName);

    /// <summary>
    /// Environment variable naming a directory of packed Exoforge packages, for a plugin built
    /// outside a checkout. A caller that knows where the feed is passes it instead; a published feed
    /// needs neither, since nuget.org is already a source.
    /// </summary>
    public const string FeedEnvVar = "EXOFORGE_FEED";

    /// <summary>
    /// Minimum supported .NET major version for Exoforge extensions.
    /// </summary>
    public const int MinimumMajorDotnetVersion = 9;

    /// <summary>
    /// Resolves the default local NuGet package feed for Exoforge SDK packages.
    /// Checks explicit feed, EXOFORGE_FEED environment variable, and the bundled NuGet~ package directory.
    /// </summary>
    public static string? ResolveDefaultFeed(string? explicitFeed = null)
    {
        if (!string.IsNullOrEmpty(explicitFeed) && Directory.Exists(explicitFeed))
            return Path.GetFullPath(explicitFeed);

        string? envFeed = Environment.GetEnvironmentVariable(FeedEnvVar);
        if (!string.IsNullOrEmpty(envFeed) && Directory.Exists(envFeed))
            return Path.GetFullPath(envFeed);

        // Check adjacent NuGet~ folder next to Exoforge.Management.dll (when inside Editor/Plugins)
        string? asmDir = Path.GetDirectoryName(typeof(ExoScaffolder).Assembly.Location);
        var candidateRoots = new System.Collections.Generic.List<string>();

        if (!string.IsNullOrEmpty(asmDir))
        {
            string adjacent = Path.Combine(asmDir, "NuGet~");
            if (Directory.Exists(adjacent)) return Path.GetFullPath(adjacent);

            candidateRoots.Add(Path.GetFullPath(Path.Combine(asmDir, "..", "..")));
        }

        // In Unity, Assembly.Location is empty because assemblies are loaded from memory streams.
        // Check current working directory (Unity sets this to project root) and AppDomain base directory.
        string currentDir = Directory.GetCurrentDirectory();
        if (!string.IsNullOrEmpty(currentDir) && !candidateRoots.Contains(currentDir))
            candidateRoots.Add(currentDir);

        string appDomainDir = AppDomain.CurrentDomain.BaseDirectory;
        if (!string.IsNullOrEmpty(appDomainDir) && !candidateRoots.Contains(appDomainDir))
            candidateRoots.Add(appDomainDir);

        foreach (string projectRoot in candidateRoots)
        {
            string embeddedPkg = Path.Combine(projectRoot, "Packages", "com.exoforge.sdk", "Editor", "Plugins", "NuGet~");
            if (Directory.Exists(embeddedPkg)) return Path.GetFullPath(embeddedPkg);

            string pkgCache = Path.Combine(projectRoot, "Library", "PackageCache");
            if (Directory.Exists(pkgCache))
            {
                try
                {
                    foreach (string dir in Directory.GetDirectories(pkgCache, "com.exoforge.sdk*"))
                    {
                        string cachedNuget = Path.Combine(dir, "Editor", "Plugins", "NuGet~");
                        if (Directory.Exists(cachedNuget)) return Path.GetFullPath(cachedNuget);
                    }
                }
                catch
                {
                    // Ignore package cache read errors
                }
            }
        }

        return null;
    }

    /// <summary>
    /// Detects the highest installed .NET SDK major version with a minimum floor of 9.
    /// </summary>
    public static int DetectHighestInstalledSdkMajor(string dotnetPath = "dotnet")
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = ExoDeployer.ResolveDotnetPath(dotnetPath),
                Arguments = "--list-sdks",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = System.Diagnostics.Process.Start(psi);
            if (proc != null)
            {
                string output = proc.StandardOutput.ReadToEnd();
                proc.WaitForExit(3000);
                int highest = 0;
                foreach (string line in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    int dot = line.IndexOf('.');
                    if (dot > 0 && int.TryParse(line.Substring(0, dot).Trim(), out int major))
                    {
                        if (major > highest) highest = major;
                    }
                }
                if (highest >= MinimumMajorDotnetVersion) return highest;
            }
        }
        catch
        {
            // Fall back to runtime version or floor
        }

        return Math.Max(MinimumMajorDotnetVersion, Environment.Version.Major);
    }

    /// <summary>
    /// Resolves the default TargetFramework moniker for scaffolded extensions, targeting the latest
    /// installed .NET SDK with a minimum of net9.0.
    /// </summary>
    public static string DetectTargetFramework(string dotnetPath = "dotnet")
    {
        int major = DetectHighestInstalledSdkMajor(dotnetPath);
        return $"net{major}.0";
    }

    /// <summary>
    /// Ensures nuget.config exists in the workspace root, pointing to the local feed if resolved.
    /// </summary>
    public static void EnsureLocalFeed(string workspaceRoot, string? explicitFeed = null)
    {
        string nugetConfig = Path.Combine(workspaceRoot, "nuget.config");
        string? feed = ResolveDefaultFeed(explicitFeed);
        if (string.IsNullOrEmpty(feed) || !Directory.Exists(feed)) return;

        string normFeed = feed!.Replace('\\', '/');
        string config =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<configuration>\n" +
            "  <!-- Local packages feed for Exoforge extensions -->\n" +
            "  <packageSources>\n" +
            $"    <add key=\"exoforge\" value=\"{normFeed}\" />\n" +
            "  </packageSources>\n" +
            "</configuration>\n";

        if (!File.Exists(nugetConfig) || !File.ReadAllText(nugetConfig).Contains(normFeed))
        {
            File.WriteAllText(nugetConfig, config);
        }
    }

    /// <summary>
    /// Pre-restores dependencies for a newly scaffolded extension so IDEs have project assets ready.
    /// </summary>
    private static void RestoreExtension(string srcDir, string cleanName)
    {
        try
        {
            string csprojPath = Path.Combine(srcDir, $"{cleanName}.csproj");
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = ExoDeployer.ResolveDotnetPath("dotnet"),
                Arguments = $"restore \"{csprojPath}\"",
                WorkingDirectory = srcDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = System.Diagnostics.Process.Start(psi);
            proc?.WaitForExit(5000);
        }
        catch
        {
            // Non-fatal if dotnet is unavailable or network-isolated
        }
    }

    /// <summary>
    /// Points the workspace at a local feed, once, when one is configured.
    /// </summary>
    private static void RegisterLocalFeed(string pluginsDirectory, string? explicitFeed)
    {
        string? workspace = Path.GetDirectoryName(Path.GetFullPath(pluginsDirectory));
        if (workspace is null) return;

        EnsureLocalFeed(workspace, explicitFeed);
    }

    /// <summary>
    /// The published package a scaffolded plugin references, and gets everything from.
    ///
    /// The version is a literal because a scaffolded plugin is usually outside this repository, where
    /// no property is available to it. In here, <c>Directory.Build.props</c> holds the same number for
    /// everything the build hook wires up — the two have to be bumped together.
    /// </summary>
    public const string SdkPackageId = "Exoforge.Plugin.SDK";

    /// <summary>Version of <see cref="SdkPackageId"/> a scaffolded plugin references.</summary>
    public const string SdkPackageVersion = "0.1.0";

    public static string GenerateCsproj(string? targetFramework = null) => $@"
<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <TargetFramework>{targetFramework ?? DetectTargetFramework()}</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <OutputType>Exe</OutputType>

    <!--
      An Exoforge extension. The package below brings the SDK, the generator and the manifest plumbing
      together, which is why nothing else is here: no path into a checkout, and nothing to adjust
      for where the extension happens to be built.
    -->
    <ExoforgeExtension>true</ExoforgeExtension>

    <!-- A native extension is a process. Building it through the CLI overrides the build stamp. -->
    <ExoforgePluginType>native</ExoforgePluginType>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include=""{SdkPackageId}"" Version=""{SdkPackageVersion}"" />
  </ItemGroup>
</Project>
";

    private static string GenerateReadme(string cleanName, string className, bool isExtension = true)
    {
        string term = isExtension ? "extension" : "plugin";
        string suffix = isExtension ? "Extension" : "Plugin";
        return $"""
        # {cleanName}

        An Exoforge {term}. Actions are declared with attributes and discovered at build time.

        ## Layout

        | Path | What it is |
        | :--- | :--- |
        | `src/{className}{suffix}.cs` | the {term}: `[ExoAction]` methods are what callers invoke |
        | `src/Generated/` | typed service stubs and the JSON context (`exo {term} stubs {cleanName}`) |
        | `manifest.json` | generated from the attributes; do not edit |
        | `{cleanName}` | the staged native binary; generated |

        ## Working on it

        ```bash
        exo {term} build {cleanName}     # compile
        exo {term} push  {cleanName}     # build, deploy, verify
        exo {term} dev   {cleanName}     # redeploy on every save
        exo {term} logs  {cleanName}     # what the {term} just did
        ```

        In Unity: **Exoforge ▸ Studio**, then the Extensions tab.
        """;
    }

    public static string GenerateSln(string cleanName)
    {
        string projGuid = Guid.NewGuid().ToString("B").ToUpperInvariant();
        return $$"""
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "{{cleanName}}", "src/{{cleanName}}.csproj", "{{projGuid}}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{{projGuid}}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		{{projGuid}}.Debug|Any CPU.Build.0 = Debug|Any CPU
		{{projGuid}}.Release|Any CPU.ActiveCfg = Release|Any CPU
		{{projGuid}}.Release|Any CPU.Build.0 = Release|Any CPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
""";
    }

    private static string GenerateSolution(string cleanName) => $"""
<Solution>
  <Project Path="src/{cleanName}.csproj" />
</Solution>
""";

    public static string GeneratePluginCode(string serviceName, string className, string template) =>
        GenerateCode(serviceName, className, isExtension: false, template: template);

    public static string GenerateExtensionCode(string serviceName, string className, string template) =>
        GenerateCode(serviceName, className, isExtension: true, template: template);

    private static string GenerateCode(string serviceName, string className, bool isExtension, string template)
    {
        string kind = template.ToLowerInvariant();

        if (!isExtension && kind is "standard" or "")
        {
            return LegacyStandardTemplate(serviceName, className);
        }

        return kind switch
        {
            "standard" or "basic" or "" => BasicTemplate(serviceName, className, isExtension),
            "persistent" => PersistentTemplate(serviceName, className, isExtension),
            "config" => ConfigTemplate(serviceName, className, isExtension),
            "events" => EventsTemplate(serviceName, className, isExtension),
            _ => throw new ArgumentException(
                $"Unknown template '{template}'. Available templates: basic, standard, persistent, config, events.", nameof(template))
        };
    }

    private static string LegacyStandardTemplate(string serviceName, string className)
    {
        return $$"""
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

[ExoService("{{serviceName}}", Version = "0.1.0", Resources = new[] { typeof({{className}}Item) },
    Category = "Game", Title = "{{className}}", Icon = "🧩")]
public class {{className}}Plugin
{
    [ExoAction]
    public int Ping()
    {
        ExoServices.Logger.Info("[{{serviceName}}] ping");
        return 42;
    }

    [ExoAction]
    public int Echo(int value) => value;
}

[ExoResource("{{serviceName}}_items", PrimaryKey = "id", DrawerTabs = new[] { "overview", "attributes" })]
public record {{className}}Item
{
    [ExoColumn(Sortable = true, Filterable = true)]
    public string Id { get; init; } = "";

    [ExoColumn(Sortable = true, Filterable = true)]
    public string OwnerId { get; init; } = "";

    [ExoColumn(Sortable = true)]
    public int Quantity { get; init; }

    [ExoColumn(Badge = true)]
    public string Status { get; init; } = "active";
}
""";
    }

    private static string BasicTemplate(string serviceName, string className, bool isExtension = true)
    {
        string ns = isExtension ? "Exoforge.Extensions" : "Exoforge.Plugins";
        string attr = isExtension ? "ExoExtension" : "ExoService";
        string suffix = isExtension ? "Extension" : "Plugin";

        return $$"""
using System;
using Exoforge.Plugin.SDK;

namespace {{ns}};

[{{attr}}("{{serviceName}}", Version = "0.1.0", Resources = [typeof({{className}}Claim)])]
public class {{className}}{{suffix}}
{
    [ExoAction]
    public {{className}}Reward ClaimDailyReward()
    {
        var playerId = ExoServices.Context.CallerPlayerId;
        if (string.IsNullOrEmpty(playerId))
            throw new ExoActionException("unauthorized", "Player must be authenticated to claim rewards.");

        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");

        var lastClaim = ExoServices.Database.Get<{{className}}Claim>(playerId);
        if (lastClaim != null && lastClaim.ClaimDate == today)
            throw new ExoActionException("already_claimed", "Daily reward already claimed today. Come back tomorrow!");

        var reward = new {{className}}Reward("coins", 100);
        ExoServices.Database.Put(new {{className}}Claim(playerId, today, reward.Amount));

        return reward;
    }
}

[ExoResource("{{serviceName}}_claims", PrimaryKey = nameof(PlayerId))]
public record {{className}}Claim(
    [property: ExoColumn(Label = "Player ID", Filterable = true, Role = "user_id")] string PlayerId,
    [property: ExoColumn(Label = "Claim Date", Sortable = true)] string ClaimDate,
    [property: ExoColumn(Label = "Amount", Sortable = true)] int Amount
);

public record {{className}}Reward(string Kind, int Amount);
""";
    }

    private static string PersistentTemplate(string serviceName, string className, bool isExtension = true)
    {
        string ns = isExtension ? "Exoforge.Extensions" : "Exoforge.Plugins";
        string attr = isExtension ? "ExoExtension" : "ExoService";
        string suffix = isExtension ? "Extension" : "Plugin";

        return $$"""
using System.Collections.Generic;
using Exoforge.Plugin.SDK;

namespace {{ns}};

[{{attr}}("{{serviceName}}", Version = "0.1.0", Resources = [typeof({{className}}Item)])]
public class {{className}}{{suffix}}
{
    [ExoAction]
    public {{className}}Item? GetItem(string id) =>
        ExoServices.Database.Get<{{className}}Item>(id);

    [ExoAction]
    public IReadOnlyList<{{className}}Item> ListItems() =>
        ExoServices.Database.All<{{className}}Item>();

    [ExoAction]
    public {{className}}Item SaveItem(string id, int quantity)
    {
        var item = new {{className}}Item(id, quantity);
        ExoServices.Database.Put(item);
        return item;
    }
}

[ExoResource("{{serviceName}}_items", PrimaryKey = nameof(Id))]
public record {{className}}Item(
    [property: ExoColumn(Sortable = true, Filterable = true)] string Id,
    [property: ExoColumn(Sortable = true)] int Quantity
);
""";
    }

    private static string ConfigTemplate(string serviceName, string className, bool isExtension = true)
    {
        string ns = isExtension ? "Exoforge.Extensions" : "Exoforge.Plugins";
        string attr = isExtension ? "ExoExtension" : "ExoService";
        string suffix = isExtension ? "Extension" : "Plugin";

        return $$"""
using Exoforge.Plugin.SDK;

namespace {{ns}};

[{{attr}}("{{serviceName}}", Version = "0.1.0", Resources = [typeof({{className}}Config)])]
public class {{className}}{{suffix}}
{
    [ExoAction]
    public {{className}}Config GetConfig() =>
        ExoServices.Database.First<{{className}}Config>() ?? new {{className}}Config("normal", 3);

    [ExoAction]
    public {{className}}Config UpdateConfig(string difficulty, int maxLives)
    {
        var config = new {{className}}Config(difficulty, maxLives);
        ExoServices.Database.Put(config);
        return config;
    }
}

[ExoSingletonResource("{{serviceName}}_config")]
public record {{className}}Config(
    [property: ExoColumn(Label = "Difficulty")] string Difficulty,
    [property: ExoColumn(Label = "Max Lives")] int MaxLives
);
""";
    }

    private static string EventsTemplate(string serviceName, string className, bool isExtension = true)
    {
        string ns = isExtension ? "Exoforge.Extensions" : "Exoforge.Plugins";
        string attr = isExtension ? "ExoExtension" : "ExoService";
        string suffix = isExtension ? "Extension" : "Plugin";

        return $$"""
using System;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace {{ns}};

[{{attr}}("{{serviceName}}", Version = "0.1.0")]
public class {{className}}{{suffix}}
{
    [ExoAction]
    public async Task GreetPlayerAsync(string name)
    {
        var playerId = ExoServices.Context.CallerPlayerId ?? "anonymous";
        await ExoServices.Events.EmitAsync(new {{className}}PlayerGreeted(playerId, name, DateTimeOffset.UtcNow.ToUnixTimeSeconds()));
    }
}

[ExoEvent("player_greeted", Topic = "{{serviceName}}:events")]
public record {{className}}PlayerGreeted(string PlayerId, string Name, long Timestamp);
""";
    }

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
