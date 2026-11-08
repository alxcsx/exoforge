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
        var dotnetRes = ExoforgeDotnetValidator.Validate(ExoforgeEditorConfig.DotnetPath);
        if (dotnetRes.IsValid)
        {
            EditorGUILayout.LabelField(
                $"✓ .NET SDK: {dotnetRes.ResolvedPath} (v{dotnetRes.Version})",
                EditorStyles.miniLabel);

            string runtimesStr = dotnetRes.InstalledRuntimes.Count > 0
                ? string.Join(", ", dotnetRes.InstalledRuntimes)
                : "Standard .NET runtime";
            EditorGUILayout.LabelField(
                $"✓ Installed Runtimes: {runtimesStr}",
                EditorStyles.miniLabel);

            EditorGUILayout.LabelField(
                $"✓ Host Platform: {dotnetRes.HostRid} | Target Server: {dotnetRes.TargetServerRid}",
                EditorStyles.miniLabel);

            EditorGUILayout.Space(2);
            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button("⬇️ Pre-warm / Restore Runtime Packs (linux-musl-x64, linux-x64 & host)", GUILayout.Height(22)))
            {
                ShowStatus("Restoring targeting packs for linux-musl-x64, linux-x64 and host RID...", MessageType.Info);
                bool ok = ExoforgeDotnetValidator.PrewarmRuntimePacks(
                    $"{dotnetRes.HostRid},{ExoforgeDotnetValidator.StandardServerRid},{ExoforgeDotnetValidator.FallbackServerRid}",
                    ExoforgeEditorConfig.DotnetPath,
                    msg => UnityEngine.Debug.Log($"[Exoforge] {msg}"));
                if (ok)
                {
                    ShowStatus("✓ Runtime packs (linux-musl-x64, linux-x64 & host) successfully restored and cached.", MessageType.Info);
                }
                else
                {
                    ShowStatus("⚠️ Some runtime packs could not be restored; check internet connection to nuget.org.", MessageType.Warning);
                }
            }
            if (GUILayout.Button("🔍 Re-scan", GUILayout.Width(90), GUILayout.Height(22)))
            {
                var fresh = ExoforgeDotnetValidator.Validate(ExoforgeEditorConfig.DotnetPath, forceFresh: true);
                ShowStatus($"✓ .NET SDK refreshed: v{fresh.Version}", MessageType.Info);
            }
            EditorGUILayout.EndHorizontal();
        }
        else
        {
            EditorGUILayout.Space(2);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.HelpBox(
                !dotnetRes.IsInstalled
                    ? $"⚠️ .NET SDK not detected at '{dotnetRes.ResolvedPath}'. Native C# extension builds and deployments will fail without the .NET SDK (v9.0+)."
                    : $"⚠️ Detected .NET SDK v{dotnetRes.Version}, but Exoforge requires .NET 9.0 or newer.",
                MessageType.Warning);

            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button("⬇️ Download .NET SDK (.NET 9.0) ↗", GUILayout.Height(24)))
            {
                ExoforgeDotnetValidator.OpenDownloadPage();
            }
            if (GUILayout.Button("🔍 Verify Installation", GUILayout.Width(140), GUILayout.Height(24)))
            {
                var fresh = ExoforgeDotnetValidator.Validate(ExoforgeEditorConfig.DotnetPath, forceFresh: true);
                if (fresh.IsValid)
                {
                    ShowStatus($"✓ .NET SDK verified: v{fresh.Version} at {fresh.ResolvedPath}", MessageType.Info);
                }
                else
                {
                    ExoforgeDotnetValidator.PromptIfMissing("build C# backend extensions");
                }
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.EndVertical();
            EditorGUILayout.Space(2);
        }

        EditorGUILayout.Space(4);
        string currentRid = ExoforgeEditorConfig.TargetBuildRid;
        if (string.IsNullOrEmpty(currentRid)) currentRid = "auto";
        string[] ridOptions = new[] { "auto", "linux-musl-x64", "linux-x64", "linux-arm64", "win-x64", "osx-arm64" };
        string[] ridLabels = new[] {
            $"Auto (Deploy: {(!string.IsNullOrEmpty(_clusterTargetRid) ? _clusterTargetRid : ExoforgeDotnetValidator.StandardServerRid)}, Local: {dotnetRes.HostRid})",
            "linux-musl-x64 (Docker / Alpine Container - Default)",
            "linux-x64 (Standard Linux glibc / VPS)",
            "linux-arm64 (Linux ARM64 / AWS Graviton)",
            "win-x64 (Windows Server / Local Dev)",
            "osx-arm64 (macOS Apple Silicon)"
        };
        int selectedIndex = Array.IndexOf(ridOptions, currentRid.ToLowerInvariant());
        if (selectedIndex < 0) selectedIndex = 0;
        int newIndex = EditorGUILayout.Popup("Target Runtime (RID)", selectedIndex, ridLabels);
        if (newIndex != selectedIndex)
        {
            ExoforgeEditorConfig.TargetBuildRid = newIndex == 0 ? "" : ridOptions[newIndex];
        }

        EditorGUILayout.Space(2);
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
        EditorGUILayout.LabelField($"Player Name: {PlayerPrefs.GetString("Exoforge.PlayerName", "(none)")}", EditorStyles.miniLabel);
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

        EditorGUILayout.Space(8);

        // Troubleshooting & Upgrade Helpers (Progressive Disclosure Fold)
        _showTroubleshootingFold = EditorGUILayout.Foldout(_showTroubleshootingFold, "🛠️ Troubleshooting & Upgrade Helpers", true, EditorStyles.foldoutHeader);
        if (_showTroubleshootingFold)
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField("Resolve IDE sync issues, regenerate stubs, or clean local caches.", EditorStyles.miniLabel);
            EditorGUILayout.Space(4);

            // 1. IDE Re-link
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("IDE Integration & Solution Link", EditorStyles.boldLabel, GUILayout.Width(220));
            if (GUILayout.Button("Re-link IDE Projects (Rider / VS)", GUILayout.Height(24)))
            {
                ExoforgeIdeProjectGenerator.EnsureIdeConfiguration(forceRegenerate: true);
                ShowStatus("✓ Re-linked IDE project generation flags, nuget.config, and .csproj solutions.", MessageType.Info);
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.LabelField("Reconfigures LocalTarBall flags (128), nuget feeds, and generates dedicated Exoforge.Extensions.sln.", EditorStyles.miniLabel);

            EditorGUILayout.Space(6);

            // 2. Client Stubs
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("Strongly-Typed Client Stubs", EditorStyles.boldLabel, GUILayout.Width(220));
            if (GUILayout.Button("Force Regenerate Stubs & Config", GUILayout.Height(24)))
            {
                _ = SyncAndGenerateClientAsync(forceReload: true);
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.LabelField("Re-fetches contracts, regenerates Assets/Exoforge/Generated/ and runtime config.", EditorStyles.miniLabel);

            EditorGUILayout.Space(6);

            // 3. Clear Caches
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("Caches & Session State", EditorStyles.boldLabel, GUILayout.Width(220));
            if (GUILayout.Button("Clear SDK & Staging Caches", GUILayout.Height(24)))
            {
                ClearSdkCaches();
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.LabelField("Purges temporary build artifacts, session flags, and triggers clean asset re-index.", EditorStyles.miniLabel);

            EditorGUILayout.Space(6);

            // 4. Update / Download SDK
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("Cluster SDK Package", EditorStyles.boldLabel, GUILayout.Width(220));
            using (new EditorGUI.DisabledScope(!_isConnected))
            {
                if (GUILayout.Button("Download Latest SDK Tarball", GUILayout.Height(24)))
                {
                    _ = DownloadOrUpdateSdkAsync();
                }
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.LabelField($"Installed: v{ExoforgePackageVersion.SdkVersion} • Cluster: v{RemoteSdkVersion ?? RemoteVersion}", EditorStyles.miniLabel);

            EditorGUILayout.EndVertical();
        }

        EditorGUILayout.EndScrollView();
    }

    private static bool _showTroubleshootingFold = false;

    private void ClearSdkCaches()
    {
        try
        {
            string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            string tempStaging = Path.Combine(projectRoot, "Temp", "ExoforgeStaging");
            if (Directory.Exists(tempStaging))
            {
                Directory.Delete(tempStaging, true);
            }

            SessionState.EraseBool(WasConnectedSessionKey);
            SessionState.EraseBool(AutoConnectSessionKey);
            SessionState.EraseBool("Exoforge_PackageWarned");

            ExoforgeIdeProjectGenerator.EnsureIdeConfiguration(forceRegenerate: true);
            AssetDatabase.Refresh();
            ShowStatus("✓ Exoforge caches cleared and project files regenerated.", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Failed to clear caches: {ex.Message}", MessageType.Error);
        }
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
