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

            var warnTitle = new Label(_isConnecting ? "CONNECTING TO SERVER..." : (NeedsSignIn ? "SIGN IN AGAIN — LOCAL MODE ACTIVE" : "SERVER OFFLINE — LOCAL MODE ACTIVE"));
            warnTitle.style.fontSize = 13;
            warnTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            warnTitle.style.color = _isConnecting ? ExoforgeUIStyle.AccentBlue : ExoforgeUIStyle.AccentOrange;
            warnHeader.Add(warnTitle);
            warningCard.Add(warnHeader);

            var warnDesc = new Label(
                _isConnecting
                    ? $"Connecting to server at {ActiveWsUrl}… Metrics, event streaming, and remote synchronization will unlock once connected."
                    : NeedsSignIn
                        ? $"The server at {ActiveWsUrl} did not accept your saved session, so it may have expired or been revoked. Sign in again with the Account button to deploy and see live data. Editing extensions still works."
                        : $"Exoforge is a BaaS system. The editor is not connected to {ActiveWsUrl}. Developing and editing extensions is available locally, but deploying, streaming logs, metrics, and live events require an online server.");
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
            string titleText = $"SDK VERSION OUT OF SYNC — SERVER v{targetVer} (INSTALLED: v{ExoforgePackageVersion.SdkVersion})";

            var syncTitle = new Label(titleText);
            syncTitle.style.fontSize = 13;
            syncTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            syncTitle.style.color = ExoforgeUIStyle.AccentOrange;
            syncHeader.Add(syncTitle);
            outOfSyncCard.Add(syncHeader);

            var syncDesc = new Label("Your Unity SDK version differs from the connected server. You can still list, inspect, and develop extensions, but some contracts or features may require updating the package.");
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
                var updateBtn = ExoforgeUIStyle.CreateModernButton("⬇️ Download / Update SDK from Server", () => _ = DownloadOrUpdateSdkAsync(), bg: ExoforgeUIStyle.BrandPurple, height: 26);
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

        // 4. The last build's output. Kept across a domain reload, so the reason a build failed is still here
        // after Unity recompiles; the status line's "see Build Log" points at this.
        if (!string.IsNullOrEmpty(_buildLog))
        {
            var logFold = new Foldout { text = "Build Log", value = _buildLog.Contains("error") || _buildLog.Contains("failed") };
            var logText = new TextField { value = _buildLog, multiline = true, isReadOnly = true };
            logText.style.minHeight = 90;
            logText.style.maxHeight = 260;
            logText.style.whiteSpace = WhiteSpace.Normal;
            logFold.Add(logText);
            scroll.Add(logFold);
        }

        // 5. Remote / Immutable Extensions Section
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

        var descLabel = new Label("Pre-installed and remote server extensions running on the connected server (read-only / immutable).");
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

            var offMsg = new Label("Connect to the server to view active remote and immutable extensions.");
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

            var emptyMsg = new Label("No remote extensions reported by the server.");
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

        bool isSystem = (plugin.TryGetProperty("system", out var sysProp) && sysProp.ValueKind == JsonValueKind.True)
            || (plugin.TryGetProperty("category", out var catProp) && string.Equals(catProp.GetString(), "System", StringComparison.OrdinalIgnoreCase));

        var immutableBadge = isSystem
            ? ExoforgeUIStyle.CreatePill("⚙️ System", new Color(0.6f, 0.6f, 0.7f), new Color(0.15f, 0.15f, 0.2f))
            : ExoforgeUIStyle.CreatePill("🔒 Remote / Immutable", new Color(0.6f, 0.6f, 0.7f), new Color(0.15f, 0.15f, 0.2f));
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
        string? deployError = ExoforgeExtensionOps.DeployFailure(plugin.Name);
        bool failed = buildError.Length > 0;
        bool deployFailed = !failed && deployError != null;
        string? deployedVersion = RemotePluginVersion(plugin.Name);
        bool notDeployed = _isConnected && plugin.IsBuilt && !plugin.Modified && deployedVersion != plugin.Version;

        var card = new VisualElement();
        card.style.backgroundColor = failed || deployFailed ? new Color(0.22f, 0.12f, 0.12f) : ExoforgeUIStyle.BgCard;
        card.style.borderTopWidth = 1;
        card.style.borderBottomWidth = 1;
        card.style.borderLeftWidth = 1;
        card.style.borderRightWidth = 1;
        card.style.borderTopColor = failed || deployFailed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderBottomColor = failed || deployFailed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderLeftColor = failed || deployFailed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
        card.style.borderRightColor = failed || deployFailed ? ExoforgeUIStyle.AccentRed : ExoforgeUIStyle.BorderSubtle;
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
        else if (deployFailed)
        {
            statusPill = ExoforgeUIStyle.CreatePill("✗ Deploy Failed", Color.white, ExoforgeUIStyle.AccentRed, 10);
            statusPill.tooltip = deployError;
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

        // The reason, on the card: a tooltip on a pill is where an error goes to be missed.
        if (failed || deployFailed)
        {
            var reason = new Label(FirstLines(failed ? buildError : deployError!, 3));
            reason.style.fontSize = 11;
            reason.style.color = ExoforgeUIStyle.TextPrimary;
            reason.style.whiteSpace = WhiteSpace.Normal;
            reason.style.marginTop = 6;
            reason.style.marginBottom = 4;
            card.Add(reason);
        }

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

    private static string BuildFailureKey(string pluginName) => ExoforgeExtensionOps.BuildFailureKey(pluginName);

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

    /// <summary>The first lines of a long message (a compiler log, a stack trace), enough to say what went wrong.</summary>
    private static string FirstLines(string text, int count)
    {
        var lines = text.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).Take(count);
        string joined = string.Join("\n", lines);
        return joined.Length > 400 ? joined.Substring(0, 400) + "…" : joined;
    }

    /// <summary>
    /// Providers before the extensions that call them, so a caller starts with its dependencies already running and
    /// its stubs can be generated from their manifests. A problem (a circle, a service nobody provides) is shown,
    /// and the order is still returned so one bad link does not stop the rest.
    /// </summary>
    private List<LocalPluginInfo> InDeployOrder(List<LocalPluginInfo> plugins)
    {
        var plan = ExoDeployOrder.Plan(ExoDeployOrder.ReadNodes(Workspace.ExtensionsPath, plugins.Select(p => p.Name)));
        if (!plan.IsClean)
        {
            ShowStatus(string.Join(" ", plan.Problems), MessageType.Warning);
        }

        return plan.Order.Select(name => plugins.First(p => p.Name == name)).ToList();
    }

    private async Task BuildAndDeployAllAsync()
    {
        if (_isBuilding) return;
        if (!_isConnected)
        {
            ShowStatus("Cannot deploy: not connected to server.", MessageType.Warning);
            return;
        }

        var targets = InDeployOrder(_localPlugins.Where(p => p.CanBuild).ToList());
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
            ShowStatus("Cannot deploy: not connected to server.", MessageType.Warning);
            return;
        }

        var unbuilt = InDeployOrder(_localPlugins.Where(p => p.CanBuild && (!p.IsBuilt || p.Modified)).ToList());
        if (unbuilt.Count > 0)
        {
            ShowStatus($"Building {unbuilt.Count} unbuilt/modified extension(s) before deploy…", MessageType.Info);
            foreach (var plugin in unbuilt)
            {
                await BuildPluginAsync(plugin, thenDeploy: false);
            }
        }

        var deployable = InDeployOrder(_localPlugins.Where(p => p.IsBuilt && SessionState.GetString(BuildFailureKey(p.Name), "").Length == 0).ToList());
        if (deployable.Count == 0)
        {
            ShowStatus("No built extensions available to deploy.", MessageType.Warning);
            return;
        }

        if (!ExoforgeExtensionOps.ConfirmDeploy(ActiveEnvironment?.Name ?? "default", ActiveWsUrl, deployable.Count))
        {
            ShowStatus("Deploy cancelled.", MessageType.Info);
            return;
        }

        _isBuilding = true;
        ShowStatus($"Deploying {deployable.Count} extension(s) to server, dependencies first…", MessageType.Info);
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
                    await deployer.UploadExtensionAsync(plugin.Name, existingClient: _editorClient);
                    ExoforgeExtensionOps.ClearDeployFailure(plugin.Name);
                    successCount++;
                }
                catch (Exception ex)
                {
                    string msg = ExoforgeExtensionOps.DescribeDeployError(ex);
                    ExoforgeExtensionOps.RecordDeployFailure(plugin.Name, msg);
                    errors.Add($"{plugin.Name}: {msg}");
                }
            }

            await RefreshPluginsAsync();
            await SyncAndGenerateClientAsync();

            if (errors.Count == 0)
            {
                ShowStatus($"✓ Successfully deployed all {successCount} extension(s) to server.", MessageType.Info);
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
        _buildLog = $"Building {plugin.Name} ({plugin.PluginType})...\n";
        ShowStatus($"Building '{plugin.Name}'… (see Build Log)", MessageType.Info);
        Repaint();

        try
        {
            var deployer = new ExoDeployer(Workspace);
            string effectiveRid = ExoforgeExtensionOps.ResolveRid(_buildRid, ExoforgeEditorConfig.TargetBuildRid, thenDeploy, _clusterTargetRid);

            var build = await deployer.BuildExtensionAsync(
                plugin.Name, effectiveRid, ExoforgeEditorConfig.DotnetPath, AppendBuildLog);

            _buildLog = build.Output;
            ExoforgeExtensionOps.RecordBuildLog(_buildLog);
            SessionState.EraseString(BuildFailureKey(plugin.Name));
            ShowStatus($"✓ Built '{plugin.Name}' ({build.ExtensionType}).", MessageType.Info);
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
            ExoforgeExtensionOps.RecordBuildLog(errorDetails);
            ExoforgeExtensionOps.RecordBuildFailure(plugin.Name, errorDetails);

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

    private async Task GenerateStubsAsync(LocalPluginInfo plugin)
    {
        try
        {
            var deployer = new ExoDeployer(Workspace);
            string output = await deployer.GenerateExtensionStubsAsync(plugin.Name, existingClient: _isConnected ? _editorClient : null);
            ShowStatus($"✓ Generated typed service stubs for '{plugin.Name}' → {output}", MessageType.Info);
        }
        catch (Exception ex)
        {
            ShowStatus($"Stub generation failed for '{plugin.Name}': {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task DeployPluginAsync(LocalPluginInfo plugin)
    {
        if (!ExoforgeExtensionOps.ConfirmDeploy(ActiveEnvironment?.Name ?? "default", ActiveWsUrl, 1))
        {
            ShowStatus("Deploy cancelled.", MessageType.Info);
            return;
        }

        try
        {
            var deployer = new ExoDeployer(Workspace);
            await deployer.UploadExtensionAsync(plugin.Name, existingClient: _editorClient);
            ExoforgeExtensionOps.ClearDeployFailure(plugin.Name);
            ShowStatus($"Successfully deployed '{plugin.Name}' to server.", MessageType.Info);
            await RefreshPluginsAsync();
            await SyncAndGenerateClientAsync();
        }
        catch (Exception ex)
        {
            string msg = ExoforgeExtensionOps.DescribeDeployError(ex);
            ExoforgeExtensionOps.RecordDeployFailure(plugin.Name, msg);
            ShowStatus($"Deploy failed for '{plugin.Name}': {msg}", MessageType.Error);
            RefreshTabContent();
        }

        Repaint();
    }

    /// <summary>
    /// Opens the extension solution or folder in the configured external code editor (e.g. Rider, VS, VS Code).
    /// Opening the extension's dedicated .sln file avoids loading the extension under Unity's parent solution.
    /// </summary>
    public static void OpenExtensionInEditor(string extensionDir)
    {
        if (string.IsNullOrEmpty(extensionDir) || !Directory.Exists(extensionDir)) return;

        // 1. Prefer opening the standalone solution file (.sln) or project file (.csproj)
        string? slnPath = Directory.GetFiles(extensionDir, "*.sln").FirstOrDefault();
        if (string.IsNullOrEmpty(slnPath))
        {
            slnPath = Directory.GetFiles(extensionDir, "*.csproj", SearchOption.AllDirectories).FirstOrDefault();
        }

        string? mainFile = FindExtensionMainFile(extensionDir);
        string targetPath = slnPath ?? mainFile ?? extensionDir;

        // If a standalone solution exists, prioritize opening it directly with the configured external editor or system default app
        if (!string.IsNullOrEmpty(slnPath) && File.Exists(slnPath))
        {
            string extEditor = EditorPrefs.GetString("kScriptsDefaultApp", "");
            if (!string.IsNullOrEmpty(extEditor) && File.Exists(extEditor))
            {
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = extEditor,
                        Arguments = $"\"{slnPath}\"",
                        UseShellExecute = true
                    };
                    using var proc = Process.Start(psi);
                    if (proc != null) return;
                }
                catch { }
            }

            try
            {
                EditorUtility.OpenWithDefaultApp(slnPath);
                return;
            }
            catch { }
        }

        // 2. Try launching VS Code if available with folder and navigate to main file in the same window
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

        // 3. Fallback: Unity external script editor
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

        // 4. Fallback: AssetDatabase if within Assets
        if (targetPath.StartsWith(Application.dataPath, StringComparison.OrdinalIgnoreCase))
        {
            string rel = "Assets" + targetPath.Substring(Application.dataPath.Length).Replace('\\', '/');
            var asset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(rel);
            if (asset != null && AssetDatabase.OpenAsset(asset))
            {
                return;
            }
        }

        // 5. Fallback: System default editor
        EditorUtility.OpenWithDefaultApp(targetPath);
    }
}
}
