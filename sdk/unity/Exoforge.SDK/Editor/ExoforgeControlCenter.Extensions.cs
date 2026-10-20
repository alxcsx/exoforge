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

    private void DrawExtensions()
    {
        _pluginsScroll = EditorGUILayout.BeginScrollView(_pluginsScroll);

        if (!CanReachCluster)
        {
            var origBg = GUI.backgroundColor;
            GUI.backgroundColor = _isConnecting
                ? new Color(0.90f, 0.94f, 1.0f)
                : new Color(1.0f, 0.88f, 0.60f); // Bright highlighted warm amber

            EditorGUILayout.BeginVertical(GUI.skin.box);
            GUI.backgroundColor = origBg;
            EditorGUILayout.Space(6);

            EditorGUILayout.BeginHorizontal();

            // Large Warning Badge / Icon
            var iconStyle = new GUIStyle(EditorStyles.label)
            {
                fontSize = 28,
                alignment = TextAnchor.MiddleCenter
            };
            GUILayout.Label(_isConnecting ? "🔄" : "⚠️", iconStyle, GUILayout.Width(46), GUILayout.Height(46));

            EditorGUILayout.BeginVertical();
            var titleStyle = new GUIStyle(EditorStyles.boldLabel)
            {
                fontSize = 15,
                normal = { textColor = _isConnecting ? ExoforgeUIStyle.AccentBlue : new Color(0.85f, 0.40f, 0.0f) }
            };
            EditorGUILayout.LabelField(_isConnecting ? "Connecting to Cluster…" : "CLUSTER OFFLINE — LOCAL MODE ACTIVE", titleStyle);

            var descStyle = new GUIStyle(EditorStyles.wordWrappedLabel)
            {
                fontSize = 12,
                normal = { textColor = ExoforgeUIStyle.TextPrimary }
            };
            EditorGUILayout.LabelField(
                _isConnecting
                    ? $"Connecting to cluster at {ActiveWsUrl}… Metrics, event streaming, and remote synchronization will unlock once connected."
                    : $"The editor is not connected to the cluster ({ActiveWsUrl}). Scaffolding and C# extension editing are available locally, but deploying, streaming logs, metrics, and live events require a running cluster.",
                descStyle);
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndHorizontal();
            EditorGUILayout.Space(6);
            EditorGUILayout.EndVertical();
            EditorGUILayout.Space(6);
        }

        // --- 1. SCAFFOLD NEW EXTENSION BUTTON ---
        var origBoxBg = GUI.backgroundColor;
        GUI.backgroundColor = ExoforgeUIStyle.ImguiHeroBoxBg;
        EditorGUILayout.BeginVertical(GUI.skin.box);
        GUI.backgroundColor = origBoxBg;
        EditorGUILayout.Space(2);

        EditorGUILayout.BeginHorizontal();
        var scaffoldIconStyle = new GUIStyle(EditorStyles.label) { fontSize = 22, alignment = TextAnchor.MiddleCenter };
        GUILayout.Label("⚡", scaffoldIconStyle, GUILayout.Width(32), GUILayout.Height(32));

        EditorGUILayout.BeginVertical();
        var mainTitleStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 14 };
        EditorGUILayout.LabelField("Create New Extension", mainTitleStyle);
        EditorGUILayout.LabelField("Scaffold a new first-party C# extension module directly into your workspace.", EditorStyles.miniLabel);
        EditorGUILayout.EndVertical();

        var prevBg = GUI.backgroundColor;
        var prevContent = GUI.contentColor;
        GUI.backgroundColor = ExoforgeUIStyle.BrandPurple;
        GUI.contentColor = Color.white;

        var bigBtnStyle = new GUIStyle(GUI.skin.button)
        {
            fontSize = 12,
            fontStyle = FontStyle.Bold,
            alignment = TextAnchor.MiddleCenter
        };

        if (GUILayout.Button("⚡ New Extension...", bigBtnStyle, GUILayout.Width(150), GUILayout.Height(32)))
        {
            ExoforgeScaffoldModal.Open(onCreated: () =>
            {
                RefreshLocalPlugins();
                _ = RefreshPluginsAsync();
                ShowStatus("✓ Extension scaffolded successfully.", MessageType.Info);
            });
        }

        GUI.backgroundColor = prevBg;
        GUI.contentColor = prevContent;

        EditorGUILayout.EndHorizontal();
        EditorGUILayout.Space(2);
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(6);

        // --- 2. GENERATE UNITY CLIENT ---
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.BeginHorizontal();

        string lastSync = !string.IsNullOrEmpty(ExoforgeEditorConfig.LastSyncTime)
            ? ExoforgeEditorConfig.LastSyncTime
            : "Not yet generated";

        EditorGUILayout.LabelField($"Unity Client  •  Last: {lastSync}", EditorStyles.miniBoldLabel);

        if (GUILayout.Button("⚡ Generate Unity Client", GUILayout.Width(175), GUILayout.Height(24)))
        {
            _ = SyncAndGenerateClientAsync();
        }
        EditorGUILayout.EndHorizontal();
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // --- 3. WORKSPACE EXTENSIONS ---
        EditorGUILayout.BeginHorizontal();
        var secTitleStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 13 };
        EditorGUILayout.LabelField($"Workspace Extensions ({_localPlugins.Count})", secTitleStyle);

        using (new EditorGUI.DisabledScope(_isBuilding || !_isConnected || _localPlugins.Count == 0))
        {
            if (GUILayout.Button(new GUIContent("🚀 Build & Deploy All", "Build all workspace extensions and deploy them to the cluster"), EditorStyles.miniButton, GUILayout.Width(135)))
            {
                _ = BuildAndDeployAllAsync();
            }
        }

        if (GUILayout.Button(new GUIContent("⬇ Generate Stubs", "Generate type stubs for all extensions in the workspace"), EditorStyles.miniButton, GUILayout.Width(130)))
        {
            _ = GenerateAllStubsAsync();
        }

        if (GUILayout.Button("🔄 Refresh", EditorStyles.miniButton, GUILayout.Width(75)))
        {
            _ = RefreshPluginsAsync();
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        if (_localPlugins.Count == 0)
        {
            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField("No extensions found in workspace. Create your first extension above!", EditorStyles.centeredGreyMiniLabel);
            EditorGUILayout.Space(8);
        }
        else
        {
            foreach (var plugin in _localPlugins)
            {
                string buildError = SessionState.GetString(BuildFailureKey(plugin.Name), "");
                bool failed = buildError.Length > 0;
                string? deployedVersion = RemotePluginVersion(plugin.Name);
                bool notDeployed = _isConnected && plugin.IsBuilt && !plugin.Modified && deployedVersion != plugin.Version;

                var origCardBg = GUI.backgroundColor;
                if (failed)
                {
                    GUI.backgroundColor = new Color(1.0f, 0.88f, 0.88f);
                }
                else
                {
                    GUI.backgroundColor = ExoforgeUIStyle.ImguiCardBg;
                }
                EditorGUILayout.BeginVertical(GUI.skin.box);
                GUI.backgroundColor = origCardBg;
                EditorGUILayout.Space(3);

                EditorGUILayout.BeginHorizontal();

                // 1. Icon (Bigger emoji / icon)
                var pluginIconStyle = new GUIStyle(EditorStyles.label)
                {
                    fontSize = 22,
                    alignment = TextAnchor.MiddleCenter
                };
                GUILayout.Label(plugin.Icon, pluginIconStyle, GUILayout.Width(34), GUILayout.Height(34));

                // 2. Title & ID & Type (Bigger text, bold)
                EditorGUILayout.BeginVertical();
                string displayTitle = !string.IsNullOrEmpty(plugin.Title) && plugin.Title != plugin.Name
                    ? $"{plugin.Title} ({plugin.Name})"
                    : plugin.Name;

                var titleStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 13 };
                EditorGUILayout.LabelField(displayTitle, titleStyle);

                // Subtitle: Type, Version, Size
                string tag = BuildTag(plugin.Version);
                string sizeStr = plugin.BinarySizeBytes > 0 ? $"{plugin.BinarySizeBytes / 1024} KB" : "";
                string subText = $"{plugin.PluginType.ToUpperInvariant()} • {plugin.Version ?? "1.0.0"} {tag} {(sizeStr != "" ? "• " + sizeStr : "")}";
                EditorGUILayout.LabelField(subText, EditorStyles.miniLabel);
                EditorGUILayout.EndVertical();

                // 3. Status indicator
                if (failed)
                {
                    var prev = GUI.color;
                    GUI.color = ExoforgeUIStyle.AccentRed;
                    EditorGUILayout.LabelField(new GUIContent("✗ Build Failed", "Extension build failed. See Unity Console or Build Log for compiler errors."), EditorStyles.miniBoldLabel, GUILayout.Width(95));
                    GUI.color = prev;
                }
                else if (!plugin.IsBuilt)
                {
                    var prev = GUI.color;
                    GUI.color = ExoforgeUIStyle.AccentOrange;
                    EditorGUILayout.LabelField("○ Not built", EditorStyles.miniLabel, GUILayout.Width(80));
                    GUI.color = prev;
                }
                else if (plugin.Modified)
                {
                    var prev = GUI.color;
                    GUI.color = ExoforgeUIStyle.AccentOrange;
                    EditorGUILayout.LabelField("● Modified", EditorStyles.miniBoldLabel, GUILayout.Width(80));
                    GUI.color = prev;
                }
                else
                {
                    var prev = GUI.color;
                    GUI.color = ExoforgeUIStyle.AccentGreen;
                    EditorGUILayout.LabelField("✓ Ready", EditorStyles.miniBoldLabel, GUILayout.Width(80));
                    GUI.color = prev;
                }

                // Smart Lifecycle Action Button: Build (if modified/not built) or Deploy (if already built and not deployed)
                bool needsBuild = !plugin.IsBuilt || plugin.Modified || failed;
                bool needsDeploy = !needsBuild && notDeployed;

                if (needsBuild)
                {
                    if (_isConnected && !failed)
                    {
                        using (new EditorGUI.DisabledScope(_isBuilding || !plugin.CanBuild))
                        {
                            var origBg = GUI.backgroundColor;
                            GUI.backgroundColor = new Color(0.30f, 0.85f, 0.45f);
                            if (GUILayout.Button(new GUIContent("🚀 Build & Deploy", "Compile and immediately deploy this extension to the running cluster"), EditorStyles.miniButton, GUILayout.Width(110), GUILayout.Height(24)))
                            {
                                _ = BuildPluginAsync(plugin, thenDeploy: true);
                            }
                            GUI.backgroundColor = origBg;
                        }
                    }

                    string btnLabel = plugin.Modified ? "🔨 Build" : (failed ? "🔨 Retry" : "🔨 Build");
                    using (new EditorGUI.DisabledScope(_isBuilding || !plugin.CanBuild))
                    {
                        var origBg = GUI.backgroundColor;
                        GUI.backgroundColor = failed ? new Color(1.0f, 0.45f, 0.4f) : new Color(0.35f, 0.65f, 1.0f);
                        if (GUILayout.Button(new GUIContent(btnLabel, failed ? "Retry compiling this extension" : "Compile and build this extension's C# assembly"), EditorStyles.miniButton, GUILayout.Width(65), GUILayout.Height(24)))
                        {
                            _ = BuildPluginAsync(plugin, thenDeploy: false);
                        }
                        GUI.backgroundColor = origBg;
                    }
                }
                else if (needsDeploy)
                {
                    using (new EditorGUI.DisabledScope(_isBuilding || !_isConnected))
                    {
                        var origBg = GUI.backgroundColor;
                        GUI.backgroundColor = new Color(0.30f, 0.85f, 0.45f);
                        if (GUILayout.Button(new GUIContent("🚀 Deploy", "Deploy the built extension to the running cluster"), EditorStyles.miniButton, GUILayout.Width(75), GUILayout.Height(24)))
                        {
                            _ = DeployPluginAsync(plugin);
                        }
                        GUI.backgroundColor = origBg;
                    }
                }
                else
                {
                    using (new EditorGUI.DisabledScope(true))
                    {
                        string statusLabel = !_isConnected ? "Built (Offline)" : "✓ Deployed";
                        GUILayout.Button(new GUIContent(statusLabel, "Extension is built and up to date"), EditorStyles.miniButton, GUILayout.Width(85), GUILayout.Height(24));
                    }
                }

                // 4. Secondary actions: Inspect, Folder
                if (GUILayout.Button(new GUIContent("Inspect ↗", "Inspect and manage this extension in the Exoforge Extensions window"), EditorStyles.miniButton, GUILayout.Width(75), GUILayout.Height(24)))
                {
                    ExoforgeExtensionsWindow.OpenExtension(plugin.Name);
                }

                if (GUILayout.Button("📁 Folder", EditorStyles.miniButton, GUILayout.Width(65), GUILayout.Height(24)))
                {
                    EditorUtility.RevealInFinder(plugin.Directory);
                }

                EditorGUILayout.EndHorizontal();
                EditorGUILayout.Space(3);
                EditorGUILayout.EndVertical();
            }
        }
        EditorGUILayout.EndVertical();

        if (!string.IsNullOrEmpty(_buildLog))
        {
            EditorGUILayout.Space(6);
            _showBuildLog = EditorGUILayout.Foldout(_showBuildLog, "Build Log", true);
            if (_showBuildLog)
            {
                _buildLogScroll = EditorGUILayout.BeginScrollView(_buildLogScroll, GUILayout.Height(120));
                EditorGUILayout.TextArea(_buildLog, EditorStyles.textArea);
                EditorGUILayout.EndScrollView();
            }
        }

        EditorGUILayout.Space(10);
        _showRemotePlugins = EditorGUILayout.Foldout(_showRemotePlugins, $"Advanced: Cluster Remote Extensions ({_remotePlugins.Count})", true);
        if (_showRemotePlugins)
        {
            EditorGUI.indentLevel++;
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField($"Active Remote Extensions ({_remotePlugins.Count})", EditorStyles.boldLabel);
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
                EditorGUILayout.LabelField(_isConnected ? "No active remote extensions." : "Connect to view remote extensions.", EditorStyles.miniLabel);
            }
            else
            {
                foreach (var plugin in _remotePlugins)
                {
                    string id = plugin.TryGetProperty("id", out var idProp) && idProp.ValueKind == JsonValueKind.String ? idProp.GetString() ?? "?" : "?";
                    string version = plugin.TryGetProperty("version", out var vProp) && vProp.ValueKind == JsonValueKind.String ? vProp.GetString() ?? "" : "";
                    string icon = plugin.TryGetProperty("icon", out var icProp) && icProp.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(icProp.GetString())
                        ? icProp.GetString()!
                        : (plugin.TryGetProperty("dashboard_view", out var dv) && dv.ValueKind == JsonValueKind.Object && dv.TryGetProperty("icon", out var dvIcon) && dvIcon.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(dvIcon.GetString())
                            ? dvIcon.GetString()!
                            : "🧩");
                    string title = plugin.TryGetProperty("title", out var tProp) && tProp.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(tProp.GetString())
                        ? tProp.GetString()!
                        : (plugin.TryGetProperty("dashboard_view", out var dv2) && dv2.ValueKind == JsonValueKind.Object && dv2.TryGetProperty("title", out var dvTitle) && dvTitle.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(dvTitle.GetString())
                            ? dvTitle.GetString()!
                            : id);

                    var origRemBg = GUI.backgroundColor;
                    GUI.backgroundColor = ExoforgeUIStyle.ImguiCardBg;
                    EditorGUILayout.BeginVertical(GUI.skin.box);
                    GUI.backgroundColor = origRemBg;
                    EditorGUILayout.BeginHorizontal();

                    var remIconStyle = new GUIStyle(EditorStyles.label) { fontSize = 20, alignment = TextAnchor.MiddleCenter };
                    GUILayout.Label(icon, remIconStyle, GUILayout.Width(30), GUILayout.Height(30));

                    EditorGUILayout.BeginVertical();
                    EditorGUILayout.LabelField(title, EditorStyles.boldLabel);
                    string remSub = (title != id && !string.IsNullOrEmpty(title)) ? $"{id} • REMOTE • {version}" : $"REMOTE • {version}";
                    EditorGUILayout.LabelField(remSub, EditorStyles.miniLabel);
                    EditorGUILayout.EndVertical();

                    if (GUILayout.Button(
                            new GUIContent("Inspect ↗", "Inspect this extension in the Exoforge Extensions window"),
                            EditorStyles.miniButton, GUILayout.Width(75), GUILayout.Height(24)))
                    {
                        ExoforgeExtensionsWindow.OpenExtension(id);
                    }
                    using (new EditorGUI.DisabledScope(!_isConnected))
                    {
                        if (GUILayout.Button("Remove", EditorStyles.miniButton, GUILayout.Width(65), GUILayout.Height(24)))
                        {
                            bool confirmed = EditorUtility.DisplayDialog(
                                "Remove extension",
                                $"Remove '{id}' from the cluster?\n\nIts files stay on the server; the extension stops running.",
                                "Remove", "Cancel");

                            if (confirmed)
                            {
                                _ = RemovePluginAsync(id);
                            }
                        }
                    }
                    EditorGUILayout.EndHorizontal();
                    EditorGUILayout.EndVertical();
                }
            }
            EditorGUILayout.EndVertical();
            EditorGUI.indentLevel--;
        }

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
        int failCount = 0;
        foreach (var plugin in targets)
        {
            await BuildPluginAsync(plugin, thenDeploy: false);
            if (SessionState.GetString(BuildFailureKey(plugin.Name), "").Length > 0)
            {
                failCount++;
            }
        }

        if (failCount == 0)
        {
            ShowStatus($"✓ Built {targets.Count} plugin(s).", MessageType.Info);
        }
        else
        {
            ShowStatus($"Build completed: {targets.Count - failCount} succeeded, {failCount} failed — see Unity Console or Build Log.", MessageType.Error);
        }
    }

    private async Task BuildAndDeployAllAsync()
    {
        if (_isBuilding) return;
        if (!_isConnected)
        {
            ShowStatus("Cannot deploy: not connected to cluster.", MessageType.Warning);
            return;
        }

        var targets = _localPlugins.Where(p => p.CanBuild).ToList();
        if (targets.Count == 0)
        {
            ShowStatus("No buildable workspace extensions found.", MessageType.Warning);
            return;
        }

        ShowStatus($"Building all ({targets.Count}) workspace extension(s)…", MessageType.Info);
        foreach (var plugin in targets)
        {
            await BuildPluginAsync(plugin, thenDeploy: false);
        }

        await DeployAllAsync();
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
            string errorDetails = ex is InvalidOperationException ? ex.Message : ex.ToString();
            _buildLog = errorDetails;
            SessionState.SetString(BuildFailureKey(plugin.Name), errorDetails);
            _showBuildLog = true;

            UnityEngine.Debug.LogError($"[Exoforge] Build failed for extension '{plugin.Name}':\n{errorDetails}");
            ShowStatus($"Build failed for '{plugin.Name}' — see Unity Console or Build Log.", MessageType.Error);
            RefreshLocalPlugins();
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

    /// <summary>Jumps to the Plugins window Action Sandbox with one of this plugin's actions selected.</summary>
    private void OpenInSandbox(string pluginId)
    {
        ExoforgePluginsWindow.OpenSandbox(pluginId: pluginId);
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

    private void DrawPlugins() => DrawExtensions();
}
}
