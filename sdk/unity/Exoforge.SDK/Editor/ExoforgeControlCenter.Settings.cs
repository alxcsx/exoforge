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
        _settingsScroll = EditorGUILayout.BeginScrollView(_settingsScroll);

        // Project & Studio Identity
        EditorGUILayout.LabelField("Project & Studio Identity", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        if (Workspace?.Config != null)
        {
            Workspace.Config.StudioName = EditorGUILayout.TextField("Studio Name", Workspace.Config.StudioName);
            Workspace.Config.ProjectName = EditorGUILayout.TextField("Project Title", Workspace.Config.ProjectName);
            Workspace.Config.Description = EditorGUILayout.TextField("Description", Workspace.Config.Description ?? "");

            EditorGUILayout.Space(2);
            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button("Save to exoforge.json", EditorStyles.miniButton))
            {
                Workspace.Save();
                ExoforgeRuntimeConfigGenerator.Generate();
                ShowStatus("✓ Saved project metadata to exoforge.json.", MessageType.Info);
            }

            using (new EditorGUI.DisabledScope(!_isConnected))
            {
                if (GUILayout.Button("Push to Cluster", EditorStyles.miniButton, GUILayout.Width(115)))
                {
                    _ = PushProjectMetadataToClusterAsync();
                }
                if (GUILayout.Button("Pull from Cluster", EditorStyles.miniButton, GUILayout.Width(120)))
                {
                    PullProjectMetadataFromCluster();
                }
            }
            EditorGUILayout.EndHorizontal();

            if (_isConnected && RemoteProjectName != "—")
            {
                EditorGUILayout.LabelField($"Cluster Identity: {RemoteStudioName} / {RemoteProjectName}", EditorStyles.miniLabel);
            }
        }
        else
        {
            EditorGUILayout.HelpBox("Workspace config not loaded.", MessageType.Info);
        }

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

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
        if (GUILayout.Button("📁 Reveal", GUILayout.Width(65)))
        {
            EditorUtility.RevealInFinder(Workspace.RootPath);
        }
        EditorGUILayout.EndHorizontal();

        bool wsExists = ExoWorkspace.Exists(Workspace.RootPath);
        if (!wsExists)
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.HelpBox($"Workspace not initialized at: {Workspace.RootPath}", MessageType.Warning);
            if (GUILayout.Button("Initialize Workspace", GUILayout.Width(140)))
            {
                ExoWorkspace.Initialize(Workspace.RootPath);
                _workspaceLoadedFrom = "";
                ShowStatus($"Initialized workspace at {Workspace.RootPath}", MessageType.Info);
            }
            EditorGUILayout.EndHorizontal();
        }

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

        EditorGUILayout.Space(4);
        ExoforgeEditorConfig.AutoGenerateStubsOnBuild = EditorGUILayout.Toggle(
            new GUIContent("Auto-Generate Stubs on Build", "Automatically regenerate typed C# plugin stubs after compiling or rebuilding an extension"),
            ExoforgeEditorConfig.AutoGenerateStubsOnBuild);

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

        string activeEnvName = ActiveEnvironment?.Name ?? "local";
        var activeEnvConfig = Workspace?.Config?.Environments != null && Workspace.Config.Environments.TryGetValue(activeEnvName, out var foundEnv)
            ? foundEnv
            : null;

        string currentWs = activeEnvConfig?.WsUrl ?? ActiveWsUrl;
        string currentHttp = activeEnvConfig?.HttpUrl ?? ActiveHttpUrl;

        string currentBase = ExoforgeEditorConfig.DeriveBaseUrl(currentWs, currentHttp);
        EditorGUI.BeginChangeCheck();
        string newBase = EditorGUILayout.TextField("Cluster Base URL", currentBase);
        if (EditorGUI.EndChangeCheck() && !string.IsNullOrWhiteSpace(newBase) && newBase != currentBase)
        {
            ExoforgeEditorConfig.DeriveEndpoints(newBase, out var derivedWs, out var derivedHttp);
            if (activeEnvConfig != null)
            {
                activeEnvConfig.WsUrl = derivedWs;
                activeEnvConfig.HttpUrl = derivedHttp;
                currentWs = derivedWs;
                currentHttp = derivedHttp;
            }
        }

        string newWs = EditorGUILayout.TextField("WebSocket URL", activeEnvConfig?.WsUrl ?? currentWs);
        string newHttp = EditorGUILayout.TextField("HTTP REST URL", activeEnvConfig?.HttpUrl ?? currentHttp);

        if (activeEnvConfig != null && (newWs != (activeEnvConfig?.WsUrl ?? currentWs) || newHttp != (activeEnvConfig?.HttpUrl ?? currentHttp)))
        {
            activeEnvConfig.WsUrl = newWs;
            activeEnvConfig.HttpUrl = newHttp;
        }

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("Save Endpoints to exoforge.json", EditorStyles.miniButton))
        {
            try
            {
                if (Workspace != null)
                {
                    if (activeEnvConfig != null)
                    {
                        Workspace.Config.Environments[activeEnvName] = activeEnvConfig;
                    }
                    Workspace.Save();
                    ExoforgeRuntimeConfigGenerator.Generate();
                    ShowStatus($"✓ Saved endpoints for '{activeEnvName}' to exoforge.json and relinked runtime config.", MessageType.Info);
                    if (_isConnected)
                    {
                        _ = ConnectAsync();
                    }
                }
            }
            catch (Exception ex)
            {
                ShowStatus($"Failed to save exoforge.json: {ex.Message}", MessageType.Error);
            }
        }

        if (GUILayout.Button("Reset to Localhost", EditorStyles.miniButton, GUILayout.Width(125)))
        {
            if (activeEnvConfig != null)
            {
                activeEnvConfig.WsUrl = "ws://localhost:4000/ws";
                activeEnvConfig.HttpUrl = "http://localhost:4001";
                Workspace?.Save();
                ExoforgeRuntimeConfigGenerator.Generate();
                ShowStatus("✓ Endpoints reset to localhost.", MessageType.Info);
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(4);
        if (GUILayout.Button("🚀 Re-Run Setup Wizard..."))
        {
            ExoforgeSetupModal.Open(onCompleted: () =>
            {
                InvalidateWorkspace();
                RebuildStudioUI();
            });
        }

        EditorGUILayout.Space(4);

        string currentStudioToken = ExoTokenStore.StudioToken;
        string newToken = EditorGUILayout.TextField("Bearer Token", currentStudioToken);
        if (newToken != currentStudioToken)
        {
            ExoTokenStore.SaveStudioSession(newToken);
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Anonymous Player Session
        EditorGUILayout.LabelField("Anonymous Player Session", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField($"Device ID: {PlayerPrefs.GetString("Exoforge.DeviceId", "(none)")}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Player Token: {(PlayerPrefs.HasKey("Exoforge.Token") ? "(cached in PlayerPrefs)" : "(none)")}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Player Name: {PlayerPrefs.GetString("Exoforge.PlayerName", "(unnamed)")}", EditorStyles.miniLabel);
        EditorGUILayout.Space(4);
        if (GUILayout.Button("Reset Anonymous Player Session (New Device ID & Fresh Account)"))
        {
            ResetAnonymousPlayerSession();
            ShowStatus("Anonymous player session reset. A fresh player account will be minted on next run.", MessageType.Info);
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Configured Environments
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Configured Environments", EditorStyles.boldLabel);
        if (GUILayout.Button("➕ New Environment", EditorStyles.miniButton, GUILayout.Width(135)))
        {
            ExoforgeEnvironmentModal.Open(Repaint);
        }
        EditorGUILayout.EndHorizontal();
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
        EditorGUILayout.LabelField($"Studio Token: {ExoTokenStore.StudioToken}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Studio Player ID: {ExoTokenStore.StudioPlayerId}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Scopes: {ExoTokenStore.StudioScopes}", EditorStyles.miniLabel);
        EditorGUILayout.Space(4);
        if (GUILayout.Button("Purge All Saved Credentials (EditorPrefs & PlayerPrefs)"))
        {
            _ = LogOutAsync();
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Developer Tools & API Documentation
        EditorGUILayout.LabelField("Developer Tools & Documentation", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        using (new EditorGUI.DisabledScope(string.IsNullOrEmpty(ActiveHttpUrl)))
        {
            if (GUILayout.Button("📖 Open Swagger REST API Docs ↗", GUILayout.Height(26)))
            {
                Application.OpenURL(new Uri(new Uri(ActiveHttpUrl), "/swagger").ToString());
            }
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.EndScrollView();
    }

    private async Task PushProjectMetadataToClusterAsync()
    {
        if (_editorClient == null || !_isConnected || Workspace?.Config == null) return;
        try
        {
            var payload = new Dictionary<string, object>
            {
                ["project_name"] = Workspace.Config.ProjectName,
                ["studio_name"] = Workspace.Config.StudioName,
                ["description"] = Workspace.Config.Description ?? ""
            };
            await _editorClient.SendActionAsync<JsonElement>("dashboard", "update_project_metadata", payload);
            RemoteProjectName = Workspace.Config.ProjectName;
            RemoteStudioName = Workspace.Config.StudioName;
            RemoteDescription = Workspace.Config.Description ?? "";
            ShowStatus("✓ Pushed project metadata to cluster.", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Failed to push project metadata: {ex.Message}", MessageType.Error);
        }
        Repaint();
    }

    private void PullProjectMetadataFromCluster()
    {
        if (Workspace?.Config == null) return;
        if (RemoteProjectName != "—") Workspace.Config.ProjectName = RemoteProjectName;
        if (RemoteStudioName != "—") Workspace.Config.StudioName = RemoteStudioName;
        if (!string.IsNullOrEmpty(RemoteDescription)) Workspace.Config.Description = RemoteDescription;
        if (!string.IsNullOrEmpty(RemoteWebsiteUrl)) Workspace.Config.WebsiteUrl = RemoteWebsiteUrl;
        Workspace.Save();
        ExoforgeRuntimeConfigGenerator.Generate();
        ShowStatus("✓ Pulled project metadata from cluster and saved to exoforge.json.", MessageType.Info);
        Repaint();
    }
}
}
