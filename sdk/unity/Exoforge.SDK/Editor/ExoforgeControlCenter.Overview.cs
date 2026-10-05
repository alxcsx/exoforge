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

/// <summary>Overview tab: cluster telemetry and extension metric widgets.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Tab 1: Overview
    // =========================================================================

    private void DrawOverview()
    {
        _mainScroll = EditorGUILayout.BeginScrollView(_mainScroll);

        // 1. Cluster Telemetry Card
        EditorGUILayout.LabelField("Cluster Telemetry", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Node", _nodeName);
        DrawMetricPill("Uptime", _uptime);
        DrawMetricPill("Memory", _memoryMb);
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(2);

        EditorGUILayout.BeginHorizontal();
        DrawMetricPill("Active Entities", _activeEntities.ToString());
        DrawMetricPill("Plugins", _pluginsCount.ToString());
        DrawMetricPill("Status", _isConnected ? "HEALTHY" : "OFFLINE");
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // 2. Client Code Generation & Contract Sync Card
        EditorGUILayout.LabelField("Contract Synchronization & Code Generation", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        string lastSync = !string.IsNullOrEmpty(ExoforgeEditorConfig.LastSyncTime)
            ? ExoforgeEditorConfig.LastSyncTime
            : "Not yet synced";

        EditorGUILayout.LabelField($"Last Synced: {lastSync}", EditorStyles.miniLabel);
        EditorGUILayout.LabelField($"Generated Output: {ExoforgeEditorConfig.GeneratedScriptPath}", EditorStyles.miniLabel);

        EditorGUILayout.Space(4);

        if (GUILayout.Button("⚡ Sync Contracts & Generate C# Client", GUILayout.Height(30)))
        {
            _ = SyncAndGenerateClientAsync();
        }

        if (GUILayout.Button("⬇ Generate Plugin Type Stubs (all plugins)", GUILayout.Height(24)))
        {
            _ = GenerateAllStubsAsync();
        }

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("Reveal Generated File", EditorStyles.miniButton))
        {
            string absGenPath = ExoforgeEditorConfig.GetAbsoluteGeneratedScriptPath();
            if (File.Exists(absGenPath))
            {
                EditorUtility.RevealInFinder(absGenPath);
            }
            else
            {
                ShowStatus($"Generated file not found at {absGenPath}. Run Sync first.", MessageType.Warning);
            }
        }

        if (GUILayout.Button("Open Workspace Folder", EditorStyles.miniButton))
        {
            string absWs = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
            if (Directory.Exists(absWs))
            {
                EditorUtility.RevealInFinder(absWs);
            }
            else
            {
                ShowStatus($"Workspace folder not found at {absWs}.", MessageType.Warning);
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(8);

        // 3. Cluster Operations & Tools Card
        EditorGUILayout.LabelField("Cluster Operations & Developer Tools", EditorStyles.boldLabel);
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        using (new EditorGUI.DisabledScope(!_isConnected))
        {
            if (GUILayout.Button("🔄 Hot-Restart Cluster Supervision", GUILayout.Height(24)))
            {
                _ = RestartClusterAsync();
            }
        }

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("🌐 Open Web Dashboard (:4005)", GUILayout.Height(24)))
        {
            Application.OpenURL("http://localhost:4005");
        }

        if (GUILayout.Button("📖 Open Swagger API Docs (:4001)", GUILayout.Height(24)))
        {
            Application.OpenURL("http://localhost:4001/swagger");
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.EndVertical();

        EditorGUILayout.EndScrollView();
    }

    private static void DrawMetricPill(string label, string val)
    {
        EditorGUILayout.BeginVertical(GUI.skin.box);
        EditorGUILayout.LabelField(label, EditorStyles.miniLabel);
        EditorGUILayout.LabelField(val, EditorStyles.boldLabel);
        EditorGUILayout.EndVertical();
    }
}
}
