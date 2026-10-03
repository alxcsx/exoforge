using System;
using System.IO;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Management;

#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
#endif

namespace Exoforge.Unity.Editor;

#if UNITY_EDITOR
/// <summary>
/// Menu items and shortcuts for Exoforge operations inside Unity Editor.
/// </summary>
public static class ExoforgeMenu
{
    [MenuItem("Tools/Exoforge/Control Center", false, 100)]
    public static void OpenControlCenter()
    {
        ExoforgeControlCenter.ShowWindow();
    }

    [MenuItem("Tools/Exoforge/Sync Client Bindings", false, 101)]
    public static void SyncClientBindings()
    {
        _ = SyncClientBindingsAsync();
    }

    [MenuItem("Tools/Exoforge/Initialize Workspace", false, 102)]
    public static void InitializeWorkspace()
    {
        string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
        if (ExoWorkspace.Exists(wsPath))
        {
            EditorUtility.DisplayDialog("Workspace Exists", $"An Exoforge workspace already exists at:\n{wsPath}", "OK");
            return;
        }

        ExoWorkspace.Initialize(wsPath);
        EditorUtility.DisplayDialog("Workspace Created", $"Initialized new Exoforge workspace at:\n{wsPath}", "OK");
    }

    private static async Task SyncClientBindingsAsync()
    {
        EditorUtility.DisplayProgressBar("Exoforge Sync", "Connecting to cluster...", 0.2f);
        ExoClient? client = null;

        try
        {
            client = new ExoClient(ExoforgeEditorConfig.ServerUrl);
            await client.ConnectAsync();

            var auth = await client.AuthenticateAsync(ExoforgeEditorConfig.AdminToken);
            if (!auth.Success)
            {
                EditorUtility.ClearProgressBar();
                EditorUtility.DisplayDialog("Sync Failed", $"Authentication rejected: {auth.Error}", "OK");
                return;
            }

            EditorUtility.DisplayProgressBar("Exoforge Sync", "Fetching contract schemas...", 0.5f);
            var deployer = new ExoDeployer(client);
            string? exportJson = await deployer.SyncContractsAsync();

            if (string.IsNullOrEmpty(exportJson))
            {
                EditorUtility.ClearProgressBar();
                EditorUtility.DisplayDialog("Sync Failed", "Received empty contract export from server.", "OK");
                return;
            }

            EditorUtility.DisplayProgressBar("Exoforge Sync", "Synthesizing C# client API...", 0.8f);
            string code = ExoCodeGenerator.GenerateCode(exportJson, "Exoforge.Client");
            string outPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();

            string? dir = Path.GetDirectoryName(outPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            await File.WriteAllTextAsync(outPath, code);

            EditorUtility.ClearProgressBar();
            AssetDatabase.Refresh();
            EditorUtility.DisplayDialog("Sync Complete", $"Strongly-typed client bindings generated at:\n{ExoforgeEditorConfig.GeneratedScriptPath}", "OK");
        }
        catch (Exception ex)
        {
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("Sync Error", $"Failed to sync contracts: {ex.Message}", "OK");
        }
        finally
        {
            if (client != null)
            {
                await client.DisconnectAsync();
                client.Dispose();
            }
        }
    }
}
#endif
