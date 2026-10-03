using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Time;

#if UNITY_2018_1_OR_NEWER
using UnityEngine;
#endif

namespace Exoforge.Unity.Samples;

#if UNITY_2018_1_OR_NEWER
/// <summary>
/// Interactive sample Unity controller demonstrating end-to-end integration with Exoforge:
/// - Connects via WebSocket to deployed or local cluster
/// - Authenticates session with token
/// - Dispatches typed combat actions to C# WASM plugin
/// - Subscribes to real-time event broadcasts on the Unity main thread
/// - Renders an interactive debug HUD via OnGUI()
/// </summary>
public class CombatDemoController : MonoBehaviour
{
    [Header("Backend Connection")]
    [SerializeField] private string serverUrl = "ws://127.0.0.1:4000/ws";
    [SerializeField] private string authToken = "admin";

    [Header("Combat Simulation")]
    [SerializeField] private string targetPlayerId = "boss_dummy_1";
    [SerializeField] private int attackDamage = 35;

    private ExoClient _client;
    private bool _isConnected = false;
    private string _status = "Disconnected";
    private readonly List<string> _eventHistory = new();
    private string _lastActionResult = "—";
    private int _attackCount = 0;

    private async void Start()
    {
        await ConnectBackendAsync();
    }

    public async Task ConnectBackendAsync()
    {
        _status = "Connecting...";
        try
        {
            _client?.Dispose();
            _client = new ExoClient();

            // 1. Listen for real-time broadcast events on Unity main thread
            _client.OnAnyEvent += HandleEvent;

            // 2. Connect to WebSocket ingress
            await _client.ConnectAsync(new Uri(serverUrl));

            // 3. Authenticate session
            var authResult = await _client.AuthenticateAsync(authToken);
            if (authResult.Success)
            {
                _isConnected = true;
                _status = $"Authenticated ({authResult.PlayerId})";
                Debug.Log($"[Exoforge Sample] Connected & Authenticated as {authResult.PlayerId}");

                // 4. Subscribe to event topics
                await _client.SubscribeAsync("*");
            }
            else
            {
                _isConnected = false;
                _status = $"Auth Failed: {authResult.Error}";
                Debug.LogError($"[Exoforge Sample] Auth failed: {authResult.Error}");
            }
        }
        catch (Exception ex)
        {
            _isConnected = false;
            _status = $"Error: {ex.Message}";
            Debug.LogError($"[Exoforge Sample] Connection error: {ex.Message}");
        }
    }

    public async Task PerformAttackAsync()
    {
        if (_client == null || !_isConnected) return;

        _attackCount++;
        Debug.Log($"[Exoforge Sample] Invoking combat_wasm.attack against {targetPlayerId} with {attackDamage} damage...");

        var payload = new
        {
            target_player_id = targetPlayerId,
            damage = attackDamage
        };

        try
        {
            // Invoke the sandboxed C# WASM plugin action
            var result = await _client.SendActionAsync<JsonElement>("combat_wasm", "attack", payload);
            _lastActionResult = $"Damage dealt: {attackDamage} (Total: {_attackCount})";
            Debug.Log($"[Exoforge Action Result] attack executed successfully: {result}");
        }
        catch (Exception ex)
        {
            _lastActionResult = $"Failed: {ex.Message}";
            Debug.LogError($"[Exoforge Action Error] Failed: {ex.Message}");
        }
    }

    private void HandleEvent(ExoEventFrame evt)
    {
        string entry = $"[{DateTime.UtcNow:HH:mm:ss}] {evt.Topic} -> {evt.Event}";
        _eventHistory.Insert(0, entry);
        if (_eventHistory.Count > 10) _eventHistory.RemoveAt(_eventHistory.Count - 1);
        Debug.Log($"[Exoforge Event] Received {entry}");
    }

    private void OnGUI()
    {
        // On-screen GameDev Interactive HUD
        GUI.Box(new Rect(10, 10, 380, 320), "⚡ Exoforge LiveOps & Combat Showcase");

        GUI.Label(new Rect(20, 35, 360, 20), $"Server: {serverUrl}");
        GUI.Label(new Rect(20, 55, 360, 20), $"Status: {_status}");

        if (!_isConnected)
        {
            if (GUI.Button(new Rect(20, 80, 160, 28), "Connect to Cluster"))
            {
                _ = ConnectBackendAsync();
            }
        }
        else
        {
            if (GUI.Button(new Rect(20, 80, 170, 28), "⚡ Attack (Send Action)"))
            {
                _ = PerformAttackAsync();
            }

            if (GUI.Button(new Rect(200, 80, 170, 28), "Disconnect"))
            {
                _ = _client.DisconnectAsync();
                _isConnected = false;
                _status = "Disconnected";
            }
        }

        GUI.Label(new Rect(20, 115, 360, 20), $"Target: {targetPlayerId} (Damage: {attackDamage})");
        GUI.Label(new Rect(20, 135, 360, 20), $"Last Action Result: {_lastActionResult}");

        GUI.Label(new Rect(20, 165, 360, 20), "Recent Server Broadcast Events:");
        for (int i = 0; i < Math.Min(6, _eventHistory.Count); i++)
        {
            GUI.Label(new Rect(20, 188 + (i * 20), 360, 20), _eventHistory[i]);
        }

        if (_eventHistory.Count == 0)
        {
            GUI.Label(new Rect(20, 188, 360, 20), "No events received yet. Click 'Attack'!");
        }
    }

    private async void OnDestroy()
    {
        if (_client != null)
        {
            await _client.DisconnectAsync();
            _client.Dispose();
        }
    }
}
#endif
