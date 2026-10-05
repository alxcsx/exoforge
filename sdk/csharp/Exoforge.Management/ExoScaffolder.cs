using System;
using System.IO;

namespace Exoforge.Management;

/// <summary>
/// Generates a plugin project skeleton:
/// <code>
/// plugins/&lt;name&gt;/
///   &lt;name&gt;.slnx          solution for the plugin
///   .gitignore           ignores the staged native binary
///   src/&lt;name&gt;.csproj
///   src/&lt;Name&gt;Plugin.cs  the actions
///   src/&lt;Name&gt;JsonContext.cs  source-generated JSON metadata
/// </code>
/// The built binary and <c>manifest.exs</c> stay at the plugin root, where the deployer expects them.
/// </summary>
public static class ExoScaffolder
{
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
        File.WriteAllText(Path.Combine(srcDir, $"{className}JsonContext.cs"), GenerateJsonContextCode(className, template));
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.slnx"), GenerateSolution(cleanName));

        // The staged native binary and the local build counter are build artifacts.
        File.WriteAllText(Path.Combine(targetDir, ".gitignore"), $"/{cleanName}\n/.buildcount\n");

        return targetDir;
    }

    private static string NormalizeName(string rawName) =>
        rawName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");

    private static string? FindSdkProjectPath(string fromDir)
    {
        string? dir = fromDir;

        for (int i = 0; i < 10 && dir != null; i++)
        {
            foreach (string relative in new[]
            {
                Path.Combine("sdk", "csharp", "Exoforge.Plugin.SDK", "Exoforge.Plugin.SDK.csproj"),
                Path.Combine("csharp", "Exoforge.Plugin.SDK", "Exoforge.Plugin.SDK.csproj")
            })
            {
                string candidate = Path.Combine(dir, relative);
                if (File.Exists(candidate)) return Path.GetRelativePath(fromDir, candidate);
            }

            dir = Directory.GetParent(dir)?.FullName;
        }

        return null;
    }

    private static string GenerateCsproj(string? sdkProjectPath, string srcDir)
    {
        bool referencesSdk = sdkProjectPath != null &&
            File.Exists(Path.GetFullPath(Path.Combine(srcDir, sdkProjectPath)));

        string reference = referencesSdk
            ? $"    <ProjectReference Include=\"{sdkProjectPath}\" />"
            : "    <PackageReference Include=\"Exoforge.Plugin.SDK\" Version=\"0.1.0\" />";

        return $"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <OutputType>Exe</OutputType>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>

  <ItemGroup>
{reference}
  </ItemGroup>
</Project>
""";
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
        if (kind.Contains("liveops") || kind.Contains("schedule")) return LiveOpsTemplate(serviceName, className);
        return StandardTemplate(serviceName, className);
    }

    private static string GenerateJsonContextCode(string className, string template)
    {
        string kind = template.ToLowerInvariant();

        string attributes;
        if (kind.Contains("inventory"))
        {
            attributes =
                $"[JsonSerializable(typeof({className}Item))]\n" +
                "[JsonSerializable(typeof(ItemGrantedEvent))]";
        }
        else if (kind.Contains("liveops") || kind.Contains("schedule"))
        {
            attributes =
                $"[JsonSerializable(typeof({className}Schedule))]\n" +
                "[JsonSerializable(typeof(LiveOpsBannerEvent))]";
        }
        else
        {
            attributes = $"[JsonSerializable(typeof({className}Item))]";
        }

        return $$"""
using System.Text.Json.Serialization;

namespace Exoforge.Plugins;

// Source-generated JSON for this plugin's records — NativeAOT has no reflection.
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
{{attributes}}
internal partial class {{className}}JsonContext : JsonSerializerContext
{
}
""";
    }

    private static string StandardTemplate(string serviceName, string className) => $$"""
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

// Native Exoforge plugin: attributes declare the contract, the host injects capabilities,
// and `exo plugin build` produces the NativeAOT binary.
[ExoService("{{serviceName}}", Version = "0.1.0", Resources = new[] { typeof({{className}}Item) },
    Category = "Game", Title = "{{className}}")]
public class {{className}}Plugin
{
    [Inject("database")]
    public static IDatabase? Database { get; set; }

    [Inject]
    public static ILogger? Logger { get; set; }

    [ExoAction]
    public int Ping()
    {
        Logger?.Info("[{{serviceName}}] ping");
        return 42;
    }

    [ExoAction]
    public int Echo(int value) => value;

    public static void Main() => PluginHost.Run<{{className}}Plugin, {{className}}JsonContext>();
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
    Category = "Game", Title = "{{className}}")]
public class {{className}}Plugin
{
    [Inject("database")]
    public static IDatabase? Database { get; set; }

    [Inject]
    public static IEventDispatcher? Events { get; set; }

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

    public static void Main() => PluginHost.Run<{{className}}Plugin, {{className}}JsonContext>();
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

    private static string LiveOpsTemplate(string serviceName, string className) => $$"""
using System;
using System.Collections.Generic;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

// Native Exoforge plugin: attributes declare the contract, the host injects capabilities,
// and `exo plugin build` produces the NativeAOT binary.
[ExoService("{{serviceName}}", Version = "0.1.0", Resources = new[] { typeof({{className}}Schedule) },
    Category = "Game", Title = "{{className}}")]
public class {{className}}Plugin
{
    [Inject]
    public static IEventDispatcher? Events { get; set; }

    [ExoAction]
    public List<{{className}}Schedule> ListEvents() => new()
    {
        new {{className}}Schedule
        {
            Id = "{{serviceName}}_double_xp",
            Title = "Double XP Weekend",
            StartAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            EndAt = DateTimeOffset.UtcNow.AddDays(2).ToUnixTimeSeconds(),
            Recurrence = "weekly",
            Status = "active"
        }
    };

    [ExoAction]
    [ExoEvent("liveops_banner", Topic = "{{serviceName}}:events", PayloadType = typeof(LiveOpsBannerEvent))]
    public void BroadcastBanner(string message, int durationSeconds = 30)
    {
        Events?.EmitAsync(
            "liveops_banner",
            new LiveOpsBannerEvent { Message = message, DurationSeconds = durationSeconds },
            "{{serviceName}}:events");
    }

    public static void Main() => PluginHost.Run<{{className}}Plugin, {{className}}JsonContext>();
}

public record LiveOpsBannerEvent
{
    public string Message { get; init; } = "";
    public int DurationSeconds { get; init; }
}

[ExoResource("{{serviceName}}_schedules", PrimaryKey = "id", DrawerTabs = new[] { "overview", "schedule" })]
public record {{className}}Schedule
{
    [ExoColumn(Label = "Id", Sortable = true, Filterable = true)]
    public string Id { get; init; } = "";

    [ExoColumn(Label = "Title", Sortable = true)]
    public string Title { get; init; } = "";

    [ExoColumn(Label = "Starts", Sortable = true)]
    public long StartAt { get; init; }

    [ExoColumn(Label = "Ends", Sortable = true)]
    public long EndAt { get; init; }

    [ExoColumn(Label = "Recurrence", Badge = true)]
    public string Recurrence { get; init; } = "once";

    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "scheduled";
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
