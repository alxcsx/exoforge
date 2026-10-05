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

/// <summary>
/// Unity Editor Exoforge Studio — cluster management, authentication, live events, action sandbox,
/// plugin scaffolding/build/deploy/stubs, and client/runtime-config generation.
/// </summary>
public class ExoforgeControlCenter : EditorWindow
{
    private enum Tab { Overview, LiveEvents, ActionSandbox, Plugins, Settings }

    // Per-editor-session flag: auto-connect on editor start, but not on every script reload.
    private const string AutoConnectSessionKey = "Exoforge_AutoConnected";

    private static readonly string[] TabNames =
    {
        "Overview", "Live Events", "Action Sandbox", "Plugins", "Settings"
    };

    // Connection & Client
    private ExoClient? _editorClient;
    private ExoWorkspace _workspace = null!;
    private bool _isConnected;
    private bool _isConnecting;
    private string _connectionStatus = "Disconnected";

    // Authentication foldout
    private bool _showAuthFoldout = false;
    private string _loginEmail = ExoforgeEditorConfig.DefaultLoginEmail;
    private string _loginPassword = "";

    // Status Banner
    private string _statusMessage = "";
    private MessageType _statusMessageType = MessageType.Info;

    // Cluster Telemetry
    private string _nodeName = "—";
    private string _uptime = "—";
    private string _memoryMb = "—";
    private int _activeEntities;
    private int _pluginsCount;

    /// <summary>One action from the live contract export, with the params needed to build a payload.</summary>
    private sealed record ActionSpec(string Name, Dictionary<string, JsonElement> Params);

    /// <summary>
    /// Discovered services and actions, filled from the live export. Deliberately starts empty:
    /// a seeded list drifts out of date and the Sandbox then opens on an action that 404s.
    /// </summary>
    private readonly Dictionary<string, List<ActionSpec>> _serviceCatalog = new();

    /// <summary>Plugin id → the service names it provides, for the per-plugin "Test" shortcut.</summary>
    private readonly Dictionary<string, List<string>> _pluginServices = new();
    private int _selectedServiceIndex = 0;
    private int _selectedActionIndex = 0;

    // Live Events
    private sealed record LoggedEvent(DateTime At, string Topic, string EventName, string RawJson);
    private readonly List<LoggedEvent> _eventLog = new();
    private bool _eventPaused;
    private bool _eventAutoScroll = true;
    private string _eventFilter = "";
    private Vector2 _eventScroll;
    private LoggedEvent? _selectedEvent;
    private Vector2 _eventDetailScroll;

    // Action Sandbox
    private string _sandboxService = "";
    private string _sandboxAction = "";
    private string _sandboxPayload = "{}";
    private string _sandboxResult = "";
    private string _sandboxLatency = "";
    private bool _sandboxSuccess = true;
    private Vector2 _sandboxResultScroll;

    // Plugins
    private string _newPluginName = "";
    private int _newPluginTemplateIndex;
    private string _pluginLogs = "";
    private string _pluginLogsFor = "";
    private bool _showPluginLogs;
    private Vector2 _pluginLogsScroll;
    private bool _showScaffoldPrompt = false;
    private List<LocalPluginInfo> _localPlugins = new();
    private List<JsonElement> _remotePlugins = new();
    private Vector2 _pluginsScroll;
    private string _buildRid = "";
    private bool _isBuilding;
    private string _buildLog = "";
    private bool _showBuildLog;
    private Vector2 _buildLogScroll;

    private Tab _currentTab = Tab.Overview;
    private Vector2 _mainScroll;

    private sealed record LocalPluginInfo(
        string Name,
        string Directory,
        string PluginType,
        bool IsBuilt,
        bool CanBuild,
        string BinaryPath,
        long BinarySizeBytes,
        bool Modified,
        string? Version);

    [MenuItem("Tools/Exoforge/Exoforge Studio", false, 100)]
    [MenuItem("Window/Exoforge/Exoforge Studio", false, 2000)]
    public static void ShowWindow()
    {
        var window = GetWindow<ExoforgeControlCenter>("Exoforge Studio");
        window.minSize = new Vector2(480, 560);
    }

    private void OnEnable()
    {
        // Migrate legacy token ("admin" -> "dev:developer")
        if (ExoforgeEditorConfig.AdminToken == "admin")
        {
            ExoforgeEditorConfig.AdminToken = "dev:developer";
        }

        // Bi-directional sync between EditorPrefs and PlayerPrefs
        if (!string.IsNullOrEmpty(ExoforgeEditorConfig.AdminToken))
        {
            ExoTokenStore.Token = ExoforgeEditorConfig.AdminToken;
        }
        else if (ExoTokenStore.HasToken)
        {
            ExoforgeEditorConfig.AdminToken = ExoTokenStore.Token;
        }
        else
        {
            ExoforgeEditorConfig.AdminToken = ExoforgeEditorConfig.DefaultAdminToken;
            ExoTokenStore.Token = ExoforgeEditorConfig.DefaultAdminToken;
        }

        if (ExoforgeEditorConfig.WorkspacePath == "exoforge")
        {
            ExoforgeEditorConfig.WorkspacePath = ExoforgeEditorConfig.DefaultWorkspaceRelPath;
        }

        // Restore the last login so the auth form doesn't reset on every editor start.
        _loginEmail = ExoforgeEditorConfig.LastLoginEmail;
        _loginPassword = ExoforgeEditorConfig.RememberedPassword;

        _workspace = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
        RefreshLocalPlugins();

        EditorApplication.update += OnEditorUpdate;

        // Reconnect when the editor opens. `SessionState` survives script reloads, so the guard stops
        // reconnect spam; it is cleared when Unity exits, so this still runs on every editor start.
        if (!SessionState.GetBool(AutoConnectSessionKey, false))
        {
            SessionState.SetBool(AutoConnectSessionKey, true);
            // Defer: OnEnable can run before the editor/network stack is ready.
            EditorApplication.delayCall += TryAutoConnect;
        }
    }

    private void TryAutoConnect()
    {
        bool hasSession = !string.IsNullOrEmpty(ExoforgeEditorConfig.PlayerId)
            || (!string.IsNullOrEmpty(ExoforgeEditorConfig.AdminToken)
                && ExoforgeEditorConfig.AdminToken != ExoforgeEditorConfig.DefaultAdminToken);
        bool hasSavedLogin = !string.IsNullOrEmpty(ExoforgeEditorConfig.RememberedPassword);

        // Saved email/password but no session yet: sign in. Otherwise reconnect with the token.
        if (!hasSession && hasSavedLogin)
        {
            ShowStatus("Signing in with saved credentials…", MessageType.Info);
            _ = LogInAsync();
            return;
        }

        if (string.IsNullOrWhiteSpace(ExoTokenStore.Token))
        {
            _showAuthFoldout = true;
            ShowStatus("No saved credentials — sign in below, or set a bearer token in Settings.", MessageType.Warning);
            return;
        }

        ShowStatus("Connecting to the cluster…", MessageType.Info);
        _ = ConnectAsync();
    }

    private void OnDisable()
    {
        EditorApplication.update -= OnEditorUpdate;
        _ = DisconnectAsync();
    }

    // Keeps the window repainting while a build runs, so the streamed build log updates live.
    private void OnEditorUpdate()
    {
        if (_isBuilding) Repaint();
    }

    private void AppendBuildLog(string line)
    {
        _buildLog += line + "\n";
    }

    private void OnGUI()
    {
        DrawHeader();
        EditorGUILayout.Space(2);

        _currentTab = (Tab)GUILayout.Toolbar((int)_currentTab, TabNames, GUILayout.Height(24));
        EditorGUILayout.Space(4);

        if (!string.IsNullOrEmpty(_statusMessage))
        {
            DrawStatusBanner();
        }

        switch (_currentTab)
        {
            case Tab.Overview: DrawOverview(); break;
            case Tab.LiveEvents: DrawLiveEvents(); break;
            case Tab.ActionSandbox: DrawSandbox(); break;
            case Tab.Plugins: DrawPlugins(); break;
            case Tab.Settings: DrawSettings(); break;
        }
    }

    // =========================================================================
    // Header & Authentication
    // =========================================================================

    private void DrawHeader()
    {
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        // Top Row: Title, Scaffold Shortcut, Status Badge, Connect/Disconnect
        EditorGUILayout.BeginHorizontal();
        GUILayout.Label("⚡ Exoforge Studio", EditorStyles.boldLabel);

        // Shortcut to Scaffold a new C# Plugin
        if (GUILayout.Button("+ New C# Plugin", EditorStyles.miniButton, GUILayout.Width(115)))
        {
            _showScaffoldPrompt = !_showScaffoldPrompt;
        }

        GUILayout.FlexibleSpace();

        // Status Badge Pill
        var prevColor = GUI.color;
        if (_isConnecting)
        {
            GUI.color = new Color(1.0f, 0.85f, 0.3f);
            GUILayout.Label("◌ CONNECTING", EditorStyles.miniBoldLabel);
        }
        else if (_isConnected)
        {
            GUI.color = new Color(0.3f, 0.9f, 0.4f);
            GUILayout.Label($"● ONLINE ({_connectionStatus})", EditorStyles.miniBoldLabel);
        }
        else
        {
            GUI.color = new Color(0.6f, 0.6f, 0.6f);
            GUILayout.Label("○ OFFLINE", EditorStyles.miniBoldLabel);
        }
        GUI.color = prevColor;

        if (_isConnected)
        {
            if (GUILayout.Button("Disconnect", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                _ = DisconnectAsync();
            }
        }
        else
        {
            using (new EditorGUI.DisabledScope(_isConnecting))
            {
                if (GUILayout.Button("Connect", EditorStyles.miniButton, GUILayout.Width(80)))
                {
                    _ = ConnectAsync();
                }
            }
        }

        EditorGUILayout.EndHorizontal();

        // Inline Scaffold Bar (when triggered by header shortcut)
        if (_showScaffoldPrompt)
        {
            EditorGUILayout.Space(3);
            EditorGUILayout.BeginVertical(GUI.skin.box);
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("Plugin Name:", GUILayout.Width(80));
            _newPluginName = EditorGUILayout.TextField(_newPluginName);
            using (new EditorGUI.DisabledScope(string.IsNullOrWhiteSpace(_newPluginName)))
            {
                if (GUILayout.Button("Scaffold", EditorStyles.miniButton, GUILayout.Width(70)))
                {
                    ScaffoldNewPlugin();
                }
            }
            if (GUILayout.Button("✕", EditorStyles.miniButton, GUILayout.Width(25)))
            {
                _showScaffoldPrompt = false;
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.EndVertical();
        }

        EditorGUILayout.Space(2);

        // Second Row: Environment Selector & Ping
        DrawEnvironmentSelector();

        // Collapsible Account / Login Section
        _showAuthFoldout = EditorGUILayout.Foldout(_showAuthFoldout, "Account & Session Management", true);
        if (_showAuthFoldout)
        {
            EditorGUILayout.BeginVertical(GUI.skin.box);

            if (!string.IsNullOrEmpty(ExoforgeEditorConfig.PlayerId))
            {
                EditorGUILayout.BeginHorizontal();
                string sessionLabel = _isConnected
                    ? $"Signed in as: {ExoforgeEditorConfig.PlayerId}"
                    : $"Stored session: {ExoforgeEditorConfig.PlayerId} (disconnected)";
                EditorGUILayout.LabelField(sessionLabel, EditorStyles.boldLabel);
                if (!string.IsNullOrEmpty(ExoforgeEditorConfig.Scopes))
                {
                    EditorGUILayout.LabelField($"Scopes: [{ExoforgeEditorConfig.Scopes}]", EditorStyles.miniLabel);
                }
                EditorGUILayout.EndHorizontal();
            }

            string typedEmail = EditorGUILayout.TextField("Email", _loginEmail);
            if (typedEmail != _loginEmail)
            {
                _loginEmail = typedEmail;
                ExoforgeEditorConfig.LastLoginEmail = typedEmail;
            }

            string typedPassword = EditorGUILayout.PasswordField("Password", _loginPassword);
            if (typedPassword != _loginPassword)
            {
                _loginPassword = typedPassword;
                ExoforgeEditorConfig.RememberedPassword = typedPassword;
            }

            EditorGUILayout.LabelField(
                "Saved in per-user EditorPrefs — never committed to the project.",
                EditorStyles.miniLabel);

            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button("Sign In (auth.login)", GUILayout.Height(22)))
            {
                _ = LogInAsync();
            }

            if (GUILayout.Button("Log Out & Clear Credentials", GUILayout.Height(22)))
            {
                _ = LogOutAsync();
            }
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.EndVertical();
        }

        EditorGUILayout.EndVertical();
    }

    private void ScaffoldNewPlugin()
    {
        if (string.IsNullOrWhiteSpace(_newPluginName)) return;

        try
        {
            string template = ExoScaffolder.Templates[Mathf.Clamp(_newPluginTemplateIndex, 0, ExoScaffolder.Templates.Length - 1)];
            string dir = ExoScaffolder.ScaffoldPlugin(_workspace.PluginsPath, _newPluginName, template: template);
            string pluginFile = Path.Combine(dir, "src", ExoScaffolder.ClassNameFor(_newPluginName) + "Plugin.cs");

            RefreshLocalPlugins();
            ShowStatus($"✓ Scaffolded '{ExoScaffolder.NormalizePluginName(_newPluginName)}' — edit {pluginFile}, then Build & Deploy.", MessageType.Info);

            // Land the developer on the file they need to edit rather than just telling them it exists.
            if (File.Exists(pluginFile))
            {
                var asset = UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(
                    "Assets" + pluginFile.Replace(Application.dataPath, ""));

                if (asset != null) UnityEditor.AssetDatabase.OpenAsset(asset);
            }

            _newPluginName = "";
            _showScaffoldPrompt = false;
            _currentTab = Tab.Plugins;
        }
        catch (Exception ex)
        {
            ShowStatus($"Scaffold failed: {ex.Message}", MessageType.Error);
        }
    }

    private sealed record EnvOption(string Name, string WsUrl, string Token, string? HttpUrl = null);

    private void DrawEnvironmentSelector()
    {
        var envList = GetConfiguredEnvironments();
        var names = envList.Select(e => e.Name).ToArray();

        int currentIndex = envList.FindIndex(e =>
            string.Equals(e.WsUrl, ExoforgeEditorConfig.ServerUrl, StringComparison.OrdinalIgnoreCase) ||
            (e.Name == "local" && ExoforgeEditorConfig.IsLocalUrl(ExoforgeEditorConfig.ServerUrl)));

        if (currentIndex < 0)
        {
            var listWithCustom = names.ToList();
            listWithCustom.Add($"(custom) {ExoforgeEditorConfig.ServerUrl}");
            names = listWithCustom.ToArray();
            currentIndex = names.Length - 1;
        }

        EditorGUILayout.BeginHorizontal();
        int selected = EditorGUILayout.Popup("Environment", currentIndex, names);
        if (selected != currentIndex && selected < envList.Count)
        {
            ApplyEnvironment(envList[selected]);
        }

        if (GUILayout.Button("Ping", EditorStyles.miniButton, GUILayout.Width(50)))
        {
            _ = PingClusterAsync();
        }

        if (GUILayout.Button("Settings ⚙", EditorStyles.miniButton, GUILayout.Width(75)))
        {
            _currentTab = Tab.Settings;
        }
        EditorGUILayout.EndHorizontal();
    }

    private List<EnvOption> GetConfiguredEnvironments()
    {
        var list = new List<EnvOption>();

        if (_workspace?.Config?.Environments != null && _workspace.Config.Environments.Count > 0)
        {
            foreach (var kvp in _workspace.Config.Environments)
            {
                list.Add(new EnvOption(kvp.Key, kvp.Value.WsUrl, kvp.Value.Token, kvp.Value.HttpUrl));
            }
        }

        if (!list.Any(e => e.Name == "local"))
        {
            list.Insert(0, new EnvOption("local", "ws://127.0.0.1:4000/ws", "dev:developer", "http://127.0.0.1:4001"));
        }

        if (!list.Any(e => e.Name == "dev"))
            list.Add(new EnvOption("dev", "wss://dev.exoforge.game/ws", ""));
        if (!list.Any(e => e.Name == "staging"))
            list.Add(new EnvOption("staging", "wss://staging.exoforge.game/ws", ""));
        if (!list.Any(e => e.Name == "production"))
            list.Add(new EnvOption("production", "wss://api.exoforge.game/ws", ""));

        return list;
    }

    private void ApplyEnvironment(EnvOption env)
    {
        ExoforgeEditorConfig.ServerUrl = env.WsUrl;
        if (!string.IsNullOrEmpty(env.Token))
        {
            ExoforgeEditorConfig.AdminToken = env.Token;
            ExoTokenStore.Token = env.Token;
        }
        ShowStatus($"Switched to environment '{env.Name}' ({env.WsUrl}).", MessageType.Info);
        if (_isConnected)
        {
            _ = ConnectAsync();
        }
    }

    private void DrawStatusBanner()
    {
        EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
        EditorGUILayout.HelpBox(_statusMessage, _statusMessageType);
        if (GUILayout.Button("✕", EditorStyles.miniButton, GUILayout.Width(22), GUILayout.Height(22)))
        {
            _statusMessage = "";
        }
        EditorGUILayout.EndHorizontal();
    }

    // =========================================================================
    // Connection & Auth Logic
    // =========================================================================

    private async Task PingClusterAsync()
    {
        try
        {
            var sw = Stopwatch.StartNew();
            using var testClient = new ExoClient();
            await testClient.ConnectAsync(new Uri(ExoforgeEditorConfig.ServerUrl));
            sw.Stop();
            ShowStatus($"Server reachable at {ExoforgeEditorConfig.ServerUrl} in {sw.ElapsedMilliseconds} ms.", MessageType.Info);
            await testClient.DisconnectAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Ping failed to {ExoforgeEditorConfig.ServerUrl}: {ex.Message}", MessageType.Error);
        }
        Repaint();
    }

    private async Task ConnectAsync()
    {
        _isConnecting = true;
        _connectionStatus = "Connecting...";
        Repaint();

        if (string.IsNullOrWhiteSpace(ExoTokenStore.Token))
        {
            _isConnected = false;
            _isConnecting = false;
            _connectionStatus = "No token";
            ShowStatus("A bearer token is required. Enter one above (e.g. 'dev:developer').", MessageType.Error);
            Repaint();
            return;
        }

        try
        {
            _editorClient?.Dispose();
            _editorClient = new ExoClient();
            _editorClient.OnAnyEvent += HandleIncomingEvent;

            await _editorClient.ConnectAsync(new Uri(ExoforgeEditorConfig.ServerUrl));

            var auth = await _editorClient.AuthenticateAsync(ExoTokenStore.Token);
            if (auth.IsSuccess)
            {
                _isConnected = true;
                _connectionStatus = auth.PlayerId ?? "authenticated";
                ExoforgeEditorConfig.SaveSession(ExoTokenStore.Token, auth.PlayerId, auth.Scopes);
                ExoTokenStore.SaveSession(ExoTokenStore.Token, auth.PlayerId, auth.Scopes);

                ShowStatus($"Connected as {auth.PlayerId} to {ExoforgeEditorConfig.ServerUrl}.", MessageType.Info);

                await _editorClient.SubscribeAsync("*");
                await RefreshRemoteInfoAsync();
            }
            else
            {
                _isConnected = false;
                _connectionStatus = "Auth failed";
                ShowStatus($"Authentication failed: {auth.Error}", MessageType.Error);
            }
        }
        catch (ExoActionException ex)
        {
            _isConnected = false;
            _connectionStatus = "Auth rejected";
            ShowStatus(
                $"Auth rejected: {ex.Message}\n" +
                "Tip: 'dev:developer' works in dev mode. For production, sign in with email/password.",
                MessageType.Error);
        }
        catch (Exception ex)
        {
            _isConnected = false;
            _connectionStatus = "Connection error";
            ShowStatus($"Could not connect to {ExoforgeEditorConfig.ServerUrl}: {ex.Message}", MessageType.Error);
        }
        finally
        {
            _isConnecting = false;
            Repaint();
        }
    }

    private async Task DisconnectAsync()
    {
        if (_editorClient != null)
        {
            try { await _editorClient.DisconnectAsync(); } catch { }
            _editorClient.Dispose();
            _editorClient = null;
        }

        _isConnected = false;
        _isConnecting = false;
        _connectionStatus = "Disconnected";
        Repaint();
    }

    private async Task LogInAsync()
    {
        if (string.IsNullOrWhiteSpace(_loginEmail) || string.IsNullOrEmpty(_loginPassword))
        {
            ShowStatus("Enter an email and password to log in.", MessageType.Error);
            Repaint();
            return;
        }

        try
        {
            if (_editorClient == null || !_isConnected)
            {
                ExoTokenStore.Token = "guest";
                ExoforgeEditorConfig.AdminToken = "guest";
                await ConnectAsync();
                if (!_isConnected) return;
            }

            var data = await _editorClient!.SendActionAsync<JsonElement>("auth", "login", new { email = _loginEmail, password = _loginPassword });
            string token = data.TryGetProperty("token", out var tProp) ? tProp.GetString() ?? "" : "";
            string playerId = data.TryGetProperty("player_id", out var pProp) ? pProp.GetString() ?? "" : "";

            if (string.IsNullOrEmpty(token))
            {
                ShowStatus("Login failed: the server returned no token.", MessageType.Error);
                Repaint();
                return;
            }

            ExoTokenStore.SaveSession(token, playerId);
            ExoforgeEditorConfig.SaveSession(token, playerId);

            // Keep the dev login for the next editor start.
            ExoforgeEditorConfig.LastLoginEmail = _loginEmail;
            ExoforgeEditorConfig.RememberedPassword = _loginPassword;
            ShowStatus($"Successfully logged in as {playerId}.", MessageType.Info);

            await ConnectAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Login failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task LogOutAsync()
    {
        ExoTokenStore.Clear();
        ExoforgeEditorConfig.ClearSession();
        await DisconnectAsync();
        ShowStatus("Logged out and cleared stored credentials from EditorPrefs and PlayerPrefs.", MessageType.Info);
        Repaint();
    }

    private void HandleIncomingEvent(ExoEventFrame evt)
    {
        if (_eventPaused) return;

        string raw;
        try { raw = JsonSerializer.Serialize(evt.Payload, new JsonSerializerOptions { WriteIndented = true }); }
        catch { raw = evt.Payload.ToString() ?? "{}"; }

        _eventLog.Insert(0, new LoggedEvent(DateTime.UtcNow, evt.Topic, evt.Event, raw));
        if (_eventLog.Count > 200) _eventLog.RemoveAt(_eventLog.Count - 1);

        if (_eventAutoScroll)
        {
            _eventScroll.y = 0;
        }

        Repaint();
    }

    private async Task RefreshRemoteInfoAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        bool updated = false;

        // 1. Remote Plugins
        try
        {
            var plugins = await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "list_plugins", null);
            if (plugins.ValueKind == JsonValueKind.Object && plugins.TryGetProperty("plugins", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                _remotePlugins = arr.EnumerateArray().ToList();
                _pluginsCount = _remotePlugins.Count;
                updated = true;
            }
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogWarning($"[Exoforge] Failed to list remote plugins: {ex.Message}");
        }

        // 2. Cluster Telemetry
        try
        {
            var info = await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "get_system_info", null);
            if (info.ValueKind == JsonValueKind.Object && info.TryGetProperty("system", out var sys))
            {
                _nodeName = sys.TryGetProperty("node", out var n) ? n.GetString() ?? "—" : "—";
                _memoryMb = sys.TryGetProperty("memory_mb", out var m) ? $"{m.GetRawText()} MB" : "—";
                _activeEntities = sys.TryGetProperty("active_entities_count", out var a) ? a.GetInt32() : 0;
                if (sys.TryGetProperty("plugins_count", out var pc))
                {
                    _pluginsCount = pc.GetInt32();
                }

                if (sys.TryGetProperty("uptime_seconds", out var u))
                {
                    int s = u.GetInt32();
                    _uptime = s < 60 ? $"{s}s" : $"{s / 60}m {s % 60}s";
                }
                updated = true;
            }
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogWarning($"[Exoforge] Failed to get system info: {ex.Message}");
        }

        // 3. Service Catalog Export
        try
        {
            var export = await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "export_plugin_info", null);
            ParseServiceCatalog(export);
            updated = true;
        }
        catch { }

        if (updated)
        {
            ShowStatus($"✓ Telemetry updated: {_pluginsCount} active plugins, cluster node: {_nodeName}.", MessageType.Info);
        }

        Repaint();
    }

    private void ParseServiceCatalog(JsonElement export)
    {
        if (!export.TryGetProperty("export", out var root) || !root.TryGetProperty("plugins", out var pluginsArr))
            return;

        // Replace, don't merge: the export is the whole truth, so a plugin that was removed must
        // disappear from the catalog too.
        _serviceCatalog.Clear();
        _pluginServices.Clear();

        foreach (var plugin in pluginsArr.EnumerateArray())
        {
            if (!plugin.TryGetProperty("services", out var servicesArr)) continue;

            foreach (var s in servicesArr.EnumerateArray())
            {
                string sName = s.TryGetProperty("name", out var sn) ? sn.GetString() ?? "" : "";
                if (string.IsNullOrEmpty(sName)) continue;

                if (!_serviceCatalog.ContainsKey(sName))
                    _serviceCatalog[sName] = new List<ActionSpec>();

                string pluginId = plugin.TryGetProperty("id", out var pid) ? pid.GetString() ?? "" : "";

                if (pluginId.Length > 0)
                {
                    if (!_pluginServices.TryGetValue(pluginId, out var provided))
                    {
                        provided = new List<string>();
                        _pluginServices[pluginId] = provided;
                    }

                    if (!provided.Contains(sName)) provided.Add(sName);
                }

                if (!s.TryGetProperty("actions", out var actionsArr)) continue;

                foreach (var a in actionsArr.EnumerateArray())
                {
                    string aName = a.TryGetProperty("name", out var an) ? an.GetString() ?? "" : "";
                    if (string.IsNullOrEmpty(aName)) continue;
                    if (_serviceCatalog[sName].Any(existing => existing.Name == aName)) continue;

                    var parameters = new Dictionary<string, JsonElement>();

                    if (a.TryGetProperty("params", out var paramsObj) && paramsObj.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var property in paramsObj.EnumerateObject())
                        {
                            parameters[property.Name] = property.Value.Clone();
                        }
                    }

                    _serviceCatalog[sName].Add(new ActionSpec(aName, parameters));
                }
            }
        }

        SelectDefaultSandboxAction();
    }

    /// <summary>
    /// Picks the first real action so the Sandbox is usable on open. Previously it defaulted to a
    /// hardcoded action name that no longer existed, so the first dispatch always failed.
    /// </summary>
    private void SelectDefaultSandboxAction()
    {
        if (_serviceCatalog.Count == 0) return;

        bool stillValid = _serviceCatalog.TryGetValue(_sandboxService, out var current) &&
                          current.Any(a => a.Name == _sandboxAction);

        if (stillValid) return;

        _sandboxService = _serviceCatalog.Keys.First();
        _sandboxAction = _serviceCatalog[_sandboxService][0].Name;
        _selectedServiceIndex = _serviceCatalog.Keys.ToList().IndexOf(_sandboxService);
        _selectedActionIndex = 0;
        LoadSamplePayload(_sandboxService, _sandboxAction);
    }

    private void RefreshLocalPlugins()
    {
        _localPlugins = new List<LocalPluginInfo>();
        string pluginsDir = _workspace.PluginsPath;
        if (!Directory.Exists(pluginsDir)) return;

        foreach (var dir in Directory.GetDirectories(pluginsDir))
        {
            string name = Path.GetFileName(dir);
            string csproj = Path.Combine(dir, "src", name + ".csproj");
            if (!File.Exists(csproj)) csproj = Path.Combine(dir, name + ".csproj");
            if (!File.Exists(csproj))
            {
                csproj = Directory.GetFiles(dir, "*.csproj", SearchOption.AllDirectories)
                    .FirstOrDefault(path => !IsBuildPath(path)) ?? "";
            }

            string buildSh = Path.Combine(dir, "build.sh");
            bool canBuild = File.Exists(csproj) || File.Exists(buildSh);

            string pluginType = "native";
            string binaryPath = "";

            var wasmFiles = Directory.GetFiles(dir, "*.wasm", SearchOption.AllDirectories);
            if (wasmFiles.Length > 0)
            {
                pluginType = "wasm";
                binaryPath = wasmFiles[0];
            }
            else
            {
                string nativeBinary = Path.Combine(dir, name);
                string nativeExe = nativeBinary + ".exe";

                if (File.Exists(nativeBinary)) binaryPath = nativeBinary;
                else if (File.Exists(nativeExe)) binaryPath = nativeExe;
            }

            bool isBuilt = binaryPath != "" && File.Exists(binaryPath);
            long size = isBuilt ? new FileInfo(binaryPath).Length : 0;

            // The manifest version carries the build stamp (1.0.0+<build>.<hash>); if the current
            // sources hash differently, the plugin changed since it was last built.
            bool modified = false;
            string? version = null;
            if (isBuilt)
            {
                version = ExoDeployer.ReadManifestVersion(dir);
                string fingerprint = ExoDeployer.ComputeSourceFingerprint(dir);
                modified = version == null || !version.EndsWith("." + fingerprint, StringComparison.Ordinal);
            }

            _localPlugins.Add(new LocalPluginInfo(name, dir, pluginType, isBuilt, canBuild, binaryPath, size, modified, version));
        }
    }

    private void ShowStatus(string message, MessageType type)
    {
        _statusMessage = message;
        _statusMessageType = type;
    }

    // =========================================================================
    // Tab 1: Overview
    // =========================================================================

    private void DrawOverview()
    {
        _mainScroll = EditorGUILayout.BeginScrollView(_mainScroll);

        // 1. Cluster Telemetry Card
        EditorGUILayout.LabelField("Cluster Telemetry", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Node", _nodeName);
        DrawMetricPill("Uptime", _uptime);
        DrawMetricPill("Memory", _memoryMb);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(2);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Active Entities", _activeEntities.ToString());
        DrawMetricPill("Plugins", _pluginsCount.ToString());
        DrawMetricPill("Status", _isConnected ? "HEALTHY" : "OFFLINE");
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // 2. Client Code Generation & Contract Sync Card
        EditorGUILayout.LabelField("Contract Synchronization & Code Generation", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        string lastSync = !string.IsNullOrEmpty(ExoforgeEditorConfig.LastSyncTime)
            ? ExoforgeEditorConfig.LastSyncTime
            : "Not yet synced";

        EditorGUILayout.LabelField($"Last Synced: {lastSync}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Generated Output: {ExoforgeEditorConfig.GeneratedScriptPath}", EditorStyles.miniLabel);

        EditorGUILayout.Space(4);

        if (GUILayout.Button("⚡ Sync Contracts & Generate C# Client", GUILayout.Height(30)))
        {
            _ = SyncAndGenerateClientAsync();
        }

        if (GUILayout.Button("⬇ Generate Plugin Type Stubs (all plugins)", GUILayout.Height(24)))
        {
            _ = GenerateAllStubsAsync();
        }

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("Reveal Generated File", EditorStyles.miniButton))
        {
            string absGenPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
            if (File.Exists(absGenPath))
            {
                EditorUtility.RevealInFinder(absGenPath);
            }
            else
            {
                ShowStatus($"Generated file not found at {absGenPath}. Run Sync first.", MessageType.Warning);
            }
        }

        if (GUILayout.Button("Open Workspace Folder", EditorStyles.miniButton))
        {
            string absWs = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
            if (Directory.Exists(absWs))
            {
                EditorUtility.RevealInFinder(absWs);
            }
            else
            {
                ShowStatus($"Workspace folder not found at {absWs}.", MessageType.Warning);
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // 3. Cluster Operations & Tools Card
        EditorGUILayout.LabelField("Cluster Operations & Developer Tools", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        using (new EditorGUI.DisabledScope(!_isConnected))
        {
            if (GUILayout.Button("🔄 Hot-Restart Cluster Supervision", GUILayout.Height(24)))
            {
                _ = RestartClusterAsync();
            }
        }

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("🌐 Open Web Dashboard (:4005)", GUILayout.Height(24)))
        {
            Application.OpenURL("http://localhost:4005");
        }

        if (GUILayout.Button("📖 Open Swagger API Docs (:4001)", GUILayout.Height(24)))
        {
            Application.OpenURL("http://localhost:4001/swagger");
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.EndScrollView();
    }

    private static void DrawMetricPill(string label, string val)
    {
        EditorGUILayout.BeginVertical(GUI.skin.box);
        EditorGUILayout.LabelField(label, EditorStyles.miniLabel);
        EditorGUILayout.LabelField(val, EditorStyles.boldLabel);
        EditorGUILayout.EndVertical();
    }

    // =========================================================================
    // Tab 2: Live Events Pub/Sub
    // =========================================================================

    private void DrawLiveEvents()
    {
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Live Broadcast Events ({_eventLog.Count})", EditorStyles.boldLabel);

        _eventAutoScroll = GUILayout.Toggle(_eventAutoScroll, "Auto-scroll", EditorStyles.miniButton, GUILayout.Width(80));

        if (GUILayout.Button(_eventPaused ? "▶ Resume" : "⏸ Pause", EditorStyles.miniButton, GUILayout.Width(70)))
        {
            _eventPaused = !_eventPaused;
        }

        if (GUILayout.Button("Clear", EditorStyles.miniButton, GUILayout.Width(50)))
        {
            _eventLog.Clear();
            _selectedEvent = null;
        }
        EditorGUILayout.EndHorizontal();

        // Search Filter
        EditorGUILayout.BeginHorizontal();
        _eventFilter = EditorGUILayout.TextField("Filter", _eventFilter);
        if (!string.IsNullOrEmpty(_eventFilter) && GUILayout.Button("✕", EditorStyles.miniButton, GUILayout.Width(22)))
        {
            _eventFilter = "";
        }
        EditorGUILayout.EndHorizontal();

        // Event List
        _eventScroll = EditorGUILayout.BeginScrollView(_eventScroll, GUILayout.Height(210));

        var filtered = string.IsNullOrWhiteSpace(_eventFilter)
            ? _eventLog
            : _eventLog.Where(e => e.Topic.Contains(_eventFilter, StringComparison.OrdinalIgnoreCase) ||
                                   e.EventName.Contains(_eventFilter, StringComparison.OrdinalIgnoreCase)).ToList();

        if (filtered.Count == 0)
        {
            EditorGUILayout.HelpBox(_isConnected ? "Listening for live events on topic '*'..." : "Connect to cluster to monitor live broadcast events.", MessageType.None);
        }
        else
        {
            foreach (var evt in filtered)
            {
                bool isSelected = _selectedEvent == evt;
                var rowStyle = isSelected ? EditorStyles.selectionRect : EditorStyles.helpBox;

                EditorGUILayout.BeginHorizontal(rowStyle);
                EditorGUILayout.LabelField(evt.At.ToString("HH:mm:ss.fff"), EditorStyles.miniLabel, GUILayout.Width(80));
                EditorGUILayout.LabelField(evt.Topic, EditorStyles.miniBoldLabel, GUILayout.Width(130));
                EditorGUILayout.LabelField(evt.EventName);

                if (GUILayout.Button(isSelected ? "Selected" : "Inspect", EditorStyles.miniButton, GUILayout.Width(60)))
                {
                    _selectedEvent = evt;
                }
                EditorGUILayout.EndHorizontal();
            }
        }

        EditorGUILayout.EndScrollView();

        EditorGUILayout.Space(4);

        // Event Detail Inspector
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField(_selectedEvent != null
            ? $"Payload: {_selectedEvent.Topic} -> {_selectedEvent.EventName}"
            : "Event Payload Inspector", EditorStyles.boldLabel);

        if (_selectedEvent != null)
        {
            if (GUILayout.Button("Copy JSON", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                EditorGUIUtility.systemCopyBuffer = _selectedEvent.RawJson;
                ShowStatus("Copied event JSON to clipboard.", MessageType.Info);
            }

            if (GUILayout.Button("Send to Sandbox", EditorStyles.miniButton, GUILayout.Width(110)))
            {
                _sandboxPayload = _selectedEvent.RawJson;
                _currentTab = Tab.ActionSandbox;
                ShowStatus("Loaded event payload into Action Sandbox.", MessageType.Info);
            }
        }
        EditorGUILayout.EndHorizontal();

        if (_selectedEvent != null)
        {
            _eventDetailScroll = EditorGUILayout.BeginScrollView(_eventDetailScroll, GUILayout.Height(150));
            EditorGUILayout.TextArea(_selectedEvent.RawJson, EditorStyles.textArea);
            EditorGUILayout.EndScrollView();
        }
        else
        {
            EditorGUILayout.HelpBox("Select an event above to inspect its JSON payload.", MessageType.None);
        }
    }

    // =========================================================================
    // Tab 3: Action Sandbox
    // =========================================================================

    private void DrawSandbox()
    {
        EditorGUILayout.LabelField("Action Sandbox & Service Dispatcher", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Test and dispatch actions directly to the cluster with typed JSON payloads.", MessageType.None);

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        // Catalog Dropdowns
        var serviceNames = _serviceCatalog.Keys.ToList();
        serviceNames.Add("(Custom)");
        _selectedServiceIndex = Mathf.Clamp(_selectedServiceIndex, 0, serviceNames.Count - 1);

        EditorGUILayout.BeginHorizontal();
        int newServiceIndex = EditorGUILayout.Popup("Quick Catalog", _selectedServiceIndex, serviceNames.ToArray());
        if (newServiceIndex != _selectedServiceIndex)
        {
            _selectedServiceIndex = newServiceIndex;
            if (_selectedServiceIndex < serviceNames.Count - 1)
            {
                _sandboxService = serviceNames[_selectedServiceIndex];
                _selectedActionIndex = 0;

                var specs = _serviceCatalog[_sandboxService];
                if (specs.Count > 0)
                {
                    _sandboxAction = specs[0].Name;
                    LoadSamplePayload(_sandboxService, _sandboxAction);
                }
            }
        }

        if (_selectedServiceIndex < serviceNames.Count - 1)
        {
            var specs = _serviceCatalog[serviceNames[_selectedServiceIndex]];
            var actionNames = specs.Select(a => a.Name).ToList();
            actionNames.Add("(Custom)");

            _selectedActionIndex = Mathf.Clamp(_selectedActionIndex, 0, actionNames.Count - 1);
            int newActionIndex = EditorGUILayout.Popup(_selectedActionIndex, actionNames.ToArray(), GUILayout.Width(130));
            if (newActionIndex != _selectedActionIndex)
            {
                _selectedActionIndex = newActionIndex;
                if (_selectedActionIndex < actionNames.Count - 1)
                {
                    _sandboxAction = actionNames[_selectedActionIndex];
                    LoadSamplePayload(_sandboxService, _sandboxAction);
                }
            }
        }
        EditorGUILayout.EndHorizontal();

        _sandboxService = EditorGUILayout.TextField("Service", _sandboxService);
        _sandboxAction = EditorGUILayout.TextField("Action", _sandboxAction);

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("JSON Payload");
        if (GUILayout.Button("Format JSON", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            FormatSandboxPayload();
        }
        if (GUILayout.Button("Load Template", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            LoadSamplePayload(_sandboxService, _sandboxAction);
        }
        EditorGUILayout.EndHorizontal();

        _sandboxPayload = EditorGUILayout.TextArea(_sandboxPayload, GUILayout.Height(90));

        EditorGUILayout.Space(2);

        using (new EditorGUI.DisabledScope(!_isConnected))
        {
            if (GUILayout.Button("🚀 Dispatch Action", GUILayout.Height(28)))
            {
                _ = DispatchSandboxAsync();
            }
        }
        EditorGUILayout.EndVertical();

        // Response View
        if (!string.IsNullOrEmpty(_sandboxResult))
        {
            EditorGUILayout.Space(4);
            EditorGUILayout.BeginHorizontal();

            var prev = GUI.color;
            GUI.color = _sandboxSuccess ? new Color(0.3f, 0.9f, 0.4f) : new Color(0.9f, 0.3f, 0.3f);
            string statusTag = _sandboxSuccess ? $"● SUCCESS ({_sandboxLatency})" : $"● ERROR ({_sandboxLatency})";
            EditorGUILayout.LabelField(statusTag, EditorStyles.boldLabel);
            GUI.color = prev;

            if (GUILayout.Button("Copy Result", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                EditorGUIUtility.systemCopyBuffer = _sandboxResult;
                ShowStatus("Copied action result to clipboard.", MessageType.Info);
            }
            EditorGUILayout.EndHorizontal();

            _sandboxResultScroll = EditorGUILayout.BeginScrollView(_sandboxResultScroll, GUILayout.Height(150));
            EditorGUILayout.TextArea(_sandboxResult, EditorStyles.textArea);
            EditorGUILayout.EndScrollView();
        }
    }

    private void FormatSandboxPayload()
    {
        try
        {
            using var doc = JsonDocument.Parse(_sandboxPayload);
            _sandboxPayload = JsonSerializer.Serialize(doc.RootElement, new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            ShowStatus($"Invalid JSON: {ex.Message}", MessageType.Error);
        }
    }

    /// <summary>
    /// Builds a payload skeleton from the action's declared params, so the Sandbox produces
    /// something the action will accept for any service — including plugins you just wrote.
    /// </summary>
    private void LoadSamplePayload(string service, string action)
    {
        if (!_serviceCatalog.TryGetValue(service, out var specs))
        {
            _sandboxPayload = "{}";
            return;
        }

        var spec = specs.FirstOrDefault(a => a.Name == action);
        if (spec == null || spec.Params.Count == 0)
        {
            _sandboxPayload = "{}";
            return;
        }

        var payload = new Dictionary<string, object?>();

        foreach (var (name, declared) in spec.Params)
        {
            // Optional params are omitted: sending a wrong-shaped value is worse than omitting it.
            if (IsOptional(declared)) continue;

            payload[name] = PlaceholderFor(declared);
        }

        _sandboxPayload = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
    }

    private static bool IsOptional(JsonElement declared) =>
        declared.ValueKind == JsonValueKind.Object &&
        declared.TryGetProperty("optional", out var optional) &&
        optional.ValueKind == JsonValueKind.True;

    private static string ParamType(JsonElement declared) =>
        declared.ValueKind switch
        {
            JsonValueKind.String => declared.GetString() ?? "string",
            JsonValueKind.Object when declared.TryGetProperty("type", out var type) => type.GetString() ?? "string",
            _ => "string"
        };

    private static object? PlaceholderFor(JsonElement declared) => ParamType(declared) switch
    {
        "integer" or "int" => 0,
        "float" or "number" => 0.0,
        "boolean" or "bool" => false,
        "list" or "array" => new List<object>(),
        "map" or "object" => new Dictionary<string, object?>(),
        "term" => null,
        _ => ""
    };

    private async Task DispatchSandboxAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        var sw = Stopwatch.StartNew();
        try
        {
            object? payload = string.IsNullOrWhiteSpace(_sandboxPayload)
                ? null
                : JsonDocument.Parse(_sandboxPayload).RootElement;

            var result = await _editorClient.SendActionAsync<JsonElement>(_sandboxService, _sandboxAction, payload);
            sw.Stop();

            _sandboxSuccess = true;
            _sandboxLatency = $"{sw.ElapsedMilliseconds} ms";
            _sandboxResult = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            sw.Stop();
            _sandboxSuccess = false;
            _sandboxLatency = $"{sw.ElapsedMilliseconds} ms";
            _sandboxResult = ex.Message;
        }

        Repaint();
    }

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
        ExoforgeEditorConfig.ServerUrl = EditorGUILayout.TextField("Server URL", ExoforgeEditorConfig.ServerUrl);

        EditorGUILayout.BeginHorizontal();
        string newToken = EditorGUILayout.TextField("Bearer Token", ExoTokenStore.Token);
        if (newToken != ExoTokenStore.Token)
        {
            ExoTokenStore.Token = newToken;
            ExoforgeEditorConfig.AdminToken = newToken;
        }

        foreach (var (label, token) in ExoforgeEditorConfig.TokenPresets)
        {
            if (GUILayout.Button(label, EditorStyles.miniButton, GUILayout.Width(45)))
            {
                ExoTokenStore.Token = token;
                ExoforgeEditorConfig.AdminToken = token;
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
        EditorGUILayout.LabelField($"Active Token: {ExoforgeEditorConfig.AdminToken}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Stored Player ID: {ExoforgeEditorConfig.PlayerId}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Scopes: {ExoforgeEditorConfig.Scopes}", EditorStyles.miniLabel);

        EditorGUILayout.Space(4);
        if (GUILayout.Button("Purge All Saved Credentials (EditorPrefs & PlayerPrefs)"))
        {
            _ = LogOutAsync();
        }
        EditorGUILayout.EndVertical();
    }

    // =========================================================================
    // Core Actions: Sync, Generate, Restart
    // =========================================================================

    private async Task SyncAndGenerateClientAsync()
    {
        ShowStatus("Syncing contracts and generating strongly-typed C# client...", MessageType.Info);
        Repaint();

        try
        {
            string outputPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
            var deployer = new ExoDeployer(_workspace);

            if (_isConnected && _editorClient != null)
            {
                await deployer.SyncContractsAsync(
                    outputPathOverride: outputPath,
                    existingClient: _editorClient);
            }
            else
            {
                await deployer.SyncContractsAsync(
                    environmentName: null,
                    outputPathOverride: outputPath);
            }

            ExoforgeRuntimeConfigGenerator.Generate();
            ExoforgeEditorConfig.LastSyncTime = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss 'UTC'");
            AssetDatabase.Refresh();
            ShowStatus($"✓ Strongly-typed C# client generated successfully at {ExoforgeEditorConfig.GeneratedScriptPath}", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Contract sync failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task RestartClusterAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        try
        {
            await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "restart_system", null);
            ShowStatus("Server supervision restarted successfully.", MessageType.Info);
            await RefreshRemoteInfoAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Restart failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }
}
}
