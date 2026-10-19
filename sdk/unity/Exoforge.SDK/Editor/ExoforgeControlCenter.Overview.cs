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
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // 2. Cluster Operations & Developer Tools Card
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
}
}
