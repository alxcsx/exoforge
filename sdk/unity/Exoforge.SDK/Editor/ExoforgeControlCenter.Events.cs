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

/// <summary>Live Events tab: the cluster's event stream, with filtering and inspection.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Tab 2: Live Events Pub/Sub
    // =========================================================================

    /// <summary>
    /// What raised an event: actions announce themselves by name, and cron/webhook runs carry their
    /// origin (an action dispatched by the scheduler is still a cron run).
    /// </summary>
    private static string EventKind(LoggedEvent evt)
    {
        string name = evt.EventName ?? "";
        string origin = evt.Origin ?? "";

        if (string.Equals(origin, "cron", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("cron", StringComparison.OrdinalIgnoreCase)) return "cron";

        if (string.Equals(origin, "webhook", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("webhook", StringComparison.OrdinalIgnoreCase)) return "webhook";

        if (name.StartsWith("action:", StringComparison.OrdinalIgnoreCase)) return "action";

        return "event";
    }

    private void DrawLiveEvents()
    {
        if (DrawClusterGate()) return;

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField($"Live Broadcast Events ({_eventLog.Count})", EditorStyles.boldLabel);

        _eventAutoScroll = GUILayout.Toggle(_eventAutoScroll, "Auto-scroll", EditorStyles.miniButton, GUILayout.Width(80));

        if (GUILayout.Button(_eventPaused ? "▶ Resume" : "⏸ Pause", EditorStyles.miniButton, GUILayout.Width(70)))
        {
            _eventPaused = !_eventPaused;
        }

        if (GUILayout.Button("Clear", EditorStyles.miniButton, GUILayout.Width(50)))
        {
            _eventLog.Clear();
            _selectedEvent = null;
        }

        // One button turns "it broke" into a report: the last 50 calls with the server's request ids.
        if (GUILayout.Button("Copy diagnostics", EditorStyles.miniButton, GUILayout.Width(120)))
        {
            EditorGUIUtility.systemCopyBuffer = ExoClient.ExportDiagnostics();
            ShowStatus("Copied the last 50 calls as JSON (each carries its request id).", MessageType.Info);
        }
        EditorGUILayout.EndHorizontal();

        // Search & kind filters
        EditorGUILayout.BeginHorizontal();
        _eventFilter = EditorGUILayout.TextField("Filter", _eventFilter);
        if (!string.IsNullOrEmpty(_eventFilter) && GUILayout.Button("✕", EditorStyles.miniButton, GUILayout.Width(22)))
        {
            _eventFilter = "";
        }

        // The type is in the event name (action:<service>.<action>) and in the origin (cron/webhook),
        // so the filter reads it rather than asking the user to remember prefixes.
        _eventKindIndex = EditorGUILayout.Popup(
            _eventKindIndex,
            new[] { "All types", "Actions", "Events", "Webhooks", "Cron" },
            EditorStyles.miniButton,
            GUILayout.Width(110));
        EditorGUILayout.EndHorizontal();

        // Event List
        _eventScroll = EditorGUILayout.BeginScrollView(_eventScroll, GUILayout.Height(210));

        string kindFilter = _eventKindIndex switch
        {
            1 => "action",
            2 => "event",
            3 => "webhook",
            4 => "cron",
            _ => ""
        };

        var filtered = _eventLog
            .Where(e => string.IsNullOrWhiteSpace(_eventFilter) ||
                        e.Topic.Contains(_eventFilter, StringComparison.OrdinalIgnoreCase) ||
                        e.EventName.Contains(_eventFilter, StringComparison.OrdinalIgnoreCase))
            .Where(e => kindFilter == "" || EventKind(e) == kindFilter)
            .ToList();

        if (filtered.Count == 0)
        {
            EditorGUILayout.HelpBox(_isConnected ? "Listening for live events on topic '*'..." : "Connect to cluster to monitor live broadcast events.", MessageType.None);
        }
        else
        {
            foreach (var evt in filtered)
            {
                bool isSelected = _selectedEvent == evt;
                var rowStyle = isSelected ? EditorStyles.selectionRect : EditorStyles.helpBox;

                EditorGUILayout.BeginHorizontal(rowStyle);
                EditorGUILayout.LabelField(evt.At.ToString("HH:mm:ss.fff"), EditorStyles.miniLabel, GUILayout.Width(80));
                EditorGUILayout.LabelField(evt.Topic, EditorStyles.miniBoldLabel, GUILayout.Width(110));
                EditorGUILayout.LabelField(evt.EventName);
                if (!string.IsNullOrEmpty(evt.Origin))
                {
                    var originStyle = new GUIStyle(EditorStyles.miniLabel)
                    {
                        normal = { textColor = ExoforgeUIStyle.TextMuted }
                    };
                    EditorGUILayout.LabelField($"← {evt.Origin}", originStyle, GUILayout.Width(110));
                }

                if (!string.IsNullOrEmpty(evt.Rid))
                {
                    var ridStyle = new GUIStyle(EditorStyles.miniLabel)
                    {
                        normal = { textColor = ExoforgeUIStyle.TextMuted }
                    };
                    EditorGUILayout.LabelField(evt.Rid, ridStyle, GUILayout.Width(115));
                }

                if (GUILayout.Button(isSelected ? "Selected" : "Inspect", EditorStyles.miniButton, GUILayout.Width(60)))
                {
                    _selectedEvent = evt;
                }
                EditorGUILayout.EndHorizontal();
            }
        }

        EditorGUILayout.EndScrollView();

        EditorGUILayout.Space(4);

        // Event Detail Inspector
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField(_selectedEvent != null
            ? $"Payload: {_selectedEvent.Topic} -> {_selectedEvent.EventName}" +
              (string.IsNullOrEmpty(_selectedEvent.Origin) ? "" : $"  (triggered by {_selectedEvent.Origin})") +
              (string.IsNullOrEmpty(_selectedEvent.Rid) ? "" : $"  ·  {_selectedEvent.Rid}")
            : "Event Payload Inspector", EditorStyles.boldLabel);

        if (_selectedEvent != null)
        {
            if (!string.IsNullOrEmpty(_selectedEvent.Rid) &&
                GUILayout.Button("Copy rid", EditorStyles.miniButton, GUILayout.Width(70)))
            {
                EditorGUIUtility.systemCopyBuffer = _selectedEvent.Rid;
                ShowStatus("Copied the request id: paste it into the Studio timeline.", MessageType.Info);
            }

            if (GUILayout.Button("Copy JSON", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                EditorGUIUtility.systemCopyBuffer = _selectedEvent.RawJson;
                ShowStatus("Copied event JSON to clipboard.", MessageType.Info);
            }

            if (GUILayout.Button("Send to Sandbox", EditorStyles.miniButton, GUILayout.Width(110)))
            {
                ExoforgePluginsWindow.OpenSandbox(payload: _selectedEvent.RawJson);
                ShowStatus("Opened event payload in Extensions Action Sandbox.", MessageType.Info);
            }
        }
        EditorGUILayout.EndHorizontal();

        if (_selectedEvent != null)
        {
            _eventDetailScroll = EditorGUILayout.BeginScrollView(_eventDetailScroll, GUILayout.Height(150));
            EditorGUILayout.TextArea(_selectedEvent.RawJson, EditorStyles.textArea);
            EditorGUILayout.EndScrollView();
        }
        else
        {
            EditorGUILayout.HelpBox("Select an event above to inspect its JSON payload.", MessageType.None);
        }
    }
}
}
