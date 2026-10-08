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

/// <summary>Action Sandbox tab: dispatch any service action with a generated payload.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Tab 3: Action Sandbox
    // =========================================================================

    private void DrawSandbox()
    {
        if (DrawClusterGate()) return;

        EditorGUILayout.LabelField("Action Sandbox & Service Dispatcher", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Test and dispatch actions directly to the cluster with typed JSON payloads.", MessageType.None);

        EditorGUILayout.BeginVertical(EditorStyles.helpBox);

        // Catalog Dropdowns
        var serviceNames = _serviceCatalog.Keys.ToList();
        serviceNames.Add("(Custom)");
        _selectedServiceIndex = Mathf.Clamp(_selectedServiceIndex, 0, serviceNames.Count - 1);

        EditorGUILayout.BeginHorizontal();
        int newServiceIndex = EditorGUILayout.Popup("Quick Catalog", _selectedServiceIndex, serviceNames.ToArray());
        if (newServiceIndex != _selectedServiceIndex)
        {
            _selectedServiceIndex = newServiceIndex;
            if (_selectedServiceIndex < serviceNames.Count - 1)
            {
                _sandboxService = serviceNames[_selectedServiceIndex];
                _selectedActionIndex = 0;

                var specs = _serviceCatalog[_sandboxService];
                if (specs.Count > 0)
                {
                    _sandboxAction = specs[0].Name;
                    LoadSamplePayload(_sandboxService, _sandboxAction);
                }
            }
        }

        if (_selectedServiceIndex < serviceNames.Count - 1)
        {
            var specs = _serviceCatalog[serviceNames[_selectedServiceIndex]];
            var actionNames = specs.Select(a => a.Name).ToList();
            actionNames.Add("(Custom)");

            _selectedActionIndex = Mathf.Clamp(_selectedActionIndex, 0, actionNames.Count - 1);
            int newActionIndex = EditorGUILayout.Popup(_selectedActionIndex, actionNames.ToArray(), GUILayout.Width(130));
            if (newActionIndex != _selectedActionIndex)
            {
                _selectedActionIndex = newActionIndex;
                if (_selectedActionIndex < actionNames.Count - 1)
                {
                    _sandboxAction = actionNames[_selectedActionIndex];
                    LoadSamplePayload(_sandboxService, _sandboxAction);
                }
            }
        }
        EditorGUILayout.EndHorizontal();

        _sandboxService = EditorGUILayout.TextField("Service", _sandboxService);
        _sandboxAction = EditorGUILayout.TextField("Action", _sandboxAction);

        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("JSON Payload");
        if (GUILayout.Button("Format JSON", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            FormatSandboxPayload();
        }
        if (GUILayout.Button("Load Template", EditorStyles.miniButton, GUILayout.Width(90)))
        {
            LoadSamplePayload(_sandboxService, _sandboxAction);
        }
        EditorGUILayout.EndHorizontal();

        _sandboxPayload = EditorGUILayout.TextArea(_sandboxPayload, GUILayout.Height(90));

        EditorGUILayout.Space(2);

        using (new EditorGUI.DisabledScope(!_isConnected))
        {
            if (GUILayout.Button("🚀 Dispatch Action", GUILayout.Height(28)))
            {
                _ = DispatchSandboxAsync();
            }
        }
        EditorGUILayout.EndVertical();

        // Response View
        if (!string.IsNullOrEmpty(_sandboxResult))
        {
            EditorGUILayout.Space(4);
            EditorGUILayout.BeginHorizontal();

            var prev = GUI.color;
            GUI.color = _sandboxSuccess ? new Color(0.3f, 0.9f, 0.4f) : new Color(0.9f, 0.3f, 0.3f);
            string statusTag = _sandboxSuccess ? $"● SUCCESS ({_sandboxLatency})" : $"● ERROR ({_sandboxLatency})";
            EditorGUILayout.LabelField(statusTag, EditorStyles.boldLabel);
            GUI.color = prev;

            if (GUILayout.Button("Copy Result", EditorStyles.miniButton, GUILayout.Width(80)))
            {
                EditorGUIUtility.systemCopyBuffer = _sandboxResult;
                ShowStatus("Copied action result to clipboard.", MessageType.Info);
            }
            EditorGUILayout.EndHorizontal();

            _sandboxResultScroll = EditorGUILayout.BeginScrollView(_sandboxResultScroll, GUILayout.Height(150));
            EditorGUILayout.TextArea(_sandboxResult, EditorStyles.textArea);
            EditorGUILayout.EndScrollView();
        }
    }

    private void FormatSandboxPayload()
    {
        try
        {
            using var doc = JsonDocument.Parse(_sandboxPayload);
            _sandboxPayload = JsonSerializer.Serialize(doc.RootElement, new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            ShowStatus($"Invalid JSON: {ex.Message}", MessageType.Error);
        }
    }

    /// <summary>
    /// Builds a payload skeleton from the action's declared params, so the Sandbox produces
    /// something the action will accept for any service — including plugins you just wrote.
    /// </summary>
    private void LoadSamplePayload(string service, string action)
    {
        if (!_serviceCatalog.TryGetValue(service, out var specs))
        {
            _sandboxPayload = "{}";
            return;
        }

        var spec = specs.FirstOrDefault(a => a.Name == action);
        if (spec == null || spec.Params.Count == 0)
        {
            _sandboxPayload = "{}";
            return;
        }

        var payload = new Dictionary<string, object?>();

        foreach (var (name, declared) in spec.Params)
        {
            // Optional params are omitted: sending a wrong-shaped value is worse than omitting it.
            if (IsOptional(declared)) continue;

            payload[name] = PlaceholderFor(declared);
        }

        _sandboxPayload = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
    }

    private static bool IsOptional(JsonElement declared) =>
        declared.ValueKind == JsonValueKind.Object &&
        declared.TryGetProperty("optional", out var optional) &&
        optional.ValueKind == JsonValueKind.True;

    private static string ParamType(JsonElement declared) =>
        declared.ValueKind switch
        {
            JsonValueKind.String => declared.GetString() ?? "string",
            JsonValueKind.Object when declared.TryGetProperty("type", out var type) => type.GetString() ?? "string",
            _ => "string"
        };

    private static object? PlaceholderFor(JsonElement declared) => ParamType(declared) switch
    {
        "integer" or "int" => 0,
        "float" or "number" => 0.0,
        "boolean" or "bool" => false,
        "list" or "array" => new List<object>(),
        "map" or "object" => new Dictionary<string, object?>(),
        "term" => null,
        _ => ""
    };

    private async Task DispatchSandboxAsync()
    {
        if (_editorClient == null || !_isConnected) return;

        var sw = Stopwatch.StartNew();
        try
        {
            object? payload = string.IsNullOrWhiteSpace(_sandboxPayload)
                ? null
                : JsonDocument.Parse(_sandboxPayload).RootElement;

            var result = await _editorClient.SendActionAsync<JsonElement>(_sandboxService, _sandboxAction, payload);
            sw.Stop();

            _sandboxSuccess = true;
            _sandboxLatency = $"{sw.ElapsedMilliseconds} ms";
            _sandboxResult = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            sw.Stop();
            _sandboxSuccess = false;
            _sandboxLatency = $"{sw.ElapsedMilliseconds} ms";
            _sandboxResult = ex.Message;
        }

        Repaint();
    }
}
}
