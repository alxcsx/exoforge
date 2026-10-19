using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Management;
using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Modern UI Toolkit Editor Window for Exoforge Plugins & Resource Management.
    /// Provides deep plugin lifecycle management (scaffold, build, deploy, stubs, logs)
    /// and first-class live cluster Resource management (query, inspect, insert, update, delete).
    /// </summary>
    public class ExoforgeExtensionsWindow : EditorWindow
    {
        public static ExoforgeExtensionsWindow? Instance { get; private set; }

        private string _searchFilter = "";
        private string? _selectedPluginId;
        private int _selectedDetailTab = 0; // 0: Overview, 1: Resources, 2: Actions, 3: Events, 4: Webhooks, 5+: Custom
        private bool _isLoading;
        private bool _isBuilding;
        private string _buildLog = "";
        private string _pluginLogs = "";
        private string? _pluginLogsFor;
        private bool _showPluginLogs;
        private string _statusMessage = "";
        private bool _lastConnected;

        // Data Models
        private List<PluginCardModel> _plugins = new();
        private Dictionary<string, JsonElement> _pluginManifests = new(StringComparer.OrdinalIgnoreCase);
        private static List<IExoforgePluginCustomEditor>? _cachedHooks;

        // Resource Management State
        private string? _selectedResourceName;
        private List<JsonElement> _liveResourceRows = new();
        private JsonElement? _selectedResourceRow;
        private bool _isLoadingResources;
        private bool _showAddRecordForm;
        private string _resourceSearch = "";
        private Dictionary<string, string> _editFieldValues = new();
        private Dictionary<string, string> _newRecordValues = new();
        private bool _resourceSchemaViewMode; // false = Data Explorer, true = Schema View

        // Actions Sandbox State
        private string? _sandboxSelectedAction;
        private string _sandboxPayload = "{}";
        private string _sandboxResult = "";
        private string _sandboxLatency = "";
        private bool _isInvokingAction;

        // UI Toolkit Element References
        private VisualElement? _root;
        private VisualElement? _connectionPill;
        private Label? _connectionStatusLabel;
        private VisualElement? _connectionDot;
        private Button? _connectBtn;
        private VisualElement? _pluginListContainer;
        private VisualElement? _detailContainer;
        private Label? _statusLabel;
        private Label? _envBadge;

        public sealed class PluginCardModel
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
            public long BinarySizeBytes { get; set; }
        }

        [MenuItem("Tools/Exoforge/Extensions", false, 101)]
        [MenuItem("Window/Exoforge/Extensions", false, 2001)]
        [MenuItem("Tools/Exoforge/Plugins", false, 102)]
        [MenuItem("Window/Exoforge/Plugins", false, 2002)]
        public static void ShowWindow()
        {
            var window = GetWindow<ExoforgeExtensionsWindow>("Exoforge Extensions");
            window.minSize = new Vector2(800, 520);
            window.Show();
        }

        public static void OpenExtension(string extensionId, bool preferCustomEditor = true) =>
            OpenPlugin(extensionId, preferCustomEditor);

        public static void OpenPlugin(string pluginId, bool preferCustomEditor = true)
        {
            var window = GetWindow<ExoforgeExtensionsWindow>("Exoforge Extensions");
            window.minSize = new Vector2(800, 520);
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
            window.RebuildUI();
        }

        public static void OpenSandbox(string? pluginId = null, string? actionName = null, string? payload = null)
        {
            var window = GetWindow<ExoforgeExtensionsWindow>("Exoforge Extensions");
            window.minSize = new Vector2(800, 520);
            if (!string.IsNullOrEmpty(pluginId))
            {
                window._selectedPluginId = pluginId;
            }
            if (!string.IsNullOrEmpty(actionName))
            {
                window._sandboxSelectedAction = actionName;
            }
            if (!string.IsNullOrEmpty(payload))
            {
                window._sandboxPayload = payload;
            }
            window._selectedDetailTab = 2; // Tab 2: Actions Sandbox
            window.Show();
            window.Focus();
            window.RebuildUI();
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
                UpdateConnectionStatusUI();
                if (connected)
                {
                    _ = RefreshPluginsDataAsync();
                }
            }
        }

        public void CreateGUI()
        {
            _root = rootVisualElement;
            _root.style.backgroundColor = ExoforgeUIStyle.BgWindow;
            _root.style.flexDirection = FlexDirection.Column;
            _root.style.flexGrow = 1;

            RebuildUI();
        }

        public void RebuildUI()
        {
            if (_root == null) return;
            _root.Clear();

            // 1. Top Header Toolbar
            _root.Add(BuildHeaderToolbar());

            // 2. Status Banner (if any)
            if (!string.IsNullOrEmpty(_statusMessage))
            {
                var banner = new VisualElement();
                banner.style.backgroundColor = ExoforgeUIStyle.AccentBlueBg;
                banner.style.paddingLeft = 12;
                banner.style.paddingRight = 12;
                banner.style.paddingTop = 6;
                banner.style.paddingBottom = 6;
                banner.style.flexDirection = FlexDirection.Row;
                banner.style.alignItems = Align.Center;

                var bannerText = new Label(_statusMessage);
                bannerText.style.color = ExoforgeUIStyle.TextPrimary;
                bannerText.style.fontSize = 11;
                bannerText.style.flexGrow = 1;
                banner.Add(bannerText);

                var dismissBtn = new Button(() => { _statusMessage = ""; RebuildUI(); }) { text = "✕" };
                dismissBtn.style.borderTopWidth = 0;
                dismissBtn.style.borderBottomWidth = 0;
                dismissBtn.style.borderLeftWidth = 0;
                dismissBtn.style.borderRightWidth = 0;
                dismissBtn.style.backgroundColor = Color.clear;
                dismissBtn.style.color = ExoforgeUIStyle.TextSecondary;
                banner.Add(dismissBtn);

                _root.Add(banner);
            }

            // 3. Two-Pane Split Layout (Left: Catalog, Right: Detail & Management)
            var split = new TwoPaneSplitView(0, 280, TwoPaneSplitViewOrientation.Horizontal);
            split.style.flexGrow = 1;

            var leftPane = BuildSidebarCatalog();
            var rightPane = BuildDetailPane();

            split.Add(leftPane);
            split.Add(rightPane);

            _root.Add(split);
        }

        // =========================================================================
        // Top Toolbar
        // =========================================================================

        private VisualElement BuildHeaderToolbar()
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

            var pluginsBadge = ExoforgeUIStyle.CreatePill("PLUGINS & RESOURCES", Color.white, ExoforgeUIStyle.BrandPurple, 9);
            brandContainer.Add(pluginsBadge);

            var divider = new VisualElement();
            divider.style.width = 1;
            divider.style.height = 18;
            divider.style.backgroundColor = new Color(1f, 1f, 1f, 0.18f);
            divider.style.marginLeft = 10;
            divider.style.marginRight = 6;
            brandContainer.Add(divider);

            string envName = ExoforgeControlCenter.ActiveEnvironment?.Name ?? "default";
            var envDropdownBtn = ExoforgeUIStyle.CreateEnvSelector(envName, ShowEnvDropdown, out _envBadge);
            brandContainer.Add(envDropdownBtn);

            masthead.Add(brandContainer);

            // Status Capsule & Connect CTA (Right)
            var statusContainer = new VisualElement();
            statusContainer.style.flexDirection = FlexDirection.Row;
            statusContainer.style.alignItems = Align.Center;
            statusContainer.style.flexShrink = 0;

            _connectionPill = new VisualElement();
            _connectionPill.style.flexDirection = FlexDirection.Row;
            _connectionPill.style.alignItems = Align.Center;
            _connectionPill.style.backgroundColor = new Color(0f, 0f, 0f, 0.35f);
            _connectionPill.style.borderTopWidth = 1;
            _connectionPill.style.borderBottomWidth = 1;
            _connectionPill.style.borderLeftWidth = 1;
            _connectionPill.style.borderRightWidth = 1;
            _connectionPill.style.borderTopColor = new Color(1f, 1f, 1f, 0.12f);
            _connectionPill.style.borderBottomColor = new Color(1f, 1f, 1f, 0.12f);
            _connectionPill.style.borderLeftColor = new Color(1f, 1f, 1f, 0.12f);
            _connectionPill.style.borderRightColor = new Color(1f, 1f, 1f, 0.12f);
            _connectionPill.style.borderTopLeftRadius = 14;
            _connectionPill.style.borderTopRightRadius = 14;
            _connectionPill.style.borderBottomLeftRadius = 14;
            _connectionPill.style.borderBottomRightRadius = 14;
            _connectionPill.style.paddingLeft = 10;
            _connectionPill.style.paddingRight = 10;
            _connectionPill.style.paddingTop = 4;
            _connectionPill.style.paddingBottom = 4;
            _connectionPill.style.marginRight = 8;

            _connectionDot = ExoforgeUIStyle.CreateStatusDot(IsConnected ? ExoforgeUIStyle.AccentGreen : ExoforgeUIStyle.AccentGray, 8f);
            _connectionPill.Add(_connectionDot);

            _connectionStatusLabel = new Label(IsConnected ? "Online" : (ExoforgeControlCenter.IsConnecting ? "Connecting..." : "Offline"));
            _connectionStatusLabel.style.fontSize = 11;
            _connectionStatusLabel.style.color = ExoforgeUIStyle.TextPrimary;
            _connectionPill.Add(_connectionStatusLabel);

            statusContainer.Add(_connectionPill);

            _connectBtn = ExoforgeUIStyle.CreateModernButton(
                IsConnected ? "Disconnect" : "⚡ Connect",
                async () =>
                {
                    if (IsConnected) await ExoforgeControlCenter.DisconnectSharedAsync();
                    else await ExoforgeControlCenter.ConnectSharedAsync();
                    RebuildUI();
                },
                bg: IsConnected ? new Color(1f, 1f, 1f, 0.08f) : ExoforgeUIStyle.BrandPurple,
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

            // Left: Catalog summary
            var leftTools = new VisualElement();
            leftTools.style.flexDirection = FlexDirection.Row;
            leftTools.style.alignItems = Align.Center;
            leftTools.style.flexShrink = 1;
            leftTools.style.overflow = Overflow.Hidden;

            var catalogChip = new Label("● Workspace Catalog & Stored Schemas");
            catalogChip.style.fontSize = 11;
            catalogChip.style.color = ExoforgeUIStyle.TextMuted;
            leftTools.Add(catalogChip);

            toolbar.Add(leftTools);

            // Right: Web-Like Action Buttons
            var actionsGroup = new VisualElement();
            actionsGroup.style.flexDirection = FlexDirection.Row;
            actionsGroup.style.alignItems = Align.Center;
            actionsGroup.style.flexShrink = 0;

            var scaffoldBtn = ExoforgeUIStyle.CreateModernButton(
                "➕ Scaffold Plugin",
                () => ExoforgeScaffoldModal.Open(onCreated: () =>
                {
                    InvalidateHooksCache();
                    _ = RefreshPluginsDataAsync();
                    ShowStatus("✓ Extension scaffolded successfully.");
                }),
                bg: ExoforgeUIStyle.BrandPurple,
                textCol: Color.white,
                height: 26);
            actionsGroup.Add(scaffoldBtn);

            var authBtn = ExoforgeUIStyle.CreateModernButton(
                "👤 Account",
                () => ExoforgeAccountModal.Open(),
                height: 26);
            actionsGroup.Add(authBtn);

            var refreshBtn = ExoforgeUIStyle.CreateModernButton(
                "🔄 Refresh",
                () =>
                {
                    InvalidateHooksCache();
                    _ = RefreshPluginsDataAsync();
                },
                height: 26);
            actionsGroup.Add(refreshBtn);

            var studioBtn = ExoforgeUIStyle.CreateModernButton(
                "⚡ Studio Window ↗",
                () => ExoforgeControlCenter.ShowWindow(),
                height: 26);
            actionsGroup.Add(studioBtn);

            toolbar.Add(actionsGroup);
            header.Add(toolbar);

            return header;
        }

        private void ShowEnvDropdown()
        {
            var menu = new GenericMenu();
            var envs = ExoforgeControlCenter.GetConfiguredEnvironments();
            string activeName = ExoforgeControlCenter.ActiveEnvironment?.Name ?? "default";

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
                        ExoforgeControlCenter.ApplyEnvironment(env);
                        RebuildUI();
                    });
                }
            }

            menu.AddSeparator("");
            menu.AddItem(new GUIContent("⚡ Open Exoforge Studio Settings..."), false, () =>
            {
                ExoforgeControlCenter.ShowWindow();
            });

            menu.ShowAsContext();
        }

        private void UpdateConnectionStatusUI()
        {
            if (_connectionDot != null && _connectionStatusLabel != null && _connectBtn != null)
            {
                _connectionDot.style.backgroundColor = IsConnected ? ExoforgeUIStyle.AccentGreen : ExoforgeUIStyle.AccentGray;
                _connectionStatusLabel.text = IsConnected ? "Online" : (ExoforgeControlCenter.IsConnecting ? "Connecting..." : "Offline");
                _connectBtn.text = IsConnected ? "Disconnect" : "⚡ Connect";
                _connectBtn.style.backgroundColor = IsConnected ? new Color(1f, 1f, 1f, 0.08f) : ExoforgeUIStyle.BrandPurple;
            }

            if (_envBadge != null)
            {
                string envName = ExoforgeControlCenter.ActiveEnvironment?.Name ?? "default";
                _envBadge.text = envName;
            }
        }

        // =========================================================================
        // Left Sidebar: Plugin Catalog
        // =========================================================================

        private VisualElement BuildSidebarCatalog()
        {
            var container = new VisualElement();
            container.style.flexDirection = FlexDirection.Column;
            container.style.backgroundColor = ExoforgeUIStyle.BgPanel;
            container.style.borderRightWidth = 1;
            container.style.borderRightColor = ExoforgeUIStyle.BorderSubtle;
            container.style.paddingLeft = 8;
            container.style.paddingRight = 8;
            container.style.paddingTop = 8;
            container.style.paddingBottom = 8;

            // Search Box
            var searchField = new ToolbarSearchField();
            searchField.value = _searchFilter;
            searchField.RegisterValueChangedCallback(evt =>
            {
                _searchFilter = evt.newValue;
                PopulatePluginList(container.Q<ScrollView>("PluginListScroll"));
            });
            container.Add(searchField);

            var divider = ExoforgeUIStyle.CreateDivider(6);
            container.Add(divider);

            // Scrollable List of Plugin Cards
            var scroll = new ScrollView(ScrollViewMode.Vertical);
            scroll.name = "PluginListScroll";
            scroll.style.flexGrow = 1;
            container.Add(scroll);

            PopulatePluginList(scroll);

            return container;
        }

        private void PopulatePluginList(ScrollView? scroll)
        {
            if (scroll == null) return;
            scroll.Clear();

            var filtered = _plugins
                .Where(p => string.IsNullOrWhiteSpace(_searchFilter) ||
                            p.Name.Contains(_searchFilter, StringComparison.OrdinalIgnoreCase) ||
                            p.Title.Contains(_searchFilter, StringComparison.OrdinalIgnoreCase) ||
                            p.Category.Contains(_searchFilter, StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (filtered.Count == 0)
            {
                var emptyLabel = new Label("No plugins match your filter.");
                emptyLabel.style.color = ExoforgeUIStyle.TextMuted;
                emptyLabel.style.fontSize = 11;
                emptyLabel.style.paddingTop = 16;
                emptyLabel.style.alignSelf = Align.Center;
                scroll.Add(emptyLabel);
                return;
            }

            string currentCategory = "";
            foreach (var p in filtered)
            {
                if (p.Category != currentCategory)
                {
                    currentCategory = p.Category;
                    var catHeader = new Label(currentCategory.ToUpperInvariant());
                    catHeader.style.fontSize = 10;
                    catHeader.style.unityFontStyleAndWeight = FontStyle.Bold;
                    catHeader.style.color = ExoforgeUIStyle.TextMuted;
                    catHeader.style.marginTop = 8;
                    catHeader.style.marginBottom = 4;
                    catHeader.style.marginLeft = 4;
                    scroll.Add(catHeader);
                }

                bool isSelected = string.Equals(p.Id, _selectedPluginId, StringComparison.OrdinalIgnoreCase);

                var card = new VisualElement();
                ExoforgeUIStyle.ApplyCard(card, isSelected);
                card.style.cursor = StyleKeyword.Auto;

                // Card Click Selection
                card.RegisterCallback<ClickEvent>(evt =>
                {
                    _selectedPluginId = p.Id;
                    _selectedDetailTab = 0;
                    _selectedResourceName = null;
                    _selectedResourceRow = null;
                    RebuildUI();
                });

                // Top row: Icon, Name, Version
                var topRow = new VisualElement();
                topRow.style.flexDirection = FlexDirection.Row;
                topRow.style.alignItems = Align.Center;

                var iconLabel = new Label(p.Icon);
                iconLabel.style.fontSize = 14;
                iconLabel.style.marginRight = 6;
                topRow.Add(iconLabel);

                var nameLabel = new Label(p.Name);
                nameLabel.style.fontSize = 12;
                nameLabel.style.unityFontStyleAndWeight = FontStyle.Bold;
                nameLabel.style.color = isSelected ? ExoforgeUIStyle.TextPrimary : ExoforgeUIStyle.TextSecondary;
                nameLabel.style.flexGrow = 1;
                topRow.Add(nameLabel);

                var verBadge = ExoforgeUIStyle.CreatePill($"v{p.Version}", ExoforgeUIStyle.TextSecondary, ExoforgeUIStyle.BgWindow, 9);
                topRow.Add(verBadge);
                card.Add(topRow);

                // Bottom row: Badges (Runtime type & status)
                var bottomRow = new VisualElement();
                bottomRow.style.flexDirection = FlexDirection.Row;
                bottomRow.style.alignItems = Align.Center;
                bottomRow.style.marginTop = 4;

                string runtimeText = p.Type == "native" ? ".NET" : "Elixir";
                var runtimeColor = p.Type == "native" ? ExoforgeUIStyle.AccentBlue : ExoforgeUIStyle.AccentPurple;
                var runtimeBg = p.Type == "native" ? ExoforgeUIStyle.AccentBlueBg : ExoforgeUIStyle.AccentPurpleBg;
                bottomRow.Add(ExoforgeUIStyle.CreatePill(runtimeText, runtimeColor, runtimeBg, 9));

                if (p.IsDeployed)
                {
                    bottomRow.Add(ExoforgeUIStyle.CreatePill("Deployed", ExoforgeUIStyle.AccentGreen, ExoforgeUIStyle.AccentGreenBg, 9));
                }
                else if (p.IsLocal && p.Modified)
                {
                    bottomRow.Add(ExoforgeUIStyle.CreatePill("Modified", ExoforgeUIStyle.AccentOrange, ExoforgeUIStyle.AccentOrangeBg, 9));
                }
                else if (p.IsLocal && p.IsBuilt)
                {
                    bottomRow.Add(ExoforgeUIStyle.CreatePill("Built", ExoforgeUIStyle.AccentBlue, ExoforgeUIStyle.AccentBlueBg, 9));
                }
                else if (p.IsLocal)
                {
                    bottomRow.Add(ExoforgeUIStyle.CreatePill("Not Built", ExoforgeUIStyle.AccentGray, ExoforgeUIStyle.AccentGrayBg, 9));
                }

                card.Add(bottomRow);
                scroll.Add(card);
            }
        }

        // =========================================================================
        // Right Detail Pane: Management, Tabs, and Live Inspectors
        // =========================================================================

        private VisualElement BuildDetailPane()
        {
            var detail = new VisualElement();
            detail.style.flexDirection = FlexDirection.Column;
            detail.style.flexGrow = 1;
            detail.style.backgroundColor = ExoforgeUIStyle.BgWindow;
            detail.style.paddingLeft = 14;
            detail.style.paddingRight = 14;
            detail.style.paddingTop = 12;
            detail.style.paddingBottom = 12;

            var selected = _plugins.FirstOrDefault(p => string.Equals(p.Id, _selectedPluginId, StringComparison.OrdinalIgnoreCase));
            if (selected == null)
            {
                var placeholder = new Label("Select a plugin from the catalog to manage its lifecycle and inspect resources.");
                placeholder.style.color = ExoforgeUIStyle.TextMuted;
                placeholder.style.fontSize = 12;
                placeholder.style.marginTop = 24;
                placeholder.style.alignSelf = Align.Center;
                detail.Add(placeholder);
                return detail;
            }

            _pluginManifests.TryGetValue(selected.Id, out var manifest);

            // 1. Plugin Hero Banner
            detail.Add(BuildPluginHeroBanner(selected, manifest));

            // 2. Navigation Tab Strip
            var customEditors = GetCustomEditorsForPlugin(selected.Id);
            var tabs = new List<string> { "Overview", "Resources 🗄️", "Actions ⚡", "Events 📡", "Webhooks 🌐" };
            foreach (var hook in customEditors)
            {
                tabs.Add($"✨ {hook.DisplayName}");
            }

            var tabStrip = new VisualElement();
            tabStrip.style.flexDirection = FlexDirection.Row;
            tabStrip.style.marginTop = 10;
            tabStrip.style.marginBottom = 10;
            tabStrip.style.borderBottomWidth = 1;
            tabStrip.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
            tabStrip.style.paddingBottom = 4;

            for (int i = 0; i < tabs.Count; i++)
            {
                int tabIndex = i;
                bool isTabActive = _selectedDetailTab == tabIndex;

                var tabBtn = new Button(() =>
                {
                    _selectedDetailTab = tabIndex;
                    RebuildUI();
                })
                { text = tabs[i] };

                tabBtn.style.backgroundColor = isTabActive ? ExoforgeUIStyle.BrandPurpleGlow : Color.clear;
                tabBtn.style.color = isTabActive ? ExoforgeUIStyle.BrandPurpleLight : ExoforgeUIStyle.TextSecondary;
                tabBtn.style.borderTopWidth = 0;
                tabBtn.style.borderBottomWidth = isTabActive ? 2 : 0;
                tabBtn.style.borderLeftWidth = 0;
                tabBtn.style.borderRightWidth = 0;
                tabBtn.style.borderBottomColor = isTabActive ? ExoforgeUIStyle.BrandPurple : Color.clear;
                tabBtn.style.borderTopLeftRadius = 6;
                tabBtn.style.borderTopRightRadius = 6;
                tabBtn.style.borderBottomLeftRadius = 0;
                tabBtn.style.borderBottomRightRadius = 0;
                tabBtn.style.paddingLeft = 14;
                tabBtn.style.paddingRight = 14;
                tabBtn.style.paddingTop = 6;
                tabBtn.style.paddingBottom = 6;
                tabBtn.style.unityFontStyleAndWeight = isTabActive ? FontStyle.Bold : FontStyle.Normal;

                tabStrip.Add(tabBtn);
            }
            detail.Add(tabStrip);

            // 3. Tab Contents
            var contentContainer = new VisualElement();
            contentContainer.style.flexGrow = 1;

            if (_selectedDetailTab == 0)
            {
                contentContainer.Add(BuildOverviewTab(selected, manifest));
            }
            else if (_selectedDetailTab == 1)
            {
                contentContainer.Add(BuildResourcesTab(selected, manifest));
            }
            else if (_selectedDetailTab == 2)
            {
                contentContainer.Add(BuildActionsTab(selected, manifest));
            }
            else if (_selectedDetailTab == 3)
            {
                contentContainer.Add(BuildEventsTab(manifest));
            }
            else if (_selectedDetailTab == 4)
            {
                contentContainer.Add(BuildWebhooksTab(selected, manifest));
            }
            else
            {
                // Custom Editor Hook execution via IMGUIContainer
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
                        () => RebuildUI(),
                        (msg, type) => Debug.Log($"[{hook.DisplayName}] {msg}")
                    );

                    var imguiContainer = new IMGUIContainer(() =>
                    {
                        hook.OnGUI(ctx);
                    });
                    imguiContainer.style.flexGrow = 1;
                    contentContainer.Add(imguiContainer);
                }
            }

            detail.Add(contentContainer);
            return detail;
        }

        private VisualElement BuildPluginHeroBanner(PluginCardModel plugin, JsonElement manifest)
        {
            var hero = new VisualElement();
            ExoforgeUIStyle.ApplyCard(hero);
            hero.style.backgroundColor = ExoforgeUIStyle.BgPanel;

            // Top Row: Icon, Title, ID, Version, Type
            var top = new VisualElement();
            top.style.flexDirection = FlexDirection.Row;
            top.style.alignItems = Align.Center;

            var icon = new Label(plugin.Icon);
            icon.style.fontSize = 24;
            icon.style.marginRight = 10;
            top.Add(icon);

            var titleCol = new VisualElement();
            var title = new Label(plugin.Title);
            title.style.fontSize = 16;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            titleCol.Add(title);

            var sub = new Label($"{plugin.Id}  •  v{plugin.Version}  •  {plugin.Category}");
            sub.style.fontSize = 11;
            sub.style.color = ExoforgeUIStyle.TextSecondary;
            titleCol.Add(sub);
            top.Add(titleCol);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            top.Add(spacer);

            // Lifecycle Action Buttons
            if (plugin.IsLocal && plugin.Type == "native")
            {
                var buildBtn = ExoforgeUIStyle.CreateModernButton("⚡ Build", async () =>
                {
                    await BuildPluginAsync(plugin);
                }, bg: ExoforgeUIStyle.AccentBlueBg, textCol: ExoforgeUIStyle.AccentBlue);
                top.Add(buildBtn);

                var forceBuildBtn = ExoforgeUIStyle.CreateModernButton("⚡ Force Build", async () =>
                {
                    await ForceBuildPluginAsync(plugin);
                }, bg: new Color(1f, 1f, 1f, 0.08f), textCol: ExoforgeUIStyle.TextPrimary);
                forceBuildBtn.tooltip = "Escape hatch: Force rebuild this plugin from source ignoring cached artifacts";
                top.Add(forceBuildBtn);

                if (IsConnected)
                {
                    var deployBtn = ExoforgeUIStyle.CreateModernButton("🚀 Deploy", async () =>
                    {
                        await DeployPluginAsync(plugin);
                    }, bg: ExoforgeUIStyle.AccentGreenBg, textCol: ExoforgeUIStyle.AccentGreen);
                    top.Add(deployBtn);
                }

                var stubsBtn = ExoforgeUIStyle.CreateModernButton("📝 Stubs", async () =>
                {
                    await GenerateStubsAsync(plugin);
                });
                top.Add(stubsBtn);

                var folderBtn = ExoforgeUIStyle.CreateModernButton("📁 Folder", () =>
                {
                    EditorUtility.RevealInFinder(plugin.LocalDirectory);
                });
                top.Add(folderBtn);
            }

            if (IsConnected)
            {
                var logsBtn = ExoforgeUIStyle.CreateModernButton("📋 Logs", async () =>
                {
                    if (_showPluginLogs && string.Equals(_pluginLogsFor, plugin.Name, StringComparison.OrdinalIgnoreCase))
                    {
                        _showPluginLogs = false;
                        RebuildUI();
                    }
                    else
                    {
                        await FetchPluginLogsAsync(plugin.Name);
                        RebuildUI();
                    }
                });
                logsBtn.tooltip = "View live runtime logs emitted by this plugin on the cluster";
                top.Add(logsBtn);

                var studioBtn = ExoforgeUIStyle.CreateModernButton("🌐 Studio Tab", () =>
                {
                    Application.OpenURL($"{GetHttpUrl()}/tab/{plugin.Id}");
                });
                top.Add(studioBtn);
            }

            hero.Add(top);

            if (_showPluginLogs && string.Equals(_pluginLogsFor, plugin.Name, StringComparison.OrdinalIgnoreCase))
            {
                var logsBox = new VisualElement();
                logsBox.style.marginTop = 10;
                logsBox.style.paddingLeft = 10;
                logsBox.style.paddingRight = 10;
                logsBox.style.paddingTop = 8;
                logsBox.style.paddingBottom = 8;
                logsBox.style.backgroundColor = new Color(0.12f, 0.12f, 0.15f);
                logsBox.style.borderTopWidth = 1;
                logsBox.style.borderTopColor = ExoforgeUIStyle.BorderSubtle;
                logsBox.style.borderTopLeftRadius = 4;
                logsBox.style.borderTopRightRadius = 4;
                logsBox.style.borderBottomLeftRadius = 4;
                logsBox.style.borderBottomRightRadius = 4;

                var logsHeader = new VisualElement();
                logsHeader.style.flexDirection = FlexDirection.Row;
                logsHeader.style.alignItems = Align.Center;
                logsHeader.style.marginBottom = 6;

                var logsTitle = new Label($"📋 Runtime Logs — {plugin.Name}");
                logsTitle.style.fontSize = 11;
                logsTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
                logsTitle.style.color = ExoforgeUIStyle.TextPrimary;
                logsTitle.style.flexGrow = 1;
                logsHeader.Add(logsTitle);

                var refreshLogsBtn = ExoforgeUIStyle.CreateModernButton("🔄 Refresh", async () =>
                {
                    await FetchPluginLogsAsync(plugin.Name);
                    RebuildUI();
                }, height: 22);
                logsHeader.Add(refreshLogsBtn);

                var closeLogsBtn = ExoforgeUIStyle.CreateModernButton("✕", () =>
                {
                    _showPluginLogs = false;
                    RebuildUI();
                }, height: 22);
                closeLogsBtn.style.marginLeft = 6;
                logsHeader.Add(closeLogsBtn);

                logsBox.Add(logsHeader);

                var logText = new TextField { value = _pluginLogs, multiline = true };
                logText.isReadOnly = true;
                logText.style.height = 140;
                logsBox.Add(logText);

                hero.Add(logsBox);
            }

            return hero;
        }

        // =========================================================================
        // Tab 0: Overview
        // =========================================================================

        private VisualElement BuildOverviewTab(PluginCardModel plugin, JsonElement manifest)
        {
            var scroll = new ScrollView();
            scroll.style.flexGrow = 1;

            // Summary Metric Cards
            int resCount = CountResources(manifest);
            int actionCount = CountActions(manifest, excludeWebhooks: true);
            int eventCount = CountEvents(manifest);
            int webhookCount = CountActions(manifest, webhooksOnly: true);

            var metricsRow = new VisualElement();
            metricsRow.style.flexDirection = FlexDirection.Row;
            metricsRow.style.marginBottom = 12;

            metricsRow.Add(CreateMetricCard("📦 Resources", resCount, 1));
            metricsRow.Add(CreateMetricCard("⚡ Actions", actionCount, 2));
            metricsRow.Add(CreateMetricCard("📡 Events", eventCount, 3));
            metricsRow.Add(CreateMetricCard("🌐 Webhooks", webhookCount, 4));
            scroll.Add(metricsRow);

            // Metadata Box
            var metaCard = new VisualElement();
            ExoforgeUIStyle.ApplyCard(metaCard);

            var metaHeader = new Label("Plugin Architecture & Contracts");
            metaHeader.style.fontSize = 12;
            metaHeader.style.unityFontStyleAndWeight = FontStyle.Bold;
            metaHeader.style.color = ExoforgeUIStyle.TextPrimary;
            metaHeader.style.marginBottom = 8;
            metaCard.Add(metaHeader);

            metaCard.Add(CreateMetaRow("Plugin Identifier", plugin.Id));
            metaCard.Add(CreateMetaRow("Runtime Process", plugin.Type == "native" ? ".NET Core Native Process" : "Elixir In-Kernel Module"));
            metaCard.Add(CreateMetaRow("Version", plugin.Version));
            metaCard.Add(CreateMetaRow("Category", plugin.Category));

            if (manifest.ValueKind == JsonValueKind.Object)
            {
                if (manifest.TryGetProperty("provides", out var providesArr) && providesArr.ValueKind == JsonValueKind.Array)
                {
                    var provides = providesArr.EnumerateArray().Select(x => x.GetString()).Where(s => !string.IsNullOrEmpty(s)).ToList();
                    metaCard.Add(CreateMetaRow("Provides Services", string.Join(", ", provides)));
                }

                if (manifest.TryGetProperty("dependencies", out var depsArr) && depsArr.ValueKind == JsonValueKind.Array)
                {
                    var deps = depsArr.EnumerateArray().Select(x => x.GetString()).Where(s => !string.IsNullOrEmpty(s)).ToList();
                    metaCard.Add(CreateMetaRow("Dependencies", deps.Count > 0 ? string.Join(", ", deps) : "(none)"));
                }
            }

            scroll.Add(metaCard);

            // Build Log View if any
            if (!string.IsNullOrEmpty(_buildLog))
            {
                var logBox = new VisualElement();
                ExoforgeUIStyle.ApplyCard(logBox);
                logBox.style.marginTop = 10;

                var logTitle = new Label("Latest Build Log");
                logTitle.style.fontSize = 12;
                logTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
                logTitle.style.color = ExoforgeUIStyle.TextPrimary;
                logTitle.style.marginBottom = 6;
                logBox.Add(logTitle);

                var logText = new TextField { value = _buildLog, multiline = true };
                logText.isReadOnly = true;
                logText.style.height = 100;
                logBox.Add(logText);

                scroll.Add(logBox);
            }

            return scroll;
        }

        private VisualElement CreateMetricCard(string label, int count, int targetTab)
        {
            var card = new VisualElement();
            ExoforgeUIStyle.ApplyCard(card);
            card.style.flexGrow = 1;
            card.style.marginRight = 6;
            card.style.alignItems = Align.Center;

            var title = new Label(label);
            title.style.fontSize = 11;
            title.style.color = ExoforgeUIStyle.TextSecondary;
            card.Add(title);

            var num = new Label(count.ToString());
            num.style.fontSize = 20;
            num.style.unityFontStyleAndWeight = FontStyle.Bold;
            num.style.color = ExoforgeUIStyle.TextPrimary;
            num.style.marginTop = 2;
            num.style.marginBottom = 4;
            card.Add(num);

            var inspectBtn = ExoforgeUIStyle.CreateModernButton("Inspect", () =>
            {
                _selectedDetailTab = targetTab;
                RebuildUI();
            }, height: 18);
            inspectBtn.style.fontSize = 10;
            card.Add(inspectBtn);

            return card;
        }

        private VisualElement CreateMetaRow(string label, string val)
        {
            var row = new VisualElement();
            row.style.flexDirection = FlexDirection.Row;
            row.style.paddingTop = 3;
            row.style.paddingBottom = 3;

            var lbl = new Label(label);
            lbl.style.width = 140;
            lbl.style.fontSize = 11;
            lbl.style.color = ExoforgeUIStyle.TextSecondary;
            row.Add(lbl);

            var valueLabel = new Label(val);
            valueLabel.style.fontSize = 11;
            valueLabel.style.color = ExoforgeUIStyle.TextPrimary;
            valueLabel.style.flexGrow = 1;
            row.Add(valueLabel);

            return row;
        }

        // =========================================================================
        // Tab 1: Resource Management (Live Cluster Explorer & Schema Viewer)
        // =========================================================================

        private VisualElement BuildResourcesTab(PluginCardModel plugin, JsonElement manifest)
        {
            var container = new VisualElement();
            container.style.flexGrow = 1;
            container.style.flexDirection = FlexDirection.Column;

            var resources = ExtractResources(manifest);
            if (resources.Count == 0)
            {
                var empty = new Label("This plugin declares no [ExoResource] or schema models.");
                empty.style.color = ExoforgeUIStyle.TextMuted;
                empty.style.fontSize = 12;
                empty.style.marginTop = 20;
                empty.style.alignSelf = Align.Center;
                container.Add(empty);
                return container;
            }

            // Default selected resource
            if (string.IsNullOrEmpty(_selectedResourceName) && resources.Count > 0)
            {
                _selectedResourceName = resources[0].TryGetProperty("name", out var n) ? n.GetString() : "";
            }

            var currentResource = resources.FirstOrDefault(r =>
                r.TryGetProperty("name", out var n) && string.Equals(n.GetString(), _selectedResourceName, StringComparison.OrdinalIgnoreCase));

            // Top Resource Sub-Toolbar: Resource Selector, Mode Toggle, Action Buttons
            var resToolbar = new VisualElement();
            resToolbar.style.flexDirection = FlexDirection.Row;
            resToolbar.style.alignItems = Align.Center;
            resToolbar.style.marginBottom = 10;

            var resNames = resources.Select(r => r.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "").ToList();
            var dropdown = new DropdownField("Resource:", resNames, Math.Max(0, resNames.IndexOf(_selectedResourceName ?? "")));
            dropdown.style.width = 240;
            dropdown.RegisterValueChangedCallback(evt =>
            {
                _selectedResourceName = evt.newValue;
                _selectedResourceRow = null;
                _showAddRecordForm = false;
                if (IsConnected) _ = FetchLiveResourceDataAsync(_selectedResourceName);
                else RebuildUI();
            });
            resToolbar.Add(dropdown);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            resToolbar.Add(spacer);

            // Mode Toggle: Live Data Explorer vs Schema Definition
            var dataToggleBtn = ExoforgeUIStyle.CreateModernButton(
                "📊 Live Data",
                () => { _resourceSchemaViewMode = false; RebuildUI(); },
                bg: !_resourceSchemaViewMode ? ExoforgeUIStyle.AccentBlueBg : null,
                textCol: !_resourceSchemaViewMode ? ExoforgeUIStyle.AccentBlue : null,
                height: 22);
            resToolbar.Add(dataToggleBtn);

            var schemaToggleBtn = ExoforgeUIStyle.CreateModernButton(
                "📐 Schema",
                () => { _resourceSchemaViewMode = true; RebuildUI(); },
                bg: _resourceSchemaViewMode ? ExoforgeUIStyle.AccentBlueBg : null,
                textCol: !_resourceSchemaViewMode ? null : ExoforgeUIStyle.AccentBlue,
                height: 22);
            resToolbar.Add(schemaToggleBtn);

            container.Add(resToolbar);

            if (currentResource.ValueKind != JsonValueKind.Object)
            {
                return container;
            }

            string pk = currentResource.TryGetProperty("primary_key", out var pkProp) ? pkProp.GetString() ?? "id" : "id";
            string recordType = currentResource.TryGetProperty("record", out var rc) ? rc.GetString() ?? "" : "";
            bool isSingleton = currentResource.TryGetProperty("singleton", out var sProp) && sProp.GetBoolean();

            // Resource Info Bar
            var infoBar = new VisualElement();
            infoBar.style.flexDirection = FlexDirection.Row;
            infoBar.style.alignItems = Align.Center;
            infoBar.style.paddingLeft = 8;
            infoBar.style.paddingRight = 8;
            infoBar.style.paddingTop = 4;
            infoBar.style.paddingBottom = 4;
            infoBar.style.backgroundColor = ExoforgeUIStyle.BgPanel;
            infoBar.style.borderTopLeftRadius = 4;
            infoBar.style.borderTopRightRadius = 4;
            infoBar.style.borderBottomLeftRadius = 4;
            infoBar.style.borderBottomRightRadius = 4;
            infoBar.style.marginBottom = 8;

            infoBar.Add(ExoforgeUIStyle.CreatePill($"PK: {pk}", ExoforgeUIStyle.TextPrimary, ExoforgeUIStyle.BgWindow));
            infoBar.Add(ExoforgeUIStyle.CreatePill(isSingleton ? "Singleton Resource" : "Table-Backed Resource", ExoforgeUIStyle.AccentPurple, ExoforgeUIStyle.AccentPurpleBg));
            if (!string.IsNullOrEmpty(recordType))
            {
                infoBar.Add(ExoforgeUIStyle.CreatePill($"Model: {recordType}", ExoforgeUIStyle.TextSecondary, ExoforgeUIStyle.BgWindow));
            }

            container.Add(infoBar);

            // Render either Schema view or Live Data Explorer
            if (_resourceSchemaViewMode)
            {
                container.Add(BuildResourceSchemaView(currentResource, pk));
            }
            else
            {
                container.Add(BuildResourceDataExplorer(currentResource, pk, isSingleton));
            }

            return container;
        }

        private VisualElement BuildResourceSchemaView(JsonElement resource, string pk)
        {
            var scroll = new ScrollView();
            scroll.style.flexGrow = 1;

            if (resource.TryGetProperty("columns", out var cols) && cols.ValueKind == JsonValueKind.Array)
            {
                // Table Header
                var tableHeader = new VisualElement();
                tableHeader.style.flexDirection = FlexDirection.Row;
                tableHeader.style.backgroundColor = ExoforgeUIStyle.BgPanel;
                tableHeader.style.borderBottomWidth = 1;
                tableHeader.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
                tableHeader.style.paddingTop = 6;
                tableHeader.style.paddingBottom = 6;
                tableHeader.style.paddingLeft = 8;

                tableHeader.Add(CreateColumnHeader("Column Name", 140));
                tableHeader.Add(CreateColumnHeader("Type", 90));
                tableHeader.Add(CreateColumnHeader("Label", 130));
                tableHeader.Add(CreateColumnHeader("Attributes / Constraints", 180));
                scroll.Add(tableHeader);

                foreach (var col in cols.EnumerateArray())
                {
                    string cName = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "";
                    string cType = col.TryGetProperty("type", out var ct) ? ct.GetString() ?? "" : "";
                    string cLabel = col.TryGetProperty("label", out var cl) ? cl.GetString() ?? "" : "";
                    bool sortable = col.TryGetProperty("sortable", out var cs) && cs.GetBoolean();
                    bool filterable = col.TryGetProperty("filterable", out var cf) && cf.GetBoolean();
                    bool badge = col.TryGetProperty("badge", out var cb) && cb.GetBoolean();

                    var row = new VisualElement();
                    row.style.flexDirection = FlexDirection.Row;
                    row.style.alignItems = Align.Center;
                    row.style.paddingTop = 5;
                    row.style.paddingBottom = 5;
                    row.style.paddingLeft = 8;
                    row.style.borderBottomWidth = 1;
                    row.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;

                    var nameCol = new Label(cName);
                    nameCol.style.width = 140;
                    nameCol.style.fontSize = 11;
                    nameCol.style.unityFontStyleAndWeight = (cName == pk) ? FontStyle.Bold : FontStyle.Normal;
                    nameCol.style.color = (cName == pk) ? ExoforgeUIStyle.AccentBlue : ExoforgeUIStyle.TextPrimary;
                    row.Add(nameCol);

                    var typeCol = new Label(cType);
                    typeCol.style.width = 90;
                    typeCol.style.fontSize = 11;
                    typeCol.style.color = ExoforgeUIStyle.TextSecondary;
                    row.Add(typeCol);

                    var labelCol = new Label(cLabel);
                    labelCol.style.width = 130;
                    labelCol.style.fontSize = 11;
                    labelCol.style.color = ExoforgeUIStyle.TextSecondary;
                    row.Add(labelCol);

                    var attrContainer = new VisualElement();
                    attrContainer.style.flexDirection = FlexDirection.Row;
                    if (cName == pk) attrContainer.Add(ExoforgeUIStyle.CreatePill("Primary Key", ExoforgeUIStyle.AccentBlue, ExoforgeUIStyle.AccentBlueBg, 9));
                    if (sortable) attrContainer.Add(ExoforgeUIStyle.CreatePill("Sortable", ExoforgeUIStyle.AccentGreen, ExoforgeUIStyle.AccentGreenBg, 9));
                    if (filterable) attrContainer.Add(ExoforgeUIStyle.CreatePill("Filterable", ExoforgeUIStyle.AccentOrange, ExoforgeUIStyle.AccentOrangeBg, 9));
                    if (badge) attrContainer.Add(ExoforgeUIStyle.CreatePill("Badge", ExoforgeUIStyle.AccentPurple, ExoforgeUIStyle.AccentPurpleBg, 9));
                    row.Add(attrContainer);

                    scroll.Add(row);
                }
            }

            return scroll;
        }

        private VisualElement BuildResourceDataExplorer(JsonElement resource, string pk, bool isSingleton)
        {
            var root = new VisualElement();
            root.style.flexGrow = 1;
            root.style.flexDirection = FlexDirection.Column;

            if (!IsConnected)
            {
                var offlineBox = new VisualElement();
                ExoforgeUIStyle.ApplyCard(offlineBox);
                offlineBox.style.marginTop = 12;

                var offlineTitle = new Label("Live Cluster Disconnected");
                offlineTitle.style.fontSize = 13;
                offlineTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
                offlineTitle.style.color = ExoforgeUIStyle.AccentOrange;
                offlineBox.Add(offlineTitle);

                var offlineDesc = new Label("Connect to your local or remote Exoforge cluster to browse live records, insert test data, edit values in place, and purge tables.");
                offlineDesc.style.fontSize = 11;
                offlineDesc.style.color = ExoforgeUIStyle.TextSecondary;
                offlineDesc.style.marginTop = 4;
                offlineDesc.style.marginBottom = 10;
                offlineBox.Add(offlineDesc);

                var connectNowBtn = ExoforgeUIStyle.CreateModernButton("⚡ Connect to Cluster", async () =>
                {
                    await ExoforgeControlCenter.ConnectSharedAsync();
                    if (IsConnected && !string.IsNullOrEmpty(_selectedResourceName))
                    {
                        await FetchLiveResourceDataAsync(_selectedResourceName);
                    }
                    RebuildUI();
                }, bg: ExoforgeUIStyle.AccentGreenBg, textCol: ExoforgeUIStyle.AccentGreen);
                offlineBox.Add(connectNowBtn);

                root.Add(offlineBox);
                return root;
            }

            // Data Operations Toolbar
            var dataBar = new VisualElement();
            dataBar.style.flexDirection = FlexDirection.Row;
            dataBar.style.alignItems = Align.Center;
            dataBar.style.marginBottom = 6;

            var refreshDataBtn = ExoforgeUIStyle.CreateModernButton("🔄 Refresh Data", async () =>
            {
                if (!string.IsNullOrEmpty(_selectedResourceName))
                {
                    await FetchLiveResourceDataAsync(_selectedResourceName);
                }
            }, height: 22);
            dataBar.Add(refreshDataBtn);

            if (!isSingleton)
            {
                var addRecordBtn = ExoforgeUIStyle.CreateModernButton(
                    _showAddRecordForm ? "Cancel Add" : "➕ Insert Record",
                    () =>
                    {
                        _showAddRecordForm = !_showAddRecordForm;
                        _newRecordValues.Clear();
                        RebuildUI();
                    },
                    bg: _showAddRecordForm ? ExoforgeUIStyle.AccentOrangeBg : ExoforgeUIStyle.AccentGreenBg,
                    textCol: _showAddRecordForm ? ExoforgeUIStyle.AccentOrange : ExoforgeUIStyle.AccentGreen,
                    height: 22);
                dataBar.Add(addRecordBtn);

                var clearTableBtn = ExoforgeUIStyle.CreateModernButton("🗑️ Clear All", async () =>
                {
                    if (EditorUtility.DisplayDialog("Clear Resource Table", $"Are you sure you want to delete all rows from '{_selectedResourceName}'?", "Clear", "Cancel"))
                    {
                        await ClearResourceDataAsync(_selectedResourceName!);
                    }
                }, bg: ExoforgeUIStyle.AccentRedBg, textCol: ExoforgeUIStyle.AccentRed, height: 22);
                dataBar.Add(clearTableBtn);
            }

            var barSpacer = new VisualElement();
            barSpacer.style.flexGrow = 1;
            dataBar.Add(barSpacer);

            var countLabel = new Label($"{_liveResourceRows.Count} record(s)");
            countLabel.style.fontSize = 11;
            countLabel.style.color = ExoforgeUIStyle.TextSecondary;
            dataBar.Add(countLabel);

            root.Add(dataBar);

            // Add Record Form (if toggled)
            if (_showAddRecordForm && !isSingleton)
            {
                root.Add(BuildAddRecordForm(resource, pk));
            }

            // Main Data Area: Table + Inspector
            var dataSplit = new TwoPaneSplitView(0, 320, TwoPaneSplitViewOrientation.Horizontal);
            dataSplit.style.flexGrow = 1;

            var tableContainer = BuildDataGrid(resource, pk);
            var inspectorContainer = BuildRecordInspector(resource, pk, isSingleton);

            dataSplit.Add(tableContainer);
            dataSplit.Add(inspectorContainer);

            root.Add(dataSplit);
            return root;
        }

        private VisualElement BuildDataGrid(JsonElement resource, string pk)
        {
            var scroll = new ScrollView();
            scroll.style.flexGrow = 1;
            scroll.style.borderTopWidth = 1;
            scroll.style.borderBottomWidth = 1;
            scroll.style.borderLeftWidth = 1;
            scroll.style.borderRightWidth = 1;
            scroll.style.borderTopColor = ExoforgeUIStyle.BorderSubtle;
            scroll.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
            scroll.style.borderLeftColor = ExoforgeUIStyle.BorderSubtle;
            scroll.style.borderRightColor = ExoforgeUIStyle.BorderSubtle;
            scroll.style.backgroundColor = ExoforgeUIStyle.BgCard;

            var cols = resource.TryGetProperty("columns", out var cArr) && cArr.ValueKind == JsonValueKind.Array
                ? cArr.EnumerateArray().ToList()
                : new List<JsonElement>();

            // Header Row
            var header = new VisualElement();
            header.style.flexDirection = FlexDirection.Row;
            header.style.backgroundColor = ExoforgeUIStyle.BgPanel;
            header.style.borderBottomWidth = 1;
            header.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
            header.style.paddingTop = 4;
            header.style.paddingBottom = 4;
            header.style.paddingLeft = 6;

            foreach (var col in cols)
            {
                string colName = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "";
                header.Add(CreateColumnHeader(colName, 100));
            }
            scroll.Add(header);

            if (_liveResourceRows.Count == 0)
            {
                var empty = new Label("No records found in this table.");
                empty.style.color = ExoforgeUIStyle.TextMuted;
                empty.style.fontSize = 11;
                empty.style.paddingTop = 16;
                empty.style.alignSelf = Align.Center;
                scroll.Add(empty);
                return scroll;
            }

            // Data Rows
            for (int i = 0; i < _liveResourceRows.Count; i++)
            {
                var rowData = _liveResourceRows[i];
                bool isSelected = _selectedResourceRow.HasValue &&
                                  string.Equals(GetRowPkValue(_selectedResourceRow.Value, pk), GetRowPkValue(rowData, pk));

                var rowEl = new VisualElement();
                rowEl.style.flexDirection = FlexDirection.Row;
                rowEl.style.paddingTop = 4;
                rowEl.style.paddingBottom = 4;
                rowEl.style.paddingLeft = 6;
                rowEl.style.borderBottomWidth = 1;
                rowEl.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
                rowEl.style.backgroundColor = isSelected ? ExoforgeUIStyle.BgCardSelected : (i % 2 == 0 ? ExoforgeUIStyle.BgCard : ExoforgeUIStyle.BgPanel);

                rowEl.RegisterCallback<ClickEvent>(evt =>
                {
                    _selectedResourceRow = rowData;
                    _editFieldValues.Clear();
                    if (rowData.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var prop in rowData.EnumerateObject())
                        {
                            _editFieldValues[prop.Name] = prop.Value.ToString();
                        }
                    }
                    RebuildUI();
                });

                foreach (var col in cols)
                {
                    string colName = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "";
                    string cellVal = rowData.TryGetProperty(colName, out var val) ? val.ToString() : "";

                    var cell = new Label(cellVal);
                    cell.style.width = 100;
                    cell.style.fontSize = 11;
                    cell.style.color = isSelected ? ExoforgeUIStyle.AccentBlue : ExoforgeUIStyle.TextPrimary;
                    rowEl.Add(cell);
                }

                scroll.Add(rowEl);
            }

            return scroll;
        }

        private VisualElement BuildRecordInspector(JsonElement resource, string pk, bool isSingleton)
        {
            var inspector = new VisualElement();
            inspector.style.flexDirection = FlexDirection.Column;
            inspector.style.backgroundColor = ExoforgeUIStyle.BgPanel;
            inspector.style.paddingLeft = 10;
            inspector.style.paddingRight = 10;
            inspector.style.paddingTop = 8;
            inspector.style.paddingBottom = 8;

            var title = new Label(isSingleton ? "Singleton Configuration" : "Record Inspector");
            title.style.fontSize = 12;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            title.style.marginBottom = 6;
            inspector.Add(title);

            if (!_selectedResourceRow.HasValue && !isSingleton)
            {
                var selectHint = new Label("Select a row in the table to inspect or edit its fields.");
                selectHint.style.fontSize = 11;
                selectHint.style.color = ExoforgeUIStyle.TextMuted;
                selectHint.style.marginTop = 12;
                inspector.Add(selectHint);
                return inspector;
            }

            var scroll = new ScrollView();
            scroll.style.flexGrow = 1;

            var cols = resource.TryGetProperty("columns", out var cArr) && cArr.ValueKind == JsonValueKind.Array
                ? cArr.EnumerateArray().ToList()
                : new List<JsonElement>();

            foreach (var col in cols)
            {
                string colName = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "";
                string curVal = _editFieldValues.TryGetValue(colName, out var v) ? v : "";

                bool isPk = colName == pk;
                var field = new TextField(colName);
                field.value = curVal;
                field.isReadOnly = isPk && !isSingleton; // Primary keys cannot be edited in-place
                field.RegisterValueChangedCallback(evt =>
                {
                    _editFieldValues[colName] = evt.newValue;
                });
                scroll.Add(field);
            }

            inspector.Add(scroll);

            // Action Buttons: Save Changes & Delete Row
            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.marginTop = 8;

            var saveBtn = ExoforgeUIStyle.CreateModernButton("💾 Save Changes", async () =>
            {
                await SaveResourceRowAsync(_selectedResourceName!, pk, isSingleton);
            }, bg: ExoforgeUIStyle.AccentGreenBg, textCol: ExoforgeUIStyle.AccentGreen, height: 24);
            btnRow.Add(saveBtn);

            if (!isSingleton)
            {
                var deleteBtn = ExoforgeUIStyle.CreateModernButton("❌ Delete Row", async () =>
                {
                    string id = _editFieldValues.TryGetValue(pk, out var idVal) ? idVal : "";
                    if (EditorUtility.DisplayDialog("Delete Record", $"Delete record with {pk} = '{id}'?", "Delete", "Cancel"))
                    {
                        await DeleteResourceRowAsync(_selectedResourceName!, id);
                    }
                }, bg: ExoforgeUIStyle.AccentRedBg, textCol: ExoforgeUIStyle.AccentRed, height: 24);
                btnRow.Add(deleteBtn);
            }

            inspector.Add(btnRow);
            return inspector;
        }

        private VisualElement BuildAddRecordForm(JsonElement resource, string pk)
        {
            var form = new VisualElement();
            ExoforgeUIStyle.ApplyCard(form);
            form.style.backgroundColor = ExoforgeUIStyle.BgCardHover;
            form.style.marginBottom = 10;

            var title = new Label("Insert New Record");
            title.style.fontSize = 12;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            title.style.marginBottom = 6;
            form.Add(title);

            var cols = resource.TryGetProperty("columns", out var cArr) && cArr.ValueKind == JsonValueKind.Array
                ? cArr.EnumerateArray().ToList()
                : new List<JsonElement>();

            var fieldsContainer = new VisualElement();
            foreach (var col in cols)
            {
                string colName = col.TryGetProperty("name", out var cn) ? cn.GetString() ?? "" : "";
                string colType = col.TryGetProperty("type", out var ct) ? ct.GetString() ?? "string" : "string";

                var tf = new TextField($"{colName} ({colType})");
                tf.RegisterValueChangedCallback(evt =>
                {
                    _newRecordValues[colName] = evt.newValue;
                });
                fieldsContainer.Add(tf);
            }
            form.Add(fieldsContainer);

            var submitBtn = ExoforgeUIStyle.CreateModernButton("Submit Record", async () =>
            {
                await InsertResourceRowAsync(_selectedResourceName!);
            }, bg: ExoforgeUIStyle.AccentGreenBg, textCol: ExoforgeUIStyle.AccentGreen, height: 24);
            submitBtn.style.marginTop = 6;
            form.Add(submitBtn);

            return form;
        }

        private static Label CreateColumnHeader(string title, float width)
        {
            var label = new Label(title);
            label.style.width = width;
            label.style.fontSize = 11;
            label.style.unityFontStyleAndWeight = FontStyle.Bold;
            label.style.color = ExoforgeUIStyle.TextSecondary;
            return label;
        }

        private static string GetRowPkValue(JsonElement row, string pk)
        {
            if (row.ValueKind == JsonValueKind.Object && row.TryGetProperty(pk, out var val))
            {
                return val.ToString();
            }
            return "";
        }

        // =========================================================================
        // Tab 2: Actions Sandbox
        // =========================================================================

        private VisualElement BuildActionsTab(PluginCardModel plugin, JsonElement manifest)
        {
            var container = new VisualElement();
            container.style.flexGrow = 1;

            var actions = ExtractActions(manifest, isWebhookOnly: false);
            if (actions.Count == 0)
            {
                var empty = new Label("No actions declared for this plugin.");
                empty.style.color = ExoforgeUIStyle.TextMuted;
                empty.style.fontSize = 12;
                empty.style.marginTop = 20;
                empty.style.alignSelf = Align.Center;
                container.Add(empty);
                return container;
            }

            var split = new TwoPaneSplitView(0, 320, TwoPaneSplitViewOrientation.Horizontal);
            split.style.flexGrow = 1;

            // Left: Actions List
            var listScroll = new ScrollView();
            listScroll.style.flexGrow = 1;

            if (string.IsNullOrEmpty(_sandboxSelectedAction) && actions.Count > 0)
            {
                _sandboxSelectedAction = actions[0].TryGetProperty("name", out var n) ? n.GetString() : "";
            }

            foreach (var a in actions)
            {
                string name = a.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                string mode = a.TryGetProperty("mode", out var m) ? m.GetString() ?? "sync" : "sync";
                string scope = a.TryGetProperty("scope", out var s) ? s.GetString() ?? "global" : "global";
                bool isSelected = string.Equals(name, _sandboxSelectedAction, StringComparison.OrdinalIgnoreCase);

                var card = new VisualElement();
                ExoforgeUIStyle.ApplyCard(card, isSelected);

                card.RegisterCallback<ClickEvent>(evt =>
                {
                    _sandboxSelectedAction = name;
                    _sandboxResult = "";
                    _sandboxLatency = "";
                    RebuildUI();
                });

                var row = new VisualElement();
                row.style.flexDirection = FlexDirection.Row;
                row.style.alignItems = Align.Center;

                var actName = new Label($"⚡ {name}");
                actName.style.fontSize = 12;
                actName.style.unityFontStyleAndWeight = FontStyle.Bold;
                actName.style.color = isSelected ? ExoforgeUIStyle.AccentBlue : ExoforgeUIStyle.TextPrimary;
                actName.style.flexGrow = 1;
                row.Add(actName);

                row.Add(ExoforgeUIStyle.CreatePill(mode, ExoforgeUIStyle.TextSecondary, ExoforgeUIStyle.BgWindow, 9));
                card.Add(row);

                listScroll.Add(card);
            }
            split.Add(listScroll);

            // Right: Interactive Action Tester
            var runner = new VisualElement();
            runner.style.flexDirection = FlexDirection.Column;
            runner.style.backgroundColor = ExoforgeUIStyle.BgPanel;
            runner.style.paddingLeft = 10;
            runner.style.paddingRight = 10;
            runner.style.paddingTop = 8;
            runner.style.paddingBottom = 8;

            var rTitle = new Label($"Invoke Action: {_sandboxSelectedAction}");
            rTitle.style.fontSize = 13;
            rTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            rTitle.style.color = ExoforgeUIStyle.TextPrimary;
            runner.Add(rTitle);

            var payloadHeader = new VisualElement();
            payloadHeader.style.flexDirection = FlexDirection.Row;
            payloadHeader.style.alignItems = Align.Center;
            payloadHeader.style.justifyContent = Justify.SpaceBetween;
            payloadHeader.style.marginTop = 6;

            var payloadLabel = new Label("JSON Payload Arguments:");
            payloadLabel.style.fontSize = 11;
            payloadLabel.style.color = ExoforgeUIStyle.TextSecondary;
            payloadHeader.Add(payloadLabel);

            var toolBtns = new VisualElement();
            toolBtns.style.flexDirection = FlexDirection.Row;

            var formatBtn = ExoforgeUIStyle.CreateModernButton("Format JSON", () =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(_sandboxPayload);
                    _sandboxPayload = JsonSerializer.Serialize(doc.RootElement, new JsonSerializerOptions { WriteIndented = true });
                    RebuildUI();
                }
                catch { }
            }, height: 20);
            formatBtn.style.fontSize = 10;
            formatBtn.style.paddingLeft = 6;
            formatBtn.style.paddingRight = 6;
            toolBtns.Add(formatBtn);

            var templateBtn = ExoforgeUIStyle.CreateModernButton("Load Template", () =>
            {
                _sandboxPayload = GenerateSamplePayload(manifest, _sandboxSelectedAction);
                RebuildUI();
            }, height: 20);
            templateBtn.style.fontSize = 10;
            templateBtn.style.paddingLeft = 6;
            templateBtn.style.paddingRight = 6;
            toolBtns.Add(templateBtn);

            payloadHeader.Add(toolBtns);
            runner.Add(payloadHeader);

            var payloadInput = new TextField { value = _sandboxPayload, multiline = true };
            payloadInput.style.height = 75;
            payloadInput.RegisterValueChangedCallback(evt => _sandboxPayload = evt.newValue);
            runner.Add(payloadInput);

            var invokeBtn = ExoforgeUIStyle.CreateModernButton(
                _isInvokingAction ? "Invoking..." : "⚡ Execute Action",
                async () =>
                {
                    await InvokeSandboxActionAsync(plugin.Id, _sandboxSelectedAction!);
                },
                bg: ExoforgeUIStyle.BrandPurple,
                textCol: Color.white,
                height: 28);
            invokeBtn.style.marginTop = 6;
            runner.Add(invokeBtn);

            if (!string.IsNullOrEmpty(_sandboxLatency))
            {
                var latencyLabel = new Label(_sandboxLatency);
                latencyLabel.style.fontSize = 10;
                latencyLabel.style.color = ExoforgeUIStyle.AccentGreen;
                latencyLabel.style.marginTop = 4;
                runner.Add(latencyLabel);
            }

            var resultLabel = new Label("Response Result:");
            resultLabel.style.fontSize = 11;
            resultLabel.style.color = ExoforgeUIStyle.TextSecondary;
            resultLabel.style.marginTop = 6;
            runner.Add(resultLabel);

            var resultBox = new TextField { value = _sandboxResult, multiline = true };
            resultBox.isReadOnly = true;
            resultBox.style.flexGrow = 1;
            runner.Add(resultBox);

            split.Add(runner);
            container.Add(split);
            return container;
        }

        // =========================================================================
        // Tab 3: Events & Tab 4: Webhooks
        // =========================================================================

        private VisualElement BuildEventsTab(JsonElement manifest)
        {
            var scroll = new ScrollView();
            scroll.style.flexGrow = 1;

            var events = ExtractEvents(manifest);
            if (events.Count == 0)
            {
                var empty = new Label("This plugin declares no events.");
                empty.style.color = ExoforgeUIStyle.TextMuted;
                empty.style.fontSize = 12;
                empty.style.marginTop = 20;
                empty.style.alignSelf = Align.Center;
                scroll.Add(empty);
                return scroll;
            }

            foreach (var e in events)
            {
                string name = e.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                string topic = e.TryGetProperty("topic", out var t) ? t.GetString() ?? "—" : "—";
                string payloadType = e.TryGetProperty("payload_type", out var pt) ? pt.GetString() ?? "" : "";

                var card = new VisualElement();
                ExoforgeUIStyle.ApplyCard(card);

                var row = new VisualElement();
                row.style.flexDirection = FlexDirection.Row;
                row.style.alignItems = Align.Center;

                var eName = new Label($"📡 {name}");
                eName.style.fontSize = 12;
                eName.style.unityFontStyleAndWeight = FontStyle.Bold;
                eName.style.color = ExoforgeUIStyle.TextPrimary;
                eName.style.flexGrow = 1;
                row.Add(eName);

                row.Add(ExoforgeUIStyle.CreatePill($"Topic: {topic}", ExoforgeUIStyle.AccentPurple, ExoforgeUIStyle.AccentPurpleBg, 9));
                card.Add(row);

                if (!string.IsNullOrEmpty(payloadType))
                {
                    var pLabel = new Label($"Payload Model: {payloadType}");
                    pLabel.style.fontSize = 11;
                    pLabel.style.color = ExoforgeUIStyle.TextSecondary;
                    pLabel.style.marginTop = 3;
                    card.Add(pLabel);
                }

                scroll.Add(card);
            }

            return scroll;
        }

        private VisualElement BuildWebhooksTab(PluginCardModel plugin, JsonElement manifest)
        {
            var scroll = new ScrollView();
            scroll.style.flexGrow = 1;

            var webhooks = ExtractActions(manifest, isWebhookOnly: true);
            if (webhooks.Count == 0)
            {
                var empty = new Label("This plugin defines no actions marked with [ExoWebhook].");
                empty.style.color = ExoforgeUIStyle.TextMuted;
                empty.style.fontSize = 12;
                empty.style.marginTop = 20;
                empty.style.alignSelf = Align.Center;
                scroll.Add(empty);
                return scroll;
            }

            string host = GetHttpUrl();
            foreach (var w in webhooks)
            {
                string actionName = w.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                string endpoint = $"{host}/api/webhooks/{plugin.Id}/{actionName}";

                var card = new VisualElement();
                ExoforgeUIStyle.ApplyCard(card);

                var title = new Label($"🌐 POST /api/webhooks/{plugin.Id}/{actionName}");
                title.style.fontSize = 12;
                title.style.unityFontStyleAndWeight = FontStyle.Bold;
                title.style.color = ExoforgeUIStyle.TextPrimary;
                card.Add(title);

                var urlRow = new VisualElement();
                urlRow.style.flexDirection = FlexDirection.Row;
                urlRow.style.alignItems = Align.Center;
                urlRow.style.marginTop = 4;

                var tf = new TextField { value = endpoint, isReadOnly = true };
                tf.style.flexGrow = 1;
                urlRow.Add(tf);

                var copyBtn = ExoforgeUIStyle.CreateModernButton("Copy", () =>
                {
                    EditorGUIUtility.systemCopyBuffer = endpoint;
                    ShowStatus($"Copied webhook URL to clipboard: {endpoint}");
                }, height: 20);
                urlRow.Add(copyBtn);

                card.Add(urlRow);
                scroll.Add(card);
            }

            return scroll;
        }

        // =========================================================================
        // Cluster & SDK Operations (Async)
        // =========================================================================

        private static ExoClient? GetClient() => ExoforgeControlCenter.SharedClient;
        private static bool IsConnected => ExoforgeControlCenter.IsClusterConnected;
        private static string GetHttpUrl() => ExoforgeControlCenter.ActiveHttpEndpoint;

        private void ShowStatus(string msg)
        {
            _statusMessage = msg;
            RebuildUI();
        }

        private async Task RefreshPluginsDataAsync()
        {
            _isLoading = true;
            try
            {
                var list = new List<PluginCardModel>();
                var manifests = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);

                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                var ws = ExoWorkspace.Load(wsPath);

                // 1. Scan Local Workspace Plugins
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

                // 2. Query Cluster Manifest Export
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
                RebuildUI();
            }
        }

        private async Task FetchLiveResourceDataAsync(string resourceName)
        {
            var client = GetClient();
            if (client == null || !client.IsConnected) return;

            _isLoadingResources = true;
            try
            {
                // Query resource_store.list
                var payload = new Dictionary<string, object>
                {
                    ["resource"] = resourceName,
                    ["limit"] = 50
                };

                var res = await client.SendActionAsync<JsonElement>("resource_store", "list", payload);
                var rowsList = new List<JsonElement>();

                if (res.ValueKind == JsonValueKind.Object && res.TryGetProperty("rows", out var rowsArr) && rowsArr.ValueKind == JsonValueKind.Array)
                {
                    foreach (var r in rowsArr.EnumerateArray())
                    {
                        rowsList.Add(r.Clone());
                    }
                }

                _liveResourceRows = rowsList;
                if (_liveResourceRows.Count > 0 && !_selectedResourceRow.HasValue)
                {
                    _selectedResourceRow = _liveResourceRows[0];
                    _editFieldValues.Clear();
                    foreach (var prop in _selectedResourceRow.Value.EnumerateObject())
                    {
                        _editFieldValues[prop.Name] = prop.Value.ToString();
                    }
                }
            }
            catch (Exception ex)
            {
                ShowStatus($"Failed to fetch data for '{resourceName}': {ex.Message}");
            }
            finally
            {
                _isLoadingResources = false;
                RebuildUI();
            }
        }

        private async Task SaveResourceRowAsync(string resourceName, string pk, bool isSingleton)
        {
            var client = GetClient();
            if (client == null || !client.IsConnected) return;

            try
            {
                var attrs = new Dictionary<string, object>();
                foreach (var kvp in _editFieldValues)
                {
                    // Convert basic types if applicable
                    if (int.TryParse(kvp.Value, out int intVal)) attrs[kvp.Key] = intVal;
                    else if (double.TryParse(kvp.Value, out double doubleVal)) attrs[kvp.Key] = doubleVal;
                    else if (bool.TryParse(kvp.Value, out bool boolVal)) attrs[kvp.Key] = boolVal;
                    else attrs[kvp.Key] = kvp.Value;
                }

                if (isSingleton)
                {
                    var payload = new Dictionary<string, object>
                    {
                        ["resource"] = resourceName,
                        ["attributes"] = attrs
                    };
                    await client.SendActionAsync<JsonElement>("resource_store", "update", payload);
                    ShowStatus($"✓ Updated singleton configuration for '{resourceName}'.");
                }
                else
                {
                    string id = _editFieldValues.TryGetValue(pk, out var idVal) ? idVal : "";
                    var payload = new Dictionary<string, object>
                    {
                        ["resource"] = resourceName,
                        ["id"] = id,
                        ["attributes"] = attrs
                    };
                    await client.SendActionAsync<JsonElement>("resource_store", "update", payload);
                    ShowStatus($"✓ Updated record '{id}' in '{resourceName}'.");
                }

                await FetchLiveResourceDataAsync(resourceName);
            }
            catch (Exception ex)
            {
                ShowStatus($"Save failed: {ex.Message}");
            }
        }

        private async Task InsertResourceRowAsync(string resourceName)
        {
            var client = GetClient();
            if (client == null || !client.IsConnected) return;

            try
            {
                var attrs = new Dictionary<string, object>();
                foreach (var kvp in _newRecordValues)
                {
                    if (int.TryParse(kvp.Value, out int intVal)) attrs[kvp.Key] = intVal;
                    else if (double.TryParse(kvp.Value, out double doubleVal)) attrs[kvp.Key] = doubleVal;
                    else if (bool.TryParse(kvp.Value, out bool boolVal)) attrs[kvp.Key] = boolVal;
                    else attrs[kvp.Key] = kvp.Value;
                }

                var payload = new Dictionary<string, object>
                {
                    ["resource"] = resourceName,
                    ["attributes"] = attrs
                };

                await client.SendActionAsync<JsonElement>("resource_store", "create", payload);
                _showAddRecordForm = false;
                _newRecordValues.Clear();
                ShowStatus($"✓ Created record in '{resourceName}'.");
                await FetchLiveResourceDataAsync(resourceName);
            }
            catch (Exception ex)
            {
                ShowStatus($"Insert failed: {ex.Message}");
            }
        }

        private async Task DeleteResourceRowAsync(string resourceName, string id)
        {
            var client = GetClient();
            if (client == null || !client.IsConnected) return;

            try
            {
                var payload = new Dictionary<string, object>
                {
                    ["resource"] = resourceName,
                    ["id"] = id
                };

                await client.SendActionAsync<JsonElement>("resource_store", "delete", payload);
                _selectedResourceRow = null;
                _editFieldValues.Clear();
                ShowStatus($"✓ Deleted record '{id}' from '{resourceName}'.");
                await FetchLiveResourceDataAsync(resourceName);
            }
            catch (Exception ex)
            {
                ShowStatus($"Delete failed: {ex.Message}");
            }
        }

        private async Task ClearResourceDataAsync(string resourceName)
        {
            var client = GetClient();
            if (client == null || !client.IsConnected) return;

            try
            {
                var payload = new Dictionary<string, object>
                {
                    ["resource"] = resourceName
                };

                await client.SendActionAsync<JsonElement>("resource_store", "clear", payload);
                _selectedResourceRow = null;
                _editFieldValues.Clear();
                ShowStatus($"✓ Cleared all records from '{resourceName}'.");
                await FetchLiveResourceDataAsync(resourceName);
            }
            catch (Exception ex)
            {
                ShowStatus($"Clear failed: {ex.Message}");
            }
        }

        private async Task InvokeSandboxActionAsync(string pluginId, string actionName)
        {
            var client = GetClient();
            if (client == null || !client.IsConnected)
            {
                _sandboxResult = "Error: Not connected to cluster.";
                RebuildUI();
                return;
            }

            _isInvokingAction = true;
            RebuildUI();

            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                object? payloadObj = null;
                if (!string.IsNullOrWhiteSpace(_sandboxPayload) && _sandboxPayload.Trim() != "{}")
                {
                    payloadObj = JsonDocument.Parse(_sandboxPayload).RootElement;
                }

                var res = await client.SendActionAsync<JsonElement>(pluginId, actionName, payloadObj);
                sw.Stop();
                _sandboxLatency = $"Latency: {sw.ElapsedMilliseconds} ms";

                var options = new JsonSerializerOptions { WriteIndented = true };
                _sandboxResult = JsonSerializer.Serialize(res, options);
            }
            catch (Exception ex)
            {
                sw.Stop();
                _sandboxLatency = $"Failed after {sw.ElapsedMilliseconds} ms";
                _sandboxResult = $"Error invoking {actionName}: {ex.Message}";
            }
            finally
            {
                _isInvokingAction = false;
                RebuildUI();
            }
        }

        private async Task ForceBuildPluginAsync(PluginCardModel plugin)
        {
            if (_isBuilding) return;

            // Escape hatch: clean out intermediate artifacts and rebuild cleanly
            try
            {
                string stagedDir = Path.Combine(plugin.LocalDirectory, ".exoforge");
                if (Directory.Exists(stagedDir)) Directory.Delete(stagedDir, true);
                string binDir = Path.Combine(plugin.LocalDirectory, "bin");
                if (Directory.Exists(binDir)) Directory.Delete(binDir, true);
                string objDir = Path.Combine(plugin.LocalDirectory, "obj");
                if (Directory.Exists(objDir)) Directory.Delete(objDir, true);
            }
            catch { }

            await BuildPluginAsync(plugin);
        }

        private async Task BuildPluginAsync(PluginCardModel plugin)
        {
            if (_isBuilding) return;

            _isBuilding = true;
            _buildLog = $"Building {plugin.Name}...\n";
            ShowStatus($"Building '{plugin.Name}'…");

            try
            {
                var ws = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
                var deployer = new ExoDeployer(ws);
                var build = await deployer.BuildPluginAsync(plugin.Name, null, ExoforgeEditorConfig.DotnetPath, s => _buildLog += s + "\n");
                _buildLog = build.Output;
                ShowStatus($"✓ Successfully built '{plugin.Name}'.");
                await RefreshPluginsDataAsync();
            }
            catch (Exception ex)
            {
                _buildLog = ex.ToString();
                ShowStatus($"Build failed for '{plugin.Name}': {ex.Message}");
            }
            finally
            {
                _isBuilding = false;
                RebuildUI();
            }
        }

        private async Task DeployPluginAsync(PluginCardModel plugin)
        {
            if (!IsConnected)
            {
                ShowStatus("Cannot deploy: not connected to cluster.");
                return;
            }

            ShowStatus($"Deploying '{plugin.Name}' to cluster…");
            try
            {
                var ws = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
                var deployer = new ExoDeployer(ws);
                await deployer.UploadPluginAsync(plugin.Name, existingClient: GetClient());
                ShowStatus($"✓ Successfully deployed '{plugin.Name}' to cluster.");
                await RefreshPluginsDataAsync();
                int changed = await deployer.SyncContractsAsync(outputPathOverride: ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath(), existingClient: GetClient());
                if (changed > 0)
                {
                    AssetDatabase.Refresh();
                }
            }
            catch (Exception ex)
            {
                ShowStatus($"Deploy failed: {ex.Message}");
            }
        }

        private async Task GenerateStubsAsync(PluginCardModel plugin)
        {
            ShowStatus($"Generating service stubs for '{plugin.Name}'…");
            try
            {
                var ws = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
                var deployer = new ExoDeployer(ws);
                string output = await deployer.GeneratePluginStubsAsync(plugin.Name, existingClient: GetClient());
                ShowStatus($"✓ Generated stubs for '{plugin.Name}' → {output}");
            }
            catch (Exception ex)
            {
                ShowStatus($"Stub generation failed: {ex.Message}");
            }
        }

        private async Task FetchPluginLogsAsync(string pluginId)
        {
            string clean = ExoScaffolder.NormalizePluginName(pluginId);
            try
            {
                var ws = ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());
                var deployer = new ExoDeployer(ws);
                var lines = await deployer.GetPluginLogsAsync(clean, 100, existingClient: IsConnected ? GetClient() : null);

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
        }

        // =========================================================================
        // Helpers & Manifest Extraction
        // =========================================================================

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

        private static void InvalidateHooksCache() => _cachedHooks = null;

        private static List<IExoforgePluginCustomEditor> GetCustomEditorsForPlugin(string pluginId)
        {
            if (_cachedHooks == null)
            {
                _cachedHooks = new List<IExoforgePluginCustomEditor>();
                var types = TypeCache.GetTypesDerivedFrom<IExoforgePluginCustomEditor>().ToList();

                if (types.Count == 0)
                {
#pragma warning disable UAC0005
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

        private static int CountResources(JsonElement manifest) => ExtractResources(manifest).Count;
        private static int CountEvents(JsonElement manifest) => ExtractEvents(manifest).Count;
        private static int CountActions(JsonElement manifest, bool excludeWebhooks = false, bool webhooksOnly = false)
        {
            var actions = ExtractActions(manifest, isWebhookOnly: webhooksOnly);
            return excludeWebhooks ? actions.Count(a => !IsWebhookAction(a)) : actions.Count;
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
                        foreach (var r in resArr.EnumerateArray()) result.Add(r);
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
                        foreach (var e in eventsArr.EnumerateArray()) result.Add(e);
                    }
                }
            }
            return result;
        }

        private static string GenerateSamplePayload(JsonElement manifest, string? actionName)
        {
            if (string.IsNullOrEmpty(actionName)) return "{}";
            var actions = ExtractActions(manifest, isWebhookOnly: false);
            var act = actions.FirstOrDefault(a =>
                a.TryGetProperty("name", out var n) && string.Equals(n.GetString(), actionName, StringComparison.OrdinalIgnoreCase));

            if (act.ValueKind == JsonValueKind.Object && act.TryGetProperty("params", out var pArr))
            {
                var dict = new Dictionary<string, object?>();
                if (pArr.ValueKind == JsonValueKind.Array)
                {
                    foreach (var param in pArr.EnumerateArray())
                    {
                        string pName = param.TryGetProperty("name", out var pn) ? pn.GetString() ?? "param" : "param";
                        string pType = param.TryGetProperty("type", out var pt) ? pt.GetString() ?? "string" : "string";
                        dict[pName] = PlaceholderForType(pType);
                    }
                }
                else if (pArr.ValueKind == JsonValueKind.Object)
                {
                    foreach (var prop in pArr.EnumerateObject())
                    {
                        string pType = prop.Value.ValueKind == JsonValueKind.String ? prop.Value.GetString() ?? "string" : "string";
                        dict[prop.Name] = PlaceholderForType(pType);
                    }
                }
                if (dict.Count > 0)
                {
                    return JsonSerializer.Serialize(dict, new JsonSerializerOptions { WriteIndented = true });
                }
            }

            return "{\n  \"example\": \"value\"\n}";
        }

        private static object? PlaceholderForType(string pType) => pType.ToLowerInvariant() switch
        {
            "integer" or "int" => 0,
            "float" or "number" or "double" => 0.0,
            "boolean" or "bool" => false,
            "list" or "array" => new List<object>(),
            "map" or "object" => new Dictionary<string, object?>(),
            _ => ""
        };
    }

    [Obsolete("Use ExoforgeExtensionsWindow instead.")]
    public class ExoforgePluginsWindow : ExoforgeExtensionsWindow
    {
    }
}
