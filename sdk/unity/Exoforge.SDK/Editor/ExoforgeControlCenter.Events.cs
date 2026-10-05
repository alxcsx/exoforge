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

    private void DrawLiveEvents()
    {
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
        EditorGUILayout.EndHorizontal();

        // Search Filter
        EditorGUILayout.BeginHorizontal();
        _eventFilter = EditorGUILayout.TextField("Filter", _eventFilter);
        if (!string.IsNullOrEmpty(_eventFilter) && GUILayout.Button("✕", EditorStyles.miniButton, GUILayout.Width(22)))
        {
            _eventFilter = "";
        }
        EditorGUILayout.EndHorizontal();

        // Event List
        _eventScroll = EditorGUILayout.BeginScrollView(_eventScroll, GUILayout.Height(210));

        var filtered = string.IsNullOrWhiteSpace(_eventFilter)
            ? _eventLog
            : _eventLog.Where(e => e.Topic.Contains(_eventFilter, StringComparison.OrdinalIgnoreCase) ||
                                   e.EventName.Contains(_eventFilter, StringComparison.OrdinalIgnoreCase)).ToList();

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
                EditorGUILayout.LabelField(evt.Topic, EditorStyles.miniBoldLabel, GUILayout.Width(130));
                EditorGUILayout.LabelField(evt.EventName);

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
            ? $"Payload: {_selectedEvent.Topic} -> {_selectedEvent.EventName}"
            : "Event Payload Inspector", EditorStyles.boldLabel);

        if (_selectedEvent != null)
        {
            if (GUILayout.Button("Copy JSON", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                EditorGUIUtility.systemCopyBuffer = _selectedEvent.RawJson;
                ShowStatus("Copied event JSON to clipboard.", MessageType.Info);
            }

            if (GUILayout.Button("Send to Sandbox", EditorStyles.miniButton, GUILayout.Width(110)))
            {
                _sandboxPayload = _selectedEvent.RawJson;
                _currentTab = Tab.ActionSandbox;
                ShowStatus("Loaded event payload into Action Sandbox.", MessageType.Info);
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
