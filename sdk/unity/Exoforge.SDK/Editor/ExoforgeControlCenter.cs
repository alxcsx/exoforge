using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using Exoforge.Management;
using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine;
using UnityEngine.UIElements;

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
    private enum Tab { Plugins, Metrics, LiveEvents, Settings }

    // Per-editor-session flag: auto-connect on editor start, but not on every script reload.
    private const string AutoConnectSessionKey = "Exoforge_AutoConnected";
    private const string WasConnectedSessionKey = "Exoforge_WasConnected";

    /// <summary>
    /// The tabs in order. One list on purpose: the toolbar returns an index, so a separate array of
    /// labels that drifted out of step would silently select the wrong tab.
    /// </summary>
    private static readonly (Tab Id, string Label)[] Tabs =
    {
        (Tab.Plugins, "Extensions"),
        (Tab.Metrics, "Metrics"),
        (Tab.LiveEvents, "Event Stream"),
        (Tab.Settings, "Settings"),
    };

    private static readonly string[] TabLabels = Tabs.Select(t => t.Label).ToArray();

    public static ExoforgeControlCenter? Instance { get; private set; }
    [NonSerialized] private static ExoClient? s_editorClient;
    public static ExoClient? SharedClient => s_editorClient;
    public ExoClient? ActiveClient => s_editorClient;
    private static ExoClient? _editorClient
    {
        get => s_editorClient;
        set => s_editorClient = value;
    }

    public static string ActiveHttpEndpoint
    {
        get
        {
            if (Instance != null && !string.IsNullOrEmpty(Instance.ActiveHttpUrl))
            {
                return Instance.ActiveHttpUrl;
            }
            try
            {
                var env = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath())?.GetActiveEnvironment();
                return env?.HttpUrl ?? "http://localhost:4001";
            }
            catch
            {
                return "http://localhost:4001";
            }
        }
    }

    // Connection & Client
    private ExoWorkspace? _workspace;
    private string _workspaceLoadedFrom = "";

    /// <summary>
    /// The workspace, reloaded whenever the configured path changes.
    ///
    /// It used to be loaded once in OnEnable, so changing the path in Settings left Build, Deploy and
    /// Stubs pointed at the old workspace until the window was reloaded.
    /// </summary>
    public ExoWorkspace Workspace
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
    [NonSerialized] private static bool s_rawConnected;
    private static bool _rawConnected
    {
        get => s_rawConnected;
        set => s_rawConnected = value;
    }
    public static bool IsClusterConnected => s_rawConnected && s_editorClient != null && s_editorClient.IsConnected;
    private bool _isConnected
    {
        get => IsClusterConnected;
        set => s_rawConnected = value;
    }
    [NonSerialized] private static bool s_isConnecting;
    public static bool IsConnecting => s_isConnecting;
    private bool _isConnecting
    {
        get => s_isConnecting;
        set => s_isConnecting = value;
    }
    [NonSerialized] private CancellationTokenSource? _connectCts;
    [NonSerialized] private static string s_connectionStatus = "Disconnected";
    public static string ConnectionStatus => s_connectionStatus;
    private string _connectionStatus
    {
        get => s_connectionStatus;
        set => s_connectionStatus = value;
    }
    private string _connectionLatency = "";

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
    private bool _showScaffoldAdvanced;
    private bool _showRemotePlugins;
    private string _pluginLogs = "";
    private string _pluginLogsFor = "";
    private bool _showPluginLogs;
    private Vector2 _pluginLogsScroll;
    private List<LocalPluginInfo> _localPlugins = new();
    private List<JsonElement> _remotePlugins = new();
    private Vector2 _pluginsScroll;
    private string _buildRid = "";
    private bool _isBuilding;
    private string _buildLog = "";
    private bool _showBuildLog;
    private Vector2 _buildLogScroll;

    private Tab _currentTab = Tab.Plugins;
    private Vector2 _mainScroll;
    private Vector2 _settingsScroll;

    // UI Toolkit references
    private VisualElement? _root;
    private VisualElement? _connectionDot;
    private Label? _connectionText;
    private Label? _envBadge;
    private Label? _endpointLabel;
    private Label? _latencyPill;
    private Button? _connectBtn;
    private VisualElement? _tabContentArea;
    private List<Button> _tabButtons = new();

    private sealed record LocalPluginInfo(
        string Name,
        string Directory,
        string PluginType,
        bool IsBuilt,
        bool CanBuild,
        string BinaryPath,
        long BinarySizeBytes,
        bool Modified,
        string? Version,
        string Icon = "🧩",
        string Title = "");

    [MenuItem("Tools/Exoforge/Exoforge Studio", false, 100)]
    [MenuItem("Window/Exoforge/Exoforge Studio", false, 2000)]
    public static void ShowWindow()
    {
        var window = GetWindow<ExoforgeControlCenter>("Exoforge Studio");
        window.minSize = new Vector2(480, 560);
    }

    [MenuItem("Tools/Exoforge/Repair & Regenerate Client", false, 110)]
    [MenuItem("Window/Exoforge/Repair & Regenerate Client", false, 2005)]
    public static async void RepairAndRegenerateClientMenu()
    {
        EditorUtility.DisplayProgressBar("Exoforge Repair", "Repairing C# client bindings and runtime configuration...", 0.3f);
        try
        {
            var ws = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
            var deployer = new ExoDeployer(ws);
            string outputPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();

            // Run offline-capable sync
            int changed = await deployer.SyncContractsAsync(outputPathOverride: outputPath);

            // Generate runtime config
            ExoforgeRuntimeConfigGenerator.Generate();

            // Generate stubs for local plugins
            await deployer.GenerateAllPluginStubsAsync();

            AssetDatabase.Refresh();
            UnityEngine.Debug.Log("[Exoforge] ✓ Successfully repaired and regenerated C# client bindings and plugin stubs.");
            EditorUtility.DisplayDialog("Exoforge Repair", "C# client bindings and plugin stubs were regenerated successfully.\n\nFile: " + ExoforgeEditorConfig.GeneratedScriptPath, "OK");
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogError($"[Exoforge] Repair failed: {ex.Message}");
            EditorUtility.DisplayDialog("Exoforge Repair Error", $"Failed to repair client bindings: {ex.Message}", "OK");
        }
        finally
        {
            EditorUtility.ClearProgressBar();
        }
    }

    [InitializeOnLoadMethod]
    private static void AutoCheckClientBindings()
    {
        EditorApplication.delayCall += async () =>
        {
            try
            {
                string outputPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
                if (!File.Exists(outputPath) || new FileInfo(outputPath).Length == 0)
                {
                    UnityEngine.Debug.Log("[Exoforge] Missing client bindings detected. Auto-generating baseline C# client from workspace...");
                    var ws = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
                    var deployer = new ExoDeployer(ws);
                    await deployer.SyncContractsAsync(outputPathOverride: outputPath);
                    ExoforgeRuntimeConfigGenerator.Generate();
                    AssetDatabase.Refresh();
                }
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning($"[Exoforge] Auto-check client bindings deferred: {ex.Message}");
            }
        };
    }

    [MenuItem("Tools/Exoforge/Reset Anonymous Player Session", false, 200)]
    [MenuItem("Window/Exoforge/Reset Anonymous Player Session", false, 2001)]
    public static void ResetAnonymousPlayerSession()
    {
        PlayerPrefs.DeleteKey("Exoforge.Token");
        PlayerPrefs.DeleteKey("Exoforge.PlayerId");
        PlayerPrefs.DeleteKey("Exoforge.Scopes");
        PlayerPrefs.DeleteKey("Exoforge.PlayerName");
        PlayerPrefs.Save();
        ExoDeviceId.ResetWithNewId();
        UnityEngine.Debug.Log("[Exoforge] Cleared anonymous player session and generated a new unique device identifier.");
    }

    [MenuItem("Tools/Exoforge/Clear All Sessions (Player & Studio)", false, 201)]
    [MenuItem("Window/Exoforge/Clear All Sessions (Player & Studio)", false, 2002)]
    public static void ClearAllSessions()
    {
        ResetAnonymousPlayerSession();
        ExoTokenStore.ClearStudioSession();
        UnityEngine.Debug.Log("[Exoforge] Cleared all stored sessions.");
    }

    private void OnEnable()
    {
        Instance = this;
        // The editor authenticates with the runtime session token. Seed it from the active
        // environment, so exoforge.json decides what a fresh editor signs in as rather than a
        // hardcoded default.
        if (string.IsNullOrEmpty(ExoTokenStore.StudioToken) && !string.IsNullOrEmpty(ActiveToken))
        {
            ExoTokenStore.SaveStudioSession(ActiveToken);
        }

        if (ExoforgeEditorConfig.WorkspacePath == "exoforge")
        {
            ExoforgeEditorConfig.WorkspacePath = ExoforgeEditorConfig.DefaultWorkspaceRelPath;
        }

        // Restore the last login and password so the auth form doesn't reset on every editor start.
        _loginEmail = ExoforgeEditorConfig.LastLoginEmail;
        _loginPassword = ExoforgeEditorConfig.LastLoginPassword;

        RefreshLocalPlugins();

        EditorApplication.update += OnEditorUpdate;

        // Reconnect when the editor opens or reloads.
        bool wasConnected = SessionState.GetBool(WasConnectedSessionKey, false);
        if (wasConnected)
        {
            _isConnecting = true;
            _connectionStatus = "Reconnecting...";
            EditorApplication.delayCall += () => _ = ReconnectWithRetryAsync(maxRetries: 6, delayMs: 800);
        }
        else if (!SessionState.GetBool(AutoConnectSessionKey, false))
        {
            SessionState.SetBool(AutoConnectSessionKey, true);
            // Defer: OnEnable can run before the editor/network stack is ready.
            EditorApplication.delayCall += TryAutoConnect;
        }
    }

    private void TryAutoConnect()
    {
        string token = !string.IsNullOrWhiteSpace(ExoTokenStore.StudioToken)
            ? ExoTokenStore.StudioToken
            : ExoTokenStore.Token;

        if (string.IsNullOrWhiteSpace(token))
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
        if (Instance == this) Instance = null;
        EditorApplication.update -= OnEditorUpdate;
        // Do not disconnect! In Unity, OnDisable is called when an EditorWindow is docked behind another tab
        // (such as when switching to the Exoforge Plugins window or the Inspector).
        // Disconnecting here would prematurely sever the cluster connection for background tools.
    }

    private void OnDestroy()
    {
        if (Instance == this) Instance = null;
        EditorApplication.update -= OnEditorUpdate;

        // Cleanly disconnect only if there are no open Exoforge windows left (Studio or Plugins)
        if (!HasAnyExoforgeWindowsOpen())
        {
            _ = DisconnectAsync();
        }
    }

    public static bool HasAnyExoforgeWindowsOpen()
    {
        var studios = Resources.FindObjectsOfTypeAll<ExoforgeControlCenter>();
        var plugins = Resources.FindObjectsOfTypeAll<ExoforgePluginsWindow>();
        return studios.Length > 0 || plugins.Length > 0;
    }

    [InitializeOnLoadMethod]
    private static void InitLifecycleHooks()
    {
        AssemblyReloadEvents.beforeAssemblyReload += () =>
        {
            if (s_editorClient != null)
            {
                SessionState.SetBool(WasConnectedSessionKey, IsClusterConnected);
                try { s_editorClient.Dispose(); } catch { }
                s_editorClient = null;
                s_rawConnected = false;
            }
        };

        EditorApplication.quitting += () =>
        {
            try { s_editorClient?.Dispose(); } catch { }
            s_editorClient = null;
            s_rawConnected = false;
        };
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

        UpdateModernHeaderUI();

        if (_isBuilding || arrived) Repaint();
    }

    private void AppendBuildLog(string line)
    {
        _buildLog += line + "\n";
    }

    public void CreateGUI()
    {
        _root = rootVisualElement;
        _root.style.backgroundColor = ExoforgeUIStyle.BgWindow;
        _root.style.flexDirection = FlexDirection.Column;
        _root.style.flexGrow = 1;

        RebuildStudioUI();
    }

    public void RebuildStudioUI()
    {
        if (_root == null) return;
        _root.Clear();

        // 1. Top Modern Header Bar
        _root.Add(BuildModernHeader());

        // 2. Modern Tab Strip
        _root.Add(BuildModernTabStrip());

        // 3. Tab Content Area (hosting active tab via IMGUIContainer)
        _tabContentArea = new VisualElement();
        _tabContentArea.style.flexGrow = 1;
        _tabContentArea.style.paddingLeft = 8;
        _tabContentArea.style.paddingRight = 8;
        _tabContentArea.style.paddingTop = 6;
        _tabContentArea.style.paddingBottom = 8;

        var imgui = new IMGUIContainer(() =>
        {
            DrawHeader();

            if (!string.IsNullOrEmpty(_statusMessage))
            {
                DrawStatusBanner();
            }

            switch (_currentTab)
            {
                case Tab.Plugins:
                    if (_localPlugins.Count == 0) RefreshLocalPlugins();
                    DrawPlugins();
                    break;
                case Tab.Metrics: DrawOverview(); break;
                case Tab.LiveEvents: DrawLiveEvents(); break;
                case Tab.Settings: DrawSettings(); break;
            }
        });
        imgui.style.flexGrow = 1;
        _tabContentArea.Add(imgui);

        _root.Add(_tabContentArea);
    }

    private VisualElement BuildModernHeader()
    {
        var header = new VisualElement();
        header.style.flexDirection = FlexDirection.Column;
        header.style.backgroundColor = ExoforgeUIStyle.BgHeaderDark;
        header.style.borderBottomWidth = 1;
        header.style.borderBottomColor = ExoforgeUIStyle.BrandPurpleBorder;

        // --- ROW 1: BRAND MASTHEAD, ENV SELECTOR & CONNECTION (Height: 46px) ---
        var masthead = new VisualElement();
        masthead.style.height = 46;
        masthead.style.flexDirection = FlexDirection.Row;
        masthead.style.alignItems = Align.Center;
        masthead.style.justifyContent = Justify.SpaceBetween;
        masthead.style.paddingLeft = 16;
        masthead.style.paddingRight = 16;

        // Brand & Env Selector (Left)
        var brandContainer = new VisualElement();
        brandContainer.style.flexDirection = FlexDirection.Row;
        brandContainer.style.alignItems = Align.Center;
        brandContainer.style.flexShrink = 0;

        var logo = new Label("⚡ EXOFORGE");
        logo.style.fontSize = 15;
        logo.style.unityFontStyleAndWeight = FontStyle.Bold;
        logo.style.color = Color.white;
        logo.style.marginRight = 6;
        brandContainer.Add(logo);

        var studioBadge = ExoforgeUIStyle.CreatePill("STUDIO", Color.white, ExoforgeUIStyle.BrandPurple, 9);
        brandContainer.Add(studioBadge);

        var divider = new VisualElement();
        divider.style.width = 1;
        divider.style.height = 18;
        divider.style.backgroundColor = new Color(1f, 1f, 1f, 0.18f);
        divider.style.marginLeft = 10;
        divider.style.marginRight = 6;
        brandContainer.Add(divider);

        string envName = ActiveEnvironment?.Name ?? "default";
        var envDropdownBtn = ExoforgeUIStyle.CreateEnvSelector(envName, ShowEnvDropdown, out _envBadge);
        brandContainer.Add(envDropdownBtn);

        masthead.Add(brandContainer);

        // Status & Connect CTA (Right)
        var statusContainer = new VisualElement();
        statusContainer.style.flexDirection = FlexDirection.Row;
        statusContainer.style.alignItems = Align.Center;
        statusContainer.style.flexShrink = 0;

        var statusCapsule = new VisualElement();
        statusCapsule.style.flexDirection = FlexDirection.Row;
        statusCapsule.style.alignItems = Align.Center;
        statusCapsule.style.backgroundColor = new Color(0f, 0f, 0f, 0.35f);
        statusCapsule.style.borderTopWidth = 1;
        statusCapsule.style.borderBottomWidth = 1;
        statusCapsule.style.borderLeftWidth = 1;
        statusCapsule.style.borderRightWidth = 1;
        statusCapsule.style.borderTopColor = new Color(1f, 1f, 1f, 0.12f);
        statusCapsule.style.borderBottomColor = new Color(1f, 1f, 1f, 0.12f);
        statusCapsule.style.borderLeftColor = new Color(1f, 1f, 1f, 0.12f);
        statusCapsule.style.borderRightColor = new Color(1f, 1f, 1f, 0.12f);
        statusCapsule.style.borderTopLeftRadius = 14;
        statusCapsule.style.borderTopRightRadius = 14;
        statusCapsule.style.borderBottomLeftRadius = 14;
        statusCapsule.style.borderBottomRightRadius = 14;
        statusCapsule.style.paddingLeft = 10;
        statusCapsule.style.paddingRight = 10;
        statusCapsule.style.paddingTop = 4;
        statusCapsule.style.paddingBottom = 4;
        statusCapsule.style.marginRight = 8;

        Color dotColor = _isConnected ? ExoforgeUIStyle.AccentGreen : (_isConnecting ? ExoforgeUIStyle.AccentOrange : ExoforgeUIStyle.AccentGray);
        _connectionDot = ExoforgeUIStyle.CreateStatusDot(dotColor, 8f);
        statusCapsule.Add(_connectionDot);

        string statusText = _isConnected ? $"Online ({_connectionStatus})" : (_isConnecting ? "Connecting..." : "Offline");
        _connectionText = new Label(statusText);
        _connectionText.style.fontSize = 11;
        _connectionText.style.color = ExoforgeUIStyle.TextPrimary;
        statusCapsule.Add(_connectionText);

        _latencyPill = new Label(!string.IsNullOrEmpty(_connectionLatency) ? $" • {_connectionLatency}" : "");
        _latencyPill.style.fontSize = 10;
        _latencyPill.style.color = ExoforgeUIStyle.AccentGreen;
        statusCapsule.Add(_latencyPill);

        statusContainer.Add(statusCapsule);

        _connectBtn = ExoforgeUIStyle.CreateModernButton(
            _isConnected ? "Disconnect" : (_isConnecting ? "Retry" : "⚡ Connect"),
            () =>
            {
                if (_isConnected) _ = DisconnectAsync();
                else _ = ConnectAsync();
            },
            bg: _isConnected ? new Color(1f, 1f, 1f, 0.08f) : ExoforgeUIStyle.BrandPurple,
            textCol: Color.white,
            height: 28);
        statusContainer.Add(_connectBtn);

        masthead.Add(statusContainer);
        header.Add(masthead);

        // --- ROW 2: SUB-HEADER TOOLBAR (Height: 38px) ---
        var toolbar = new VisualElement();
        toolbar.style.height = 38;
        toolbar.style.backgroundColor = ExoforgeUIStyle.BgHeader;
        toolbar.style.borderTopWidth = 1;
        toolbar.style.borderTopColor = new Color(1f, 1f, 1f, 0.06f);
        toolbar.style.flexDirection = FlexDirection.Row;
        toolbar.style.alignItems = Align.Center;
        toolbar.style.justifyContent = Justify.SpaceBetween;
        toolbar.style.paddingLeft = 16;
        toolbar.style.paddingRight = 16;

        // Left: Endpoint & Ping
        var leftTools = new VisualElement();
        leftTools.style.flexDirection = FlexDirection.Row;
        leftTools.style.alignItems = Align.Center;
        leftTools.style.flexShrink = 1;
        leftTools.style.overflow = Overflow.Hidden;

        string wsUrl = ActiveWsUrl;
        _endpointLabel = new Label(!string.IsNullOrEmpty(wsUrl) ? $"WS: {wsUrl}" : "No WS endpoint");
        _endpointLabel.style.fontSize = 10;
        _endpointLabel.style.color = ExoforgeUIStyle.TextMuted;
        _endpointLabel.style.marginRight = 8;
        leftTools.Add(_endpointLabel);

        var pingBtn = ExoforgeUIStyle.CreateModernButton("🏓 Ping", () => _ = PingClusterAsync(), height: 22);
        pingBtn.style.paddingLeft = 8;
        pingBtn.style.paddingRight = 8;
        pingBtn.style.fontSize = 10;
        leftTools.Add(pingBtn);

        toolbar.Add(leftTools);

        // Right: Web-Like Action Buttons
        var actionsGroup = new VisualElement();
        actionsGroup.style.flexDirection = FlexDirection.Row;
        actionsGroup.style.alignItems = Align.Center;
        actionsGroup.style.flexShrink = 0;

        var syncBtn = ExoforgeUIStyle.CreateModernButton("🔄 Sync Client", () => _ = SyncAndGenerateClientAsync(), height: 26);
        actionsGroup.Add(syncBtn);

        var extensionsBtn = ExoforgeUIStyle.CreateModernButton("🔌 Extensions", () => ExoforgeExtensionsWindow.ShowWindow(), height: 26);
        actionsGroup.Add(extensionsBtn);

        var studioBtn = ExoforgeUIStyle.CreateModernButton("🌐 Web Studio ↗", () =>
        {
            string url = ActiveHttpEndpoint;
            if (!string.IsNullOrEmpty(url)) Application.OpenURL(url);
        }, height: 26);
        actionsGroup.Add(studioBtn);

        var authBtn = ExoforgeUIStyle.CreateModernButton("👤 Account", () =>
        {
            ExoforgeAccountModal.Open();
        }, height: 26);
        actionsGroup.Add(authBtn);

        toolbar.Add(actionsGroup);
        header.Add(toolbar);

        return header;
    }

    private void ShowEnvDropdown()
    {
        var menu = new GenericMenu();
        var envs = GetConfiguredEnvironments();
        string activeName = ActiveEnvironment?.Name ?? "default";

        if (envs.Count == 0)
        {
            menu.AddDisabledItem(new GUIContent("No environments configured in exoforge.json"));
        }
        else
        {
            foreach (var env in envs)
            {
                bool isCurrent = env.Name == activeName;
                menu.AddItem(new GUIContent($"{env.Name}  ({env.WsUrl})"), isCurrent, () =>
                {
                    ApplyEnvironment(env);
                });
            }
        }

        menu.AddSeparator("");
        menu.AddItem(new GUIContent("⚙ Configure Environments in Settings..."), false, () =>
        {
            _currentTab = Tab.Settings;
            UpdateTabButtonStyles();
            Repaint();
        });

        menu.ShowAsContext();
    }

    private VisualElement BuildModernTabStrip()
    {
        var strip = new VisualElement();
        strip.style.height = 36;
        strip.style.flexDirection = FlexDirection.Row;
        strip.style.alignItems = Align.Center;
        strip.style.backgroundColor = ExoforgeUIStyle.BgPanel;
        strip.style.borderBottomWidth = 1;
        strip.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
        strip.style.paddingLeft = 12;
        strip.style.paddingRight = 12;

        _tabButtons.Clear();

        var tabDefs = new (Tab Id, string Icon, string Label)[]
        {
            (Tab.Plugins, "🔌", "Extensions"),
            (Tab.Metrics, "📊", "Metrics"),
            (Tab.LiveEvents, "📡", "Event Stream"),
            (Tab.Settings, "⚙️", "Settings")
        };

        foreach (var def in tabDefs)
        {
            bool isActive = _currentTab == def.Id;
            var btn = new Button(() =>
            {
                _currentTab = def.Id;
                UpdateTabButtonStyles();
                Repaint();
            })
            { text = $"{def.Icon} {def.Label}" };

            btn.userData = def.Id;
            btn.style.height = 26;
            btn.style.borderTopWidth = 0;
            btn.style.borderBottomWidth = isActive ? 2 : 0;
            btn.style.borderLeftWidth = 0;
            btn.style.borderRightWidth = 0;
            btn.style.borderBottomColor = isActive ? ExoforgeUIStyle.BrandPurple : Color.clear;
            btn.style.backgroundColor = isActive ? ExoforgeUIStyle.BrandPurpleGlow : Color.clear;
            btn.style.color = isActive ? ExoforgeUIStyle.BrandPurpleLight : ExoforgeUIStyle.TextSecondary;
            btn.style.unityFontStyleAndWeight = isActive ? FontStyle.Bold : FontStyle.Normal;
            btn.style.borderTopLeftRadius = 6;
            btn.style.borderTopRightRadius = 6;
            btn.style.borderBottomLeftRadius = 0;
            btn.style.borderBottomRightRadius = 0;
            btn.style.paddingLeft = 14;
            btn.style.paddingRight = 14;
            btn.style.marginLeft = 2;
            btn.style.marginRight = 2;

            _tabButtons.Add(btn);
            strip.Add(btn);
        }

        return strip;
    }

    private void UpdateTabButtonStyles()
    {
        foreach (var btn in _tabButtons)
        {
            if (btn.userData is Tab tabId)
            {
                bool isActive = _currentTab == tabId;
                btn.style.borderBottomWidth = isActive ? 2 : 0;
                btn.style.borderBottomColor = isActive ? ExoforgeUIStyle.BrandPurple : Color.clear;
                btn.style.backgroundColor = isActive ? ExoforgeUIStyle.BrandPurpleGlow : Color.clear;
                btn.style.color = isActive ? ExoforgeUIStyle.BrandPurpleLight : ExoforgeUIStyle.TextSecondary;
                btn.style.unityFontStyleAndWeight = isActive ? FontStyle.Bold : FontStyle.Normal;
            }
        }
    }

    private void UpdateModernHeaderUI()
    {
        if (_connectionDot != null && _connectionText != null && _connectBtn != null)
        {
            Color dotColor = _isConnected ? ExoforgeUIStyle.AccentGreen : (_isConnecting ? ExoforgeUIStyle.AccentOrange : ExoforgeUIStyle.AccentGray);
            _connectionDot.style.backgroundColor = dotColor;
            _connectionText.text = _isConnected ? $"Online ({_connectionStatus})" : (_isConnecting ? "Connecting..." : "Offline");
            _connectBtn.text = _isConnected ? "Disconnect" : (_isConnecting ? "Retry" : "⚡ Connect");
        }

        if (_envBadge != null)
        {
            string envName = ActiveEnvironment?.Name ?? "default";
            _envBadge.text = envName;
        }

        if (_endpointLabel != null)
        {
            string wsUrl = ActiveWsUrl;
            _endpointLabel.text = !string.IsNullOrEmpty(wsUrl) ? $"WS: {wsUrl}" : "No WS endpoint";
        }

        if (_latencyPill != null)
        {
            _latencyPill.text = !string.IsNullOrEmpty(_connectionLatency) ? $" • {_connectionLatency}" : "";
        }
    }

    // =========================================================================
    // Header & Authentication
    // =========================================================================

    private void DrawHeader()
    {
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
            _currentTab = Tab.Plugins;
        }
        catch (Exception ex)
        {
            ShowStatus($"Scaffold failed: {ex.Message}", MessageType.Error);
        }
    }

    public sealed record EnvOption(string Name, string WsUrl, string Token, string? HttpUrl = null);

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
    public static List<EnvOption> GetConfiguredEnvironments()
    {
        var list = new List<EnvOption>();
        var ws = Instance?.Workspace ?? ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());

        if (ws?.Config?.Environments != null)
        {
            foreach (var kvp in ws.Config.Environments)
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
    public static EnvOption? ActiveEnvironment
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

    public static void ApplyEnvironment(EnvOption env)
    {
        ExoforgeEditorConfig.SelectedEnvironment = env.Name;
        Instance?.ShowStatus($"Switched to environment '{env.Name}' ({env.WsUrl}).", MessageType.Info);

        if (IsClusterConnected || IsConnecting)
        {
            if (Instance != null) _ = Instance.ConnectAsync();
            else _ = ConnectSharedAsync();
        }

        Instance?.UpdateModernHeaderUI();
        ExoforgePluginsWindow.Instance?.RebuildUI();
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

    private async Task SyncAndGenerateClientAsync(bool forceReload = false)
    {
        ShowStatus("Syncing contracts and generating strongly-typed C# client...", MessageType.Info);
        Repaint();

        try
        {
            string outputPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
            var deployer = new ExoDeployer(Workspace);
            int changedCount = 0;

            if (_isConnected && _editorClient != null)
            {
                changedCount = await deployer.SyncContractsAsync(
                    outputPathOverride: outputPath,
                    existingClient: _editorClient);
            }
            else
            {
                changedCount = await deployer.SyncContractsAsync(
                    environmentName: null,
                    outputPathOverride: outputPath);
            }

            ExoforgeRuntimeConfigGenerator.Generate();
            ExoforgeEditorConfig.LastSyncTime = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss 'UTC'");
            if (_rawConnected)
            {
                SessionState.SetBool(WasConnectedSessionKey, true);
            }

            if (changedCount > 0 || !File.Exists(outputPath) || forceReload)
            {
                AssetDatabase.Refresh();
                ShowStatus($"✓ Strongly-typed C# client updated at {ExoforgeEditorConfig.GeneratedScriptPath}", MessageType.Info);
            }
            else
            {
                ShowStatus("✓ C# client bindings are already up-to-date (skipped reload).", MessageType.Info);
            }
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
