using System;
using System.IO;

namespace Exoforge.Management;

public static class ExoScaffolder
{
    public static string ScaffoldPlugin(string pluginsDirectory, string rawName, string? sdkProjectPath = null, string template = "standard")
    {
        string cleanName = rawName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");
        string className = ToPascalCase(cleanName);
        string targetDir = Path.Combine(pluginsDirectory, cleanName);

        Directory.CreateDirectory(targetDir);

        // 1. .csproj
        string csprojContent = GenerateCsproj(sdkProjectPath);
        File.WriteAllText(Path.Combine(targetDir, $"{cleanName}.csproj"), csprojContent);

        // 2. Main Service Class
        string serviceContent = GenerateServiceCode(cleanName, className, template);
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

    private static string GenerateServiceCode(string serviceName, string className, string template = "standard")
    {
        if (template.ToLowerInvariant().Contains("liveops") || template.ToLowerInvariant().Contains("schedule"))
        {
            return $$"""
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

/// <summary>
/// Custom LiveOps and seasonal event scheduling plugin.
/// </summary>
[ExoService("{{serviceName}}", Description = "{{className}} LiveOps event scheduling.")]
public class {{className}}Plugin : PluginBehaviour
{
    [ExoAction("list_events", Description = "Lists all active and scheduled game events.")]
    public object ListEvents()
    {
        return new[]
        {
            new
            {
                id = "{{serviceName}}_double_xp",
                title = "Double XP Weekend",
                start_at = DateTime.UtcNow.ToString("O"),
                end_at = DateTime.UtcNow.AddDays(2).ToString("O"),
                recurrence = "weekly",
                status = "active",
                metadata = new { xp_multiplier = 2.0 }
            }
        };
    }

    [ExoAction("broadcast_banner", Description = "Broadcasts a live banner message to all players.")]
    public void BroadcastBanner(string message, int durationSeconds = 30)
    {
        Events.Emit("{{serviceName}}:events", "liveops_banner", new
        {
            message,
            duration = durationSeconds,
            timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        });
    }
}

/// <summary>
/// LiveOps schedule resource rendered by Producer Studio calendar and timeline.
/// </summary>
[ExoResource("{{serviceName}}_schedules", Description = "Scheduled events managed by {{className}}.", Drawer = "schedule")]
public record {{className}}Schedule(
    [property: PrimaryKey] string Id,
    string Title,
    string StartAt,
    string EndAt,
    string Recurrence,
    string Status
);
""";
        }

        if (template.ToLowerInvariant().Contains("inventory"))
        {
            return $$"""
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

/// <summary>
/// Custom player inventory game service.
/// </summary>
[ExoService("{{serviceName}}", Description = "{{className}} player inventory.")]
public class {{className}}Plugin : PluginBehaviour
{
    [ExoAction("get_inventory", Description = "Fetches inventory for player.")]
    public object GetInventory(string playerId)
    {
        return new[]
        {
            new { item_id = "starter_sword", quantity = 1, equipped = true },
            new { item_id = "health_potion", quantity = 5, equipped = false }
        };
    }

    [ExoAction("grant_item", Description = "Grants item to player inventory.")]
    public bool GrantItem(string playerId, string itemId, int quantity = 1)
    {
        Events.Emit("{{serviceName}}:events", "item_granted", new
        {
            player_id = playerId,
            item_id = itemId,
            quantity = quantity,
            timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        });

        return true;
    }
}

[ExoResource("{{serviceName}}_items", Description = "Items managed by {{className}}.", Drawer = "table")]
public record {{className}}Item(
    [property: PrimaryKey] string Id,
    string OwnerId,
    int Quantity,
    string Status
);
""";
        }

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
[ExoResource("{{serviceName}}_items", Description = "Items managed by {{className}}.", Drawer = "table")]
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
