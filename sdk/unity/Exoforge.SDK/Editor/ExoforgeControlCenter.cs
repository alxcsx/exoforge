using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Time;
using Exoforge.Management;

#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
#endif

namespace Exoforge.Unity.Editor;

#if UNITY_EDITOR
/// <summary>
/// GameDev-first Unity Editor Studio for Exoforge.
/// Provides one-click client code generation, live event streaming monitor,
/// in-engine RPC action sandbox, C# WASM plugin management, and LiveOps schedule inspection.
/// </summary>
public class ExoforgeControlCenter : EditorWindow
{
    private enum Tab
    {
        Overview = 0,
        LiveEvents = 1,
        ActionSandbox = 2,
        Plugins = 3,
        Schedule = 4,
        Settings = 5
    }

    private Tab _currentTab = Tab.Overview;
    private readonly string[] _tabNames =
    {
        "⚡ Overview",
        "📡 Live Events",
        "🧪 Action Sandbox",
        "📦 Plugins & WASM",
        "📅 LiveOps & Schedules",
        "⚙️ Settings"
    };

    // Connection & Telemetry
    private ExoClient? _editorClient;
    private bool _isConnected = false;
    private string _connectionStatus = "Disconnected";
    private long _lastPingMs = -1;
    private string _nodeName = "—";
    private string _uptime = "—";
    private string _memoryMb = "—";
    private int _activeEntities = 0;
    private int _pluginsCount = 0;

    // Status Banner
    private string _statusMessage = "";
    private MessageType _statusMessageType = MessageType.Info;

    // Live Event Monitor
    public record LoggedEvent(DateTime Timestamp, string Topic, string EventName, string RawJson);
    private readonly List<LoggedEvent> _eventLog = new();
    private bool _isEventStreamPaused = false;
    private string _eventSearchFilter = "";
    private Vector2 _eventScroll;
    private LoggedEvent? _selectedEvent;

    // Action Sandbox
    private string _sandboxService = "combat_wasm";
    private string _sandboxAction = "attack";
    private string _sandboxPayloadJson = "{\n  \"target_player_id\": \"boss_demon_1\",\n  \"damage\": 25\n}";
    private string _sandboxResult = "";
    private string _sandboxResultLatency = "";
    private bool _sandboxResultSuccess = true;
    private Vector2 _sandboxResultScroll;

    // Plugins & WASM
    private string _newPluginName = "";
    private int _scaffoldTemplateIndex = 0;
    private readonly string[] _scaffoldTemplates = { "Standard Service", "Player Inventory", "Custom LiveOps Event" };
    private List<LocalPluginInfo> _localPlugins = new();
    private List<JsonElement> _remotePlugins = new();
    private Vector2 _pluginsScroll;
    private Vector2 _remoteScroll;

    // LiveOps Schedules
    private List<ExoTimeWindow> _liveopsWindows = new();
    private Vector2 _scheduleScroll;

    // Scroll positions
    private Vector2 _mainScroll;

    public record LocalPluginInfo(string Name, string DirectoryPath, bool HasWasm, string WasmPath, long WasmSizeBytes);

    [MenuItem("Window/Exoforge/Control Center", false, 2000)]
    public static void ShowWindow()
    {
        var window = GetWindow<ExoforgeControlCenter>("Exoforge Studio");
        window.minSize = new Vector2(620, 520);
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
            // Allow manual connect
        }
    }

    private async Task ConnectAsync()
    {
        _connectionStatus = "Connecting...";
        Repaint();

        var sw = Stopwatch.StartNew();
        try
        {
            _editorClient?.Dispose();
            _editorClient = new ExoClient();

            // Wire up real-time event streaming monitor
            _editorClient.OnAnyEvent += HandleIncomingEvent;

            var uri = new Uri(ExoforgeEditorConfig.ServerUrl);
            await _editorClient.ConnectAsync(uri);

            var authResult = await _editorClient.AuthenticateAsync(ExoforgeEditorConfig.AdminToken);
            sw.Stop();
            _lastPingMs = sw.ElapsedMilliseconds;

            if (authResult.Success)
            {
                _isConnected = true;
                _connectionStatus = $"Connected ({authResult.PlayerId})";

                if (!ExoforgeEditorConfig.ServerUrl.Contains("localhost") && !ExoforgeEditorConfig.ServerUrl.Contains("127.0.0.1") && ExoforgeEditorConfig.AdminToken.StartsWith("dev:"))
                {
                    ShowStatus("Security Warning: 'dev:*' token used with remote server! Dev tokens are disabled on production clusters.", MessageType.Warning);
                }
                else
                {
                    ShowStatus($"Connected to Exoforge server ({_lastPingMs} ms).", MessageType.Info);
                }

                // Auto-subscribe to all events for the live event monitor
                await _editorClient.SubscribeAsync("*");
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
            sw.Stop();
            _isConnected = false;
            _lastPingMs = -1;
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
        _lastPingMs = -1;
        Repaint();
    }

    private void HandleIncomingEvent(ExoEventFrame evt)
    {
        if (_isEventStreamPaused) return;

        string rawJson;
        try
        {
            rawJson = JsonSerializer.Serialize(evt.Payload, new JsonSerializerOptions { WriteIndented = true });
        }
        catch
        {
            rawJson = evt.Payload.ToString() ?? "{}";
        }

        var logged = new LoggedEvent(DateTime.UtcNow, evt.Topic, evt.Event, rawJson);
        _eventLog.Insert(0, logged);

        // Keep buffer bounded
        if (_eventLog.Count > 150)
        {
            _eventLog.RemoveAt(_eventLog.Count - 1);
        }

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

            // Refresh LiveOps schedules
            RefreshSchedules();
        }
        catch (Exception ex)
        {
            ShowStatus($"Failed to refresh remote cluster telemetry: {ex.Message}", MessageType.Warning);
        }

        Repaint();
    }

    private void RefreshSchedules()
    {
        _liveopsWindows.Clear();
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
                long wasmSize = 0;

                if (!hasWasm)
                {
                    var wasmFiles = Directory.GetFiles(dir, "*.wasm");
                    if (wasmFiles.Length > 0)
                    {
                        hasWasm = true;
                        wasmPath = wasmFiles[0];
                    }
                }

                if (hasWasm && File.Exists(wasmPath))
                {
                    wasmSize = new FileInfo(wasmPath).Length;
                }

                _localPlugins.Add(new LocalPluginInfo(name, dir, hasWasm, wasmPath, wasmSize));
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
        DrawModernHeader();

        EditorGUILayout.Space(2);
        _currentTab = (Tab)GUILayout.Toolbar((int)_currentTab, _tabNames, GUILayout.Height(28));
        EditorGUILayout.Space(6);

        if (!string.IsNullOrEmpty(_statusMessage))
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.HelpBox(_statusMessage, _statusMessageType);
            if (GUILayout.Button("✕", GUILayout.Width(24), GUILayout.Height(38)))
            {
                _statusMessage = "";
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.Space(4);
        }

        switch (_currentTab)
        {
            case Tab.Overview:
                DrawOverviewTab();
                break;
            case Tab.LiveEvents:
                DrawLiveEventsTab();
                break;
            case Tab.ActionSandbox:
                DrawActionSandboxTab();
                break;
            case Tab.Plugins:
                DrawPluginsTab();
                break;
            case Tab.Schedule:
                DrawScheduleTab();
                break;
            case Tab.Settings:
                DrawSettingsTab();
                break;
        }
    }

    private void DrawModernHeader()
    {
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        // Line 1: Title, Ping Badge, Connect/Disconnect Button
        EditorGUILayout.BeginHorizontal();

        GUIStyle titleStyle = new GUIStyle(EditorStyles.boldLabel)
        {
            fontSize = 14,
            normal = { textColor = new Color(0.6f, 0.4f, 0.95f) }
        };
        GUILayout.Label("⚡ EXOFORGE CONTROL CENTER", titleStyle);

        GUILayout.FlexibleSpace();

        // Ping latency badge
        if (_isConnected && _lastPingMs >= 0)
        {
            GUIStyle pingBadge = new GUIStyle(EditorStyles.miniLabel)
            {
                fontStyle = FontStyle.Bold,
                normal = { textColor = _lastPingMs < 50 ? new Color(0.2f, 0.8f, 0.4f) : new Color(0.9f, 0.7f, 0.2f) }
            };
            GUILayout.Label($"⚡ {_lastPingMs} ms", pingBadge);
            GUILayout.Space(8);
        }

        // Connection dot
        GUIStyle statusBadge = new GUIStyle(EditorStyles.miniLabel)
        {
            fontStyle = FontStyle.Bold,
            normal = { textColor = _isConnected ? new Color(0.2f, 0.85f, 0.35f) : new Color(0.85f, 0.3f, 0.25f) }
        };
        GUILayout.Label(_isConnected ? "● ONLINE" : "○ OFFLINE", statusBadge);

        GUILayout.Space(6);

        if (_isConnected)
        {
            if (GUILayout.Button("Disconnect", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                _ = DisconnectAsync();
            }
        }
        else
        {
            if (GUILayout.Button("Connect", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                _ = ConnectAsync();
            }
        }

        EditorGUILayout.EndHorizontal();

        // Line 2: Environment Quick Switcher Pills
        EditorGUILayout.BeginHorizontal();
        GUILayout.Label("Env:", EditorStyles.miniLabel, GUILayout.Width(30));

        foreach (var (name, url) in ExoforgeEditorConfig.EnvironmentPresets)
        {
            bool isCurrent = ExoforgeEditorConfig.ServerUrl == url;
            GUIStyle btnStyle = new GUIStyle(EditorStyles.miniButton)
            {
                fontStyle = isCurrent ? FontStyle.Bold : FontStyle.Normal
            };

            if (GUILayout.Button(name, btnStyle))
            {
                ExoforgeEditorConfig.ServerUrl = url;
                _ = ConnectAsync();
            }
        }

        GUILayout.FlexibleSpace();

        // Token quick switcher
        GUILayout.Label("Role:", EditorStyles.miniLabel, GUILayout.Width(32));
        foreach (var (label, token) in ExoforgeEditorConfig.TokenPresets)
        {
            bool isCurrent = ExoforgeEditorConfig.AdminToken == token;
            GUIStyle btnStyle = new GUIStyle(EditorStyles.miniButton)
            {
                fontStyle = isCurrent ? FontStyle.Bold : FontStyle.Normal
            };

            if (GUILayout.Button(label, btnStyle))
            {
                ExoforgeEditorConfig.AdminToken = token;
                if (_isConnected)
                {
                    _ = ConnectAsync();
                }
            }
        }

        EditorGUILayout.EndHorizontal();

        EditorGUILayout.LabelField($"{ExoforgeEditorConfig.ServerUrl}  •  {_connectionStatus}", EditorStyles.miniLabel);

        EditorGUILayout.EndVertical();
    }

    private void DrawOverviewTab()
    {
        _mainScroll = EditorGUILayout.BeginScrollView(_mainScroll);

        // Metric Cards Grid
        EditorGUILayout.LabelField("Server Telemetry & Node Status", EditorStyles.boldLabel);
        EditorGUILayout.BeginHorizontal();

        DrawMetricCard("Cluster Node", _nodeName, "BEAM Core");
        DrawMetricCard("Uptime", _uptime, "Supervised");
        DrawMetricCard("Memory", _memoryMb, "BEAM Process");
        DrawMetricCard("Virtual Entities", _activeEntities.ToString(), "Horde Clustered");
        DrawMetricCard("Active Plugins", _pluginsCount.ToString(), "Standard & Custom");

        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(12);

        // Golden Path Actions
        EditorGUILayout.LabelField("Quick Actions & Golden Path", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        GUI.enabled = _isConnected;
        if (GUILayout.Button("⚡ Sync Contracts & Generate C# API", GUILayout.Height(36)))
        {
            _ = SyncAndGenerateClientAsync();
        }
        GUI.enabled = true;

        if (GUILayout.Button("🌐 Open Producer Studio (Port 4005)", GUILayout.Height(36)))
        {
            Application.OpenURL("http://localhost:4005");
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(4);

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("🎮 Load CombatDemo Scene", GUILayout.Height(28)))
        {
            OpenSampleScene();
        }

        GUI.enabled = _isConnected;
        if (GUILayout.Button("🔄 Hot-Restart Server Supervision", GUILayout.Height(28)))
        {
            _ = RestartClusterAsync();
        }
        GUI.enabled = true;
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(12);

        // Getting Started Gamedev Checklist
        EditorGUILayout.LabelField("Game Developer Golden Path Checklist", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        DrawChecklistRow("1. Connect to Exoforge Cluster", _isConnected, "Connect button in top header bar.");
        DrawChecklistRow("2. Scaffold Game Service Plugin", _localPlugins.Count > 0, "Use the 'Plugins & WASM' tab to create C# WASM logic.");
        DrawChecklistRow("3. Generate Strongly-Typed C# API", File.Exists(ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath()), "Click 'Sync Contracts' to generate pure C# client bindings.");
        DrawChecklistRow("4. Listen to Live Cluster Events", _eventLog.Count > 0, "Monitor real-time event broadcasts in the 'Live Events' tab.");

        EditorGUILayout.EndVertical();

        EditorGUILayout.EndScrollView();
    }

    private void DrawMetricCard(string title, string value, string subtitle)
    {
        EditorGUILayout.BeginVertical(EditorStyles.helpBox, GUILayout.Width(110), GUILayout.Height(64));
        EditorGUILayout.LabelField(title.ToUpperInvariant(), EditorStyles.miniLabel);
        GUIStyle valStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 13 };
        EditorGUILayout.LabelField(value, valStyle);
        EditorGUILayout.LabelField(subtitle, EditorStyles.miniLabel);
        EditorGUILayout.EndVertical();
    }

    private void DrawChecklistRow(string title, bool isDone, string hint)
    {
        EditorGUILayout.BeginHorizontal();
        GUIStyle markStyle = new GUIStyle(EditorStyles.boldLabel)
        {
            normal = { textColor = isDone ? new Color(0.2f, 0.8f, 0.3f) : new Color(0.5f, 0.5f, 0.5f) }
        };
        GUILayout.Label(isDone ? "✔" : "○", markStyle, GUILayout.Width(20));
        EditorGUILayout.LabelField(title, EditorStyles.boldLabel, GUILayout.Width(230));
        EditorGUILayout.LabelField(hint, EditorStyles.miniLabel);
        EditorGUILayout.EndHorizontal();
    }

    private void DrawLiveEventsTab()
    {
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Live Cluster Event Stream ({_eventLog.Count})", EditorStyles.boldLabel);

        _eventSearchFilter = EditorGUILayout.TextField(_eventSearchFilter, EditorStyles.toolbarSearchField, GUILayout.Width(180));

        if (GUILayout.Button(_isEventStreamPaused ? "▶ Resume" : "⏸ Pause", EditorStyles.miniButton, GUILayout.Width(75)))
        {
            _isEventStreamPaused = !_isEventStreamPaused;
        }

        if (GUILayout.Button("Clear", EditorStyles.miniButton, GUILayout.Width(55)))
        {
            _eventLog.Clear();
            _selectedEvent = null;
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(4);

        // Event List
        _eventScroll = EditorGUILayout.BeginScrollView(_eventScroll, GUILayout.Height(200));
        var filteredEvents = string.IsNullOrWhiteSpace(_eventSearchFilter)
            ? _eventLog
            : _eventLog.Where(e => e.Topic.Contains(_eventSearchFilter, StringComparison.OrdinalIgnoreCase) ||
                                   e.EventName.Contains(_eventSearchFilter, StringComparison.OrdinalIgnoreCase)).ToList();

        if (filteredEvents.Count == 0)
        {
            EditorGUILayout.HelpBox(_isConnected
                ? "Waiting for broadcast events from Exoforge backend (e.g., combat:damage_dealt, player:updated)..."
                : "Connect to cluster to monitor live events.", MessageType.None);
        }
        else
        {
            foreach (var evt in filteredEvents)
            {
                bool isSelected = _selectedEvent == evt;
                EditorGUILayout.BeginHorizontal(isSelected ? EditorStyles.selectionRect : EditorStyles.helpBox);

                GUILayout.Label("📡", GUILayout.Width(20));
                EditorGUILayout.LabelField(evt.Timestamp.ToString("HH:mm:ss.fff"), EditorStyles.miniLabel, GUILayout.Width(75));
                EditorGUILayout.LabelField(evt.Topic, EditorStyles.boldLabel, GUILayout.Width(130));
                EditorGUILayout.LabelField(evt.EventName, EditorStyles.label, GUILayout.Width(150));

                GUILayout.FlexibleSpace();

                if (GUILayout.Button("Inspect", EditorStyles.miniButton, GUILayout.Width(65)))
                {
                    _selectedEvent = evt;
                }

                EditorGUILayout.EndHorizontal();
            }
        }
        EditorGUILayout.EndScrollView();

        EditorGUILayout.Space(6);

        // JSON Inspector Box
        EditorGUILayout.LabelField("Event Payload JSON Inspector", EditorStyles.boldLabel);
        if (_selectedEvent != null)
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField($"{_selectedEvent.Topic} -> {_selectedEvent.EventName}", EditorStyles.miniBoldLabel);
            if (GUILayout.Button("Copy JSON", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                GUIUtility.systemCopyBuffer = _selectedEvent.RawJson;
                ShowStatus("Copied event JSON to clipboard!", MessageType.Info);
            }
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.TextArea(_selectedEvent.RawJson, GUILayout.Height(120));
        }
        else
        {
            EditorGUILayout.HelpBox("Select an event above to inspect its JSON payload.", MessageType.None);
        }
    }

    private void DrawActionSandboxTab()
    {
        EditorGUILayout.LabelField("In-Engine RPC Action Runner", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Dispatch typed actions directly to the Exoforge Kernel and measure server latency in milliseconds without leaving Unity.", MessageType.Info);

        EditorGUILayout.Space(6);

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Service Atom:", GUILayout.Width(110));
        _sandboxService = EditorGUILayout.TextField(_sandboxService);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Action Name:", GUILayout.Width(110));
        _sandboxAction = EditorGUILayout.TextField(_sandboxAction);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("JSON Payload:");
        _sandboxPayloadJson = EditorGUILayout.TextArea(_sandboxPayloadJson, GUILayout.Height(80));

        EditorGUILayout.Space(6);

        // Payload Preset Templates
        EditorGUILayout.BeginHorizontal();
        GUILayout.Label("Presets:", EditorStyles.miniLabel, GUILayout.Width(50));
        if (GUILayout.Button("Combat Attack", EditorStyles.miniButton))
        {
            _sandboxService = "combat_wasm";
            _sandboxAction = "attack";
            _sandboxPayloadJson = "{\n  \"target_player_id\": \"goblin_boss\",\n  \"damage\": 30\n}";
        }
        if (GUILayout.Button("Player Profile", EditorStyles.miniButton))
        {
            _sandboxService = "player_data";
            _sandboxAction = "get_profile";
            _sandboxPayloadJson = "{\n  \"player_id\": \"player_1\"\n}";
        }
        if (GUILayout.Button("DB Health", EditorStyles.miniButton))
        {
            _sandboxService = "lldb";
            _sandboxAction = "health_check";
            _sandboxPayloadJson = "{}";
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(8);

        GUI.enabled = _isConnected;
        if (GUILayout.Button("⚡ Dispatch Action Request", GUILayout.Height(32)))
        {
            _ = DispatchSandboxActionAsync();
        }
        GUI.enabled = true;

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Action Result Box
        if (!string.IsNullOrEmpty(_sandboxResult))
        {
            EditorGUILayout.BeginHorizontal();
            GUIStyle resStyle = new GUIStyle(EditorStyles.boldLabel)
            {
                normal = { textColor = _sandboxResultSuccess ? new Color(0.2f, 0.8f, 0.3f) : new Color(0.8f, 0.3f, 0.2f) }
            };
            GUILayout.Label(_sandboxResultSuccess ? "✔ ACTION SUCCEEDED" : "✖ ACTION FAILED", resStyle);
            GUILayout.FlexibleSpace();
            GUILayout.Label(_sandboxResultLatency, EditorStyles.miniBoldLabel);
            EditorGUILayout.EndHorizontal();

            _sandboxResultScroll = EditorGUILayout.BeginScrollView(_sandboxResultScroll, GUILayout.Height(100));
            EditorGUILayout.TextArea(_sandboxResult);
            EditorGUILayout.EndScrollView();
        }
    }

    private async Task DispatchSandboxActionAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        var sw = Stopwatch.StartNew();
        try
        {
            object? payload = null;
            if (!string.IsNullOrWhiteSpace(_sandboxPayloadJson))
            {
                payload = JsonDocument.Parse(_sandboxPayloadJson).RootElement;
            }

            var result = await _editorClient.SendActionAsync<JsonElement>(_sandboxService, _sandboxAction, payload);
            sw.Stop();
            double micros = (sw.ElapsedTicks / (double)System.Diagnostics.Stopwatch.Frequency) * 1_000_000.0;
            _sandboxResultLatency = $"⚡ {sw.ElapsedMilliseconds} ms ({micros:F0} µs)";
            _sandboxResultSuccess = true;
            _sandboxResult = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            sw.Stop();
            _sandboxResultLatency = $"⚡ {sw.ElapsedMilliseconds} ms";
            _sandboxResultSuccess = false;
            _sandboxResult = $"Error: {ex.Message}";
        }

        Repaint();
    }

    private void DrawPluginsTab()
    {
        string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
        bool wsExists = ExoWorkspace.Exists(wsPath);

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
        EditorGUILayout.LabelField("Scaffold New C# WASM Plugin", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Plugin Name:", GUILayout.Width(90));
        _newPluginName = EditorGUILayout.TextField(_newPluginName);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Template:", GUILayout.Width(90));
        _scaffoldTemplateIndex = EditorGUILayout.Popup(_scaffoldTemplateIndex, _scaffoldTemplates);

        if (GUILayout.Button("+ Scaffold Plugin", GUILayout.Width(140)))
        {
            ScaffoldPluginAction(wsPath);
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // Local Plugins List
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Local Custom Plugins ({_localPlugins.Count})", EditorStyles.boldLabel);
        if (GUILayout.Button("Refresh Local", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            RefreshLocalPlugins();
        }
        EditorGUILayout.EndHorizontal();

        _pluginsScroll = EditorGUILayout.BeginScrollView(_pluginsScroll, GUILayout.Height(130));
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
                    string sizeKb = $"{plugin.WasmSizeBytes / 1024.0:F1} KB";
                    GUILayout.Label($"WASM ({sizeKb})", wasmStyle, GUILayout.Width(90));
                }
                else
                {
                    GUILayout.Label("Not Compiled", EditorStyles.miniLabel, GUILayout.Width(90));
                }

                GUILayout.FlexibleSpace();

                GUI.enabled = _isConnected && plugin.HasWasm;
                if (GUILayout.Button("Push to Server", EditorStyles.miniButton, GUILayout.Width(100)))
                {
                    _ = DeployLocalPluginAsync(plugin);
                }
                GUI.enabled = true;

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
        EditorGUILayout.LabelField($"Installed Remote Plugins ({_remotePlugins.Count})", EditorStyles.boldLabel);
        if (GUILayout.Button("Refresh Server", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            _ = RefreshRemoteInfoAsync();
        }
        EditorGUILayout.EndHorizontal();

        _remoteScroll = EditorGUILayout.BeginScrollView(_remoteScroll, GUILayout.Height(110));
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

    private void ScaffoldPluginAction(string wsPath)
    {
        if (string.IsNullOrWhiteSpace(_newPluginName))
        {
            ShowStatus("Please enter a valid plugin name.", MessageType.Error);
            return;
        }

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

    private void DrawScheduleTab()
    {
        EditorGUILayout.LabelField("LiveOps Schedules & Event Timelines", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Exoforge provides built-in time constructs for game developers to build custom seasonal events, scheduled maintenance, and timed loot tables without opinionated boilerplate.", MessageType.Info);

        _scheduleScroll = EditorGUILayout.BeginScrollView(_scheduleScroll);

        if (_liveopsWindows.Count == 0)
        {
            EditorGUILayout.HelpBox("No active or scheduled LiveOps events currently loaded from cluster.\n\nUse the golden-path template below to scaffold a custom C# WASM LiveOps plugin with [ExoResource(..., Drawer = \"schedule\")] and full calendar support.", MessageType.Info);
            EditorGUILayout.Space(8);
            if (GUILayout.Button("+ Scaffold Custom LiveOps Event Plugin Template", GUILayout.Height(32)))
            {
                _currentTab = Tab.Plugins;
                _newPluginName = "liveops_events";
                _scaffoldTemplateIndex = 2; // "Custom LiveOps Event"
            }
        }
        else
        {
            foreach (var window in _liveopsWindows)
            {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.BeginHorizontal();
            GUIStyle titleStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 12 };
            GUILayout.Label(window.Title, titleStyle);

            if (window.Recurrence != "none")
            {
                GUIStyle recStyle = new GUIStyle(EditorStyles.miniLabel)
                {
                    normal = { textColor = new Color(0.6f, 0.4f, 0.95f) }
                };
                GUILayout.Label($"[{window.Recurrence.ToUpperInvariant()}]", recStyle);
            }

            GUILayout.FlexibleSpace();

            bool isActive = window.EvaluateIsActive();
            GUIStyle statusStyle = new GUIStyle(EditorStyles.miniBoldLabel)
            {
                normal = { textColor = isActive ? new Color(0.2f, 0.8f, 0.3f) : new Color(0.3f, 0.6f, 0.9f) }
            };
            GUILayout.Label(isActive ? "● ACTIVE NOW" : "○ UPCOMING", statusStyle);
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(2);
            EditorGUILayout.LabelField($"ID: {window.Id}  •  Remaining: {window.CountdownText}", EditorStyles.miniLabel);

            // Progress bar
            if (isActive && window.Progress > 0)
            {
                Rect r = EditorGUILayout.GetControlRect(false, 6);
                EditorGUI.ProgressBar(r, (float)window.Progress, "");
            }

            EditorGUILayout.EndVertical();
            EditorGUILayout.Space(4);
        }
        EditorGUILayout.EndScrollView();
    }

    private void DrawSettingsTab()
    {
        EditorGUILayout.LabelField("Studio Preferences & Paths", EditorStyles.boldLabel);

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField("WebSocket Server URL:");
        ExoforgeEditorConfig.ServerUrl = EditorGUILayout.TextField(ExoforgeEditorConfig.ServerUrl);

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("Admin Bearer Token / Role:");
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

    private async Task RestartClusterAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        if (EditorUtility.DisplayDialog("Restart Cluster", "Hot-reload all plugin supervision trees on remote server?", "Restart", "Cancel"))
        {
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
    }

    private void OpenSampleScene()
    {
        string samplePath = "Packages/com.exoforge.sdk/Samples~/CombatDemo";
        if (Directory.Exists(samplePath))
        {
            EditorUtility.RevealInFinder(samplePath);
        }
        else
        {
            ShowStatus("CombatDemo sample files located in Samples~/CombatDemo", MessageType.Info);
        }
    }
}
#endif
