using System;
using System.IO;

namespace Exoforge.Management;

public static class ExoScaffolder
{
    public static string ScaffoldPlugin(string pluginsDirectory, string rawName, string? sdkProjectPath = null)
    {
        string cleanName = rawName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");
        string className = ToPascalCase(cleanName);
        string targetDir = Path.Combine(pluginsDirectory, cleanName);

        Directory.CreateDirectory(targetDir);

        // 1. .csproj
        string csprojContent = GenerateCsproj(sdkProjectPath);
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.csproj"), csprojContent);

        // 2. Main Service Class
        string serviceContent = GenerateServiceCode(cleanName, className);
        File.WriteAllText(Path.Combine(targetDir, $"{className}Plugin.cs"), serviceContent);

        return targetDir;
    }

    private static string GenerateCsproj(string? sdkProjectPath)
    {
        string refSection;
        if (!string.IsNullOrEmpty(sdkProjectPath) && File.Exists(sdkProjectPath))
        {
            refSection = $"    <ProjectReference Include=\"{sdkProjectPath}\" />";
        }
        else
        {
            refSection = "    <PackageReference Include=\"Exoforge.Plugin.SDK\" Version=\"0.1.0\" />";
        }

        return $"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <OutputType>Exe</OutputType>
  </PropertyGroup>

  <ItemGroup>
{refSection}
  </ItemGroup>
</Project>
""";
    }

    private static string GenerateServiceCode(string serviceName, string className)
    {
        return $$"""
using System;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

/// <summary>
/// Custom game service plugin for Exoforge.
/// </summary>
[ExoService("{{serviceName}}", Description = "{{className}} game service.")]
public class {{className}}Plugin : PluginBehaviour
{
    [ExoAction("ping", Description = "Health verification ping.")]
    public int Ping()
    {
        Logger.Info("[{{className}}] Ping received!");
        return 42;
    }

    [ExoAction("execute", Description = "Sample game action.")]
    public async Task<int> Execute(int playerId, int amount)
    {
        Logger.Info($"[{{className}}] Executing for player {playerId} with amount {amount}");

        // Broadcast event to connected clients across the cluster
        Events.Emit("{{serviceName}}:events", "{{serviceName}}_updated", new
        {
            player_id = playerId,
            amount = amount,
            timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        });

        return amount;
    }
}

/// <summary>
/// Declared resource model.
/// Automatically inferred by ManifestGen for persistence and Studio visualization.
/// </summary>
[ExoResource("{{serviceName}}_items", Description = "Items managed by {{className}}.")]
public record {{className}}Item(
    [property: PrimaryKey] string Id,
    string OwnerId,
    int Quantity,
    string Status
);
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
