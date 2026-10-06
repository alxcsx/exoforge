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
    // Tab 4: Plugins & WASM
    // =========================================================================

    private void DrawPlugins()
    {
        _pluginsScroll = EditorGUILayout.BeginScrollView(_pluginsScroll);

        bool wsExists = ExoWorkspace.Exists(_workspace.RootPath);

        // Workspace
        EditorGUILayout.LabelField("Workspace", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField(_workspace.RootPath, EditorStyles.miniLabel);

        EditorGUILayout.BeginHorizontal();
        if (!wsExists && GUILayout.Button("Initialize Workspace", EditorStyles.miniButton))
        {
            _workspace = ExoWorkspace.Initialize(_workspace.RootPath);
            ShowStatus($"Initialized workspace at {_workspace.RootPath}", MessageType.Info);
        }

        if (GUILayout.Button("Reveal in Finder", EditorStyles.miniButton))
        {
            EditorUtility.RevealInFinder(_workspace.RootPath);
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
        if (GUILayout.Button("Refresh Local", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            RefreshLocalPlugins();
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
        using (new EditorGUI.DisabledScope(_isBuilding))
        {
            if (GUILayout.Button("Build All", EditorStyles.miniButton, GUILayout.Width(70)))
            {
                _ = BuildAllAsync();
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

                using (new EditorGUI.DisabledScope(!_isConnected || FirstActionFor(plugin.Name) == null))
                {
                    if (GUILayout.Button(
                            new GUIContent("Test", "Open this plugin's first action in the Action Sandbox"),
                            EditorStyles.miniButton, GUILayout.Width(45)))
                    {
                        OpenInSandbox(plugin.Name);
                    }
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
                _ = RefreshRemoteInfoAsync();
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
        // Everything that is not already up to date — not just the never-built ones, or clicking
        // "Build All" after an edit would silently do nothing.
        var stale = _localPlugins.Where(p => p.CanBuild && (!p.IsBuilt || p.Modified)).ToList();

        if (stale.Count == 0)
        {
            ShowStatus("All plugins are already up to date.", MessageType.Info);
            return;
        }

        foreach (var plugin in stale)
        {
            await BuildPluginAsync(plugin, thenDeploy: false);
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
            var deployer = new ExoDeployer(_workspace);
            string? rid = string.IsNullOrWhiteSpace(_buildRid) ? null : _buildRid.Trim();
            // The generator ships inside the SDK; resolve it through the package rather than
            // letting the deployer guess at a layout.
            string? manifestGen = ExoforgeEditorConfig.ManifestGenPath;

            if (manifestGen == null)
            {
                ShowStatus(
                    "The SDK's manifest generator is missing from this package — reinstall com.exoforge.sdk.",
                    MessageType.Error);
                return;
            }

            var build = await deployer.BuildPluginAsync(
                plugin.Name, rid, ExoforgeEditorConfig.DotnetPath, AppendBuildLog, manifestGen);

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
            var deployer = new ExoDeployer(_workspace);
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
            var deployer = new ExoDeployer(_workspace);
            var outputs = await deployer.GenerateAllPluginStubsAsync(existingClient: _isConnected ? _editorClient : null);
            ShowStatus($"✓ Generated typed service stubs for {outputs.Count} plugin(s).", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Stub generation failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task DeployPluginAsync(LocalPluginInfo plugin)    {
        try
        {
            var deployer = new ExoDeployer(_workspace);
            await deployer.UploadPluginAsync(plugin.Name, existingClient: _editorClient);
            ShowStatus($"Successfully deployed '{plugin.Name}' to cluster.", MessageType.Info);
            await RefreshRemoteInfoAsync();
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
            var deployer = new ExoDeployer(_workspace);
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
            var deployer = new ExoDeployer(_workspace);
            await deployer.RemovePluginAsync(pluginId, existingClient: _editorClient);
            ShowStatus($"Removed remote plugin '{pluginId}'.", MessageType.Info);
            await RefreshRemoteInfoAsync();
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
