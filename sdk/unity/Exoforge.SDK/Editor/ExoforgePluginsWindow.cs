using System;
using System.Collections.Generic;
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
    /// <summary>
    /// Dedicated Editor Window for Exoforge Plugins.
    /// Provides listing of local/remote plugins, automatic visualization of Resources, Actions, Events,
    /// and Webhooks, and seamlessly hosts custom engine editor UI hooks (IExoforgePluginCustomEditor).
    /// </summary>
    public class ExoforgePluginsWindow : EditorWindow
    {
        private Vector2 _sidebarScroll;
        private Vector2 _detailScroll;
        private string _searchFilter = "";
        private string? _selectedPluginId;

        // Custom editor hooks discovered in loaded assemblies
        private static List<IExoforgePluginCustomEditor>? _cachedHooks;
        private int _selectedDetailTab = 0; // 0: Overview & Declarations, 1: Resources, 2: Actions, 3: Events, 4: Webhooks, 5+: Custom Editor hooks

        // Data caches
        private List<PluginCardModel> _plugins = new();
        private Dictionary<string, JsonElement> _pluginManifests = new();
        private bool _isLoading;

        private sealed class PluginCardModel
        {
            public string Id { get; set; } = "";
            public string Name { get; set; } = "";
            public string Version { get; set; } = "";
            public string Type { get; set; } = "native";
            public string Category { get; set; } = "Extension";
            public string Title { get; set; } = "";
            public string Icon { get; set; } = "🧩";
            public bool IsLocal { get; set; }
            public bool IsDeployed { get; set; }
            public bool IsBuilt { get; set; }
            public bool Modified { get; set; }
            public string LocalDirectory { get; set; } = "";
        }

        public static ExoforgePluginsWindow? Instance { get; private set; }
        private bool _lastConnected;

        [MenuItem("Tools/Exoforge/Plugins", false, 101)]
        [MenuItem("Window/Exoforge/Plugins", false, 2001)]
        public static void ShowWindow()
        {
            var window = GetWindow<ExoforgePluginsWindow>("Exoforge Plugins");
            window.minSize = new Vector2(700, 480);
            window.Show();
        }

        public static void OpenPlugin(string pluginId, bool preferCustomEditor = true)
        {
            var window = GetWindow<ExoforgePluginsWindow>("Exoforge Plugins");
            window.minSize = new Vector2(700, 480);
            window._selectedPluginId = pluginId;
            var hooks = GetCustomEditorsForPlugin(pluginId);
            if (preferCustomEditor && hooks.Count > 0)
            {
                window._selectedDetailTab = 5;
            }
            else
            {
                window._selectedDetailTab = 0;
            }
            window.Show();
            window.Focus();
            window.Repaint();
        }

        private void OnEnable()
        {
            Instance = this;
            InvalidateHooksCache();
            EnsureLocalPluginPackagesRegistered();
            EditorApplication.update += OnEditorUpdate;
            _lastConnected = IsConnected;
            _ = RefreshPluginsDataAsync();
        }

        private void OnDisable()
        {
            if (Instance == this) Instance = null;
            EditorApplication.update -= OnEditorUpdate;
        }

        private void OnDestroy()
        {
            if (Instance == this) Instance = null;
            EditorApplication.update -= OnEditorUpdate;

            if (!ExoforgeControlCenter.HasAnyExoforgeWindowsOpen())
            {
                _ = ExoforgeControlCenter.DisconnectSharedAsync();
            }
        }

        private void OnEditorUpdate()
        {
            bool connected = IsConnected;
            if (connected != _lastConnected)
            {
                _lastConnected = connected;
                Repaint();
                if (connected)
                {
                    _ = RefreshPluginsDataAsync();
                }
            }
        }

        public static void EnsureLocalPluginPackagesRegistered()
        {
            try
            {
                string projectPath = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                string manifestPath = Path.Combine(projectPath, "Packages", "manifest.json");
                if (!File.Exists(manifestPath)) return;

                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                var ws = ExoWorkspace.Load(wsPath);
                if (!Directory.Exists(ws.PluginsPath)) return;

                string manifestText = File.ReadAllText(manifestPath);
                using var doc = JsonDocument.Parse(manifestText);
                var root = doc.RootElement;
                if (!root.TryGetProperty("dependencies", out var depsElement)) return;

                var deps = new Dictionary<string, string>();
                foreach (var prop in depsElement.EnumerateObject())
                {
                    deps[prop.Name] = prop.Value.GetString() ?? "";
                }

                bool modified = false;
                foreach (var dir in Directory.GetDirectories(ws.PluginsPath))
                {
                    string unityPkgJsonPath = Path.Combine(dir, "unity", "package.json");
                    string pkgJsonPath = File.Exists(unityPkgJsonPath) ? unityPkgJsonPath : Path.Combine(dir, "package.json");

                    if (File.Exists(pkgJsonPath))
                    {
                        try
                        {
                            var pkgDoc = JsonDocument.Parse(File.ReadAllText(pkgJsonPath));
                            if (pkgDoc.RootElement.TryGetProperty("name", out var nameProp))
                            {
                                string pkgName = nameProp.GetString() ?? "";
                                if (!string.IsNullOrEmpty(pkgName) && !deps.ContainsKey(pkgName))
                                {
                                    string packagesDir = Path.Combine(projectPath, "Packages");
                                    string targetDir = File.Exists(unityPkgJsonPath) ? Path.Combine(dir, "unity") : dir;
                                    string rel = Path.GetRelativePath(packagesDir, targetDir).Replace('\\', '/');
                                    deps[pkgName] = $"file:{rel}";
                                    modified = true;
                                }
                            }
                        }
                        catch { }
                    }
                }

                if (modified)
                {
                    var options = new JsonSerializerOptions { WriteIndented = true };
                    var newRoot = new Dictionary<string, object>
                    {
                        ["dependencies"] = deps
                    };
                    File.WriteAllText(manifestPath, JsonSerializer.Serialize(newRoot, options));
                    AssetDatabase.Refresh();
                }
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Failed to register local plugin packages: {ex.Message}");
            }
        }

        private static void InvalidateHooksCache()
        {
            _cachedHooks = null;
        }

        private static List<IExoforgePluginCustomEditor> GetCustomEditorsForPlugin(string pluginId)
        {
            if (_cachedHooks == null)
            {
                _cachedHooks = new List<IExoforgePluginCustomEditor>();
                var types = TypeCache.GetTypesDerivedFrom<IExoforgePluginCustomEditor>().ToList();

                if (types.Count == 0)
                {
#pragma warning disable UAC0005
                    // Fallback to AppDomain scan in case TypeCache is building or bypassed
                    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
                    {
                        try
                        {
                            foreach (var t in asm.GetTypes())
                            {
                                if (!t.IsAbstract && !t.IsInterface && typeof(IExoforgePluginCustomEditor).IsAssignableFrom(t))
                                {
                                    types.Add(t);
                                }
                            }
                        }
                        catch { }
                    }
#pragma warning restore UAC0005
                }

                foreach (var type in types)
                {
                    if (type.IsAbstract || type.IsInterface) continue;
                    try
                    {
                        if (Activator.CreateInstance(type) is IExoforgePluginCustomEditor editor)
                        {
                            if (!_cachedHooks.Any(e => e.GetType() == editor.GetType()))
                            {
                                _cachedHooks.Add(editor);
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Debug.LogWarning($"[Exoforge Plugins] Failed to instantiate custom editor '{type.FullName}': {ex.Message}");
                    }
                }
            }

            return _cachedHooks
                .Where(h => string.Equals(h.PluginId, pluginId, StringComparison.OrdinalIgnoreCase))
                .OrderBy(h => h.Priority)
                .ToList();
        }

        private static ExoClient? GetClient()
        {
            return ExoforgeControlCenter.SharedClient;
        }

        private static bool IsConnected => ExoforgeControlCenter.IsClusterConnected;

        private static string GetHttpUrl()
        {
            return ExoforgeControlCenter.ActiveHttpEndpoint;
        }

        private async Task RefreshPluginsDataAsync()
        {
            _isLoading = true;
            Repaint();

            try
            {
                var list = new List<PluginCardModel>();
                var manifests = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);

                // 1. Scan local plugins in Workspace
                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                var ws = ExoWorkspace.Load(wsPath);

                if (Directory.Exists(ws.PluginsPath))
                {
                    foreach (var dir in Directory.GetDirectories(ws.PluginsPath))
                    {
                        string name = Path.GetFileName(dir);
                        string manifestPath = Path.Combine(dir, "manifest.json");

                        string title = name;
                        string category = "Extension";
                        string icon = "🧩";
                        string version = "1.0.0";
                        string type = "native";

                        if (File.Exists(manifestPath))
                        {
                            try
                            {
                                var json = File.ReadAllText(manifestPath);
                                var doc = JsonDocument.Parse(json);
                                var root = doc.RootElement.Clone();
                                manifests[name] = root;

                                if (root.TryGetProperty("version", out var v)) version = v.GetString() ?? version;
                                if (root.TryGetProperty("type", out var t)) type = t.GetString() ?? type;
                                if (root.TryGetProperty("category", out var c)) category = c.GetString() ?? category;
                                if (root.TryGetProperty("title", out var tit)) title = tit.GetString() ?? title;
                                if (root.TryGetProperty("icon", out var ic)) icon = ic.GetString() ?? icon;
                            }
                            catch { }
                        }

                        string stagedBin = ExoDeployer.StagedBinary(dir, name);
                        bool isBuilt = !string.IsNullOrEmpty(stagedBin) && File.Exists(stagedBin);

                        bool modified = false;
                        if (isBuilt)
                        {
                            string? builtVer = ExoDeployer.ReadManifestVersion(dir);
                            string fingerprint = ExoDeployer.ComputeSourceFingerprint(dir);
                            modified = builtVer == null || !builtVer.EndsWith("." + fingerprint, StringComparison.Ordinal);
                        }

                        list.Add(new PluginCardModel
                        {
                            Id = name,
                            Name = name,
                            Version = version,
                            Type = type,
                            Category = category,
                            Title = title,
                            Icon = icon,
                            IsLocal = true,
                            IsBuilt = isBuilt,
                            Modified = modified,
                            LocalDirectory = dir
                        });
                    }
                }

                // 2. Fetch remote plugins and export from cluster if connected
                var client = GetClient();
                if (client != null && client.IsConnected)
                {
                    try
                    {
                        var exportRes = await client.SendActionAsync<JsonElement>("plugin_manager", "export_plugin_info", null);
                        if (exportRes.TryGetProperty("export", out var exp) && exp.TryGetProperty("plugins", out var pluginsArr))
                        {
                            foreach (var p in pluginsArr.EnumerateArray())
                            {
                                string pid = p.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
                                if (string.IsNullOrEmpty(pid)) continue;

                                manifests[pid] = p.Clone();

                                var existing = list.FirstOrDefault(item => string.Equals(item.Id, pid, StringComparison.OrdinalIgnoreCase));
                                if (existing != null)
                                {
                                    existing.IsDeployed = true;
                                    if (p.TryGetProperty("version", out var v)) existing.Version = v.GetString() ?? existing.Version;
                                    if (p.TryGetProperty("category", out var c)) existing.Category = c.GetString() ?? existing.Category;
                                    if (p.TryGetProperty("title", out var tit)) existing.Title = tit.GetString() ?? existing.Title;
                                    if (p.TryGetProperty("icon", out var ic)) existing.Icon = ic.GetString() ?? existing.Icon;
                                }
                                else
                                {
                                    list.Add(new PluginCardModel
                                    {
                                        Id = pid,
                                        Name = pid,
                                        Version = p.TryGetProperty("version", out var v) ? v.GetString() ?? "1.0.0" : "1.0.0",
                                        Type = p.TryGetProperty("type", out var t) ? t.GetString() ?? "elixir" : "elixir",
                                        Category = p.TryGetProperty("category", out var c) ? c.GetString() ?? "Extension" : "Extension",
                                        Title = p.TryGetProperty("title", out var tit) ? tit.GetString() ?? pid : pid,
                                        Icon = p.TryGetProperty("icon", out var ic) ? ic.GetString() ?? "🧩" : "🧩",
                                        IsLocal = false,
                                        IsDeployed = true
                                    });
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Debug.LogWarning($"[Exoforge Plugins] Failed to fetch cluster manifest export: {ex.Message}");
                    }
                }

                _plugins = list.OrderBy(p => p.Name).ToList();
                _pluginManifests = manifests;

                if (string.IsNullOrEmpty(_selectedPluginId) && _plugins.Count > 0)
                {
                    _selectedPluginId = _plugins[0].Id;
                }
            }
            finally
            {
                _isLoading = false;
                Repaint();
            }
        }

        private void OnGUI()
        {
            DrawHeader();

            EditorGUILayout.BeginHorizontal();

            // Left column: Plugin List Sidebar
            DrawSidebar(GUILayout.Width(240));

            // Right column: Detailed Plugin & Visualizations
            DrawDetailPane();

            EditorGUILayout.EndHorizontal();
        }

        private void DrawHeader()
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.BeginHorizontal();

            GUILayout.Label("🔌 Exoforge Plugins", EditorStyles.boldLabel);
            GUILayout.FlexibleSpace();

            if (IsConnected)
            {
                var prevColor = GUI.color;
                GUI.color = new Color(0.3f, 0.9f, 0.4f);
                GUILayout.Label("● Cluster Connected", EditorStyles.miniBoldLabel);
                GUI.color = prevColor;
            }
            else
            {
                var prevColor = GUI.color;
                GUI.color = new Color(0.6f, 0.6f, 0.6f);
                GUILayout.Label(ExoforgeControlCenter.IsConnecting ? "◌ Connecting..." : "○ Offline Mode", EditorStyles.miniBoldLabel);
                GUI.color = prevColor;

                if (!ExoforgeControlCenter.IsConnecting && GUILayout.Button(new GUIContent("⚡ Connect", "Connect to Exoforge Cluster"), EditorStyles.miniButton, GUILayout.Width(75)))
                {
                    _ = ExoforgeControlCenter.ConnectSharedAsync();
                }
            }

            if (_isLoading)
            {
                GUILayout.Label("⏳ Loading...", EditorStyles.miniLabel);
            }

            if (GUILayout.Button(new GUIContent("🔄 Refresh", "Reload local and cluster plugins"), EditorStyles.miniButton, GUILayout.Width(75)))
            {
                InvalidateHooksCache();
                _ = RefreshPluginsDataAsync();
            }

            if (GUILayout.Button(new GUIContent("⚡ Studio", "Open Exoforge Studio"), EditorStyles.miniButton, GUILayout.Width(65)))
            {
                ExoforgeControlCenter.ShowWindow();
            }

            EditorGUILayout.EndHorizontal();
            EditorGUILayout.EndVertical();
        }

        private void DrawSidebar(params GUILayoutOption[] options)
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox, options);

            _searchFilter = EditorGUILayout.TextField(_searchFilter, EditorStyles.toolbarSearchField);
            EditorGUILayout.Space(4);

            _sidebarScroll = EditorGUILayout.BeginScrollView(_sidebarScroll);

            var filtered = _plugins
                .Where(p => string.IsNullOrWhiteSpace(_searchFilter) ||
                            p.Name.Contains(_searchFilter, StringComparison.OrdinalIgnoreCase) ||
                            p.Title.Contains(_searchFilter, StringComparison.OrdinalIgnoreCase) ||
                            p.Category.Contains(_searchFilter, StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (filtered.Count == 0)
            {
                EditorGUILayout.LabelField("No plugins found.", EditorStyles.miniLabel);
            }
            else
            {
                string currentCategory = "";
                foreach (var p in filtered)
                {
                    if (p.Category != currentCategory)
                    {
                        currentCategory = p.Category;
                        EditorGUILayout.Space(4);
                        EditorGUILayout.LabelField(currentCategory.ToUpperInvariant(), EditorStyles.miniBoldLabel);
                    }

                    bool isSelected = string.Equals(p.Id, _selectedPluginId, StringComparison.OrdinalIgnoreCase);

                    var style = isSelected ? EditorStyles.selectionRect : EditorStyles.label;

                    EditorGUILayout.BeginHorizontal(isSelected ? "SelectionRect" : GUIStyle.none);

                    string statusIcon = p.IsDeployed ? "●" : (p.IsLocal && p.IsBuilt ? "✓" : "○");
                    var statusColor = p.IsDeployed ? new Color(0.3f, 0.9f, 0.4f) :
                                      (p.IsLocal && p.Modified ? new Color(0.95f, 0.7f, 0.2f) :
                                      (p.IsLocal && p.IsBuilt ? new Color(0.4f, 0.7f, 1f) : new Color(0.6f, 0.6f, 0.6f)));

                    var prevColor = GUI.color;
                    GUI.color = statusColor;
                    GUILayout.Label(statusIcon, GUILayout.Width(14));
                    GUI.color = prevColor;

                    string display = $"{p.Icon} {p.Name}";
                    if (GUILayout.Button(display, EditorStyles.label))
                    {
                        _selectedPluginId = p.Id;
                        _selectedDetailTab = 0;
                        GUI.FocusControl(null);
                    }

                    EditorGUILayout.EndHorizontal();
                }
            }

            EditorGUILayout.EndScrollView();
            EditorGUILayout.EndVertical();
        }

        private void DrawDetailPane()
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            var selected = _plugins.FirstOrDefault(p => string.Equals(p.Id, _selectedPluginId, StringComparison.OrdinalIgnoreCase));
            if (selected == null)
            {
                EditorGUILayout.HelpBox("Select a plugin from the list to view its architecture and tools.", MessageType.Info);
                EditorGUILayout.EndVertical();
                return;
            }

            _pluginManifests.TryGetValue(selected.Id, out var manifest);

            // Plugin Header Banner
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.BeginHorizontal();
            GUILayout.Label($"{selected.Icon} {selected.Title} ({selected.Name})", EditorStyles.boldLabel);
            GUILayout.FlexibleSpace();
            GUILayout.Label($"v{selected.Version}", EditorStyles.miniLabel);
            GUILayout.Label($"[{selected.Type.ToUpperInvariant()}]", EditorStyles.miniBoldLabel);
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.BeginHorizontal();
            GUILayout.Label($"Category: {selected.Category}", EditorStyles.miniLabel);
            GUILayout.FlexibleSpace();
            if (selected.IsLocal && GUILayout.Button("Reveal Files", EditorStyles.miniButton, GUILayout.Width(90)))
            {
                EditorUtility.RevealInFinder(selected.LocalDirectory);
            }
            if (GUILayout.Button("Open Studio Tab", EditorStyles.miniButton, GUILayout.Width(110)))
            {
                Application.OpenURL($"{GetHttpUrl()}/tab/{selected.Id}");
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(4);

            // Tab Navigation: Overview, Resources, Actions, Events, Webhooks, + Custom Editor Hooks
            var customEditors = GetCustomEditorsForPlugin(selected.Id);

            var tabLabels = new List<string> { "Overview", "Resources", "Actions", "Events", "Webhooks" };
            foreach (var hook in customEditors)
            {
                tabLabels.Add(hook.DisplayName);
            }

            _selectedDetailTab = GUILayout.Toolbar(_selectedDetailTab, tabLabels.ToArray(), GUILayout.Height(24));
            EditorGUILayout.Space(6);

            // Tab Contents
            if (_selectedDetailTab == 0)
            {
                DrawOverviewTab(selected, manifest);
            }
            else if (_selectedDetailTab == 1)
            {
                DrawResourcesTab(manifest);
            }
            else if (_selectedDetailTab == 2)
            {
                DrawActionsTab(manifest, isWebhookOnly: false);
            }
            else if (_selectedDetailTab == 3)
            {
                DrawEventsTab(manifest);
            }
            else if (_selectedDetailTab == 4)
            {
                DrawWebhooksTab(selected, manifest);
            }
            else
            {
                // Custom Editor Hook Execution
                int customIndex = _selectedDetailTab - 5;
                if (customIndex >= 0 && customIndex < customEditors.Count)
                {
                    var hook = customEditors[customIndex];
                    var ws = ExoforgeControlCenter.Instance?.Workspace
                             ?? ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
                    var ctx = new ExoforgePluginContext(
                        selected.Id,
                        GetClient(),
                        GetHttpUrl(),
                        ws,
                        Repaint,
                        (msg, type) => Debug.Log($"[{hook.DisplayName}] {msg}")
                    );
                    hook.OnGUI(ctx);
                }
            }

            EditorGUILayout.EndVertical();
        }

        private void DrawOverviewTab(PluginCardModel plugin, JsonElement manifest)
        {
            _detailScroll = EditorGUILayout.BeginScrollView(_detailScroll);

            EditorGUILayout.LabelField("Plugin Metadata", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField($"Identifier:", plugin.Id);
            EditorGUILayout.LabelField($"Runtime Kind:", plugin.Type);
            EditorGUILayout.LabelField($"Version:", plugin.Version);
            EditorGUILayout.LabelField($"Category:", plugin.Category);

            if (manifest.ValueKind == JsonValueKind.Object)
            {
                if (manifest.TryGetProperty("provides", out var providesArr) && providesArr.ValueKind == JsonValueKind.Array)
                {
                    var provides = providesArr.EnumerateArray().Select(x => x.GetString()).Where(s => !string.IsNullOrEmpty(s)).ToList();
                    EditorGUILayout.LabelField("Provides Services:", string.Join(", ", provides));
                }

                if (manifest.TryGetProperty("dependencies", out var depsArr) && depsArr.ValueKind == JsonValueKind.Array)
                {
                    var deps = depsArr.EnumerateArray().Select(x => x.GetString()).Where(s => !string.IsNullOrEmpty(s)).ToList();
                    EditorGUILayout.LabelField("Dependencies:", deps.Count > 0 ? string.Join(", ", deps) : "(none)");
                }
            }
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // Summary Counts
            int resCount = CountResources(manifest);
            int actionCount = CountActions(manifest, excludeWebhooks: true);
            int eventCount = CountEvents(manifest);
            int webhookCount = CountActions(manifest, webhooksOnly: true);

            EditorGUILayout.LabelField("Exported Capabilities Summary", EditorStyles.boldLabel);
            EditorGUILayout.BeginHorizontal();

            DrawCountCard("📦 Resources", resCount, () => _selectedDetailTab = 1);
            DrawCountCard("⚡ Actions", actionCount, () => _selectedDetailTab = 2);
            DrawCountCard("📡 Events", eventCount, () => _selectedDetailTab = 3);
            DrawCountCard("🌐 Webhooks", webhookCount, () => _selectedDetailTab = 4);

            EditorGUILayout.EndHorizontal();

            var customEditors = GetCustomEditorsForPlugin(plugin.Id);
            if (customEditors.Count > 0)
            {
                EditorGUILayout.Space(8);
                EditorGUILayout.LabelField("Custom Engine Editor Extensions", EditorStyles.boldLabel);
                foreach (var hook in customEditors)
                {
                    EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                    EditorGUILayout.BeginHorizontal();
                    GUILayout.Label($"✨ {hook.DisplayName}", EditorStyles.boldLabel);
                    GUILayout.FlexibleSpace();
                    if (GUILayout.Button($"Open {hook.DisplayName} Tab", EditorStyles.miniButton, GUILayout.Width(180)))
                    {
                        int hookIdx = customEditors.IndexOf(hook);
                        _selectedDetailTab = 5 + hookIdx;
                    }
                    EditorGUILayout.EndHorizontal();
                    EditorGUILayout.EndVertical();
                }
            }

            EditorGUILayout.EndScrollView();
        }

        private void DrawCountCard(string title, int count, Action onClick)
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox, GUILayout.Height(60));
            GUILayout.Label(title, EditorStyles.miniLabel);
            GUILayout.Label(count.ToString(), EditorStyles.boldLabel);
            if (GUILayout.Button("Inspect", EditorStyles.miniButton))
            {
                onClick();
            }
            EditorGUILayout.EndVertical();
        }

        private void DrawResourcesTab(JsonElement manifest)
        {
            _detailScroll = EditorGUILayout.BeginScrollView(_detailScroll);

            var resources = ExtractResources(manifest);
            EditorGUILayout.LabelField($"Declared Resources ({resources.Count})", EditorStyles.boldLabel);

            if (resources.Count == 0)
            {
                EditorGUILayout.HelpBox("This plugin declares no [ExoResource] or table models.", MessageType.None);
            }
            else
            {
                foreach (var r in resources)
                {
                    string name = r.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    string pk = r.TryGetProperty("primary_key", out var p) ? p.GetString() ?? "id" : "id";
                    string record = r.TryGetProperty("record", out var rc) ? rc.GetString() ?? "" : "";

                    EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                    EditorGUILayout.BeginHorizontal();
                    GUILayout.Label($"📦 {name}", EditorStyles.boldLabel);
                    GUILayout.FlexibleSpace();
                    GUILayout.Label($"PK: {pk}", EditorStyles.miniBoldLabel);
                    EditorGUILayout.EndHorizontal();

                    if (!string.IsNullOrEmpty(record))
                    {
                        EditorGUILayout.LabelField($"C# Model: {record}", EditorStyles.miniLabel);
                    }

                    if (r.TryGetProperty("columns", out var cols) && cols.ValueKind == JsonValueKind.Array)
                    {
                        EditorGUILayout.Space(2);
                        EditorGUILayout.LabelField("Columns:", EditorStyles.miniBoldLabel);

                        EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
                        GUILayout.Label("Column", EditorStyles.miniBoldLabel, GUILayout.Width(130));
                        GUILayout.Label("Type", EditorStyles.miniBoldLabel, GUILayout.Width(80));
                        GUILayout.Label("Label", EditorStyles.miniBoldLabel, GUILayout.Width(120));
                        GUILayout.Label("Attributes", EditorStyles.miniBoldLabel);
                        EditorGUILayout.EndHorizontal();

                        foreach (var col in cols.EnumerateArray())
                        {
                            string cName = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "";
                            string cType = col.TryGetProperty("type", out var ct) ? ct.GetString() ?? "" : "";
                            string cLabel = col.TryGetProperty("label", out var cl) ? cl.GetString() ?? "" : "";
                            bool sortable = col.TryGetProperty("sortable", out var cs) && cs.GetBoolean();
                            bool filterable = col.TryGetProperty("filterable", out var cf) && cf.GetBoolean();
                            bool badge = col.TryGetProperty("badge", out var cb) && cb.GetBoolean();

                            var attrs = new List<string>();
                            if (sortable) attrs.Add("sortable");
                            if (filterable) attrs.Add("filterable");
                            if (badge) attrs.Add("badge");

                            EditorGUILayout.BeginHorizontal();
                            GUILayout.Label(cName, EditorStyles.miniLabel, GUILayout.Width(130));
                            GUILayout.Label(cType, EditorStyles.miniLabel, GUILayout.Width(80));
                            GUILayout.Label(cLabel, EditorStyles.miniLabel, GUILayout.Width(120));
                            GUILayout.Label(string.Join(", ", attrs), EditorStyles.miniLabel);
                            EditorGUILayout.EndHorizontal();
                        }
                    }

                    EditorGUILayout.EndVertical();
                    EditorGUILayout.Space(4);
                }
            }

            EditorGUILayout.EndScrollView();
        }

        private void DrawActionsTab(JsonElement manifest, bool isWebhookOnly)
        {
            _detailScroll = EditorGUILayout.BeginScrollView(_detailScroll);

            var actions = ExtractActions(manifest, isWebhookOnly);
            string header = isWebhookOnly ? $"Inbound Webhooks ({actions.Count})" : $"Exposed Actions ({actions.Count})";
            EditorGUILayout.LabelField(header, EditorStyles.boldLabel);

            if (actions.Count == 0)
            {
                EditorGUILayout.HelpBox(isWebhookOnly ? "No webhooks declared for this plugin." : "No actions declared for this plugin.", MessageType.None);
            }
            else
            {
                foreach (var a in actions)
                {
                    string name = a.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    string mode = a.TryGetProperty("mode", out var m) ? m.GetString() ?? "sync" : "sync";
                    string scope = a.TryGetProperty("scope", out var s) ? s.GetString() ?? "global" : "global";
                    string transport = a.TryGetProperty("transport", out var t) ? t.GetString() ?? "auto" : "auto";
                    int arity = a.TryGetProperty("arity", out var ar) ? ar.GetInt32() : 0;
                    string returnsType = a.TryGetProperty("returns_type", out var rt) ? rt.GetString() ?? "" : "";

                    EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                    EditorGUILayout.BeginHorizontal();
                    GUILayout.Label($"⚡ {name}", EditorStyles.boldLabel);
                    GUILayout.FlexibleSpace();
                    GUILayout.Label($"[{mode}] scope:{scope} transport:{transport} arity:{arity}", EditorStyles.miniLabel);
                    EditorGUILayout.EndHorizontal();

                    if (!string.IsNullOrEmpty(returnsType))
                    {
                        EditorGUILayout.LabelField($"Returns: {returnsType}", EditorStyles.miniLabel);
                    }

                    if (a.TryGetProperty("params", out var pObj) && pObj.ValueKind == JsonValueKind.Object)
                    {
                        var paramList = new List<string>();
                        foreach (var prop in pObj.EnumerateObject())
                        {
                            paramList.Add($"{prop.Name}: {prop.Value.GetString()}");
                        }

                        if (paramList.Count > 0)
                        {
                            EditorGUILayout.LabelField($"Parameters: ({string.Join(", ", paramList)})", EditorStyles.miniLabel);
                        }
                    }

                    EditorGUILayout.EndVertical();
                    EditorGUILayout.Space(2);
                }
            }

            EditorGUILayout.EndScrollView();
        }

        private void DrawEventsTab(JsonElement manifest)
        {
            _detailScroll = EditorGUILayout.BeginScrollView(_detailScroll);

            var events = ExtractEvents(manifest);
            EditorGUILayout.LabelField($"Declared Events ({events.Count})", EditorStyles.boldLabel);

            if (events.Count == 0)
            {
                EditorGUILayout.HelpBox("This plugin declares no events.", MessageType.None);
            }
            else
            {
                foreach (var e in events)
                {
                    string name = e.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    string topic = e.TryGetProperty("topic", out var t) ? t.GetString() ?? "—" : "—";
                    string scope = e.TryGetProperty("scope", out var s) ? s.GetString() ?? "global" : "global";
                    string payloadType = e.TryGetProperty("payload_type", out var pt) ? pt.GetString() ?? "" : "";

                    EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                    EditorGUILayout.BeginHorizontal();
                    GUILayout.Label($"📡 {name}", EditorStyles.boldLabel);
                    GUILayout.FlexibleSpace();
                    GUILayout.Label($"Topic: {topic}", EditorStyles.miniBoldLabel);
                    GUILayout.Label($"Scope: {scope}", EditorStyles.miniLabel);
                    EditorGUILayout.EndHorizontal();

                    if (!string.IsNullOrEmpty(payloadType))
                    {
                        EditorGUILayout.LabelField($"Payload Type: {payloadType}", EditorStyles.miniLabel);
                    }

                    if (e.TryGetProperty("payload", out var pObj) && pObj.ValueKind == JsonValueKind.Object)
                    {
                        var fields = new List<string>();
                        foreach (var prop in pObj.EnumerateObject())
                        {
                            fields.Add($"{prop.Name}: {prop.Value.GetString()}");
                        }
                        if (fields.Count > 0)
                        {
                            EditorGUILayout.LabelField($"Fields: {{{string.Join(", ", fields)}}}", EditorStyles.miniLabel);
                        }
                    }

                    EditorGUILayout.EndVertical();
                    EditorGUILayout.Space(2);
                }
            }

            EditorGUILayout.EndScrollView();
        }

        private void DrawWebhooksTab(PluginCardModel plugin, JsonElement manifest)
        {
            _detailScroll = EditorGUILayout.BeginScrollView(_detailScroll);

            var webhooks = ExtractActions(manifest, isWebhookOnly: true);
            EditorGUILayout.LabelField($"Inbound HTTP Webhook Endpoints ({webhooks.Count})", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Webhooks accept external HTTP payloads (Stripe, GitHub, Discord, Apple, Google) and trigger plugin logic.",
                EditorStyles.wordWrappedMiniLabel);

            EditorGUILayout.Space(4);

            string host = GetHttpUrl();

            if (webhooks.Count == 0)
            {
                EditorGUILayout.HelpBox("This plugin defines no actions marked with [ExoWebhook] or transport: 'webhook'.", MessageType.None);
            }
            else
            {
                foreach (var w in webhooks)
                {
                    string actionName = w.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    string endpoint = $"{host}/api/webhooks/{plugin.Id}/{actionName}";

                    EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                    EditorGUILayout.LabelField($"🌐 POST /api/webhooks/{plugin.Id}/{actionName}", EditorStyles.boldLabel);

                    EditorGUILayout.BeginHorizontal();
                    EditorGUILayout.TextField("Endpoint URL", endpoint);
                    if (GUILayout.Button("Copy", EditorStyles.miniButton, GUILayout.Width(50)))
                    {
                        EditorGUIUtility.systemCopyBuffer = endpoint;
                        Debug.Log($"[Exoforge Plugins] Copied webhook URL to clipboard: {endpoint}");
                    }
                    EditorGUILayout.EndHorizontal();

                    if (w.TryGetProperty("params", out var pObj) && pObj.ValueKind == JsonValueKind.Object)
                    {
                        var paramList = new List<string>();
                        foreach (var prop in pObj.EnumerateObject())
                        {
                            paramList.Add($"{prop.Name} ({prop.Value.GetString()})");
                        }
                        if (paramList.Count > 0)
                        {
                            EditorGUILayout.LabelField($"Payload: {string.Join(", ", paramList)}", EditorStyles.miniLabel);
                        }
                    }

                    EditorGUILayout.EndVertical();
                    EditorGUILayout.Space(4);
                }
            }

            EditorGUILayout.EndScrollView();
        }

        // =========================================================================
        // Helpers
        // =========================================================================

        private static int CountResources(JsonElement manifest) => ExtractResources(manifest).Count;

        private static int CountEvents(JsonElement manifest) => ExtractEvents(manifest).Count;

        private static int CountActions(JsonElement manifest, bool excludeWebhooks = false, bool webhooksOnly = false)
        {
            var actions = ExtractActions(manifest, isWebhookOnly: webhooksOnly);
            if (excludeWebhooks)
            {
                return actions.Count(a => !IsWebhookAction(a));
            }
            return actions.Count;
        }

        private static bool IsWebhookAction(JsonElement action)
        {
            string transport = action.TryGetProperty("transport", out var t) ? t.GetString() ?? "" : "";
            string scope = action.TryGetProperty("scope", out var s) ? s.GetString() ?? "" : "";
            return string.Equals(transport, "webhook", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(scope, "webhook", StringComparison.OrdinalIgnoreCase);
        }

        private static List<JsonElement> ExtractResources(JsonElement manifest)
        {
            var result = new List<JsonElement>();
            if (manifest.ValueKind != JsonValueKind.Object) return result;

            if (manifest.TryGetProperty("services", out var servicesArr) && servicesArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var s in servicesArr.EnumerateArray())
                {
                    if (s.TryGetProperty("resources", out var resArr) && resArr.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var r in resArr.EnumerateArray())
                        {
                            result.Add(r);
                        }
                    }
                }
            }

            return result;
        }

        private static List<JsonElement> ExtractActions(JsonElement manifest, bool isWebhookOnly = false)
        {
            var result = new List<JsonElement>();
            if (manifest.ValueKind != JsonValueKind.Object) return result;

            if (manifest.TryGetProperty("services", out var servicesArr) && servicesArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var s in servicesArr.EnumerateArray())
                {
                    if (s.TryGetProperty("actions", out var actionsArr) && actionsArr.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var a in actionsArr.EnumerateArray())
                        {
                            bool isHook = IsWebhookAction(a);
                            if (isWebhookOnly && isHook) result.Add(a);
                            else if (!isWebhookOnly && !isHook) result.Add(a);
                        }
                    }
                }
            }

            return result;
        }

        private static List<JsonElement> ExtractEvents(JsonElement manifest)
        {
            var result = new List<JsonElement>();
            if (manifest.ValueKind != JsonValueKind.Object) return result;

            if (manifest.TryGetProperty("services", out var servicesArr) && servicesArr.ValueKind == JsonValueKind.Array)
            {
                foreach (var s in servicesArr.EnumerateArray())
                {
                    if (s.TryGetProperty("events", out var eventsArr) && eventsArr.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var e in eventsArr.EnumerateArray())
                        {
                            result.Add(e);
                        }
                    }
                }
            }

            return result;
        }
    }
}
