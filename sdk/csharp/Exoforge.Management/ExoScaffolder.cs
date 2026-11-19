using System;
using System.IO;
using System.Reflection;

namespace Exoforge.Management;

/// <summary>
/// Generates a plugin project skeleton:
/// <code>
/// plugins/&lt;name&gt;/
///   &lt;name&gt;.sln           solution for the plugin
///   .gitignore           ignores the build outputs (the staged binary, the manifest)
///   src/&lt;name&gt;.csproj
///   src/&lt;Name&gt;Plugin.cs  the actions
/// </code>
/// The built binary is staged under <c>.exoforge/</c> and <c>manifest.json</c> is written at the plugin
/// root; both are build outputs.
/// </summary>
public static class ExoScaffolder
{
    /// <summary>Templates a caller may ask for. Keep in step with <see cref="GenerateExtensionCode"/>.</summary>
    public static readonly string[] Templates = { "standard", "basic", "blank", "persistent", "config", "events" };

    public static string ScaffoldExtension(string extensionsDirectory, string rawName, string template = "standard", string? feed = null)
    {
        string cleanName = NormalizeName(rawName);
        string className = ToPascalCase(cleanName);
        string targetDir = Path.Combine(extensionsDirectory, cleanName);
        string srcDir = Path.Combine(targetDir, "src");

        Directory.CreateDirectory(srcDir);

        string workspaceRoot = Path.GetDirectoryName(Path.GetFullPath(extensionsDirectory))!;
        string? version = EnsureProjectFeed(workspaceRoot, feed);
        string sdkVersion = version ?? SdkPackageVersion;

        File.WriteAllText(Path.Combine(srcDir, $"{cleanName}.csproj"), GenerateCsproj(sdkVersion: sdkVersion));
        File.WriteAllText(Path.Combine(srcDir, $"{className}Extension.cs"), GenerateExtensionCode(cleanName, className, template));
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.sln"), GenerateSln(cleanName));

        // The staged native binary and the local build counter are build artifacts.
        File.WriteAllText(Path.Combine(targetDir, ".gitignore"), "/.exoforge/\n/.buildcount\n/manifest.json\n");

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
    /// The project-relative directory a workspace keeps its packed Exoforge packages in. Relative
    /// because a package cache path is machine-specific and a package reference is not.
    /// </summary>
    public const string FeedDirectoryName = ".feed";

    /// <summary>
    /// The workspace nuget.config. A relative source is resolved against the file that names it, so
    /// this is the same two lines everywhere: a project commits it, and nothing rewrites it.
    /// </summary>
    public static string NugetConfigContent =>
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
        "<configuration>\n" +
        "  <!-- Exoforge extensions: nuget.org for runtime packs, plus the extension SDK packed in .feed. -->\n" +
        "  <packageSources>\n" +
        "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" protocolVersion=\"3\" />\n" +
        $"    <add key=\"exoforge\" value=\"{FeedDirectoryName}\" />\n" +
        "  </packageSources>\n" +
        "</configuration>\n";

    public static bool NeedsFeedMigration(string workspaceRoot)
    {
        if (string.IsNullOrEmpty(workspaceRoot) || !Directory.Exists(workspaceRoot)) return false;

        string nugetConfig = Path.Combine(workspaceRoot, "nuget.config");
        if (!File.Exists(nugetConfig) || NormalizeLineEndings(File.ReadAllText(nugetConfig)) != NugetConfigContent)
            return true;

        string extensionsDir = Path.Combine(workspaceRoot, "extensions");
        if (!Directory.Exists(extensionsDir)) return false;

        foreach (string extDir in Directory.EnumerateDirectories(extensionsDir))
        {
            if (IsStaleExoforgeNugetConfig(Path.Combine(extDir, "nuget.config")))
                return true;
        }

        return false;
    }

    private static string NormalizeLineEndings(string text) => text.Replace("\r\n", "\n");

    private static readonly System.Text.RegularExpressions.Regex ExoforgeSourcePattern =
        new("<add\\b[^>]*key=\"exoforge\"[^>]*value=\"([^\"]*)\"|<add\\b[^>]*value=\"([^\"]*)\"[^>]*key=\"exoforge\"",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Compiled);

    private static bool IsStaleExoforgeNugetConfig(string path)
    {
        if (!File.Exists(path)) return false;
        string text = File.ReadAllText(path);
        var match = ExoforgeSourcePattern.Match(text);
        if (!match.Success) return false;

        string value = (match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value).Replace('\\', '/');
        if (value == FeedDirectoryName) return false;

        if (value.Contains("Library/PackageCache/", StringComparison.OrdinalIgnoreCase)
            || value.EndsWith("/Plugins/NuGet~", StringComparison.OrdinalIgnoreCase)
            || value.Contains("/Plugins/NuGet~/", StringComparison.OrdinalIgnoreCase))
            return true;

        // A pre-.feed config can also name a feed folder that no longer exists (an old checkout, another
        // machine); NuGet would keep merging it. A URL or a folder that is there is the user's own feed.
        if (value.Contains("://", StringComparison.Ordinal)) return false;
        string folder = Path.IsPathRooted(value) ? value : Path.Combine(Path.GetDirectoryName(path) ?? ".", value);
        return !Directory.Exists(folder);
    }

    /// <summary>
    /// Makes a workspace able to build an extension with no repository around it: the static
    /// nuget.config, and the SDK package itself in <see cref="FeedDirectoryName"/> when it is not
    /// there yet. Returns the version the feed now carries.
    /// </summary>
    public static string? EnsureProjectFeed(string workspaceRoot, string? explicitFeed = null)
    {
        Directory.CreateDirectory(workspaceRoot);
        string nugetConfig = Path.Combine(workspaceRoot, "nuget.config");
        if (!File.Exists(nugetConfig) || NormalizeLineEndings(File.ReadAllText(nugetConfig)) != NugetConfigContent)
            File.WriteAllText(nugetConfig, NugetConfigContent);

        string feedDir = Path.Combine(workspaceRoot, FeedDirectoryName);
        string? bundled = NewestSdkPackage(feedDir);
        string? source = NewestSdkPackage(ResolveDefaultFeed(explicitFeed));

        // NuGet caches a package by id and version, so every release is a new file and the old ones
        // stay: an extension that has not been upgraded yet still restores from the feed.
        if (source != null && (bundled == null || CompareVersions(source, bundled) > 0))
        {
            Directory.CreateDirectory(feedDir);
            string target = Path.Combine(feedDir, Path.GetFileName(source));
            if (!File.Exists(target)) File.Copy(source, target);
            bundled = target;
        }

        return bundled == null ? null : PackageVersion(bundled);
    }

    /// <summary>
    /// Prepares one extension to build: the project feed, its package reference moved to the version
    /// the feed carries (an SDK upgrade would otherwise leave it on a version that is not there), and
    /// the machine-specific config an older SDK wrote beside it, which NuGet would still merge into
    /// its sources.
    /// </summary>
    public static bool EnsureBuildFeed(string workspaceRoot, string extensionDir, string? explicitFeed = null)
    {
        string? version = EnsureProjectFeed(workspaceRoot, explicitFeed);
        bool changed = version != null && EnsurePackageReference(extensionDir, version);

        string stale = Path.Combine(extensionDir, "nuget.config");
        if (!IsStaleExoforgeNugetConfig(stale)) return changed;

        File.Delete(stale);
        return true;
    }

    /// <summary>
    /// Moves an extension's <c>Exoforge.Plugin.SDK</c> reference to <paramref name="version"/>. The
    /// element is edited in place rather than the project rewritten, so comments and settings a
    /// developer added survive.
    /// </summary>
    public static bool EnsurePackageReference(string extensionDir, string version)
    {
        string srcDir = Path.Combine(extensionDir, "src");
        string projectDir = Directory.Exists(srcDir) ? srcDir : extensionDir;
        bool changed = false;

        foreach (string csproj in Directory.GetFiles(projectDir, "*.csproj"))
        {
            string text = File.ReadAllText(csproj);
            string updated = System.Text.RegularExpressions.Regex.Replace(
                text,
                "(<PackageReference\\s+Include=\"Exoforge\\.Plugin\\.SDK\"\\s+Version=\")([^\"]*)(\")",
                "${1}" + version + "${3}");

            if (updated == text) continue;
            File.WriteAllText(csproj, updated);
            changed = true;
        }

        return changed;
    }

    private static string? NewestSdkPackage(string? dir)
    {
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return null;

        string? newest = null;
        foreach (string file in Directory.GetFiles(dir!, SdkPackageId + ".*.nupkg"))
        {
            if (newest == null || CompareVersions(file, newest) > 0) newest = file;
        }

        return newest;
    }

    /// <summary>The version a packaged SDK's file name carries: <c>Exoforge.Plugin.SDK.&lt;version&gt;.nupkg</c>.</summary>
    public static string PackageVersion(string nupkgPath)
    {
        string name = Path.GetFileName(nupkgPath);
        string prefix = SdkPackageId + ".";
        string suffix = ".nupkg";

        if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ||
            !name.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
        {
            return "";
        }

        return name.Substring(prefix.Length, name.Length - prefix.Length - suffix.Length);
    }

    private static int CompareVersions(string left, string right)
    {
        string a = PackageVersion(left);
        string b = PackageVersion(right);

        return Version.TryParse(a, out var va) && Version.TryParse(b, out var vb)
            ? va.CompareTo(vb)
            : string.CompareOrdinal(a, b);
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
    /// The package a scaffolded plugin references, and gets everything from.
    /// </summary>
    public const string SdkPackageId = "Exoforge.Plugin.SDK";

    /// <summary>
    /// The version of <see cref="SdkPackageId"/> this tooling ships, for a project scaffolded with no
    /// feed to read one from. The assembly carries it: <c>Directory.Build.props</c> stamps it from the
    /// Unity package's own version, so an installed Studio and the <c>NuGet~</c> package beside it
    /// name the same release.
    /// </summary>
    public static string SdkPackageVersion
    {
        get
        {
            string? informational = typeof(ExoScaffolder).Assembly
                .GetCustomAttribute<System.Reflection.AssemblyInformationalVersionAttribute>()?.InformationalVersion;

            if (!string.IsNullOrEmpty(informational))
            {
                string version = informational!;
                int plus = version.IndexOf('+');
                return (plus > 0 ? version.Substring(0, plus) : version).Trim();
            }

            Version? assemblyVersion = typeof(ExoScaffolder).Assembly.GetName().Version;
            return assemblyVersion == null
                ? "0.1.0"
                : $"{assemblyVersion.Major}.{assemblyVersion.Minor}.{assemblyVersion.Build}";
        }
    }

    public static string GenerateCsproj(string? targetFramework = null, string? sdkVersion = null) => $@"
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
    <PackageReference Include=""{SdkPackageId}"" Version=""{sdkVersion ?? SdkPackageVersion}"" />
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
        | `obj/exoforge/` | typed service stubs generated from `[ExoDependency]` declarations |
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

    public static string GenerateExtensionCode(string serviceName, string className, string template)
    {
        string kind = template.ToLowerInvariant();

        return kind switch
        {
            "blank" or "empty" or "minimal" => BlankTemplate(serviceName, className),
            "standard" or "basic" or "" => BasicTemplate(serviceName, className),
            "persistent" => PersistentTemplate(serviceName, className),
            "config" => ConfigTemplate(serviceName, className),
            "events" => EventsTemplate(serviceName, className),
            _ => throw new ArgumentException(
                $"Unknown template '{template}'. Available templates: blank, basic, standard, persistent, config, events.", nameof(template))
        };
    }

    private static string BlankTemplate(string serviceName, string className)
    {
        return $$"""
using System;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("{{serviceName}}", Version = "0.1.0", Category = "Game", Title = "{{className}}", Icon = "🧩")]
public class {{className}}Extension
{
    [ExoAction]
    public string Ping()
    {
        Exo.Logger.Info("[{{serviceName}}] ping");
        return "pong";
    }
}
""";
    }

    private static string BasicTemplate(string serviceName, string className)
    {
        return $$"""
using System;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("{{serviceName}}", Version = "0.1.0", Category = "Game", Title = "{{className}}", Icon = "🎁", Resources = [typeof({{className}}Claim)])]
public class {{className}}Extension
{
    [ExoAction]
    public {{className}}Reward ClaimDailyReward()
    {
        var playerId = Exo.Context.CallerPlayerId;
        if (string.IsNullOrEmpty(playerId))
            throw new ExoActionException("unauthorized", "Player must be authenticated to claim rewards.");

        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");

        var lastClaim = Exo.Database.Get<{{className}}Claim>(playerId);
        if (lastClaim != null && lastClaim.ClaimDate == today)
            throw new ExoActionException("already_claimed", "Daily reward already claimed today. Come back tomorrow!");

        var reward = new {{className}}Reward("coins", 100);
        Exo.Database.Put(new {{className}}Claim(playerId, today, reward.Amount));

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

    private static string PersistentTemplate(string serviceName, string className)
    {
        return $$"""
using System.Collections.Generic;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("{{serviceName}}", Version = "0.1.0", Category = "Game", Title = "{{className}}", Icon = "📦", Resources = [typeof({{className}}Item)])]
public class {{className}}Extension
{
    [ExoAction]
    public {{className}}Item? GetItem(string id) =>
        Exo.Database.Get<{{className}}Item>(id);

    [ExoAction]
    public IReadOnlyList<{{className}}Item> ListItems() =>
        Exo.Database.All<{{className}}Item>();

    [ExoAction]
    public {{className}}Item SaveItem(string id, int quantity)
    {
        var item = new {{className}}Item(id, quantity);
        Exo.Database.Put(item);
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

    private static string ConfigTemplate(string serviceName, string className)
    {
        return $$"""
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("{{serviceName}}", Version = "0.1.0", Category = "Game", Title = "{{className}}", Icon = "⚙️", Resources = [typeof({{className}}Config)])]
public class {{className}}Extension
{
    [ExoAction]
    public {{className}}Config GetConfig() =>
        Exo.Database.First<{{className}}Config>() ?? new {{className}}Config("normal", 3);

    [ExoAction]
    public {{className}}Config UpdateConfig(string difficulty, int maxLives)
    {
        var config = new {{className}}Config(difficulty, maxLives);
        Exo.Database.Put(config);
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

    private static string EventsTemplate(string serviceName, string className)
    {
        return $$"""
using System;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("{{serviceName}}", Version = "0.1.0", Category = "Game", Title = "{{className}}", Icon = "📡")]
public class {{className}}Extension
{
    [ExoAction]
    public async Task GreetPlayerAsync(string name)
    {
        var playerId = Exo.Context.CallerPlayerId ?? "anonymous";
        await Exo.Events.EmitAsync(new {{className}}PlayerGreeted(playerId, name, DateTimeOffset.UtcNow.ToUnixTimeSeconds()));
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
