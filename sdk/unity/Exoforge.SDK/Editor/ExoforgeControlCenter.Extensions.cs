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
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
// NOTE: keep this a block-scoped namespace. Unity's layout serializer drops windows declared
// with file-scoped namespaces, so the window would vanish from saved layouts (Unity issue 9734).

/// <summary>Plugins tab: scaffold, build, deploy, reload and inspect local and remote plugins.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // UI Toolkit Modern Studio Cockpit (Phase 2)
    // =========================================================================

    public VisualElement BuildExtensionsTabToolkit()
    {
        if (_localPlugins.Count == 0) RefreshLocalPlugins();

        var container = new VisualElement();
        container.style.flexDirection = FlexDirection.Column;
        container.style.flexGrow = 1;

        // 1. BaaS Offline Warning Banner
        if (!CanReachCluster)
        {
            var warningCard = new VisualElement();
            warningCard.style.backgroundColor = new Color(0.18f, 0.14f, 0.08f);
            warningCard.style.borderTopWidth = 1;
            warningCard.style.borderBottomWidth = 1;
            warningCard.style.borderLeftWidth = 1;
            warningCard.style.borderRightWidth = 1;
            warningCard.style.borderTopColor = ExoforgeUIStyle.AccentOrange;
            warningCard.style.borderBottomColor = ExoforgeUIStyle.AccentOrange;
            warningCard.style.borderLeftColor = ExoforgeUIStyle.AccentOrange;
            warningCard.style.borderRightColor = ExoforgeUIStyle.AccentOrange;
            warningCard.style.borderTopLeftRadius = 8;
            warningCard.style.borderTopRightRadius = 8;
            warningCard.style.borderBottomLeftRadius = 8;
            warningCard.style.borderBottomRightRadius = 8;
            warningCard.style.paddingLeft = 14;
            warningCard.style.paddingRight = 14;
            warningCard.style.paddingTop = 10;
            warningCard.style.paddingBottom = 10;
            warningCard.style.marginBottom = 10;

            var warnHeader = new VisualElement();
            warnHeader.style.flexDirection = FlexDirection.Row;
            warnHeader.style.alignItems = Align.Center;
            warnHeader.style.marginBottom = 4;

            var warnIcon = new Label(_isConnecting ? "🔄" : "⚠️");
            warnIcon.style.fontSize = 18;
            warnIcon.style.marginRight = 8;
            warnHeader.Add(warnIcon);

            var warnTitle = new Label(_isConnecting ? "CONNECTING TO CLUSTER..." : "CLUSTER OFFLINE — LOCAL MODE ACTIVE");
            warnTitle.style.fontSize = 13;
            warnTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            warnTitle.style.color = _isConnecting ? ExoforgeUIStyle.AccentBlue : ExoforgeUIStyle.AccentOrange;
            warnHeader.Add(warnTitle);
            warningCard.Add(warnHeader);

            var warnDesc = new Label(
                _isConnecting
                    ? $"Connecting to cluster at {ActiveWsUrl}… Metrics, event streaming, and remote synchronization will unlock once connected."
                    : $"Exoforge is a BaaS system. The editor is not connected to {ActiveWsUrl}. Developing and editing extensions is available locally, but deploying, streaming logs, metrics, and live events require an online cluster.");
            warnDesc.style.fontSize = 11;
            warnDesc.style.color = ExoforgeUIStyle.TextPrimary;
            warnDesc.style.whiteSpace = WhiteSpace.Normal;
            warningCard.Add(warnDesc);

            container.Add(warningCard);
        }
        else if (SdkStatus == SdkCompatibilityStatus.UpdateAvailable)
        {
            var outOfSyncCard = new VisualElement();
            outOfSyncCard.style.backgroundColor = new Color(0.96f, 0.62f, 0.12f, 0.10f); // theme-safe amber-500/10
            outOfSyncCard.style.borderTopWidth = 1;
            outOfSyncCard.style.borderBottomWidth = 1;
            outOfSyncCard.style.borderLeftWidth = 1;
            outOfSyncCard.style.borderRightWidth = 1;
            outOfSyncCard.style.borderTopColor = new Color(0.96f, 0.62f, 0.12f, 0.35f);
            outOfSyncCard.style.borderBottomColor = new Color(0.96f, 0.62f, 0.12f, 0.35f);
            outOfSyncCard.style.borderLeftColor = new Color(0.96f, 0.62f, 0.12f, 0.35f);
            outOfSyncCard.style.borderRightColor = new Color(0.96f, 0.62f, 0.12f, 0.35f);
            outOfSyncCard.style.borderTopLeftRadius = 8;
            outOfSyncCard.style.borderTopRightRadius = 8;
            outOfSyncCard.style.borderBottomLeftRadius = 8;
            outOfSyncCard.style.borderBottomRightRadius = 8;
            outOfSyncCard.style.paddingLeft = 14;
            outOfSyncCard.style.paddingRight = 14;
            outOfSyncCard.style.paddingTop = 10;
            outOfSyncCard.style.paddingBottom = 10;
            outOfSyncCard.style.marginBottom = 10;

            var syncHeader = new VisualElement();
            syncHeader.style.flexDirection = FlexDirection.Row;
            syncHeader.style.alignItems = Align.Center;
            syncHeader.style.marginBottom = 4;

            var syncIcon = new Label("⚠️");
            syncIcon.style.fontSize = 18;
            syncIcon.style.marginRight = 8;
            syncHeader.Add(syncIcon);

            string targetVer = RemoteSdkVersion ?? RemoteVersion;
            string titleText = $"SDK VERSION OUT OF SYNC — CLUSTER v{targetVer} (INSTALLED: v{ExoforgePackageVersion.SdkVersion})";

            var syncTitle = new Label(titleText);
            syncTitle.style.fontSize = 13;
            syncTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            syncTitle.style.color = ExoforgeUIStyle.AccentOrange;
            syncHeader.Add(syncTitle);
            outOfSyncCard.Add(syncHeader);

            var syncDesc = new Label("Your Unity SDK version differs from the connected cluster. You can still list, inspect, and develop extensions, but some contracts or features may require updating the package.");
            syncDesc.style.fontSize = 11;
            syncDesc.style.color = ExoforgeUIStyle.TextPrimary;
            syncDesc.style.whiteSpace = WhiteSpace.Normal;
            syncDesc.style.marginBottom = 8;
            outOfSyncCard.Add(syncDesc);

            var syncActionRow = new VisualElement();
            syncActionRow.style.flexDirection = FlexDirection.Row;
            syncActionRow.style.alignItems = Align.Center;

            if (SdkStatus == SdkCompatibilityStatus.UpdateAvailable)
            {
                var updateBtn = ExoforgeUIStyle.CreateModernButton("⬇️ Download / Update SDK from Cluster", () => _ = DownloadOrUpdateSdkAsync(), bg: ExoforgeUIStyle.BrandPurple, height: 26);
                updateBtn.style.marginRight = 8;
                syncActionRow.Add(updateBtn);
            }

            var resyncBtn = ExoforgeUIStyle.CreateModernButton("🔄 Force Sync Client Stubs", () => _ = SyncAndGenerateClientAsync(forceReload: true), height: 26);
            syncActionRow.Add(resyncBtn);

            outOfSyncCard.Add(syncActionRow);
            container.Add(outOfSyncCard);
        }

        // 2. Action Strip (New Extension + Unity Client Sync)
        var actionStrip = new VisualElement();
        actionStrip.style.flexDirection = FlexDirection.Row;
        actionStrip.style.alignItems = Align.Center;
        actionStrip.style.justifyContent = Justify.SpaceBetween;
        actionStrip.style.backgroundColor = ExoforgeUIStyle.BgCard;
        actionStrip.style.paddingLeft = 12;
        actionStrip.style.paddingRight = 12;
        actionStrip.style.paddingTop = 8;
        actionStrip.style.paddingBottom = 8;
        actionStrip.style.borderTopLeftRadius = 8;
        actionStrip.style.borderTopRightRadius = 8;
        actionStrip.style.borderBottomLeftRadius = 8;
        actionStrip.style.borderBottomRightRadius = 8;
        actionStrip.style.marginBottom = 12;

        var leftActions = new VisualElement();
        leftActions.style.flexDirection = FlexDirection.Row;
        leftActions.style.alignItems = Align.Center;

        var newExtBtn = ExoforgeUIStyle.CreateModernButton("⚡ New Extension...", () =>
        {
            ExoforgeScaffoldModal.Open(onCreatedWithId: id =>
            {
                RefreshLocalPlugins();
                _ = RefreshPluginsAsync();
                ShowStatus($"✓ Extension '{id}' scaffolded successfully.", MessageType.Info);
                RefreshTabContent();
            });
        }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 28);
        newExtBtn.style.marginRight = 10;
        leftActions.Add(newExtBtn);

        string lastSync = !string.IsNullOrEmpty(ExoforgeEditorConfig.LastSyncTime)
            ? ExoforgeEditorConfig.LastSyncTime
            : "Not yet generated";
        var syncLabel = new Label($"Client stubs: {lastSync}");
        syncLabel.style.fontSize = 11;
        syncLabel.style.color = ExoforgeUIStyle.TextMuted;
        syncLabel.style.marginRight = 8;
        leftActions.Add(syncLabel);

        var syncBtn = ExoforgeUIStyle.CreateModernButton("⚡ Regenerate Client", async () =>
        {
            await SyncAndGenerateClientAsync();
            RefreshTabContent();
        }, height: 26);
        leftActions.Add(syncBtn);

        actionStrip.Add(leftActions);

        var rightActions = new VisualElement();
        rightActions.style.flexDirection = FlexDirection.Row;
        rightActions.style.alignItems = Align.Center;

        var buildAllBtn = ExoforgeUIStyle.CreateModernButton("🚀 Build & Deploy All", async () =>
        {
            await BuildAndDeployAllAsync();
            RefreshTabContent();
        }, height: 26);
        buildAllBtn.SetEnabled(CanReachCluster && _localPlugins.Count > 0 && !_isBuilding);
        buildAllBtn.style.marginRight = 6;
        rightActions.Add(buildAllBtn);

        var refreshBtn = ExoforgeUIStyle.CreateModernButton("🔄 Refresh", async () =>
        {
            await RefreshPluginsAsync();
            RefreshTabContent();
        }, height: 26);
        rightActions.Add(refreshBtn);

        actionStrip.Add(rightActions);
        container.Add(actionStrip);

        // 3. ScrollView of Extensions Cards
        var scroll = new ScrollView();
        scroll.style.flexGrow = 1;

        if (_localPlugins.Count == 0)
        {
            var emptyBox = new VisualElement();
            emptyBox.style.alignItems = Align.Center;
            emptyBox.style.justifyContent = Justify.Center;
            emptyBox.style.paddingTop = 40;
            emptyBox.style.paddingBottom = 40;

            var emptyIcon = new Label("🧩");
            emptyIcon.style.fontSize = 32;
            emptyIcon.style.marginBottom = 8;
            emptyBox.Add(emptyIcon);

            var emptyTitle = new Label("No extensions found in workspace");
            emptyTitle.style.fontSize = 14;
            emptyTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            emptyTitle.style.color = ExoforgeUIStyle.TextPrimary;
            emptyTitle.style.marginBottom = 4;
            emptyBox.Add(emptyTitle);

            var emptySub = new Label("Click '+ New Extension' above to scaffold your first C# server extension.");
            emptySub.style.fontSize = 11;
            emptySub.style.color = ExoforgeUIStyle.TextMuted;
            emptyBox.Add(emptySub);

            scroll.Add(emptyBox);
        }
        else
        {
            foreach (var plugin in _localPlugins)
            {
                scroll.Add(BuildExtensionCardToolkit(plugin));
            }
        }

        // 4. Remote / Immutable Extensions Section
        scroll.Add(BuildRemoteExtensionsSectionToolkit());

        container.Add(scroll);
        return container;
    }

    private VisualElement BuildRemoteExtensionsSectionToolkit()
    {
        var section = new VisualElement();
        section.style.marginTop = 16;
        section.style.marginBottom = 20;

        var headerRow = new VisualElement();
        headerRow.style.flexDirection = FlexDirection.Row;
        headerRow.style.alignItems = Align.Center;
        headerRow.style.justifyContent = Justify.SpaceBetween;
        headerRow.style.marginBottom = 8;

        var titleRow = new VisualElement();
        titleRow.style.flexDirection = FlexDirection.Row;
        titleRow.style.alignItems = Align.Center;

        var secTitle = new Label("🔒 Remote / Immutable Extensions");
        secTitle.style.fontSize = 13;
        secTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
        secTitle.style.color = ExoforgeUIStyle.TextPrimary;
        titleRow.Add(secTitle);

        var countBadge = ExoforgeUIStyle.CreatePill(
            $"{_remotePlugins.Count}",
            ExoforgeUIStyle.AccentBlue,
            new Color(0.12f, 0.16f, 0.24f));
        countBadge.style.marginLeft = 8;
        titleRow.Add(countBadge);

        headerRow.Add(titleRow);

        var refreshRemoteBtn = ExoforgeUIStyle.CreateModernButton("🔄 Refresh Remote", async () =>
        {
            await RefreshPluginsAsync();
            RefreshTabContent();
        }, height: 24);
        refreshRemoteBtn.SetEnabled(CanReachCluster);
        headerRow.Add(refreshRemoteBtn);

        section.Add(headerRow);

        var descLabel = new Label("Pre-installed and remote server extensions running on the connected cluster (read-only / immutable).");
        descLabel.style.fontSize = 11;
        descLabel.style.color = ExoforgeUIStyle.TextMuted;
        descLabel.style.marginBottom = 10;
        section.Add(descLabel);

        if (!CanReachCluster && _remotePlugins.Count == 0)
        {
            var offlineBox = new VisualElement();
            offlineBox.style.backgroundColor = ExoforgeUIStyle.BgCard;
            offlineBox.style.paddingLeft = 14;
            offlineBox.style.paddingRight = 14;
            offlineBox.style.paddingTop = 12;
            offlineBox.style.paddingBottom = 12;
            offlineBox.style.borderTopLeftRadius = 6;
            offlineBox.style.borderTopRightRadius = 6;
            offlineBox.style.borderBottomLeftRadius = 6;
            offlineBox.style.borderBottomRightRadius = 6;
            offlineBox.style.borderTopWidth = 1;
            offlineBox.style.borderBottomWidth = 1;
            offlineBox.style.borderLeftWidth = 1;
            offlineBox.style.borderRightWidth = 1;
            offlineBox.style.borderTopColor = ExoforgeUIStyle.BorderSubtle;
            offlineBox.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
            offlineBox.style.borderLeftColor = ExoforgeUIStyle.BorderSubtle;
            offlineBox.style.borderRightColor = ExoforgeUIStyle.BorderSubtle;

            var offMsg = new Label("Connect to the cluster to view active remote and immutable extensions.");
            offMsg.style.fontSize = 11;
            offMsg.style.color = ExoforgeUIStyle.TextSecondary;
            offlineBox.Add(offMsg);

            section.Add(offlineBox);
            return section;
        }

        if (!CanReachCluster && _remotePlugins.Count > 0)
        {
            var cachedPill = new Label($"Showing {_remotePlugins.Count} cached remote extensions (Offline / Read-only)");
            cachedPill.style.fontSize = 11;
            cachedPill.style.color = ExoforgeUIStyle.AccentOrange;
            cachedPill.style.marginBottom = 6;
            section.Add(cachedPill);
        }

        if (_remotePlugins.Count == 0)
        {
            var emptyBox = new VisualElement();
            emptyBox.style.backgroundColor = ExoforgeUIStyle.BgCard;
            emptyBox.style.paddingLeft = 14;
            emptyBox.style.paddingRight = 14;
            emptyBox.style.paddingTop = 12;
            emptyBox.style.paddingBottom = 12;
            emptyBox.style.borderTopLeftRadius = 6;
            emptyBox.style.borderTopRightRadius = 6;
            emptyBox.style.borderBottomLeftRadius = 6;
            emptyBox.style.borderBottomRightRadius = 6;

            var emptyMsg = new Label("No remote extensions reported by the cluster.");
            emptyMsg.style.fontSize = 11;
            emptyMsg.style.color = ExoforgeUIStyle.TextSecondary;
            emptyBox.Add(emptyMsg);

            section.Add(emptyBox);
            return section;
        }

        foreach (var plugin in _remotePlugins)
        {
            section.Add(BuildRemoteExtensionCardToolkit(plugin));
        }

        return section;
    }

    private VisualElement BuildRemoteExtensionCardToolkit(JsonElement plugin)
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

        var card = new VisualElement();
        card.style.backgroundColor = ExoforgeUIStyle.BgCard;
        card.style.borderTopWidth = 1;
        card.style.borderBottomWidth = 1;
        card.style.borderLeftWidth = 1;
        card.style.borderRightWidth = 1;
        card.style.borderTopColor = ExoforgeUIStyle.BorderSubtle;
        card.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
        card.style.borderLeftColor = ExoforgeUIStyle.BorderSubtle;
        card.style.borderRightColor = ExoforgeUIStyle.BorderSubtle;
        card.style.borderTopLeftRadius = 8;
        card.style.borderTopRightRadius = 8;
        card.style.borderBottomLeftRadius = 8;
        card.style.borderBottomRightRadius = 8;
        card.style.paddingLeft = 14;
        card.style.paddingRight = 14;
        card.style.paddingTop = 10;
        card.style.paddingBottom = 10;
        card.style.marginBottom = 6;

        var row = new VisualElement();
        row.style.flexDirection = FlexDirection.Row;
        row.style.alignItems = Align.Center;
        row.style.justifyContent = Justify.SpaceBetween;

        var left = new VisualElement();
        left.style.flexDirection = FlexDirection.Row;
        left.style.alignItems = Align.Center;

        var iconLabel = new Label(icon);
        iconLabel.style.fontSize = 22;
        iconLabel.style.marginRight = 10;
        left.Add(iconLabel);

        var titleCol = new VisualElement();
        var titleRow = new VisualElement();
        titleRow.style.flexDirection = FlexDirection.Row;
        titleRow.style.alignItems = Align.Center;

        var nameLabel = new Label(title);
        nameLabel.style.fontSize = 13;
        nameLabel.style.unityFontStyleAndWeight = FontStyle.Bold;
        nameLabel.style.color = ExoforgeUIStyle.TextPrimary;
        titleRow.Add(nameLabel);

        var immutableBadge = ExoforgeUIStyle.CreatePill("🔒 Remote / Immutable", new Color(0.6f, 0.6f, 0.7f), new Color(0.15f, 0.15f, 0.2f));
        immutableBadge.style.marginLeft = 8;
        titleRow.Add(immutableBadge);

        titleCol.Add(titleRow);

        string meta = (title != id && !string.IsNullOrEmpty(title))
            ? $"{id} • v{version}"
            : $"v{version}";
        var metaLabel = new Label(meta);
        metaLabel.style.fontSize = 10;
        metaLabel.style.color = ExoforgeUIStyle.TextMuted;
        titleCol.Add(metaLabel);

        left.Add(titleCol);
        row.Add(left);

        var right = new VisualElement();
        right.style.flexDirection = FlexDirection.Row;
        right.style.alignItems = Align.Center;

        var inspectBtn = ExoforgeUIStyle.CreateModernButton("Inspect ↗", () =>
        {
            ExoforgeExtensionsWindow.OpenExtension(id);
        }, height: 24);
        right.Add(inspectBtn);

        row.Add(right);
        card.Add(row);

        return card;
    }

    private VisualElement BuildExtensionCardToolkit(LocalPluginInfo plugin)
    {
        string buildError = SessionState.GetString(BuildFailureKey(plugin.Name), "");
        bool failed = buildError.Length > 0;
        string? deployedVersion = RemotePluginVersion(plugin.Name);
        bool notDeployed = _isConnected && plugin.IsBuilt && !plugin.Modified && deployedVersion != plugin.Version;

        var card = new VisualElement();
        card.style.backgroundColor = failed ? new Color(0.22f, 0.12f, 0.12f) : ExoforgeUIStyle.BgCard;
        card.style.borderTopWidth = 1;
        card.style.borderBottomWidth = 1;
        card.style.borderLeftWidth = 1;
        card.style.borderRightWidth = 1;
        card.style.borderTopColor = failed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderBottomColor = failed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderLeftColor = failed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderRightColor = failed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderTopLeftRadius = 8;
        card.style.borderTopRightRadius = 8;
        card.style.borderBottomLeftRadius = 8;
        card.style.borderBottomRightRadius = 8;
        card.style.paddingLeft = 14;
        card.style.paddingRight = 14;
        card.style.paddingTop = 10;
        card.style.paddingBottom = 10;
        card.style.marginBottom = 8;

        // Row 1: Header (Icon, Title, Details, Status Pill)
        var row1 = new VisualElement();
        row1.style.flexDirection = FlexDirection.Row;
        row1.style.alignItems = Align.Center;
        row1.style.justifyContent = Justify.SpaceBetween;
        row1.style.marginBottom = 10;

        var headerLeft = new VisualElement();
        headerLeft.style.flexDirection = FlexDirection.Row;
        headerLeft.style.alignItems = Align.Center;

        var iconLabel = new Label(plugin.Icon);
        iconLabel.style.fontSize = 24;
        iconLabel.style.marginRight = 10;
        headerLeft.Add(iconLabel);

        var titleCol = new VisualElement();
        string displayTitle = !string.IsNullOrEmpty(plugin.Title) && plugin.Title != plugin.Name
            ? $"{plugin.Title} ({plugin.Name})"
            : plugin.Name;
        var titleLabel = new Label(displayTitle);
        titleLabel.style.fontSize = 13;
        titleLabel.style.unityFontStyleAndWeight = FontStyle.Bold;
        titleLabel.style.color = ExoforgeUIStyle.TextPrimary;
        titleCol.Add(titleLabel);

        string tag = BuildTag(plugin.Version);
        string sizeStr = plugin.BinarySizeBytes > 0 ? $"{plugin.BinarySizeBytes / 1024} KB" : "";
        string subText = $"{plugin.PluginType.ToUpperInvariant()} • v{plugin.Version ?? "0.1.0"} {tag} {(sizeStr != "" ? "• " + sizeStr : "")}";
        var subLabel = new Label(subText);
        subLabel.style.fontSize = 10;
        subLabel.style.color = ExoforgeUIStyle.TextMuted;
        titleCol.Add(subLabel);
        headerLeft.Add(titleCol);
        row1.Add(headerLeft);

        // Status Pill on the right
        VisualElement statusPill;
        if (failed)
        {
            statusPill = ExoforgeUIStyle.CreatePill("✗ Build Failed", Color.white, ExoforgeUIStyle.AccentRed, 10);
            statusPill.tooltip = buildError;
        }
        else if (!plugin.IsBuilt)
        {
            statusPill = ExoforgeUIStyle.CreatePill("○ Not Built", ExoforgeUIStyle.TextMuted, ExoforgeUIStyle.AccentGrayBg, 10);
        }
        else if (plugin.Modified)
        {
            statusPill = ExoforgeUIStyle.CreatePill("● Modified", Color.white, ExoforgeUIStyle.AccentOrange, 10);
        }
        else if (notDeployed)
        {
            statusPill = ExoforgeUIStyle.CreatePill("● Built (Needs Deploy)", Color.white, ExoforgeUIStyle.AccentBlue, 10);
        }
        else if (!_isConnected)
        {
            statusPill = ExoforgeUIStyle.CreatePill("Built (Offline)", ExoforgeUIStyle.TextSecondary, ExoforgeUIStyle.AccentGrayBg, 10);
        }
        else
        {
            statusPill = ExoforgeUIStyle.CreatePill("✓ Deployed", Color.white, ExoforgeUIStyle.AccentGreen, 10);
        }
        row1.Add(statusPill);
        card.Add(row1);

        // Row 2: Action Buttons
        var row2 = new VisualElement();
        row2.style.flexDirection = FlexDirection.Row;
        row2.style.alignItems = Align.Center;
        row2.style.justifyContent = Justify.SpaceBetween;

        var leftButtons = new VisualElement();
        leftButtons.style.flexDirection = FlexDirection.Row;
        leftButtons.style.alignItems = Align.Center;

        // Primary Action
        if (!plugin.IsBuilt || failed)
        {
            var buildBtn = ExoforgeUIStyle.CreateModernButton("🔨 Build", async () =>
            {
                await BuildPluginAsync(plugin, false);
                RefreshTabContent();
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 26);
            buildBtn.style.marginRight = 6;
            leftButtons.Add(buildBtn);
        }
        else if (plugin.Modified)
        {
            var buildDeployBtn = ExoforgeUIStyle.CreateModernButton("🚀 Build & Deploy", async () =>
            {
                await BuildPluginAsync(plugin, thenDeploy: true);
                RefreshTabContent();
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 26);
            buildDeployBtn.SetEnabled(CanReachCluster);
            buildDeployBtn.style.marginRight = 6;
            leftButtons.Add(buildDeployBtn);
        }
        else if (notDeployed)
        {
            var deployBtn = ExoforgeUIStyle.CreateModernButton("🚀 Deploy", async () =>
            {
                await DeployPluginAsync(plugin);
                RefreshTabContent();
            }, bg: ExoforgeUIStyle.AccentGreen, textCol: Color.white, height: 26);
            deployBtn.SetEnabled(CanReachCluster);
            deployBtn.style.marginRight = 6;
            leftButtons.Add(deployBtn);
        }
        else
        {
            var redeployBtn = ExoforgeUIStyle.CreateModernButton("Re-Deploy", async () =>
            {
                await DeployPluginAsync(plugin);
                RefreshTabContent();
            }, height: 26);
            redeployBtn.SetEnabled(CanReachCluster);
            redeployBtn.style.marginRight = 6;
            leftButtons.Add(redeployBtn);
        }

        var openSrcBtn = ExoforgeUIStyle.CreateModernButton("✏️ Edit", () =>
        {
            OpenExtensionInEditor(plugin.Directory);
        }, height: 26);
        openSrcBtn.style.marginRight = 6;
        leftButtons.Add(openSrcBtn);

        var folderBtn = ExoforgeUIStyle.CreateModernButton("📁 Folder", () =>
        {
            EditorUtility.RevealInFinder(plugin.Directory);
        }, height: 26);
        folderBtn.style.marginRight = 6;
        leftButtons.Add(folderBtn);

        row2.Add(leftButtons);

        var rightButtons = new VisualElement();
        rightButtons.style.flexDirection = FlexDirection.Row;
        rightButtons.style.alignItems = Align.Center;

        var inspectBtn = ExoforgeUIStyle.CreateModernButton("Inspect ↗", () =>
        {
            ExoforgeExtensionsWindow.OpenExtension(plugin.Name);
        }, height: 26);
        rightButtons.Add(inspectBtn);

        row2.Add(rightButtons);
        card.Add(row2);

        return card;
    }

    // =========================================================================
    // Legacy IMGUI fallback
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

        EditorGUILayout.BeginHorizontal();
        GUILayout.FlexibleSpace();
        bool autoStubs = EditorGUILayout.ToggleLeft(
            new GUIContent("Auto-generate stubs on rebuild", "Automatically regenerate typed C# extension stubs after compiling or rebuilding an extension"),
            ExoforgeEditorConfig.AutoGenerateStubsOnBuild,
            GUILayout.Width(220));
        if (autoStubs != ExoforgeEditorConfig.AutoGenerateStubsOnBuild)
        {
            ExoforgeEditorConfig.AutoGenerateStubsOnBuild = autoStubs;
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
                string subText = $"{plugin.PluginType.ToUpperInvariant()} • {plugin.Version ?? "0.1.0"} {tag} {(sizeStr != "" ? "• " + sizeStr : "")}";
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

                // 4. Secondary actions: Inspect, Edit, Folder
                if (GUILayout.Button(new GUIContent("Inspect ↗", "Inspect and manage this extension in the Exoforge Extensions window"), EditorStyles.miniButton, GUILayout.Width(75), GUILayout.Height(24)))
                {
                    ExoforgeExtensionsWindow.OpenExtension(plugin.Name);
                }

                if (GUILayout.Button(new GUIContent("✏️ Edit", "Open this extension folder and main source file in the code editor"), EditorStyles.miniButton, GUILayout.Width(60), GUILayout.Height(24)))
                {
                    OpenExtensionInEditor(plugin.Directory);
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
            ShowStatus("No buildable extensions found.", MessageType.Info);
            return;
        }

        var targets = buildable.Where(p => !p.IsBuilt || p.Modified).ToList();
        if (targets.Count == 0)
        {
            targets = buildable;
        }

        ShowStatus($"Building {targets.Count} extension(s)…", MessageType.Info);
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
            ShowStatus($"✓ Built {targets.Count} extension(s).", MessageType.Info);
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
            ShowStatus($"Building {unbuilt.Count} unbuilt/modified extension(s) before deploy…", MessageType.Info);
            foreach (var plugin in unbuilt)
            {
                await BuildPluginAsync(plugin, thenDeploy: false);
            }
        }

        var deployable = _localPlugins.Where(p => p.IsBuilt && SessionState.GetString(BuildFailureKey(p.Name), "").Length == 0).ToList();
        if (deployable.Count == 0)
        {
            ShowStatus("No built extensions available to deploy.", MessageType.Warning);
            return;
        }

        _isBuilding = true;
        ShowStatus($"Deploying {deployable.Count} extension(s) to cluster…", MessageType.Info);
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
                ShowStatus($"✓ Successfully deployed all {successCount} extension(s) to cluster.", MessageType.Info);
            }
            else
            {
                ShowStatus($"Deployed {successCount}/{deployable.Count} extension(s). Failures: {string.Join("; ", errors)}", MessageType.Error);
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

        if (!ExoforgeDotnetValidator.PromptIfMissing($"compile the '{plugin.Name}' extension"))
        {
            return;
        }

        _isBuilding = true;
        _showBuildLog = true;
        _buildLog = $"Building {plugin.Name} ({plugin.PluginType})...\n";
        ShowStatus($"Building '{plugin.Name}'… (see Build Log)", MessageType.Info);
        Repaint();

        try
        {
            var deployer = new ExoDeployer(Workspace);
            string? configuredRid = string.IsNullOrWhiteSpace(ExoforgeEditorConfig.TargetBuildRid) ? null : ExoforgeEditorConfig.TargetBuildRid.Trim();
            string? overrideRid = string.IsNullOrWhiteSpace(_buildRid) ? null : _buildRid.Trim();

            string effectiveRid;
            if (!string.IsNullOrEmpty(overrideRid) && !string.Equals(overrideRid, "auto", StringComparison.OrdinalIgnoreCase))
            {
                effectiveRid = overrideRid;
            }
            else if (!string.IsNullOrEmpty(configuredRid) && !string.Equals(configuredRid, "auto", StringComparison.OrdinalIgnoreCase))
            {
                effectiveRid = configuredRid;
            }
            else if (thenDeploy)
            {
                // When deploying to server: target the cluster's reported RID or standard linux-x64
                effectiveRid = !string.IsNullOrEmpty(_clusterTargetRid) ? _clusterTargetRid : ExoforgeDotnetValidator.StandardServerRid;
            }
            else
            {
                // Local build: use host RID
                effectiveRid = ExoDeployer.HostRuntimeIdentifier();
            }

            var build = await deployer.BuildPluginAsync(
                plugin.Name, effectiveRid, ExoforgeEditorConfig.DotnetPath, AppendBuildLog);

            _buildLog = build.Output;
            SessionState.EraseString(BuildFailureKey(plugin.Name));
            ShowStatus($"✓ Built '{plugin.Name}' ({build.PluginType}).", MessageType.Info);
            RefreshLocalPlugins();

            if (ExoforgeEditorConfig.AutoGenerateStubsOnBuild)
            {
                try
                {
                    await GenerateStubsAsync(plugin);
                }
                catch (Exception ex)
                {
                    UnityEngine.Debug.LogWarning($"[Exoforge] Auto-generation of stubs for '{plugin.Name}' skipped: {ex.Message}");
                }
            }

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
            string msg = ex.Message;
            if (msg.Contains(":eacces"))
            {
                msg = $"{msg} (Server permission denied. The previous extension process may still be releasing file locks, or the server directory has restricted permissions. Try deploying again).";
            }
            ShowStatus($"Deploy failed: {msg}", MessageType.Error);
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

    /// <summary>
    /// Locates the primary C# source file of an extension (e.g. [Name]Extension.cs or [Name]Plugin.cs).
    /// </summary>
    public static string? FindExtensionMainFile(string extensionDir)
    {
        if (string.IsNullOrEmpty(extensionDir) || !Directory.Exists(extensionDir)) return null;

        string srcDir = Path.Combine(extensionDir, "src");
        if (!Directory.Exists(srcDir)) srcDir = extensionDir;

        string name = Path.GetFileName(extensionDir);
        string className = ExoScaffolder.ClassNameFor(name);

        string candidate = Path.Combine(srcDir, $"{className}Extension.cs");
        if (File.Exists(candidate)) return candidate;

        candidate = Path.Combine(srcDir, $"{className}Plugin.cs");
        if (File.Exists(candidate)) return candidate;

        string[] matches = Directory.GetFiles(srcDir, "*Extension.cs", SearchOption.AllDirectories);
        if (matches.Length > 0) return matches[0];

        matches = Directory.GetFiles(srcDir, "*Plugin.cs", SearchOption.AllDirectories);
        if (matches.Length > 0) return matches[0];

        matches = Directory.GetFiles(srcDir, "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains("Generated") && !f.Contains(".g.cs") && !f.Contains("obj") && !f.Contains("bin"))
            .ToArray();
        if (matches.Length > 0) return matches[0];

        string[] sln = Directory.GetFiles(extensionDir, "*.sln");
        if (sln.Length > 0) return sln[0];

        string[] csproj = Directory.GetFiles(extensionDir, "*.csproj", SearchOption.AllDirectories);
        if (csproj.Length > 0) return csproj[0];

        return null;
    }

    /// <summary>
    /// Opens the extension folder and main source file in the code editor.
    /// </summary>
    public static void OpenExtensionInEditor(string extensionDir)
    {
        if (string.IsNullOrEmpty(extensionDir) || !Directory.Exists(extensionDir)) return;

        string? mainFile = FindExtensionMainFile(extensionDir);
        string targetPath = mainFile ?? extensionDir;

        // Try launching VS Code if available with folder and navigate to main file in the same window
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = Application.platform == RuntimePlatform.WindowsEditor ? "code.cmd" : "code",
                Arguments = !string.IsNullOrEmpty(mainFile)
                    ? $"\"{extensionDir}\" -g \"{mainFile}:1\""
                    : $"\"{extensionDir}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            if (proc != null) return;
        }
        catch { }

        // Fallback 1: Unity external script editor
        if (File.Exists(targetPath))
        {
            try
            {
                if (UnityEditorInternal.InternalEditorUtility.OpenFileAtLineExternal(targetPath, 1))
                {
                    return;
                }
            }
            catch { }
        }

        // Fallback 2: AssetDatabase if within Assets
        if (targetPath.StartsWith(Application.dataPath, StringComparison.OrdinalIgnoreCase))
        {
            string rel = "Assets" + targetPath.Substring(Application.dataPath.Length).Replace('\\', '/');
            var asset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(rel);
            if (asset != null && AssetDatabase.OpenAsset(asset))
            {
                return;
            }
        }

        // Fallback 3: System default editor
        EditorUtility.OpenWithDefaultApp(targetPath);
    }
}
}
