using System.IO;
using Exoforge.Client.Unity;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor;

/// <summary>
/// Links the workspace <c>exoforge.json</c> into <c>Resources/exoforge.json</c> so the
/// standard Exoforge prefab can resolve cluster settings at runtime with zero scene wiring.
/// </summary>
public static class ExoforgeRuntimeConfigGenerator
{
    public const string OutputPath = "Assets/Resources/" + ExoforgeRuntimeConfig.ResourcePath + ".json";

    /// <summary>Copies the workspace config into Resources. Returns false when none exists.</summary>
    public static bool Generate()
    {
        string? configPath = FindWorkspaceConfig();
        if (configPath == null)
        {
            Debug.LogWarning("[Exoforge] No exoforge.json found under Assets/; skipping runtime config link.");
            return false;
        }

        string source = Path.GetFullPath(configPath);
        string destination = Path.GetFullPath(OutputPath);

        if (source != destination)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, overwrite: true);
            AssetDatabase.ImportAsset(OutputPath);
        }

        var config = ExoforgeRuntimeConfig.FromWorkspaceJson(File.ReadAllText(destination));
        Debug.Log($"[Exoforge] Runtime config linked from {configPath} → {OutputPath} (env: {config.Environment})");
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
