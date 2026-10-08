using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;

#if UNITY_2018_1_OR_NEWER
using UnityEngine;
#endif

namespace Exoforge.Unity.Samples;

#if UNITY_2018_1_OR_NEWER
/// <summary>
/// Minimal sample showing the standard Exoforge integration:
/// - The cluster connection is owned by the <c>Exoforge</c> prefab
///   (<see cref="ExoforgeManager"/>), which resolves settings from the workspace
///   <c>exoforge.json</c>. Gameplay scripts contain no URLs, tokens, or session code.
/// - Dispatches actions to a deployed WASM plugin.
/// - Receives real-time event broadcasts on the Unity main thread.
/// - Renders a small OnGUI() debug HUD.
/// </summary>
public class BasicUsageController : MonoBehaviour
{
    [Header("Sample")]
    [SerializeField] private int counterId = 1;
    [SerializeField] private int amount = 10;

    private ExoClient? _client;
    private bool _isConnected;
    private string _status = "Connecting…";
    private string _lastResult = "—";
    private readonly List<string> _eventHistory = new();

    private async void Start()
    {
        try
        {
            // Everything connection-related is handled by the Exoforge prefab.
            _client = await ExoforgeManager.Instance.GetClientAsync();

            _client.OnAnyEvent += HandleEvent;
            await _client.SubscribeAsync("sample:events");

            _isConnected = true;
            _status = $"Online ({_client.PlayerId})";
            Debug.Log($"[Exoforge Sample] Ready as {_client.PlayerId}");
        }
        catch (Exception ex)
        {
            _isConnected = false;
            _status = "Offline";
            Debug.LogError($"[Exoforge Sample] {ex.Message}");
        }
    }

    public async Task PingAsync()
    {
        if (_client == null || !_isConnected) return;

        try
        {
            var result = await _client.SendActionAsync<JsonElement>("sample_wasm", "ping", Array.Empty<int>());
            _lastResult = $"sample_wasm.ping → {result.GetInt64()}";
        }
        catch (Exception ex)
        {
            _lastResult = $"Failed: {ex.Message}";
        }
    }

    public async Task IncrementAsync()
    {
        if (_client == null || !_isConnected) return;

        try
        {
            var result = await _client.SendActionAsync<JsonElement>("sample_wasm", "increment", new[] { counterId, amount });
            _lastResult = $"sample_wasm.increment → {result.GetInt64()}";
        }
        catch (Exception ex)
        {
            _lastResult = $"Failed: {ex.Message}";
        }
    }

    private void HandleEvent(ExoEventFrame evt)
    {
        string entry = $"[{DateTime.UtcNow:HH:mm:ss}] {evt.Topic} → {evt.Event}";
        _eventHistory.Insert(0, entry);
        if (_eventHistory.Count > 8) _eventHistory.RemoveAt(_eventHistory.Count - 1);
        Debug.Log($"[Exoforge Event] {entry}");
    }

    private void OnGUI()
    {
        GUI.Box(new Rect(10, 10, 400, 300), "Exoforge SDK — Basic Usage");

        GUI.Label(new Rect(20, 35, 380, 20), $"Status: {_status}");
        GUI.Label(new Rect(20, 55, 380, 20), $"Last Result: {_lastResult}");

        if (_isConnected)
        {
            if (GUI.Button(new Rect(20, 85, 170, 28), "Ping (WS)"))
            {
                _ = PingAsync();
            }

            if (GUI.Button(new Rect(200, 85, 190, 28), $"Increment #{counterId} (+{amount})"))
            {
                _ = IncrementAsync();
            }
        }

        GUI.Label(new Rect(20, 130, 380, 20), "Recent Broadcast Events:");
        for (int i = 0; i < _eventHistory.Count; i++)
        {
            GUI.Label(new Rect(20, 152 + (i * 18), 380, 18), _eventHistory[i]);
        }

        if (_eventHistory.Count == 0)
        {
            GUI.Label(new Rect(20, 152, 380, 20), "None yet — click Increment to emit one.");
        }
    }
}
#endif
