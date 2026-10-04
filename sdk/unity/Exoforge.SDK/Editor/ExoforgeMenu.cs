using System;
using System.IO;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Management;

#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
#endif

namespace Exoforge.Unity.Editor
{
#if UNITY_EDITOR
/// <summary>
/// Menu items and shortcuts for Exoforge operations inside Unity Editor.
/// </summary>
public static class ExoforgeMenu
{

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

    [MenuItem("Tools/Exoforge/Scaffold New C# Plugin", false, 103)]
    public static void ScaffoldNewPlugin()
    {
        var window = EditorWindow.GetWindow<ExoforgeControlCenter>("Exoforge");
        window.minSize = new Vector2(480, 560);
        window.PromptScaffoldFromHeader();
    }

    private static async Task SyncClientBindingsAsync()
    {
        EditorUtility.DisplayProgressBar("Exoforge Sync", "Fetching contract schemas...", 0.4f);

        try
        {
            string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
            var workspace = ExoWorkspace.Load(wsPath);
            var deployer = new ExoDeployer(workspace);

            await deployer.SyncContractsAsync();

            EditorUtility.ClearProgressBar();
            AssetDatabase.Refresh();
            EditorUtility.DisplayDialog("Sync Complete", $"Strongly-typed client bindings generated at:\n{ExoforgeEditorConfig.GeneratedScriptPath}", "OK");
        }
        catch (Exception ex)
        {
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("Sync Error", $"Failed to sync contracts: {ex.Message}", "OK");
        }
    }
}
#endif
}
