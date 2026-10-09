using System;
using System.Collections.Concurrent;
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
public partial class ExoforgeControlCenter : EditorWindow
{
    private enum Tab { Overview, LiveEvents, ActionSandbox, Plugins, Settings }

    // Per-editor-session flag: auto-connect on editor start, but not on every script reload.
    private const string AutoConnectSessionKey = "Exoforge_AutoConnected";

    /// <summary>
    /// The tabs in order. One list on purpose: the toolbar returns an index, so a separate array of
    /// labels that drifted out of step would silently select the wrong tab.
    /// </summary>
    private static readonly (Tab Id, string Label)[] Tabs =
    {
        (Tab.Overview, "Overview"),
        (Tab.LiveEvents, "Live Events"),
        (Tab.ActionSandbox, "Action Sandbox"),
        (Tab.Plugins, "Plugins"),
        (Tab.Settings, "Settings"),
    };

    private static readonly string[] TabLabels = Tabs.Select(t => t.Label).ToArray();

    // Connection & Client
    private ExoClient? _editorClient;
    private ExoWorkspace? _workspace;
    private string _workspaceLoadedFrom = "";

    /// <summary>
    /// The workspace, reloaded whenever the configured path changes.
    ///
    /// It used to be loaded once in OnEnable, so changing the path in Settings left Build, Deploy and
    /// Stubs pointed at the old workspace until the window was reloaded.
    /// </summary>
    private ExoWorkspace Workspace
    {
        get
        {
            string path = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();

            if (_workspace == null || _workspaceLoadedFrom != path)
            {
                _workspace = ExoWorkspace.Load(path);
                _workspaceLoadedFrom = path;
            }

            return _workspace;
        }
    }
    private bool _isConnected;
    private bool _isConnecting;
    private string _connectionStatus = "Disconnected";

    // Authentication foldout
    private bool _showAuthFoldout;
    private string _loginEmail = ExoforgeEditorConfig.DefaultLoginEmail;
    private string _loginPassword = "";

    // Status Banner
    private string _statusMessage = "";
    private MessageType _statusMessageType = MessageType.Info;

    // Cluster Telemetry
    private string _nodeName = "—";
    private string _uptime = "—";
    private string _memoryMb = "—";
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

    // Network callbacks arrive on background threads; OnGUI enumerates _eventLog on the main one.
    // Incoming events are staged here and drained in OnEditorUpdate (M33 Fix 17).
    private readonly ConcurrentQueue<LoggedEvent> _pendingEvents = new();
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
            // The editor authenticates with the runtime session token. Seed it from the active
            // environment, so exoforge.json decides what a fresh editor signs in as rather than a
            // hardcoded default. A legacy "admin" migration used to live here; that is the
            // workspace's business now.
            if (!ExoTokenStore.HasToken && !string.IsNullOrEmpty(ActiveToken))
            {
                ExoTokenStore.Token = ActiveToken;
            }

        if (ExoforgeEditorConfig.WorkspacePath == "exoforge")
        {
            ExoforgeEditorConfig.WorkspacePath = ExoforgeEditorConfig.DefaultWorkspaceRelPath;
        }

        // Restore the last login so the auth form doesn't reset on every editor start. The password
        // is not restored: it is not stored anywhere (M33 Fix 22).
        _loginEmail = ExoforgeEditorConfig.LastLoginEmail;
        _loginPassword = "";

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
        bool hasSession = !string.IsNullOrEmpty(ExoTokenStore.StudioPlayerId)
            || (!string.IsNullOrEmpty(ActiveToken)
                && ActiveToken != "dev:developer");

        // A saved password no longer exists to sign in with (M33 Fix 22): reconnect with the token.
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
        // Drain what background threads staged, on the thread that renders it (M33 Fix 17).
        bool arrived = false;

        while (_pendingEvents.TryDequeue(out var evt))
        {
            _eventLog.Insert(0, evt);
            if (_eventLog.Count > 200) _eventLog.RemoveAt(_eventLog.Count - 1);
            arrived = true;
        }

        if (arrived && _eventAutoScroll)
        {
            _eventScroll.y = 0;
        }

        if (_isBuilding || arrived) Repaint();
    }

    private void AppendBuildLog(string line)
    {
        _buildLog += line + "\n";
    }

    private void OnGUI()
    {
        DrawHeader();
        EditorGUILayout.Space(2);

        _currentTab = Tabs[GUILayout.Toolbar((int)_currentTab, TabLabels, GUILayout.Height(24))].Id;
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

            if (!string.IsNullOrEmpty(ExoTokenStore.StudioPlayerId))
            {
                EditorGUILayout.BeginHorizontal();
                string sessionLabel = _isConnected
                    ? $"Signed in as: {ExoTokenStore.StudioPlayerId}"
                    : $"Stored session: {ExoTokenStore.StudioPlayerId} (disconnected)";
                EditorGUILayout.LabelField(sessionLabel, EditorStyles.boldLabel);
                if (!string.IsNullOrEmpty(ExoTokenStore.StudioScopes))
                {
                    EditorGUILayout.LabelField($"Scopes: [{ExoTokenStore.StudioScopes}]", EditorStyles.miniLabel);
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
                // Held for this editor session only — never into EditorPrefs (M33 Fix 22).
                _loginPassword = typedPassword;
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
            // The package ships the plugin SDK as a local feed, so a scaffolded plugin builds with no
            // repository and no published package anywhere.
            string? feed = ExoforgeEditorConfig.PackageRoot is { } root
                ? Path.Combine(root, "Editor", "Plugins", "NuGet~")
                : null;

            string dir = ExoScaffolder.ScaffoldPlugin(Workspace.PluginsPath, _newPluginName, template: template, feed: feed);
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
            string.Equals(e.WsUrl, ActiveWsUrl, StringComparison.OrdinalIgnoreCase) ||
            (e.Name == "local" && ExoforgeEditorConfig.IsLocalUrl(ActiveWsUrl)));

        if (currentIndex < 0)
        {
            var listWithCustom = names.ToList();
            listWithCustom.Add($"(custom) {ActiveWsUrl}");
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

    /// <summary>
    /// The environments the workspace declares, in exoforge.json order.
    ///
    /// Only what the workspace defines. This used to invent local/dev/staging/production with
    /// hardcoded URLs whenever the config lacked one, so the editor could be pointed at an endpoint
    /// nobody configured - and a second copy of the same URLs lived in ExoforgeEditorConfig.
    /// </summary>
    private List<EnvOption> GetConfiguredEnvironments()
    {
        var list = new List<EnvOption>();

        if (Workspace?.Config?.Environments != null)
        {
            foreach (var kvp in Workspace.Config.Environments)
            {
                list.Add(new EnvOption(kvp.Key, kvp.Value.WsUrl, kvp.Value.Token, kvp.Value.HttpUrl));
            }
        }

        return list;
    }

    /// <summary>
    /// The environment the editor is pointed at, or null when the workspace declares none.
    ///
    /// exoforge.json is the source of truth for where a cluster is and how to authenticate to it.
    /// These used to be copied into EditorPrefs and into the token store on every switch: three
    /// places to configure one thing, and three ways for them to disagree.
    /// </summary>
    private EnvOption? ActiveEnvironment
    {
        get
        {
            var environments = GetConfiguredEnvironments();
            if (environments.Count == 0) return null;

            string selected = ExoforgeEditorConfig.SelectedEnvironment;
            return environments.FirstOrDefault(e => e.Name == selected) ?? environments[0];
        }
    }

    private string ActiveWsUrl => ActiveEnvironment?.WsUrl ?? "";

    private string ActiveToken => ActiveEnvironment?.Token ?? "";

    /// <summary>The HTTP endpoint the active environment declares; sign-in, Swagger and the dashboard hang off this host (M33 Fix 23).</summary>
    private string ActiveHttpUrl => ActiveEnvironment?.HttpUrl ?? "";

    private void ApplyEnvironment(EnvOption env)
    {
        ExoforgeEditorConfig.SelectedEnvironment = env.Name;
        ShowStatus($"Switched to environment '{env.Name}' ({env.WsUrl}).", MessageType.Info);

        if (_isConnected)
        {
            _ = ConnectAsync();
        }
    }


    /// <summary>Whether the cluster is reachable. One name for the state every remote action checks.</summary>
    private bool CanReachCluster => _isConnected && _editorClient != null;

    /// <summary>
    /// Renders a gate for a tab that needs the cluster, and says whether it did. Returns false when
    /// connected, so a caller reads <c>if (DrawClusterGate()) return;</c>.
    ///
    /// The status banner used to say "sign in below" while the login form sat collapsed, so there was
    /// nothing to click; this puts the button where the message is.
    /// </summary>
    private bool DrawClusterGate()
    {
        if (CanReachCluster) return false;

        EditorGUILayout.Space(4);
        EditorGUILayout.HelpBox(
            _isConnecting
                ? "Connecting to the cluster…"
                : "Not connected — sign in to use this tab.",
            _isConnecting ? MessageType.Info : MessageType.Warning);

        using (new EditorGUI.DisabledScope(_isConnecting))
        {
            if (GUILayout.Button(_isConnecting ? "Connecting…" : "Sign in", GUILayout.Height(26)))
            {
                _showAuthFoldout = true;
                Repaint();
            }
        }

        return true;
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
    // Core Actions: Sync, Generate, Restart
    // =========================================================================

    private async Task SyncAndGenerateClientAsync()
    {
        ShowStatus("Syncing contracts and generating strongly-typed C# client...", MessageType.Info);
        Repaint();

        try
        {
            string outputPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
            var deployer = new ExoDeployer(Workspace);

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
