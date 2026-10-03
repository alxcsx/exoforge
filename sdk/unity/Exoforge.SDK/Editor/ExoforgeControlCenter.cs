using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
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
/// Unity Editor Studio Window for managing Exoforge backend plugins,
/// scaffolding C# WASM projects, syncing client code generation, and monitoring cluster health.
/// </summary>
public class ExoforgeControlCenter : EditorWindow
{
    private enum Tab
    {
        Plugins = 0,
        CodeGeneration = 1,
        ClusterStatus = 2,
        Settings = 3
    }

    private Tab _currentTab = Tab.Plugins;
    private readonly string[] _tabNames = { "Plugins & WASM", "Code Generation", "Cluster Status", "Settings" };

    // Connection state
    private ExoClient? _editorClient;
    private bool _isConnected = false;
    private string _connectionStatus = "Disconnected";

    // Workspace & Plugins
    private string _newPluginName = "";
    private string _statusMessage = "";
    private MessageType _statusMessageType = MessageType.Info;
    private List<LocalPluginInfo> _localPlugins = new();
    private List<JsonElement> _remotePlugins = new();

    // Telemetry
    private string _nodeName = "—";
    private string _uptime = "—";
    private string _memoryMb = "—";
    private int _activeEntities = 0;
    private int _pluginsCount = 0;

    // Scroll positions
    private Vector2 _pluginsScroll;
    private Vector2 _remoteScroll;
    private Vector2 _telemetryScroll;

    public record LocalPluginInfo(string Name, string DirectoryPath, bool HasWasm, string WasmPath);

    [MenuItem("Window/Exoforge/Control Center", false, 2000)]
    public static void ShowWindow()
    {
        var window = GetWindow<ExoforgeControlCenter>("Exoforge Studio");
        window.minSize = new Vector2(560, 480);
        window.Show();
    }

    private void OnEnable()
    {
        RefreshLocalPlugins();
        _ = AutoConnectAsync();
    }

    private void OnDisable()
    {
        _editorClient?.Dispose();
        _editorClient = null;
        _isConnected = false;
    }

    private async Task AutoConnectAsync()
    {
        try
        {
            await ConnectAsync();
        }
        catch
        {
            // Silently allow manual connect
        }
    }

    private async Task ConnectAsync()
    {
        _connectionStatus = "Connecting...";
        Repaint();

        try
        {
            _editorClient?.Dispose();
            _editorClient = new ExoClient(ExoforgeEditorConfig.ServerUrl);
            await _editorClient.ConnectAsync();

            var authResult = await _editorClient.AuthenticateAsync(ExoforgeEditorConfig.AdminToken);
            if (authResult.Success)
            {
                _isConnected = true;
                _connectionStatus = $"Connected (Player: {authResult.PlayerId})";
                ShowStatus("Connected to Exoforge server successfully.", MessageType.Info);
                await RefreshRemoteInfoAsync();
            }
            else
            {
                _isConnected = false;
                _connectionStatus = $"Auth Failed: {authResult.Error}";
                ShowStatus($"Authentication rejected: {authResult.Error}", MessageType.Error);
            }
        }
        catch (Exception ex)
        {
            _isConnected = false;
            _connectionStatus = "Connection Failed";
            ShowStatus($"Connection failed: {ex.Message}", MessageType.Warning);
        }

        Repaint();
    }

    private async Task DisconnectAsync()
    {
        if (_editorClient != null)
        {
            await _editorClient.DisconnectAsync();
            _editorClient.Dispose();
            _editorClient = null;
        }

        _isConnected = false;
        _connectionStatus = "Disconnected";
        Repaint();
    }

    private async Task RefreshRemoteInfoAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        try
        {
            var pluginMgr = _editorClient.PluginManager();

            // Fetch plugins
            var listResp = await pluginMgr.ListPluginsAsync();
            if (listResp.Success && listResp.Data != null)
            {
                var doc = JsonDocument.Parse(listResp.Data.ToString() ?? "{}");
                if (doc.RootElement.TryGetProperty("plugins", out var pArray))
                {
                    _remotePlugins = pArray.EnumerateArray().ToList();
                }
            }

            // Fetch system telemetry
            var sysResp = await pluginMgr.GetSystemInfoAsync();
            if (sysResp.Success && sysResp.Data != null)
            {
                var doc = JsonDocument.Parse(sysResp.Data.ToString() ?? "{}");
                if (doc.RootElement.TryGetProperty("system", out var sys))
                {
                    _nodeName = sys.TryGetProperty("node", out var n) ? n.GetString() ?? "—" : "—";
                    _memoryMb = sys.TryGetProperty("memory_mb", out var m) ? m.GetRawText() + " MB" : "—";
                    _activeEntities = sys.TryGetProperty("active_entities_count", out var a) ? a.GetInt32() : 0;
                    _pluginsCount = sys.TryGetProperty("plugins_count", out var pc) ? pc.GetInt32() : 0;

                    if (sys.TryGetProperty("uptime_seconds", out var u))
                    {
                        int secs = u.GetInt32();
                        _uptime = secs < 60 ? $"{secs}s" : $"{secs / 60}m {secs % 60}s";
                    }
                }
            }
        }
        catch (Exception ex)
        {
            ShowStatus($"Failed to refresh remote cluster telemetry: {ex.Message}", MessageType.Warning);
        }

        Repaint();
    }

    private void RefreshLocalPlugins()
    {
        _localPlugins.Clear();
        string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
        string pluginsDir = Path.Combine(wsPath, "plugins");

        if (!Directory.Exists(pluginsDir))
        {
            pluginsDir = Path.Combine(wsPath, "plugins_csharp");
        }

        if (Directory.Exists(pluginsDir))
        {
            foreach (var dir in Directory.GetDirectories(pluginsDir))
            {
                string name = Path.GetFileName(dir);
                string wasmPath = Path.Combine(dir, $"{name}.wasm");
                bool hasWasm = File.Exists(wasmPath);

                if (!hasWasm)
                {
                    var wasmFiles = Directory.GetFiles(dir, "*.wasm");
                    if (wasmFiles.Length > 0)
                    {
                        hasWasm = true;
                        wasmPath = wasmFiles[0];
                    }
                }

                _localPlugins.Add(new LocalPluginInfo(name, dir, hasWasm, wasmPath));
            }
        }
    }

    private void ShowStatus(string message, MessageType type)
    {
        _statusMessage = message;
        _statusMessageType = type;
    }

    private void OnGUI()
    {
        DrawHeader();

        EditorGUILayout.Space(4);
        _currentTab = (Tab)GUILayout.Toolbar((int)_currentTab, _tabNames, GUILayout.Height(28));
        EditorGUILayout.Space(6);

        if (!string.IsNullOrEmpty(_statusMessage))
        {
            EditorGUILayout.HelpBox(_statusMessage, _statusMessageType);
            EditorGUILayout.Space(4);
        }

        switch (_currentTab)
        {
            case Tab.Plugins:
                DrawPluginsTab();
                break;
            case Tab.CodeGeneration:
                DrawCodeGenerationTab();
                break;
            case Tab.ClusterStatus:
                DrawClusterStatusTab();
                break;
            case Tab.Settings:
                DrawSettingsTab();
                break;
        }
    }

    private void DrawHeader()
    {
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.BeginHorizontal();

        GUIStyle titleStyle = new GUIStyle(EditorStyles.boldLabel)
        {
            fontSize = 14,
            normal = { textColor = new Color(0.55f, 0.35f, 0.95f) }
        };

        GUILayout.Label("⚡ EXOFORGE GAME STUDIO", titleStyle);
        GUILayout.FlexibleSpace();

        // Status indicator dot
        GUIStyle statusBadge = new GUIStyle(EditorStyles.miniLabel)
        {
            fontStyle = FontStyle.Bold,
            normal = { textColor = _isConnected ? new Color(0.2f, 0.8f, 0.3f) : new Color(0.8f, 0.3f, 0.2f) }
        };

        GUILayout.Label(_isConnected ? "● CONNECTED" : "○ DISCONNECTED", statusBadge);

        if (_isConnected)
        {
            if (GUILayout.Button("Disconnect", EditorStyles.miniButton, GUILayout.Width(75)))
            {
                _ = DisconnectAsync();
            }
        }
        else
        {
            if (GUILayout.Button("Connect", EditorStyles.miniButton, GUILayout.Width(75)))
            {
                _ = ConnectAsync();
            }
        }

        EditorGUILayout.EndHorizontal();

        EditorGUILayout.LabelField($"Cluster: {ExoforgeEditorConfig.ServerUrl}  |  {_connectionStatus}", EditorStyles.miniLabel);
        EditorGUILayout.EndVertical();
    }

    private void DrawPluginsTab()
    {
        string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
        bool wsExists = ExoWorkspace.Exists(wsPath);

        // Workspace banner
        if (!wsExists)
        {
            EditorGUILayout.HelpBox($"Exoforge workspace not detected at '{wsPath}'. Initialize it to scaffold C# WASM plugins.", MessageType.Warning);
            if (GUILayout.Button("Initialize /exoforge Workspace", GUILayout.Height(26)))
            {
                ExoWorkspace.Initialize(wsPath);
                RefreshLocalPlugins();
                ShowStatus($"Initialized workspace at '{wsPath}'", MessageType.Info);
            }
            EditorGUILayout.Space(8);
        }

        // Scaffold New Plugin Box
        EditorGUILayout.LabelField("Create New C# WASM Plugin", EditorStyles.boldLabel);
        EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
        _newPluginName = EditorGUILayout.TextField(_newPluginName, GUILayout.Height(22));

        if (GUILayout.Button("+ Scaffold Plugin Boilerplate", GUILayout.Width(190), GUILayout.Height(22)))
        {
            if (string.IsNullOrWhiteSpace(_newPluginName))
            {
                ShowStatus("Please enter a valid plugin name.", MessageType.Error);
            }
            else
            {
                try
                {
                    string pluginDir = ExoScaffolder.ScaffoldPlugin(wsPath, _newPluginName.Trim());
                    RefreshLocalPlugins();
                    ShowStatus($"Scaffolded plugin '{_newPluginName}' at '{pluginDir}'", MessageType.Info);
                    _newPluginName = "";
                }
                catch (Exception ex)
                {
                    ShowStatus($"Scaffolding failed: {ex.Message}", MessageType.Error);
                }
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(8);

        // Local Plugins List
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Local Custom Plugins ({_localPlugins.Count})", EditorStyles.boldLabel);
        if (GUILayout.Button("Refresh Local", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            RefreshLocalPlugins();
        }
        EditorGUILayout.EndHorizontal();

        _pluginsScroll = EditorGUILayout.BeginScrollView(_pluginsScroll, GUILayout.Height(150));
        if (_localPlugins.Count == 0)
        {
            EditorGUILayout.HelpBox("No plugins found in workspace plugins/ folder. Create one above!", MessageType.None);
        }
        else
        {
            foreach (var plugin in _localPlugins)
            {
                EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
                GUILayout.Label("📦", GUILayout.Width(20));
                EditorGUILayout.LabelField(plugin.Name, EditorStyles.boldLabel, GUILayout.Width(140));

                if (plugin.HasWasm)
                {
                    GUIStyle wasmStyle = new GUIStyle(EditorStyles.miniLabel)
                    {
                        normal = { textColor = new Color(0.2f, 0.7f, 0.3f) }
                    };
                    GUILayout.Label("WASM Ready", wasmStyle, GUILayout.Width(80));
                }
                else
                {
                    GUILayout.Label("Not Compiled", EditorStyles.miniLabel, GUILayout.Width(80));
                }

                GUILayout.FlexibleSpace();

                if (GUILayout.Button("Deploy to Server", EditorStyles.miniButton, GUILayout.Width(110)))
                {
                    _ = DeployLocalPluginAsync(plugin);
                }

                if (GUILayout.Button("Open Folder", EditorStyles.miniButton, GUILayout.Width(80)))
                {
                    EditorUtility.RevealInFinder(plugin.DirectoryPath);
                }

                EditorGUILayout.EndHorizontal();
            }
        }
        EditorGUILayout.EndScrollView();

        EditorGUILayout.Space(8);

        // Remote Plugins List
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Installed On Remote Server ({_remotePlugins.Count})", EditorStyles.boldLabel);
        if (GUILayout.Button("Refresh Server", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            _ = RefreshRemoteInfoAsync();
        }
        EditorGUILayout.EndHorizontal();

        _remoteScroll = EditorGUILayout.BeginScrollView(_remoteScroll, GUILayout.Height(120));
        if (!_isConnected)
        {
            EditorGUILayout.HelpBox("Connect to Exoforge server to view remote installed plugins.", MessageType.None);
        }
        else if (_remotePlugins.Count == 0)
        {
            EditorGUILayout.HelpBox("No plugins reported by remote server.", MessageType.None);
        }
        else
        {
            foreach (var rp in _remotePlugins)
            {
                string id = rp.TryGetProperty("id", out var i) ? i.GetString() ?? "" : "";
                string type = rp.TryGetProperty("type", out var t) ? t.GetString() ?? "" : "";
                string ver = rp.TryGetProperty("version", out var v) ? v.GetString() ?? "" : "";

                EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
                GUILayout.Label(type.Contains("wasm") ? "⚡" : "💎", GUILayout.Width(20));
                EditorGUILayout.LabelField(id, EditorStyles.boldLabel, GUILayout.Width(180));
                EditorGUILayout.LabelField($"v{ver}", EditorStyles.miniLabel, GUILayout.Width(50));
                EditorGUILayout.LabelField($"[{type}]", EditorStyles.miniLabel, GUILayout.Width(70));
                GUILayout.FlexibleSpace();

                if (type.Contains("wasm"))
                {
                    if (GUILayout.Button("Remove", EditorStyles.miniButton, GUILayout.Width(60)))
                    {
                        _ = RemoveRemotePluginAsync(id);
                    }
                }
                EditorGUILayout.EndHorizontal();
            }
        }
        EditorGUILayout.EndScrollView();
    }

    private async Task DeployLocalPluginAsync(LocalPluginInfo plugin)
    {
        if (_editorClient == null || !_isConnected)
        {
            ShowStatus("Please connect to Exoforge server first.", MessageType.Error);
            return;
        }

        if (!plugin.HasWasm)
        {
            ShowStatus($"Plugin '{plugin.Name}' has not been compiled to .wasm yet.", MessageType.Warning);
            return;
        }

        try
        {
            byte[] wasmBytes = await File.ReadAllBytesAsync(plugin.WasmPath);
            var deployer = new ExoDeployer(_editorClient);

            bool success = await deployer.DeployWasmPluginAsync(plugin.Name, wasmBytes);
            if (success)
            {
                ShowStatus($"Successfully pushed and hot-loaded '{plugin.Name}' into cluster!", MessageType.Info);
                await RefreshRemoteInfoAsync();
            }
            else
            {
                ShowStatus($"Failed to push plugin '{plugin.Name}' to cluster.", MessageType.Error);
            }
        }
        catch (Exception ex)
        {
            ShowStatus($"Deployment failed: {ex.Message}", MessageType.Error);
        }
    }

    private async Task RemoveRemotePluginAsync(string pluginId)
    {
        if (_editorClient == null || !_isConnected) return;

        if (EditorUtility.DisplayDialog("Confirm Remove", $"Unload plugin '{pluginId}' from remote runtime?", "Yes, Remove", "Cancel"))
        {
            try
            {
                var resp = await _editorClient.PluginManager().RemovePluginAsync(pluginId);
                if (resp.Success)
                {
                    ShowStatus($"Plugin '{pluginId}' removed from server runtime.", MessageType.Info);
                    await RefreshRemoteInfoAsync();
                }
                else
                {
                    ShowStatus($"Failed to remove plugin: {resp.Error}", MessageType.Error);
                }
            }
            catch (Exception ex)
            {
                ShowStatus($"Error removing plugin: {ex.Message}", MessageType.Error);
            }
        }
    }

    private void DrawCodeGenerationTab()
    {
        EditorGUILayout.LabelField("Strongly-Typed Client Code Generation", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Fetch live service contracts and action schemas from the running cluster, and generate strongly-typed C# client classes without needing Elixir or Mix installed.", MessageType.Info);

        EditorGUILayout.Space(6);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField("Target Output Script Path (relative to project):", EditorStyles.miniBoldLabel);
        ExoforgeEditorConfig.GeneratedScriptPath = EditorGUILayout.TextField(ExoforgeEditorConfig.GeneratedScriptPath);
        EditorGUILayout.LabelField($"Resolved: {ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath()}", EditorStyles.miniLabel);
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        GUI.enabled = _isConnected;
        if (GUILayout.Button("⚡ Sync Contracts & Generate C# Client API", GUILayout.Height(36)))
        {
            _ = SyncAndGenerateClientAsync();
        }
        GUI.enabled = true;

        if (!_isConnected)
        {
            EditorGUILayout.HelpBox("Connect to Exoforge cluster to fetch live contracts.", MessageType.Warning);
        }
    }

    private async Task SyncAndGenerateClientAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        try
        {
            ShowStatus("Fetching cluster contract schemas...", MessageType.Info);
            var deployer = new ExoDeployer(_editorClient);

            string? exportJson = await deployer.SyncContractsAsync();
            if (string.IsNullOrEmpty(exportJson))
            {
                ShowStatus("Received empty contract export from server.", MessageType.Error);
                return;
            }

            string outPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
            string code = ExoCodeGenerator.GenerateCode(exportJson, "Exoforge.Client");

            string? dir = Path.GetDirectoryName(outPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            await File.WriteAllTextAsync(outPath, code);

            AssetDatabase.Refresh();
            ShowStatus($"Successfully generated typed client API at '{ExoforgeEditorConfig.GeneratedScriptPath}'!", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Code generation failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private void DrawClusterStatusTab()
    {
        EditorGUILayout.LabelField("BEAM Cluster Runtime & Health", EditorStyles.boldLabel);

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField($"Cluster Node: {_nodeName}");
        EditorGUILayout.LabelField($"Uptime: {_uptime}");
        EditorGUILayout.LabelField($"BEAM Memory: {_memoryMb}");
        EditorGUILayout.LabelField($"Active Virtual Entities: {_activeEntities}");
        EditorGUILayout.LabelField($"Total Plugins Loaded: {_pluginsCount}");
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("Refresh Telemetry", GUILayout.Height(28)))
        {
            _ = RefreshRemoteInfoAsync();
        }

        GUI.enabled = _isConnected;
        if (GUILayout.Button("Restart Server Runtime", GUILayout.Height(28)))
        {
            if (EditorUtility.DisplayDialog("Restart Cluster", "Hot-reload all plugin supervision trees on remote server?", "Restart", "Cancel"))
            {
                _ = RestartClusterAsync();
            }
        }
        GUI.enabled = true;
        EditorGUILayout.EndHorizontal();
    }

    private async Task RestartClusterAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        try
        {
            var resp = await _editorClient.PluginManager().RestartSystemAsync();
            if (resp.Success)
            {
                ShowStatus("Backend cluster runtime supervision restarted successfully.", MessageType.Info);
                await RefreshRemoteInfoAsync();
            }
            else
            {
                ShowStatus($"Restart failed: {resp.Error}", MessageType.Error);
            }
        }
        catch (Exception ex)
        {
            ShowStatus($"Error restarting cluster: {ex.Message}", MessageType.Error);
        }
    }

    private void DrawSettingsTab()
    {
        EditorGUILayout.LabelField("Studio Preferences", EditorStyles.boldLabel);

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField("WebSocket Server URL:");
        ExoforgeEditorConfig.ServerUrl = EditorGUILayout.TextField(ExoforgeEditorConfig.ServerUrl);

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("Admin Bearer Token / Scope:");
        ExoforgeEditorConfig.AdminToken = EditorGUILayout.TextField(ExoforgeEditorConfig.AdminToken);

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("Workspace Folder Path:");
        ExoforgeEditorConfig.WorkspacePath = EditorGUILayout.TextField(ExoforgeEditorConfig.WorkspacePath);
        EditorGUILayout.LabelField($"Resolved: {ExoforgeEditorConfig.GetAbsoluteWorkspacePath()}", EditorStyles.miniLabel);

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("Generated Client Script Path:");
        ExoforgeEditorConfig.GeneratedScriptPath = EditorGUILayout.TextField(ExoforgeEditorConfig.GeneratedScriptPath);
        EditorGUILayout.LabelField($"Resolved: {ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath()}", EditorStyles.miniLabel);
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);
        if (GUILayout.Button("Reconnect with New Settings", GUILayout.Height(28)))
        {
            _ = ConnectAsync();
        }
    }
}
#endif
