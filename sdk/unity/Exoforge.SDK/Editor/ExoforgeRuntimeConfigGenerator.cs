using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Exoforge.Client.Unity;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor;

/// <summary>
/// Writes the runtime config the standard Exoforge prefab reads (<c>Resources/exoforge.json</c>).
/// </summary>
public static class ExoforgeRuntimeConfigGenerator
{
    public const string OutputPath = "Assets/Resources/" + ExoforgeRuntimeConfig.ResourcePath + ".json";

    /// <summary>
    /// Writes a sanitized runtime config (M33 Fix 18): only the selected environment's public
    /// endpoints. What ships in a player build is where the game connects — not the workspace's
    /// bootstrap tokens, and not the other environments it also knows how to reach.
    /// </summary>
    public static bool Generate()
    {
        string? configPath = FindWorkspaceConfig();
        if (configPath == null)
        {
            Debug.LogWarning("[Exoforge] No exoforge.json found under Assets/; skipping runtime config link.");
            return false;
        }

        var config = ExoforgeRuntimeConfig.FromWorkspaceJson(File.ReadAllText(configPath));

        string destination = Path.GetFullPath(OutputPath);

        if (Path.GetFullPath(configPath) == destination)
        {
            // The workspace config would be overwritten with its own sanitized copy, losing every
            // other environment. Say so and leave it alone.
            Debug.LogWarning(
                "[Exoforge] The workspace exoforge.json already lives at " + OutputPath +
                "; it carries the workspace's tokens and must not be the file a build reads. Move it into the Exoforge workspace folder.");
            return false;
        }

        var payload = new Dictionary<string, object>
        {
            ["default_environment"] = config.Environment,
            ["environments"] = new Dictionary<string, object>
            {
                [config.Environment] = new Dictionary<string, string>
                {
                    ["ws_url"] = config.WsUrl,
                    ["http_url"] = config.HttpUrl
                }
            }
        };

        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.WriteAllText(
            destination,
            JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        AssetDatabase.ImportAsset(OutputPath);

        Debug.Log($"[Exoforge] Runtime config written for '{config.Environment}' → {OutputPath} (endpoints only, no token)");
        return true;
    }

    /// <summary>Prefers the configured workspace path, then falls back to any exoforge.json under Assets/.</summary>
    private static string? FindWorkspaceConfig()
    {
        var workspace = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
        if (File.Exists(workspace.ConfigPath))
        {
            return workspace.ConfigPath;
        }

        var matches = Directory.GetFiles(Application.dataPath, ExoWorkspace.ConfigFileName, SearchOption.AllDirectories);
        return matches.Length > 0 ? matches[0] : null;
    }
}
