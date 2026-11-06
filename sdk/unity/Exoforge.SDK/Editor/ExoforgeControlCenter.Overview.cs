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

/// <summary>Metrics tab: cluster telemetry, supervision health and operations.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Tab 2: Metrics
    // =========================================================================

    private void DrawOverview()
    {
        _mainScroll = EditorGUILayout.BeginScrollView(_mainScroll);

        // 0. Quickstart Banner
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField("⚡ Quickstart: Extension ➔ Stubs ➔ Gameplay Flow", EditorStyles.boldLabel);
        EditorGUILayout.LabelField("1. Connect & Auth ➔ 2. Scaffold Extension ➔ 3. Build & Deploy ➔ 4. Sync Client ➔ 5. Call typed stubs", EditorStyles.wordWrappedMiniLabel);
        EditorGUILayout.Space(2);
        if (GUILayout.Button("📖 Open Quickstart Guide & API Reference ↗", GUILayout.Height(22)))
        {
            string url = ActiveHttpUrl;
            if (!string.IsNullOrEmpty(url)) Application.OpenURL($"{url.TrimEnd('/')}/guide");
        }
        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(6);

        // 1. Cluster Telemetry Card
        EditorGUILayout.LabelField("Cluster Telemetry & Node Health", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Node", _nodeName);
        DrawMetricPill("Uptime", _uptime);
        DrawMetricPill("Memory", _memoryMb);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(2);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Plugins", _pluginsCount.ToString());
        DrawMetricPill("Status", _isConnected ? "HEALTHY" : "OFFLINE");
        DrawMetricPill("Unity SDK", $"v{ExoforgePackageVersion.SdkVersion} (#{ExoforgePackageVersion.BuildHash})");
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(2);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Cluster Version", RemoteVersion != "—" ? $"v{RemoteVersion} (#{RemoteCommitHash})" : "—");
        DrawMetricPill("Cluster Built", RemoteBuildDate);
        EditorGUILayout.EndHorizontal();

        if (_isConnected && RemoteProjectName != "—")
        {
            EditorGUILayout.Space(2);
            EditorGUILayout.BeginHorizontal();
            DrawMetricPill("Studio", RemoteStudioName);
            DrawMetricPill("Project", RemoteProjectName);
            EditorGUILayout.EndHorizontal();
        }

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(6);

        // 2. SDK Version & Compatibility Card
        DrawSdkVersionCard();

        EditorGUILayout.Space(8);

        // 3. Cluster Operations & Developer Tools Card
        EditorGUILayout.LabelField("Cluster Operations & Dashboard", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        using (new EditorGUI.DisabledScope(!_isConnected))
        {
            if (GUILayout.Button("🔄 Hot-Restart Cluster Supervision", GUILayout.Height(26)))
            {
                _ = RestartClusterAsync();
            }
        }

        EditorGUILayout.Space(4);

        using (new EditorGUI.DisabledScope(string.IsNullOrEmpty(ActiveHttpUrl)))
        {
            if (GUILayout.Button("🌐 Open Web Dashboard ↗", GUILayout.Height(26)))
            {
                Application.OpenURL(DashboardUrl());
            }

            EditorGUILayout.Space(2);

            if (GUILayout.Button("📖 Open Quickstart Guide ↗", GUILayout.Height(26)))
            {
                Application.OpenURL(DashboardUrl().TrimEnd('/') + "/guide");
            }
        }

        EditorGUILayout.EndVertical();

        EditorGUILayout.EndScrollView();
    }

    // The dashboard's port is fixed; its host is the environment's (M33 Fix 23).
    private string DashboardUrl()
    {
        if (!Uri.TryCreate(ActiveHttpUrl, UriKind.Absolute, out var uri)) return "";
        return $"{uri.Scheme}://{uri.Host}:4005";
    }

    private static void DrawMetricPill(string label, string val)
    {
        var origBg = GUI.backgroundColor;
        GUI.backgroundColor = ExoforgeUIStyle.ImguiCardBg;
        EditorGUILayout.BeginVertical(GUI.skin.box);
        GUI.backgroundColor = origBg;
        EditorGUILayout.LabelField(label, EditorStyles.miniLabel);
        EditorGUILayout.LabelField(val, EditorStyles.boldLabel);
        EditorGUILayout.EndVertical();
    }

    private void DrawSdkVersionCard()
    {
        EditorGUILayout.LabelField("SDK Version & Compatibility", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Local Unity SDK:", EditorStyles.miniLabel, GUILayout.Width(130));
        EditorGUILayout.LabelField($"v{ExoforgePackageVersion.SdkVersion} (#{ExoforgePackageVersion.BuildHash})", EditorStyles.boldLabel);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Cluster Engine:", EditorStyles.miniLabel, GUILayout.Width(130));
        EditorGUILayout.LabelField(RemoteVersion != "—" ? $"v{RemoteVersion} (#{RemoteCommitHash})" : "Offline", EditorStyles.label);
        EditorGUILayout.EndHorizontal();

        if (!string.IsNullOrEmpty(RemoteSdkVersion) && RemoteSdkVersion != "—")
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("Cluster SDK Package:", EditorStyles.miniLabel, GUILayout.Width(130));
            string packageLabel = $"v{RemoteSdkVersion}" + (RemoteSdkPackageFilename != null ? $" ({RemoteSdkPackageFilename})" : "");
            EditorGUILayout.LabelField(packageLabel, EditorStyles.label);
            EditorGUILayout.EndHorizontal();
        }

        EditorGUILayout.Space(4);

        if (!_isConnected)
        {
            EditorGUILayout.HelpBox("Connect to cluster to verify SDK version compatibility and available updates.", MessageType.None);
        }
        else
        {
            switch (SdkStatus)
            {
                case SdkCompatibilityStatus.UpToDate:
                    EditorGUILayout.HelpBox($"✓ Unity SDK is up to date and matches the connected cluster.", MessageType.Info);
                    break;

                case SdkCompatibilityStatus.UpdateAvailable:
                    EditorGUILayout.HelpBox($"⚠️ An SDK update is available on the cluster (Cluster: v{RemoteSdkVersion ?? RemoteVersion}, Installed: v{ExoforgePackageVersion.SdkVersion}).", MessageType.Warning);
                    if (GUILayout.Button("⬇️ Download / Update SDK from Cluster", GUILayout.Height(24)))
                    {
                        _ = DownloadOrUpdateSdkAsync();
                    }
                    break;

                case SdkCompatibilityStatus.Ahead:
                    EditorGUILayout.HelpBox($"ℹ️ Installed SDK (v{ExoforgePackageVersion.SdkVersion}) is newer than the connected cluster (v{RemoteVersion}).", MessageType.Info);
                    break;

                default:
                    EditorGUILayout.HelpBox("SDK version verified.", MessageType.Info);
                    break;
            }
        }

        EditorGUILayout.EndVertical();
    }
}
}
