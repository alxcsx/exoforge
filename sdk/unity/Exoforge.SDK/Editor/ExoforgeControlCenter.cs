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
public partial class ExoforgeControlCenter : EditorWindow
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
        bool hasSession = !string.IsNullOrEmpty(ExoTokenStore.PlayerId)
            || (!string.IsNullOrEmpty(ActiveToken)
                && ActiveToken != "dev:developer");
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

            if (!string.IsNullOrEmpty(ExoTokenStore.PlayerId))
            {
                EditorGUILayout.BeginHorizontal();
                string sessionLabel = _isConnected
                    ? $"Signed in as: {ExoTokenStore.PlayerId}"
                    : $"Stored session: {ExoTokenStore.PlayerId} (disconnected)";
                EditorGUILayout.LabelField(sessionLabel, EditorStyles.boldLabel);
                if (!string.IsNullOrEmpty(ExoTokenStore.Scopes))
                {
                    EditorGUILayout.LabelField($"Scopes: [{ExoTokenStore.Scopes}]", EditorStyles.miniLabel);
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

        if (_workspace?.Config?.Environments != null)
        {
            foreach (var kvp in _workspace.Config.Environments)
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

    private void ApplyEnvironment(EnvOption env)
    {
        ExoforgeEditorConfig.SelectedEnvironment = env.Name;
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
