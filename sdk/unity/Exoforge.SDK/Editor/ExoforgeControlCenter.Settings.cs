using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
// NOTE: keep this a block-scoped namespace. Unity's layout serializer drops windows declared
// with file-scoped namespaces, so the window would vanish from saved layouts (Unity issue 9734).

/// <summary>Settings tab: workspace, codegen and dotnet configuration.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Tab 5: Settings
    // =========================================================================

    private void DrawSettings()
    {
        EditorGUILayout.LabelField("Workspace & Codegen Paths", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        // Workspace Path
        EditorGUILayout.BeginHorizontal();
        ExoforgeEditorConfig.WorkspacePath = EditorGUILayout.TextField("Workspace Path", ExoforgeEditorConfig.WorkspacePath);
        if (GUILayout.Button("Browse...", GUILayout.Width(70)))
        {
            string chosen = EditorUtility.OpenFolderPanel("Choose Exoforge Workspace", ExoforgeEditorConfig.GetAbsoluteWorkspacePath(), "");
            if (!string.IsNullOrEmpty(chosen))
            {
                string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                if (chosen.StartsWith(projectRoot))
                {
                    ExoforgeEditorConfig.WorkspacePath = Path.GetRelativePath(projectRoot, chosen);
                }
                else
                {
                    ExoforgeEditorConfig.WorkspacePath = chosen;
                }
            }
        }
        EditorGUILayout.EndHorizontal();

        // Generated Script Path
        EditorGUILayout.BeginHorizontal();
        ExoforgeEditorConfig.GeneratedScriptPath = EditorGUILayout.TextField("Generated Client", ExoforgeEditorConfig.GeneratedScriptPath);
        if (GUILayout.Button("Browse...", GUILayout.Width(70)))
        {
            string chosen = EditorUtility.SaveFilePanel("Generated Client File", Path.GetDirectoryName(ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath())!, "ExoforgeServices.g.cs", "cs");
            if (!string.IsNullOrEmpty(chosen))
            {
                string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                if (chosen.StartsWith(projectRoot))
                {
                    ExoforgeEditorConfig.GeneratedScriptPath = Path.GetRelativePath(projectRoot, chosen);
                }
                else
                {
                    ExoforgeEditorConfig.GeneratedScriptPath = chosen;
                }
            }
        }
        EditorGUILayout.EndHorizontal();

        // Dotnet CLI path (native builds). GUI editors may not inherit the shell PATH.
        EditorGUILayout.BeginHorizontal();
        ExoforgeEditorConfig.DotnetPath = EditorGUILayout.TextField("Dotnet Path", ExoforgeEditorConfig.DotnetPath);
        if (GUILayout.Button("Browse...", GUILayout.Width(70)))
        {
            string chosen = EditorUtility.OpenFilePanel("Select dotnet executable", "", "");
            if (!string.IsNullOrEmpty(chosen))
            {
                ExoforgeEditorConfig.DotnetPath = chosen;
            }
        }
        EditorGUILayout.EndHorizontal();
        EditorGUILayout.LabelField(
            $"Resolved: {ExoDeployer.ResolveDotnetPath(ExoforgeEditorConfig.DotnetPath)}",
            EditorStyles.miniLabel);

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Runtime config link (Assets/Resources/exoforge.json)
        EditorGUILayout.LabelField("Runtime Config", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField($"Output: {ExoforgeRuntimeConfigGenerator.OutputPath}", EditorStyles.miniLabel);
        if (GUILayout.Button("Generate / Relink Runtime Config"))
        {
            if (ExoforgeRuntimeConfigGenerator.Generate())
            {
                ShowStatus($"✓ Runtime config linked → {ExoforgeRuntimeConfigGenerator.OutputPath}", MessageType.Info);
            }
            else
            {
                ShowStatus("No exoforge.json workspace config found; initialize the workspace first.", MessageType.Warning);
            }
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Server Connection & Authentication
        EditorGUILayout.LabelField("Server Connection & Authentication", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        // Read-only: the endpoint comes from the active environment in exoforge.json.
        EditorGUILayout.LabelField("Server URL",
            string.IsNullOrEmpty(ActiveWsUrl) ? "(no environment configured)" : ActiveWsUrl);
        EditorGUILayout.LabelField("Add or change environments in Exoforge/exoforge.json.", EditorStyles.miniLabel);

        EditorGUILayout.BeginHorizontal();
        string newToken = EditorGUILayout.TextField("Bearer Token", ExoTokenStore.Token);
        if (newToken != ExoTokenStore.Token)
        {
            ExoTokenStore.Token = newToken;
        }

        foreach (var (label, token) in ExoforgeEditorConfig.TokenPresets)
        {
            if (GUILayout.Button(label, EditorStyles.miniButton, GUILayout.Width(45)))
            {
                ExoTokenStore.Token = token;
                ShowStatus($"Switched token to '{token}'.", MessageType.Info);
                if (_isConnected)
                {
                    _ = ConnectAsync();
                }
            }
        }
        EditorGUILayout.EndHorizontal();
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Configured Environments
        EditorGUILayout.LabelField("Configured Environments", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        foreach (var env in GetConfiguredEnvironments())
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField(env.Name, EditorStyles.boldLabel, GUILayout.Width(110));
            EditorGUILayout.LabelField(env.WsUrl, EditorStyles.miniLabel);
            if (GUILayout.Button("Select", EditorStyles.miniButton, GUILayout.Width(55)))
            {
                ApplyEnvironment(env);
            }
            EditorGUILayout.EndHorizontal();
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Credential Management
        EditorGUILayout.LabelField("Credential Persistence", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField($"Active Token: {ActiveToken}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Stored Player ID: {ExoTokenStore.PlayerId}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Scopes: {ExoTokenStore.Scopes}", EditorStyles.miniLabel);

        EditorGUILayout.Space(4);
        if (GUILayout.Button("Purge All Saved Credentials (EditorPrefs & PlayerPrefs)"))
        {
            _ = LogOutAsync();
        }
        EditorGUILayout.EndVertical();
    }
}
}
