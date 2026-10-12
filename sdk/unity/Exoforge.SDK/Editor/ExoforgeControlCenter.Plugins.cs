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

/// <summary>Plugins tab: scaffold, build, deploy, reload and inspect local and remote plugins.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Tab 4: Plugins
    // =========================================================================

    private void DrawPlugins()
    {
        _pluginsScroll = EditorGUILayout.BeginScrollView(_pluginsScroll);

        // Build and Scaffold work offline; Deploy, Stubs and Logs do not. Said here rather than gating
        // the tab, which would take the one thing that does work with it.
        if (!CanReachCluster)
        {
            EditorGUILayout.HelpBox(
                _isConnecting
                    ? "Connecting to the cluster — Deploy, Stubs and Logs unlock when it lands."
                    : "Offline. Building and scaffolding work; Deploy, Stubs and Logs need a connection — sign in from the header.",
                _isConnecting ? MessageType.Info : MessageType.Warning);
        }

        bool wsExists = ExoWorkspace.Exists(Workspace.RootPath);

        // Workspace
        EditorGUILayout.LabelField("Workspace", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField(Workspace.RootPath, EditorStyles.miniLabel);

        EditorGUILayout.BeginHorizontal();
        if (!wsExists && GUILayout.Button("Initialize Workspace", EditorStyles.miniButton))
        {
            ExoWorkspace.Initialize(Workspace.RootPath);

            // Force a reload: Initialize may have created files the cached workspace has not seen.
            _workspaceLoadedFrom = "";
            ShowStatus($"Initialized workspace at {Workspace.RootPath}", MessageType.Info);
        }

        if (GUILayout.Button("Reveal in Finder", EditorStyles.miniButton))
        {
            EditorUtility.RevealInFinder(Workspace.RootPath);
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(6);

        // Scaffolder
        EditorGUILayout.LabelField("Scaffold New C# Plugin", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        _newPluginName = EditorGUILayout.TextField("Plugin Name", _newPluginName);
        _newPluginTemplateIndex = EditorGUILayout.Popup("Template", _newPluginTemplateIndex, ExoScaffolder.Templates);

        using (new EditorGUI.DisabledScope(string.IsNullOrWhiteSpace(_newPluginName)))
        {
            if (GUILayout.Button("Scaffold C# Plugin"))
            {
                ScaffoldNewPlugin();
            }
        }

        EditorGUILayout.LabelField(
            string.IsNullOrWhiteSpace(_newPluginName)
                ? "Names are lower_snake_case, e.g. guild_system."
                : $"Will be created as '{ExoScaffolder.NormalizePluginName(_newPluginName)}'.",
            EditorStyles.miniLabel);

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(6);

        // Local Plugins
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Local Plugins ({_localPlugins.Count})", EditorStyles.boldLabel);
        if (GUILayout.Button(new GUIContent("🔌 Plugins Window", "Open dedicated Exoforge Plugins visualization window"), EditorStyles.miniButton, GUILayout.Width(115)))
        {
            ExoforgePluginsWindow.ShowWindow();
        }
        if (GUILayout.Button("Refresh Local", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            _ = RefreshPluginsAsync();
        }
        using (new EditorGUI.DisabledScope(_isBuilding))
        {
            if (GUILayout.Button("Sync Stubs", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                _ = GenerateAllStubsAsync();
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Native RID", GUILayout.Width(70));
        _buildRid = EditorGUILayout.TextField(_buildRid);
        EditorGUILayout.LabelField("(blank = host)", EditorStyles.miniLabel, GUILayout.Width(90));
        using (new EditorGUI.DisabledScope(_isBuilding || _localPlugins.Count == 0))
        {
            if (GUILayout.Button(new GUIContent("Build All", "Build all local plugins in the workspace"), EditorStyles.miniButton, GUILayout.Width(70)))
            {
                _ = BuildAllAsync();
            }
        }
        using (new EditorGUI.DisabledScope(_isBuilding || !_isConnected || _localPlugins.Count == 0))
        {
            if (GUILayout.Button(new GUIContent("Deploy All", "Deploy all local plugins to the connected cluster"), EditorStyles.miniButton, GUILayout.Width(75)))
            {
                _ = DeployAllAsync();
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        if (_localPlugins.Count == 0)
        {
            EditorGUILayout.LabelField("No local plugins found in workspace/plugins.", EditorStyles.miniLabel);
        }
        else
        {
            foreach (var plugin in _localPlugins)
            {
                EditorGUILayout.BeginHorizontal();
                EditorGUILayout.LabelField(plugin.Name, EditorStyles.boldLabel, GUILayout.Width(140));
                EditorGUILayout.LabelField(plugin.PluginType.ToUpperInvariant(), EditorStyles.miniLabel, GUILayout.Width(55));

                string buildError = SessionState.GetString(BuildFailureKey(plugin.Name), "");
                bool failed = buildError.Length > 0;
                string tag = BuildTag(plugin.Version);
                string? deployedVersion = RemotePluginVersion(plugin.Name);
                bool notDeployed = _isConnected && plugin.IsBuilt && !plugin.Modified && deployedVersion != plugin.Version;

                if (failed)
                {
                    var prev = GUI.color;
                    GUI.color = new Color(0.9f, 0.3f, 0.3f);
                    EditorGUILayout.LabelField(new GUIContent("✗ Build failed", buildError), EditorStyles.miniBoldLabel, GUILayout.Width(120));
                    GUI.color = prev;
                }
                else if (!plugin.IsBuilt)
                {
                    var prev = GUI.color;
                    GUI.color = new Color(0.9f, 0.6f, 0.2f);
                    EditorGUILayout.LabelField("○ Not built", EditorStyles.miniLabel, GUILayout.Width(120));
                    GUI.color = prev;
                }
                else if (plugin.Modified)
                {
                    var prev = GUI.color;
                    GUI.color = new Color(0.95f, 0.7f, 0.2f);
                    EditorGUILayout.LabelField(new GUIContent($"● Modified {tag}", $"Sources changed since build {plugin.Version}"), EditorStyles.miniBoldLabel, GUILayout.Width(120));
                    GUI.color = prev;
                }
                else if (notDeployed)
                {
                    string deployedLabel = deployedVersion ?? "(none)";
                    var prev = GUI.color;
                    GUI.color = new Color(0.95f, 0.7f, 0.2f);
                    EditorGUILayout.LabelField(new GUIContent($"● Not deployed {tag}", $"Local {plugin.Version} differs from deployed {deployedLabel}"), EditorStyles.miniBoldLabel, GUILayout.Width(120));
                    GUI.color = prev;
                }
                else
                {
                    string sizeStr = $"{plugin.BinarySizeBytes / 1024} KB";
                    var prev = GUI.color;
                    GUI.color = new Color(0.3f, 0.9f, 0.4f);
                    EditorGUILayout.LabelField(new GUIContent($"✓ Ready {tag} ({sizeStr})", plugin.Version), EditorStyles.miniBoldLabel, GUILayout.Width(120));
                    GUI.color = prev;
                }

                using (new EditorGUI.DisabledScope(_isBuilding || !plugin.CanBuild))
                {
                    if (GUILayout.Button("Build", EditorStyles.miniButton, GUILayout.Width(55)))
                    {
                        _ = BuildPluginAsync(plugin, thenDeploy: false);
                    }
                }

                using (new EditorGUI.DisabledScope(_isBuilding || !plugin.CanBuild || !_isConnected))
                {
                    if (GUILayout.Button("Build & Deploy", EditorStyles.miniButton, GUILayout.Width(105)))
                    {
                        _ = BuildPluginAsync(plugin, thenDeploy: true);
                    }
                }

                using (new EditorGUI.DisabledScope(_isBuilding || failed || !plugin.IsBuilt || !_isConnected))
                {
                    if (GUILayout.Button("Deploy", EditorStyles.miniButton, GUILayout.Width(60)))
                    {
                        _ = DeployPluginAsync(plugin);
                    }
                }

                using (new EditorGUI.DisabledScope(_isBuilding || !plugin.CanBuild || !_isConnected))
                {
                    if (GUILayout.Button("Stubs", EditorStyles.miniButton, GUILayout.Width(50)))
                    {
                        _ = GenerateStubsAsync(plugin);
                    }
                }

                if (GUILayout.Button(
                        new GUIContent("Inspect", "Inspect this plugin in the Exoforge Plugins window"),
                        EditorStyles.miniButton, GUILayout.Width(55)))
                {
                    ExoforgePluginsWindow.OpenPlugin(plugin.Name);
                }

                using (new EditorGUI.DisabledScope(!_isConnected))
                {
                    if (GUILayout.Button("Logs", EditorStyles.miniButton, GUILayout.Width(45)))
                    {
                        _ = ShowPluginLogsAsync(plugin.Name);
                    }
                }

                if (GUILayout.Button("Folder", EditorStyles.miniButton, GUILayout.Width(55)))
                {
                    EditorUtility.RevealInFinder(plugin.Directory);
                }

                EditorGUILayout.EndHorizontal();
            }
        }
        EditorGUILayout.EndVertical();

        if (_showPluginLogs)
        {
            _showPluginLogs = EditorGUILayout.Foldout(_showPluginLogs, $"Logs — {_pluginLogsFor}", true);

            if (_showPluginLogs)
            {
                EditorGUILayout.BeginHorizontal();
                EditorGUILayout.LabelField(
                    "Recent lines the plugin emitted. Held in memory on the cluster and capped.",
                    EditorStyles.miniLabel);
                if (GUILayout.Button("Refresh", EditorStyles.miniButton, GUILayout.Width(60)))
                {
                    _ = ShowPluginLogsAsync(_pluginLogsFor);
                }
                EditorGUILayout.EndHorizontal();

                _pluginLogsScroll = EditorGUILayout.BeginScrollView(_pluginLogsScroll, GUILayout.Height(120));
                EditorGUILayout.TextArea(_pluginLogs, EditorStyles.textArea);
                EditorGUILayout.EndScrollView();
            }
        }

        if (!string.IsNullOrEmpty(_buildLog))
        {
            _showBuildLog = EditorGUILayout.Foldout(_showBuildLog, "Build Log", true);
            if (_showBuildLog)
            {
                _buildLogScroll = EditorGUILayout.BeginScrollView(_buildLogScroll, GUILayout.Height(120));
                EditorGUILayout.TextArea(_buildLog, EditorStyles.textArea);
                EditorGUILayout.EndScrollView();
            }
        }

        EditorGUILayout.Space(6);

        // Remote Plugins
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Active Remote Plugins ({_remotePlugins.Count})", EditorStyles.boldLabel);
        using (new EditorGUI.DisabledScope(!_isConnected))
        {
            if (GUILayout.Button("Refresh Remote", EditorStyles.miniButton, GUILayout.Width(100)))
            {
                _ = RefreshPluginsAsync();
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        if (_remotePlugins.Count == 0)
        {
            EditorGUILayout.LabelField(_isConnected ? "No active remote plugins." : "Connect to view remote plugins.", EditorStyles.miniLabel);
        }
        else
        {
            foreach (var plugin in _remotePlugins)
            {
                string id = plugin.TryGetProperty("id", out var idProp) ? idProp.ToString() : "?";
                string version = plugin.TryGetProperty("version", out var vProp) ? vProp.ToString() : "";

                EditorGUILayout.BeginHorizontal();
                EditorGUILayout.LabelField($"{id}  {version}", EditorStyles.boldLabel);
                if (GUILayout.Button(
                        new GUIContent("Inspect", "Inspect this plugin in the Exoforge Plugins window"),
                        EditorStyles.miniButton, GUILayout.Width(60)))
                {
                    ExoforgePluginsWindow.OpenPlugin(id);
                }
                using (new EditorGUI.DisabledScope(!_isConnected))
                {
                    if (GUILayout.Button("Remove", EditorStyles.miniButton, GUILayout.Width(65)))
                    {
                        bool confirmed = EditorUtility.DisplayDialog(
                            "Remove plugin",
                            $"Remove '{id}' from the cluster?\n\nIts files stay on the server; the plugin stops running.",
                            "Remove", "Cancel");

                        if (confirmed)
                        {
                            _ = RemovePluginAsync(id);
                        }
                    }
                }
                EditorGUILayout.EndHorizontal();
            }
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.EndScrollView();
    }

    private static string BuildFailureKey(string pluginName) => $"Exoforge_BuildFailed_{pluginName}";

    /// <summary>Compact build tag from a version's SemVer build metadata (1.0.0+42.ab12cd34 → #42).</summary>
    private static string BuildTag(string? version)
    {
        if (string.IsNullOrEmpty(version)) return "";

        int plus = version.IndexOf('+');
        if (plus < 0 || plus + 1 >= version.Length) return "";

        string metadata = version[(plus + 1)..];
        int dot = metadata.IndexOf('.');
        return "#" + (dot > 0 ? metadata[..dot] : metadata);
    }

    /// <summary>The version the cluster currently has for a plugin, or null when it is not deployed.</summary>
    private string? RemotePluginVersion(string pluginId)
    {
        foreach (var plugin in _remotePlugins)
        {
            if (plugin.ValueKind == JsonValueKind.Object &&
                plugin.TryGetProperty("id", out var id) &&
                string.Equals(id.ToString(), pluginId, StringComparison.OrdinalIgnoreCase) &&
                plugin.TryGetProperty("version", out var version))
            {
                return version.ToString();
            }
        }

        return null;
    }

    private static bool IsBuildPath(string path)
    {
        string normalized = path.Replace('\\', '/');
        return normalized.Contains("/bin/") || normalized.Contains("/obj/");
    }

    private async Task BuildAllAsync()
    {
        if (_isBuilding) return;

        var buildable = _localPlugins.Where(p => p.CanBuild).ToList();
        if (buildable.Count == 0)
        {
            ShowStatus("No buildable plugins found.", MessageType.Info);
            return;
        }

        var targets = buildable.Where(p => !p.IsBuilt || p.Modified).ToList();
        if (targets.Count == 0)
        {
            targets = buildable;
        }

        ShowStatus($"Building {targets.Count} plugin(s)…", MessageType.Info);
        foreach (var plugin in targets)
        {
            await BuildPluginAsync(plugin, thenDeploy: false);
        }

        ShowStatus($"✓ Built {targets.Count} plugin(s).", MessageType.Info);
    }

    private async Task DeployAllAsync()
    {
        if (_isBuilding) return;
        if (!_isConnected)
        {
            ShowStatus("Cannot deploy: not connected to cluster.", MessageType.Warning);
            return;
        }

        var unbuilt = _localPlugins.Where(p => p.CanBuild && (!p.IsBuilt || p.Modified)).ToList();
        if (unbuilt.Count > 0)
        {
            ShowStatus($"Building {unbuilt.Count} unbuilt/modified plugin(s) before deploy…", MessageType.Info);
            foreach (var plugin in unbuilt)
            {
                await BuildPluginAsync(plugin, thenDeploy: false);
            }
        }

        var deployable = _localPlugins.Where(p => p.IsBuilt && SessionState.GetString(BuildFailureKey(p.Name), "").Length == 0).ToList();
        if (deployable.Count == 0)
        {
            ShowStatus("No built plugins available to deploy.", MessageType.Warning);
            return;
        }

        _isBuilding = true;
        ShowStatus($"Deploying {deployable.Count} plugin(s) to cluster…", MessageType.Info);
        Repaint();

        int successCount = 0;
        var errors = new List<string>();

        try
        {
            var deployer = new ExoDeployer(Workspace);
            foreach (var plugin in deployable)
            {
                try
                {
                    await deployer.UploadPluginAsync(plugin.Name, existingClient: _editorClient);
                    successCount++;
                }
                catch (Exception ex)
                {
                    errors.Add($"{plugin.Name}: {ex.Message}");
                }
            }

            await RefreshPluginsAsync();
            await SyncAndGenerateClientAsync();

            if (errors.Count == 0)
            {
                ShowStatus($"✓ Successfully deployed all {successCount} plugin(s) to cluster.", MessageType.Info);
            }
            else
            {
                ShowStatus($"Deployed {successCount}/{deployable.Count} plugin(s). Failures: {string.Join("; ", errors)}", MessageType.Error);
            }
        }
        catch (Exception ex)
        {
            ShowStatus($"Deploy all failed: {ex.Message}", MessageType.Error);
        }
        finally
        {
            _isBuilding = false;
            Repaint();
        }
    }

    private async Task BuildPluginAsync(LocalPluginInfo plugin, bool thenDeploy)
    {
        if (_isBuilding) return;

        _isBuilding = true;
        _showBuildLog = true;
        _buildLog = $"Building {plugin.Name} ({plugin.PluginType})...\n";
        ShowStatus($"Building '{plugin.Name}'… (see Build Log)", MessageType.Info);
        Repaint();

        try
        {
            var deployer = new ExoDeployer(Workspace);
            string? rid = string.IsNullOrWhiteSpace(_buildRid) ? null : _buildRid.Trim();

            var build = await deployer.BuildPluginAsync(
                plugin.Name, rid, ExoforgeEditorConfig.DotnetPath, AppendBuildLog);

            _buildLog = build.Output;
            SessionState.EraseString(BuildFailureKey(plugin.Name));
            ShowStatus($"✓ Built '{plugin.Name}' ({build.PluginType}).", MessageType.Info);
            RefreshLocalPlugins();

            if (thenDeploy)
            {
                await DeployPluginAsync(plugin);
            }
        }
        catch (Exception ex)
        {
            _buildLog = ex.ToString();
            SessionState.SetString(BuildFailureKey(plugin.Name), ex.Message);
            _showBuildLog = true;
            ShowStatus($"Build failed for '{plugin.Name}': {ex.Message}", MessageType.Error);
        }
        finally
        {
            _isBuilding = false;
            Repaint();
        }
    }

    private async Task GenerateStubsAsync(LocalPluginInfo plugin)
    {
        try
        {
            var deployer = new ExoDeployer(Workspace);
            string output = await deployer.GeneratePluginStubsAsync(plugin.Name, existingClient: _isConnected ? _editorClient : null);
            ShowStatus($"✓ Generated typed service stubs for '{plugin.Name}' → {output}", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Stub generation failed for '{plugin.Name}': {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task GenerateAllStubsAsync()
    {
        try
        {
            var deployer = new ExoDeployer(Workspace);
            var outputs = await deployer.GenerateAllPluginStubsAsync(existingClient: _isConnected ? _editorClient : null);
            ShowStatus($"✓ Generated typed service stubs for {outputs.Count} plugin(s).", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Stub generation failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task DeployPluginAsync(LocalPluginInfo plugin)
    {
        try
        {
            var deployer = new ExoDeployer(Workspace);
            await deployer.UploadPluginAsync(plugin.Name, existingClient: _editorClient);
            ShowStatus($"Successfully deployed '{plugin.Name}' to cluster.", MessageType.Info);
            await RefreshPluginsAsync();
            await SyncAndGenerateClientAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Deploy failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    /// <summary>The first action of a plugin's first service, or null when it exposes none.</summary>
    private ActionSpec? FirstActionFor(string pluginId)
    {
        string clean = ExoScaffolder.NormalizePluginName(pluginId);

        if (!_pluginServices.TryGetValue(clean, out var services) || services.Count == 0) return null;

        return _serviceCatalog.TryGetValue(services[0], out var specs) && specs.Count > 0 ? specs[0] : null;
    }

    /// <summary>Jumps to the Sandbox with one of this plugin's actions selected.</summary>
    private void OpenInSandbox(string pluginId)
    {
        if (!_pluginServices.TryGetValue(ExoScaffolder.NormalizePluginName(pluginId), out var services) ||
            services.Count == 0)
        {
            ShowStatus($"No actions found for '{pluginId}'. Deploy it, then refresh.", MessageType.Error);
            return;
        }

        _sandboxService = services[0];
        _selectedServiceIndex = Mathf.Max(_serviceCatalog.Keys.ToList().IndexOf(_sandboxService), 0);

        var specs = _serviceCatalog[_sandboxService];
        _sandboxAction = specs[0].Name;
        _selectedActionIndex = 0;

        LoadSamplePayload(_sandboxService, _sandboxAction);
        _currentTab = Tab.ActionSandbox;
    }

    private async Task ShowPluginLogsAsync(string pluginId)
    {
        string clean = ExoScaffolder.NormalizePluginName(pluginId);

        try
        {
            var deployer = new ExoDeployer(Workspace);
            var lines = await deployer.GetPluginLogsAsync(clean, 100, existingClient: _isConnected ? _editorClient : null);

            _pluginLogs = lines.Count == 0
                ? "(no log lines recorded — the plugin may not have run yet)"
                : string.Join("\n", lines.Select(l => $"{l.LocalTime:HH:mm:ss}  {l.LevelName,-7} {l.Message}"));
        }
        catch (Exception ex)
        {
            _pluginLogs = $"Could not load logs: {ex.Message}";
        }

        _pluginLogsFor = clean;
        _showPluginLogs = true;
        Repaint();
    }

    private async Task RemovePluginAsync(string pluginId)
    {
        try
        {
            var deployer = new ExoDeployer(Workspace);
            await deployer.RemovePluginAsync(pluginId, existingClient: _editorClient);
            ShowStatus($"Removed remote plugin '{pluginId}'.", MessageType.Info);
            await RefreshPluginsAsync();
            await SyncAndGenerateClientAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Remove failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }
}
}
